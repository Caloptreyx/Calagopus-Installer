# shellcheck shell=bash
# Input validation, OS detection, requirement checks and network/DNS checks.
# The validators and verdict functions are pure (no system access) and covered by tests/.

# --- validators ----------------------------------------------------------------------------------

cala_valid_email() {
  [[ ${#1} -le 254 && "$1" =~ ^[^@[:space:]\"\'\\]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# The panel's own rule for usernames: 3 to 48 letters, digits or underscores.
cala_valid_username() {
  [[ "$1" =~ ^[A-Za-z0-9_]{3,48}$ ]]
}

# The panel accepts 8 to 512 characters.
cala_valid_password() {
  [[ ${#1} -ge 8 && ${#1} -le 512 && "$1" != *$'\n'* ]]
}

cala_valid_domain() {
  local domain="${1,,}"
  [[ ${#domain} -le 253 && "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]
}

cala_valid_domain_or_empty() {
  [[ -z "$1" ]] || cala_valid_domain "$1"
}

cala_valid_ipv4() {
  local ip="$1" octet octets=()
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$ip"
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^(0|[1-9][0-9]*)$ ]] && ((octet <= 255)) || return 1
  done
}

cala_valid_ipv6() {
  [[ "$1" == *:* && "$1" =~ ^[0-9A-Fa-f:]+$ && ${#1} -le 39 ]]
}

cala_valid_port() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (($1 <= 65535))
}

# Comma-separated ports and ranges: 25565,25570-25580
cala_valid_port_list() {
  local list="${1// /}" item items=() low high
  [[ -n "$list" ]] || return 1
  IFS=, read -r -a items <<<"$list"
  [[ "${list: -1}" != , ]] || return 1
  for item in "${items[@]}"; do
    if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      low="${BASH_REMATCH[1]}"
      high="${BASH_REMATCH[2]}"
      cala_valid_port "$low" && cala_valid_port "$high" && ((low <= high)) || return 1
    else
      cala_valid_port "$item" || return 1
    fi
  done
}

cala_valid_port_list_or_empty() {
  [[ -z "${1// /}" ]] || cala_valid_port_list "$1"
}

cala_valid_timezone() {
  [[ "$1" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || return 1
  [[ ! -d /usr/share/zoneinfo || -f "/usr/share/zoneinfo/$1" ]]
}

# Absolute directory without spaces or shell specials, and not a system directory.
cala_valid_install_dir() {
  [[ "$1" =~ ^/[A-Za-z0-9._/-]+$ && "$1" != */ && "$1" != *..* ]] || return 1
  case "$1" in
    /bin | /boot | /dev | /etc | /home | /lib | /lib64 | /opt | /proc | /root | /run | /sbin | /srv | /sys | /tmp | /usr | /var) return 1 ;;
  esac
}

cala_valid_url() {
  [[ "$1" =~ ^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ && "$1" != */ ]]
}

cala_valid_url_or_empty() {
  [[ -z "$1" ]] || cala_valid_url "$1"
}

cala_valid_enroll_code() {
  [[ "$1" =~ ^[A-Za-z0-9_-]{4,256}$ ]]
}

cala_valid_enroll_code_or_empty() {
  [[ -z "$1" ]] || cala_valid_enroll_code "$1"
}

# --- IP helpers ----------------------------------------------------------------------------------

cala_ipv4_to_int() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  printf '%d' "$(((a << 24) | (b << 16) | (c << 8) | d))"
}

cala_ipv4_in_cidr() {
  local ip="$1" cidr="$2" net bits mask
  net="${cidr%/*}"
  bits="${cidr#*/}"
  ((bits == 0)) && return 0
  mask=$(((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF))
  ((($(cala_ipv4_to_int "$ip") & mask) == ($(cala_ipv4_to_int "$net") & mask)))
}

# Cloudflare's published IPv4 ranges (https://www.cloudflare.com/ips-v4).
CALA_CLOUDFLARE_V4=(
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18
  190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
  104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
)

cala_is_cloudflare_ipv4() {
  local cidr
  for cidr in "${CALA_CLOUDFLARE_V4[@]}"; do
    cala_ipv4_in_cidr "$1" "$cidr" && return 0
  done
  return 1
}

cala_is_private_ipv4() {
  local cidr
  for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16; do
    cala_ipv4_in_cidr "$1" "$cidr" && return 0
  done
  return 1
}

# cala_dns_verdict "A records" "AAAA records" server_ipv4 server_ipv6
# Prints one finding per line: ok, no_a, a_mismatch <ip>, cloudflare <ip>, stray_aaaa <ip>, aaaa_mismatch <ip>.
cala_dns_verdict() {
  local a_records="$1" aaaa_records="$2" server_v4="$3" server_v6="$4" ip found=0 problems=0
  for ip in $a_records; do
    found=1
    if [[ "$ip" == "$server_v4" ]]; then
      continue
    fi
    problems=1
    if cala_is_cloudflare_ipv4 "$ip"; then
      printf 'cloudflare %s\n' "$ip"
    else
      printf 'a_mismatch %s\n' "$ip"
    fi
  done
  if ((found == 0)); then
    printf 'no_a\n'
    problems=1
  fi
  for ip in $aaaa_records; do
    if [[ -z "$server_v6" ]]; then
      printf 'stray_aaaa %s\n' "$ip"
      problems=1
    elif [[ "${ip,,}" != "${server_v6,,}" ]]; then
      printf 'aaaa_mismatch %s\n' "$ip"
      problems=1
    fi
  done
  if ((problems == 0)); then
    printf 'ok\n'
  fi
  return 0
}

# --- OS detection --------------------------------------------------------------------------------

# cala_os_release_value FILE KEY: reads one key without executing the file.
cala_os_release_value() {
  local file="$1" key="$2" line value
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$key="* ]]; then
      value="${line#*=}"
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
      printf '%s' "$value"
      return 0
    fi
  done <"$file"
  return 0
}

# Prints debian or rhel, or nothing for an unknown family.
cala_os_family() {
  case "$1" in
    ubuntu | debian) printf debian ;;
    rocky | almalinux | rhel | centos) printf rhel ;;
  esac
}

# cala_os_supported ID VERSION_ID ARCH: 0 when this exact combination is supported.
cala_os_supported() {
  local id="$1" version="$2" arch="$3"
  case "$arch" in
    x86_64 | amd64 | aarch64 | arm64) ;;
    *) return 1 ;;
  esac
  case "$id" in
    ubuntu) [[ "$version" == 22.04 || "$version" == 24.04 || "$version" == 26.04 ]] ;;
    debian) [[ "${version%%.*}" == 12 || "${version%%.*}" == 13 ]] ;;
    rocky | almalinux) [[ "${version%%.*}" == 9 || "${version%%.*}" == 10 ]] ;;
    *) return 1 ;;
  esac
}

cala_detect_os() {
  local file="${CALA_OS_RELEASE:-/etc/os-release}"
  [[ -r "$file" ]] || cala_die "cannot read $file, so the OS is unknown"
  OS_ID="$(cala_os_release_value "$file" ID)"
  OS_VERSION="$(cala_os_release_value "$file" VERSION_ID)"
  OS_NAME="$(cala_os_release_value "$file" PRETTY_NAME)"
  OS_ARCH="$(uname -m)"
  OS_FAMILY="$(cala_os_family "$OS_ID")"
  if [[ -z "$OS_FAMILY" ]]; then
    local like
    like="$(cala_os_release_value "$file" ID_LIKE)"
    case " $like " in
      *" debian "* | *" ubuntu "*) OS_FAMILY=debian ;;
      *" rhel "* | *" fedora "* | *" centos "*) OS_FAMILY=rhel ;;
    esac
  fi
}

cala_check_os() {
  cala_detect_os
  if cala_os_supported "$OS_ID" "$OS_VERSION" "$OS_ARCH"; then
    cala_ok "OS: ${OS_NAME:-$OS_ID $OS_VERSION} ($OS_ARCH)"
    return 0
  fi
  local message="${OS_NAME:-$OS_ID $OS_VERSION} on $OS_ARCH is not supported. Supported: Ubuntu 22.04/24.04/26.04, Debian 12/13, Rocky Linux and AlmaLinux 9/10, on x86_64 or ARM64."
  if cala_truthy "${CALA_SKIP_OS_CHECK:-no}"; then
    cala_warn "$message Continuing because CALA_SKIP_OS_CHECK is set."
    [[ -n "$OS_FAMILY" ]] || cala_warn "unknown package manager family: prerequisites must already be installed"
    return 0
  fi
  cala_die "$message Set CALA_SKIP_OS_CHECK=yes to try anyway."
}

# Prints the virtualization type (none, kvm, lxc, openvz, docker, ...).
cala_detect_virt() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt 2>/dev/null || true
    return 0
  fi
  if [[ -e /proc/user_beancounters && ! -e /proc/bc ]]; then
    printf openvz
  elif [[ -f /.dockerenv ]]; then
    printf docker
  elif grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then
    printf lxc
  else
    printf unknown
  fi
}

