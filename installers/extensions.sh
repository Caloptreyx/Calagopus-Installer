# shellcheck shell=bash
# Caloptreyx themes and extensions: picker, download with checksum verification, and installation into a
# heavy-image panel the way the docs describe for Docker ("drop the file in and restart"):
# https://calagopus.com/docs/panel/extensions/installing-extensions

CALA_EXTENSION_PICKS=()
CALA_BUILD_BASELINE=0
CALA_EXIT_CODE=0

cala_manifest() {
  printf '%s' "${CALA_MANIFEST:-$CALA_ROOT/extensions.tsv}"
}

# Prints the manifest's entries without comments: key kind repo identifier name description (tab-separated).
cala_manifest_entries() {
  grep -vE '^[[:space:]]*(#|$)' "$(cala_manifest)"
}

# cala_manifest_field KEY COLUMN (1 key, 2 kind, 3 repo, 4 identifier, 5 name, 6 description)
cala_manifest_field() {
  cala_manifest_entries | awk -F'\t' -v key="$1" -v col="$2" '$1 == key { print $col; exit }'
}

# Turns "mint, webhooks" / "all" / "none" into unique, known keys (one per line). Fails on an unknown key.
cala_resolve_extension_keys() {
  local input="${1//,/ }" key known seen=" "
  known=" $(cala_manifest_entries | cut -f1 | tr '\n' ' ') "
  if [[ "${input// /}" == all ]]; then
    input="$known"
  elif [[ "${input// /}" == none || -z "${input// /}" ]]; then
    return 0
  fi
  for key in $input; do
    key="${key,,}"
    if [[ "$known" != *" $key "* ]]; then
      printf 'unknown extension: %s\n' "$key" >&2
      return 1
    fi
    [[ "$seen" == *" $key "* ]] && continue
    seen+="$key "
    printf '%s\n' "$key"
  done
}

# Prints the themes among the given keys.
cala_themes_in() {
  local key
  for key in "$@"; do
    if [[ "$(cala_manifest_field "$key" 2)" == theme ]]; then
      printf '%s\n' "$key"
    fi
  done
  return 0
}

# Keeps only THEME among the themes: cala_keep_one_theme THEME KEY...
cala_keep_one_theme() {
  local theme="$1" key
  shift
  for key in "$@"; do
    if [[ "$(cala_manifest_field "$key" 2)" != theme || "$key" == "$theme" ]]; then
      printf '%s\n' "$key"
    fi
  done
}

cala_extension_memory_report() {
  local available swap
  available="$(cala_meminfo_mb MemAvailable)"
  swap="$(cala_meminfo_mb SwapFree)"
  if cala_extension_memory_ok "$available" "$swap"; then
    cala_ok "Memory for the build: ${available} MB available RAM + ${swap} MB free swap"
    return 0
  fi
  cala_warn "Only ${available} MB available RAM + ${swap} MB free swap. Extension builds need about 4 GB;"
  cala_warn "with less, the build is killed by the kernel. Add swap first, for example:"
  cala_warn "  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
  return 1
}

