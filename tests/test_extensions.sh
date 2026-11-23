# shellcheck shell=bash
# Extension manifest, picker resolution and build bookkeeping.

test_manifest_shape() {
  local line key kind repo identifier name description n=0
  while IFS= read -r line; do
    n=$((n + 1))
    IFS=$'\t' read -r key kind repo identifier name description <<<"$line"
    [[ "$key" =~ ^[a-z0-9]+$ ]] || fail "bad key '$key'"
    [[ "$kind" == theme || "$kind" == extension ]] || fail "$key: bad kind '$kind'"
    cala_valid_repo_name "$repo" || fail "$key: bad repository '$repo'"
    [[ "$identifier" =~ ^(dev|com)_caloptreyx_[a-z0-9]+$ ]] || fail "$key: identifier '$identifier' is not a Caloptreyx package"
    [[ -n "$name" && -n "$description" ]] || fail "$key: name or description missing"
    [[ "$(awk -F'\t' '{ print NF }' <<<"$line")" == 6 ]] || fail "$key: expected 6 columns"
  done < <(cala_manifest_entries)
  ((n >= 2)) || fail "manifest has only $n entries"
  assert_eq "$(cala_manifest_entries | cut -f1 | sort | uniq -d)" "" "duplicate keys"
  assert_eq "$(cala_manifest_entries | cut -f4 | sort | uniq -d)" "" "duplicate identifiers"
  assert_eq "$(cala_manifest_field mint 2)" theme
  assert_eq "$(cala_manifest_field zoron 2)" theme
}

cala_valid_repo_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ && "$1" != . && "$1" != .. ]]
}

test_resolve_extension_keys() {
  assert_eq "$(cala_resolve_extension_keys "webhooks, mint webhooks")" "$(printf 'webhooks\nmint')"
  assert_eq "$(cala_resolve_extension_keys "Webhooks")" webhooks
  assert_eq "$(cala_resolve_extension_keys none)" ""
  assert_eq "$(cala_resolve_extension_keys "")" ""
  assert_eq "$(cala_resolve_extension_keys all | wc -l)" "$(cala_manifest_entries | wc -l)"
  assert_fails cala_resolve_extension_keys "webhooks nosuchthing"
}

test_one_theme_only() {
  assert_eq "$(cala_themes_in webhooks mint zoron)" "$(printf 'mint\nzoron')"
  assert_eq "$(cala_themes_in webhooks)" ""
  assert_eq "$(cala_keep_one_theme zoron mint webhooks zoron)" "$(printf 'webhooks\nzoron')"
}

test_noninteractive_extension_questions() {
  local out
  # Two themes without CALA_THEME is refused.
  out="$(CALA_INTERACTIVE=0 CALA_EXTENSIONS=mint,zoron CALA_LOW_MEMORY_OK=yes cala_extension_questions 2>&1)" &&
    fail "two themes accepted"
  assert_contains "$out" CALA_THEME
  # CALA_THEME picks one; low memory is overridden.
  out="$(
    CALA_INTERACTIVE=0 CALA_EXTENSIONS=mint,zoron,webhooks CALA_THEME=zoron CALA_LOW_MEMORY_OK=yes cala_extension_questions >/dev/null 2>&1
    printf '%s ' "${CALA_EXTENSION_PICKS[@]}"
  )"
  assert_eq "$out" "zoron webhooks "
  # Not asked and not set: nothing.
  out="$(
    unset CALA_EXTENSIONS
    CALA_INTERACTIVE=0 cala_extension_questions >/dev/null 2>&1
    printf '%s' "${#CALA_EXTENSION_PICKS[@]}"
  )"
  assert_eq "$out" 0
}

test_latest_build_id() {
  local dir="$WORK/panel-builds"
  assert_eq "$(cala_latest_build_id "$dir")" 0
  mkdir -p "$dir/build/binaries/.state/builds/"{3,12,9,tmp}
  assert_eq "$(cala_latest_build_id "$dir")" 12
}

test_archive_package_name() {
  command -v zip >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || return 0
  local dir="$WORK/archive"
  mkdir -p "$dir"
  printf 'package_name = "dev.caloptreyx.webhooks"\nname = "Webhooks"\npanel_version = ">=1.2.0"\n' >"$dir/Metadata.toml"
  if command -v zip >/dev/null 2>&1; then
    (cd "$dir" && zip -q test.c7s.zip Metadata.toml)
  else
    python3 -c "import zipfile; z = zipfile.ZipFile('$dir/test.c7s.zip', 'w'); z.write('$dir/Metadata.toml', 'Metadata.toml'); z.close()"
  fi
  command -v unzip >/dev/null 2>&1 || return 0
  assert_eq "$(cala_archive_package_name "$dir/test.c7s.zip")" dev.caloptreyx.webhooks
}