cala_check_virt() {
  local virt
  virt="$(cala_detect_virt)"
  case "$virt" in
    openvz)
      cala_warn "OpenVZ detected. Docker usually does not run on OpenVZ; a KVM VPS is strongly recommended."
      ;;
    lxc | lxc-libvirt)
      cala_warn "LXC container detected. Docker inside LXC needs nesting (and keyctl) enabled on the host, and Wings' resource limits may not work."
      ;;
    *) cala_info "Virtualization: ${virt:-unknown}" ;;
  esac
}

# --- requirements --------------------------------------------------------------------------------

cala_meminfo_mb() {
  awk -v key="$1:" '$1 == key { printf "%d", $2 / 1024; found = 1 } END { if (!found) printf "0" }' /proc/meminfo
}

# Free space in MB on the filesystem that holds PATH (or its nearest existing parent).
cala_disk_free_mb() {
  local path="$1"
  while [[ ! -e "$path" && "$path" != / ]]; do
    path="$(dirname "$path")"
  done
  df -Pm "$path" | awk 'NR == 2 { print $4 }'
}

# cala_requirements_verdict RAM_MB DISK_MB HEAVY(yes|no): prints "ok", "warn <text>" or "fail <text>" lines.
cala_requirements_verdict() {
  local ram="$1" disk="$2" heavy="$3" min_disk=5000 rec_disk=20000
  if [[ "$heavy" == yes ]]; then
    min_disk=15000
    rec_disk=30000
  fi
  if ((ram < 900)); then
    printf 'fail %s\n' "${ram} MB RAM is below the 1 GB minimum"
  elif ((ram < 1900)); then
    printf 'warn %s\n' "${ram} MB RAM: the panel runs, but leaves little for game servers (2 GB+ recommended)"
  fi
  if ((disk < min_disk)); then
    printf 'fail %s\n' "${disk} MB free disk is below the ${min_disk} MB this install needs"
  elif ((disk < rec_disk)); then
    printf 'warn %s\n' "${disk} MB free disk: ${rec_disk} MB+ recommended for images, backups and games"
  fi
  printf 'ok\n'
}

