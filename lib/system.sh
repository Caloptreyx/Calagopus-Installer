# shellcheck shell=bash
# Packages, Docker, Caddy and the host firewall.

CALA_APT_UPDATED=0

cala_require_root() {
  ((EUID == 0)) || cala_die "run the installer as root: 'sudo -i' first, or: curl -sSL https://install.caloptreyx.com | sudo bash"
}

cala_pkg_install() {
  case "$OS_FAMILY" in
    debian)
      if ((CALA_APT_UPDATED == 0)); then
        cala_run "Updating the package lists" env DEBIAN_FRONTEND=noninteractive apt-get update
        CALA_APT_UPDATED=1
      fi
      cala_run "Installing $*" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
      ;;
    rhel)
      cala_run "Installing $*" dnf install -y "$@"
      ;;
    *)
      cala_die "cannot install $* on this OS automatically; install it and run the installer again"
      ;;
  esac
}

# Prints the package that provides COMMAND on this OS family.
cala_package_for() {
  local command="$1" family="$2"
  case "$command:$family" in
    dig:debian) printf bind9-dnsutils ;;
    dig:rhel) printf bind-utils ;;
    ss:debian) printf iproute2 ;;
    ss:rhel) printf iproute ;;
    *) printf '%s' "$command" ;;
  esac
}

cala_has_ca_bundle() {
  [[ -s /etc/ssl/certs/ca-certificates.crt || -s /etc/pki/tls/certs/ca-bundle.crt ]]
}

cala_install_prerequisites() {
  local missing=() command
  for command in curl openssl dig jq unzip tar ss; do
    if ! command -v "$command" >/dev/null 2>&1; then
      missing+=("$(cala_package_for "$command" "$OS_FAMILY")")
    fi
  done
  cala_has_ca_bundle || missing+=(ca-certificates)
  if ((${#missing[@]} == 0)); then
    cala_ok "Prerequisites already installed"
    return 0
  fi
  cala_pkg_install "${missing[@]}"
  cala_ok "Prerequisites installed"
}

cala_docker_ready() {
  docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1
}

cala_install_docker() {
  if cala_docker_ready; then
    cala_ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || true) with Compose $(docker compose version --short 2>/dev/null || true) is already installed"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    if ! docker compose version >/dev/null 2>&1; then
      cala_pkg_install docker-compose-plugin
    fi
  else
    cala_info "Installing Docker with get.docker.com (this takes a minute or two)"
    cala_run "Downloading get.docker.com" curl -fsSL https://get.docker.com -o "$CALA_TMP/get-docker.sh"
    cala_run "Running Docker's install script" env CHANNEL=stable bash "$CALA_TMP/get-docker.sh"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    cala_run "Starting Docker" systemctl enable --now docker
  fi
  cala_docker_ready || cala_fail "Docker is installed but not working (docker info or docker compose failed)"
  cala_ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || true) installed"
}

# --- Caddy ---------------------------------------------------------------------------------------

CALA_CADDYFILE=/etc/caddy/Caddyfile
CALA_CADDY_MARKER="# Managed by Calagopus-Installer"

cala_install_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    cala_ok "Caddy is already installed"
    return 0
  fi
  case "$OS_FAMILY" in
    debian)
      if ((CALA_APT_UPDATED == 0)); then
        cala_run "Updating the package lists" env DEBIAN_FRONTEND=noninteractive apt-get update
        CALA_APT_UPDATED=1
      fi
      if apt-cache policy caddy 2>/dev/null | grep -q 'Candidate: [0-9]'; then
        cala_pkg_install caddy
      else
        cala_info "Caddy is not in this OS's repositories; adding Caddy's official repository"
        cala_pkg_install debian-keyring debian-archive-keyring apt-transport-https gnupg
        cala_run "Adding the Caddy signing key" bash -c \
          "curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
        cala_run "Adding the Caddy repository" curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o /etc/apt/sources.list.d/caddy-stable.list
        chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
        CALA_APT_UPDATED=0
        cala_pkg_install caddy
      fi
      ;;
    rhel)
      cala_pkg_install 'dnf-command(copr)'
      cala_run "Enabling the @caddy/caddy COPR repository" dnf copr enable -y @caddy/caddy
      cala_pkg_install caddy
      ;;
    *) cala_die "install Caddy yourself (https://caddyserver.com/docs/install) and run the installer again" ;;
  esac
}