# cala_extension_questions [ask_first=yes]: fills CALA_EXTENSION_PICKS.
cala_extension_questions() {
  local ask_first="${1:-yes}"
  cala_step "Caloptreyx themes and extensions (optional)"
  if ! cala_is_set CALA_EXTENSIONS; then
    ((CALA_INTERACTIVE == 1)) || return 0
    if [[ "$ask_first" == yes ]]; then
      cala_info "Free themes and extensions from Caloptreyx (unofficial, https://github.com/Caloptreyx)."
      local CALA_WANT_EXTENSIONS
      cala_ask_yes_no CALA_WANT_EXTENSIONS "Install any of them?" n
      [[ "$CALA_WANT_EXTENSIONS" == yes ]] || return 0
    fi
  fi
  local picks=() resolved
  if cala_is_set CALA_EXTENSIONS; then
    resolved="$(cala_resolve_extension_keys "$CALA_EXTENSIONS")" ||
      cala_die "CALA_EXTENSIONS: unknown extension (known: $(cala_manifest_entries | cut -f1 | tr '\n' ' '))"
    [[ -n "$resolved" ]] || return 0
    mapfile -t picks <<<"$resolved"
  fi

  cala_warn "Extensions need the heavy panel image: they are compiled into the panel (Rust and the frontend)"
  cala_warn "inside the container. The build takes several minutes and needs about 4 GB of RAM (swap counts)."
  if ! cala_extension_memory_report; then
    cala_ask_yes_no CALA_LOW_MEMORY_OK "Build the extensions anyway?" n
    if [[ "$CALA_LOW_MEMORY_OK" != yes ]]; then
      cala_warn "Skipping the extensions. You can add them later with the 'extensions' action once there is more memory."
      return 0
    fi
  fi

  if ((${#picks[@]} == 0)); then
    local entries=() i line answer
    mapfile -t entries < <(cala_manifest_entries)
    printf '\n' >&2
    for i in "${!entries[@]}"; do
      IFS=$'\t' read -r _ kind _ _ name description <<<"${entries[$i]}"
      printf '  %2d) %-28s %s%s\n' "$((i + 1))" "$name" "$([[ "$kind" == theme ]] && printf '[theme] ')" "$description" >&2
    done
    printf '  Only one theme can be active.\n' >&2
    while true; do
      answer="$(cala_read "  Numbers to install (e.g. 1 4 9), 'all', or empty for none: ")"
      answer="${answer//,/ }"
      [[ -z "${answer// /}" ]] && return 0
      if [[ "${answer// /}" == all ]]; then
        mapfile -t picks < <(cala_resolve_extension_keys all)
        break
      fi
      picks=()
      local valid=1
      for i in $answer; do
        if [[ "$i" =~ ^[0-9]+$ ]] && ((i >= 1 && i <= ${#entries[@]})); then
          line="${entries[$((i - 1))]}"
          picks+=("${line%%$'\t'*}")
        else
          valid=0
        fi
      done
      ((valid == 1)) && break
      cala_warn "use numbers from the list"
    done
    mapfile -t picks < <(cala_resolve_extension_keys "${picks[*]}")
  fi

  local themes=()
  mapfile -t themes < <(cala_themes_in "${picks[@]}")
  if ((${#themes[@]} > 1)); then
    local options=() theme
    for theme in "${themes[@]}"; do
      options+=("$theme|$(cala_manifest_field "$theme" 5)")
    done
    cala_info "Only one theme can be active at a time."
    if ((CALA_INTERACTIVE == 0)) && ! cala_is_set CALA_THEME; then
      cala_die "CALA_EXTENSIONS names more than one theme; set CALA_THEME to the one to install"
    fi
    cala_choose CALA_THEME "Which theme do you want?" "${themes[0]}" "${options[@]}"
    mapfile -t picks < <(cala_keep_one_theme "$CALA_THEME" "${picks[@]}")
  fi
  CALA_EXTENSION_PICKS=("${picks[@]}")
  cala_ok "Selected: ${CALA_EXTENSION_PICKS[*]}"
}

# --- download and verify -------------------------------------------------------------------------

cala_github_api() {
  local url="$1" auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL --max-time 30 "${auth[@]}" -H 'Accept: application/vnd.github+json' "$url"
}

# Reads package_name from the Metadata.toml inside a .c7s.zip.
cala_archive_package_name() {
  unzip -p "$1" Metadata.toml 2>/dev/null | sed -nE 's/^[[:space:]]*package_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | head -n1
}

cala_extension_download() {
  local key="$1" repo identifier asset release="" tag="latest" zip_url sha_url digest="" expected="" actual file package
  repo="$(cala_manifest_field "$key" 3)"
  identifier="$(cala_manifest_field "$key" 4)"
  asset="$identifier.c7s.zip"
  file="$CALA_TMP/extensions/$asset"
  mkdir -p "$CALA_TMP/extensions"

  zip_url="https://github.com/Caloptreyx/$repo/releases/latest/download/$asset"
  sha_url="$zip_url.sha256"
  if release="$(cala_github_api "https://api.github.com/repos/Caloptreyx/$repo/releases/latest" 2>/dev/null)"; then
    tag="$(jq -r '.tag_name' <<<"$release")"
    jq -e --arg a "$asset" '.assets[] | select(.name == $a)' <<<"$release" >/dev/null ||
      cala_fail "$repo $tag has no $asset"
    zip_url="https://github.com/Caloptreyx/$repo/releases/download/$tag/$asset"
    sha_url="$zip_url.sha256"
    digest="$(jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .digest // ""' <<<"$release")"
    jq -e --arg a "$asset.sha256" '.assets[] | select(.name == $a)' <<<"$release" >/dev/null || sha_url=""
  fi

  cala_run "Downloading $asset ($repo $tag)" curl -fsSL --retry 3 "$zip_url" -o "$file"
  if [[ -n "$sha_url" ]] && expected="$(curl -fsSL --retry 3 "$sha_url" 2>/dev/null | awk '{ print $1; exit }')" && [[ -n "$expected" ]]; then
    :
  elif [[ "$digest" == sha256:* ]]; then
    expected="${digest#sha256:}"
  else
    expected=""
  fi
  actual="$(sha256sum "$file" | awk '{ print $1 }')"
  if [[ -n "$expected" ]]; then
    [[ "${expected,,}" == "$actual" ]] || cala_fail "$asset: checksum mismatch (expected $expected, got $actual)"
    cala_ok "$asset $tag: sha256 verified"
  else
    cala_warn "$asset $tag: the release publishes no checksum, so the download is not verified (sha256 $actual)"
  fi

  package="$(cala_archive_package_name "$file")"
  [[ "${package//./_}" == "$identifier" ]] ||
    cala_fail "$asset contains package '${package:-none}', expected ${identifier//_/.}"
}

cala_extensions_download() {
  local key
  for key in "${CALA_EXTENSION_PICKS[@]}"; do
    cala_extension_download "$key"
  done
}

# --- install into the panel ----------------------------------------------------------------------

cala_latest_build_id() {
  local builds="$1/build/binaries/.state/builds" id max=0
  [[ -d "$builds" ]] || {
    printf 0
    return 0
  }
  for id in "$builds"/*; do
    id="${id##*/}"
    if [[ "$id" =~ ^[0-9]+$ ]] && ((id > max)); then
      max="$id"
    fi
  done
  printf '%s' "$max"
}

# Copies the downloaded archives into build/extensions as <identifier>.c7s.zip. Returns 1 when every archive
# was already there unchanged (nothing to build).
cala_extensions_stage() {
  local dir="$1" key identifier target changed=0
  mkdir -p "$dir/build/extensions"
  CALA_BUILD_BASELINE="$(cala_latest_build_id "$dir")"
  for key in "${CALA_EXTENSION_PICKS[@]}"; do
    identifier="$(cala_manifest_field "$key" 4)"
    target="$dir/build/extensions/$identifier.c7s.zip"
    if [[ -f "$target" ]] && cmp -s "$target" "$CALA_TMP/extensions/$identifier.c7s.zip"; then
      cala_info "$identifier is already installed in this version"
      continue
    fi
    cp "$CALA_TMP/extensions/$identifier.c7s.zip" "$target"
    changed=1
  done
  cala_ok "Extensions placed in $dir/build/extensions"
  ((changed == 1))
}

# Waits for the heavy image's supervisor to finish a build newer than the baseline and checks that it
# compiled every pick in.
cala_extensions_wait_build() {
  local dir="$1" timeout="${CALA_EXTENSION_TIMEOUT:-3600}" waited=0 builds id record="" log state key package
  builds="$dir/build/binaries/.state/builds"
  cala_info "The panel compiles the extensions now. This takes several minutes; the panel keeps running meanwhile."
  while ((waited < timeout)); do
    id="$(cala_latest_build_id "$dir")"
    if ((id > CALA_BUILD_BASELINE)) && [[ -s "$builds/$id/build.json" ]]; then
      record="$builds/$id/build.json"
      break
    fi
    sleep 10
    waited=$((waited + 10))
    if ((waited % 60 == 0)); then
      log="$builds/$id/build.log"
      if ((id > CALA_BUILD_BASELINE)) && [[ -f "$log" ]]; then
        cala_info "building (${waited}s): $(grep -E 'Compiling|Building|vite|pnpm' "$log" | tail -n1 | cut -c1-100)"
      else
        cala_info "waiting for the build to start (${waited}s)"
      fi
    fi
  done
  if [[ -z "$record" ]]; then
    cala_compose_logs_to_log "$dir"
    cala_error "the extension build did not finish within ${timeout}s. The panel runs without the new extensions."
    cala_info "Build logs: Admin -> Extensions -> View build logs, or $builds/"
    CALA_EXIT_CODE=1
    return 0
  fi

  state="$(jq -r '.state' "$record")"
  if [[ "$state" != succeeded ]]; then
    cala_error "the extension build failed: $(jq -r '.failure_reason // "no reason given"' "$record")"
    local failed
    failed="$(jq -r '.failed_extensions | join(", ")' "$record")"
    [[ -n "$failed" ]] && cala_error "it blames: $failed"
    tail -n 30 "$builds/$id/build.log" 2>/dev/null | sed 's/^/  | /' >&2 || true
    cala_info "The panel keeps running without the new extensions. Full log: $builds/$id/build.log"
    CALA_EXIT_CODE=1
    return 0
  fi
  for key in "${CALA_EXTENSION_PICKS[@]}"; do
    package="$(cala_manifest_field "$key" 4)"
    package="${package//_/.}"
    if ! jq -e --arg p "$package" '.verified_extensions | any(.package_name == $p)' "$record" >/dev/null; then
      cala_error "the build succeeded but does not contain $package"
      CALA_EXIT_CODE=1
    fi
  done
  cala_ok "Extensions built (build $id): $(jq -r '[.verified_extensions[] | "\(.package_name) \(.version)"] | join(", ")' "$record")"
  cala_wait_http "$CALA_PANEL_LOCAL" 300 || cala_warn "the panel did not answer after switching to the new build"
}

# The `extensions` action: add extensions to an existing heavy-image panel.
cala_extensions_action() {
  local kind dir="" line
  while read -r kind line; do
    if [[ "$kind" == aio || "$kind" == panel ]]; then
      dir="$line"
      break
    fi
  done < <(cala_find_installs)
  [[ -n "$dir" ]] || cala_die "no Calagopus panel found (looked in /opt/calagopus-panel and the installer's registry; set CALA_PANEL_DIR)"
  CALA_PANEL_DIR="$dir"
  cala_step "Extensions for the panel in $dir"
  if ! cala_compose_is_heavy "$dir/compose.yml"; then
    cala_die "this panel runs $(cala_compose_panel_image "$dir/compose.yml"), not the heavy image that extensions need. Switch first: https://calagopus.com/docs/panel/extensions/switching-to-the-heavy-image"
  fi
  CALA_EXTENSION_PICKS=()
  cala_extension_questions no
  ((${#CALA_EXTENSION_PICKS[@]} > 0)) || cala_die "no extensions selected"
  local picked_theme other
  picked_theme="$(cala_themes_in "${CALA_EXTENSION_PICKS[@]}")"
  if [[ -n "$picked_theme" ]]; then
    for other in $(cala_manifest_entries | awk -F'\t' '$2 == "theme" { print $1 }'); do
      if [[ "$other" != "$picked_theme" && -f "$dir/build/extensions/$(cala_manifest_field "$other" 4).c7s.zip" ]]; then
        cala_warn "This panel already has the $(cala_manifest_field "$other" 5). Only one theme can be active: disable one under Admin -> Extensions afterwards."
      fi
    done
  fi
  cala_confirm_start
  cala_extensions_download
  if ! cala_extensions_stage "$dir"; then
    cala_ok "Nothing to do: every selected extension is already installed in its latest version"
    return 0
  fi
  cala_run "Restarting the panel so it picks up the extensions" cala_compose "$dir" restart web
  cala_extensions_wait_build "$dir"
  return "$CALA_EXIT_CODE"
}