cala_check_requirements() {
  local dir="$1" heavy="$2" ram disk line failed=0
  ram="$(cala_meminfo_mb MemTotal)"
  disk="$(cala_disk_free_mb "$dir")"
  cala_info "Memory: ${ram} MB RAM, $(cala_meminfo_mb SwapTotal) MB swap; free disk for $dir: ${disk} MB"
  while IFS= read -r line; do
    case "$line" in
      warn\ *) cala_warn "${line#warn }" ;;
      fail\ *)
        cala_error "${line#fail }"
        failed=1
        ;;
    esac
  done < <(cala_requirements_verdict "$ram" "$disk" "$heavy")
  if ((failed == 1)); then
    if cala_truthy "${CALA_SKIP_REQUIREMENTS:-no}"; then
      cala_warn "continuing below the minimum because CALA_SKIP_REQUIREMENTS is set"
    else
      cala_die "the server is below the minimum requirements (set CALA_SKIP_REQUIREMENTS=yes to continue anyway)"
    fi
  fi
}

# Extension builds compile Rust inside the panel container: about 4 GB RAM (swap counts).
cala_extension_memory_ok() {
  local ram="$1" swap="$2"
  ((ram + swap >= 3800))
}

# --- network -------------------------------------------------------------------------------------

cala_detect_public_ip() {
  local family="$1" url ip
  for url in https://api.ipify.org https://ifconfig.co/ip https://icanhazip.com; do
    if [[ "$family" == 6 ]]; then
      url="${url/api.ipify.org/api6.ipify.org}"
    fi
    ip="$(curl "-$family" -fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]')" || true
    if [[ "$family" == 4 ]] && cala_valid_ipv4 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
    if [[ "$family" == 6 ]] && cala_valid_ipv6 "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 0
}