# The Caddy site from https://calagopus.com/docs/panel/next-steps/reverse-proxy
cala_caddy_site() {
  local domain="$1"
  cat <<EOF
$CALA_CADDY_MARKER: Calagopus panel ($domain)
$domain {
    # Largest request body the proxy accepts, except under /api/remote/backups/
    @limited not path /api/remote/backups/*
    request_body @limited {
        max_size 128MiB
    }

    header {
        Referrer-Policy    "same-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=(), fullscreen=(self), clipboard-read=(self)"
    }

    reverse_proxy 127.0.0.1:8000
}
EOF
}

# True when the Caddyfile is missing, empty or still the package's default welcome page.
cala_caddyfile_is_default() {
  [[ ! -s "$1" ]] || grep -q 'root \* /usr/share/caddy' "$1"
}

# Prints the Caddyfile without the sites this installer added (marker line up to its closing brace).
cala_caddyfile_without_ours() {
  awk -v marker="$CALA_CADDY_MARKER" '
    index($0, marker) == 1 { skip = 1; next }
    skip && $0 == "}" { skip = 0; next }
    !skip { print }
  ' "$1"
}

cala_configure_caddy() {
  local domain="$1" backup
  mkdir -p "$(dirname "$CALA_CADDYFILE")"
  if [[ -f "$CALA_CADDYFILE" ]]; then
    backup="$CALA_CADDYFILE.calagopus-backup.$(date +%Y%m%d%H%M%S)"
    cp -a "$CALA_CADDYFILE" "$backup"
  fi
  if cala_caddyfile_is_default "$CALA_CADDYFILE"; then
    cala_caddy_site "$domain" >"$CALA_CADDYFILE"
  else
    cala_warn "$CALA_CADDYFILE already has other sites; adding the panel's site to it (backup: $backup)"
    {
      cala_caddyfile_without_ours "$backup"
      printf '\n'
      cala_caddy_site "$domain"
    } >"$CALA_CADDYFILE"
  fi
  cala_run "Validating the Caddyfile" caddy validate --config "$CALA_CADDYFILE" --adapter caddyfile
  cala_run "Starting Caddy" systemctl enable --now caddy
  cala_run "Reloading Caddy" systemctl reload caddy
}

# Removes the panel's site from the Caddyfile; stops Caddy when nothing else is left in it.
cala_remove_caddy_site() {
  [[ -f "$CALA_CADDYFILE" ]] && grep -q "^$CALA_CADDY_MARKER" "$CALA_CADDYFILE" || return 0
  cp -a "$CALA_CADDYFILE" "$CALA_CADDYFILE.calagopus-backup.$(date +%Y%m%d%H%M%S)"
  cala_caddyfile_without_ours "$CALA_CADDYFILE" >"$CALA_TMP/Caddyfile"
  cat "$CALA_TMP/Caddyfile" >"$CALA_CADDYFILE"
  if grep -qvE '^\s*(#.*)?$' "$CALA_CADDYFILE"; then
    cala_run "Reloading Caddy" systemctl reload caddy
  else
    cala_run "Stopping Caddy (no sites left)" systemctl disable --now caddy
  fi
  cala_ok "Removed the panel's site from $CALA_CADDYFILE"
}

# --- firewall ------------------------------------------------------------------------------------

# ufw writes ranges as 25570:25580, firewalld as 25570-25580.
cala_firewall_port_spec() {
  local port="$1" tool="$2"
  if [[ "$tool" == ufw ]]; then
    printf '%s' "${port/-/:}"
  else
    printf '%s' "$port"
  fi
}

# cala_configure_firewall "tcp ports" "game ports (tcp+udp, comma list)"
cala_configure_firewall() {
  local tcp_ports="$1" game_ports="${2// /}" port spec game=()
  [[ -n "$game_ports" ]] && IFS=, read -r -a game <<<"$game_ports"
  case "$OS_FAMILY" in
    debian)
      command -v ufw >/dev/null 2>&1 || cala_pkg_install ufw
      for port in $tcp_ports; do
        cala_run "ufw: allowing $port/tcp" ufw allow "$port/tcp"
      done
      for port in "${game[@]}"; do
        spec="$(cala_firewall_port_spec "$port" ufw)"
        cala_run "ufw: allowing $port/tcp+udp (game)" ufw allow "$spec/tcp"
        cala_run "ufw: allowing $port/udp (game)" ufw allow "$spec/udp"
      done
      cala_run "Enabling ufw" ufw --force enable
      ;;
    rhel)
      command -v firewall-cmd >/dev/null 2>&1 || cala_pkg_install firewalld
      cala_run "Starting firewalld" systemctl enable --now firewalld
      for port in $tcp_ports; do
        cala_run "firewalld: allowing $port/tcp" firewall-cmd --permanent --add-port="$port/tcp"
      done
      for port in "${game[@]}"; do
        spec="$(cala_firewall_port_spec "$port" firewalld)"
        cala_run "firewalld: allowing $port/tcp+udp (game)" firewall-cmd --permanent --add-port="$spec/tcp" --add-port="$spec/udp"
      done
      cala_run "Reloading firewalld" firewall-cmd --reload
      ;;
    *) cala_warn "no supported firewall tool for this OS; skipping the firewall" ;;
  esac
  cala_warn "Docker's published ports bypass the host firewall (https://docs.docker.com/engine/network/packet-filtering-firewalls/). Your provider's firewall is what really protects them."
}