# The local address the default route uses: a fallback when no public IP can be detected.
cala_detect_local_ipv4() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }'
}

cala_dns_records() {
  local type="$1" domain="$2"
  dig +short +time=3 +tries=2 "$type" "$domain" 2>/dev/null | while IFS= read -r line; do
    if [[ "$type" == A ]] && cala_valid_ipv4 "$line"; then
      printf '%s ' "$line"
    elif [[ "$type" == AAAA ]] && cala_valid_ipv6 "$line"; then
      printf '%s ' "$line"
    fi
  done
}

# Checks the domain against this server; returns 1 when something needs the user's attention.
cala_check_dns() {
  local domain="$1" server_v4="$2" server_v6="$3" a aaaa finding problems=0
  a="$(cala_dns_records A "$domain")"
  aaaa="$(cala_dns_records AAAA "$domain")"
  cala_info "DNS for $domain: A ${a:-none}, AAAA ${aaaa:-none}; this server: ${server_v4:-unknown} ${server_v6}"
  while IFS= read -r finding; do
    case "$finding" in
      ok) cala_ok "$domain points at this server" ;;
      no_a)
        cala_warn "$domain has no A record. Create one pointing at ${server_v4:-this server}."
        problems=1
        ;;
      a_mismatch\ *)
        cala_warn "$domain has an A record ${finding#* } that is not this server (${server_v4:-unknown})."
        problems=1
        ;;
      cloudflare\ *)
        cala_warn "$domain resolves to Cloudflare (${finding#* }): set the record to DNS only (grey cloud) so Caddy can get a certificate."
        problems=1
        ;;
      stray_aaaa\ *)
        cala_warn "$domain has an AAAA record ${finding#* }, but this server has no working IPv6. Remove the AAAA record."
        problems=1
        ;;
      aaaa_mismatch\ *)
        cala_warn "$domain has an AAAA record ${finding#* } that is not this server's IPv6 ($server_v6)."
        problems=1
        ;;
    esac
  done < <(cala_dns_verdict "$a" "$aaaa" "$server_v4" "$server_v6")
  return "$problems"
}

cala_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    [[ -n "$(ss -Hltn "sport = :$port" 2>/dev/null)" ]]
  else
    return 1
  fi
}

# Parses `sshd -T` output and SSH_CONNECTION into a unique, space-separated port list.
cala_ssh_ports_from() {
  local sshd_output="$1" connection="$2" ports=() port
  if [[ -n "$connection" ]]; then
    port="$(awk '{ print $4 }' <<<"$connection")"
    cala_valid_port "$port" && ports+=("$port")
  fi
  while read -r key port; do
    if [[ "${key,,}" == port ]] && cala_valid_port "$port"; then
      ports+=("$port")
    fi
  done <<<"$sshd_output"
  ((${#ports[@]} > 0)) || ports=(22)
  printf '%s\n' "${ports[@]}" | sort -un | tr '\n' ' ' | sed 's/ $//'
}

cala_detect_ssh_ports() {
  local sshd_output=""
  if command -v sshd >/dev/null 2>&1; then
    sshd_output="$(sshd -T 2>/dev/null || true)"
  fi
  cala_ssh_ports_from "$sshd_output" "${SSH_CONNECTION:-}"
}

cala_detect_timezone() {
  local tz=""
  if command -v timedatectl >/dev/null 2>&1; then
    tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  fi
  if [[ -z "$tz" && -L /etc/localtime ]]; then
    tz="$(readlink /etc/localtime)"
    tz="${tz#*zoneinfo/}"
  fi
  if [[ -z "$tz" && -r /etc/timezone ]]; then
    tz="$(head -n1 /etc/timezone)"
  fi
  if cala_valid_timezone "$tz"; then
    printf '%s' "$tz"
  else
    printf UTC
  fi
}
