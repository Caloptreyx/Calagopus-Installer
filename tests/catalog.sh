#!/usr/bin/env bash
# Checks extensions.tsv against the Caloptreyx organization: every Caloptreyx extension archive
# (dev_caloptreyx_* / com_caloptreyx_*) in a latest release must be listed, and every listed entry must have
# its archive in its repository's latest release. Uses GITHUB_TOKEN when set. Needs network.
set -euo pipefail

CALA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$CALA_ROOT/extensions.tsv"
auth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

api() {
  curl -fsSL --retry 3 "${auth[@]}" -H 'Accept: application/vnd.github+json' "$1"
}

found="$(mktemp)"
trap 'rm -f "$found"' EXIT
page=1
while :; do
  repos="$(api "https://api.github.com/orgs/Caloptreyx/repos?type=public&per_page=100&page=$page" |
    jq -r '.[] | select((.archived | not) and (.fork | not)) | .name')"
  [[ -n "$repos" ]] || break
  for repo in $repos; do
    release="$(api "https://api.github.com/repos/Caloptreyx/$repo/releases/latest" 2>/dev/null)" || continue
    jq -r --arg repo "$repo" '.assets[].name | select(test("^(dev|com)_caloptreyx_[a-z0-9]+\\.c7s\\.zip$")) | "\($repo)\t\(sub("\\.c7s\\.zip$"; ""))"' \
      <<<"$release" >>"$found"
  done
  page=$((page + 1))
done

failed=0
while IFS=$'\t' read -r repo identifier; do
  if ! grep -vE '^\s*(#|$)' "$manifest" | awk -F'\t' -v r="$repo" -v i="$identifier" '$3 == r && $4 == i { ok = 1 } END { exit !ok }'; then
    echo "MISSING from extensions.tsv: $identifier ($repo)"
    failed=1
  fi
done <"$found"

while IFS=$'\t' read -r key _ repo identifier _; do
  if ! grep -qxF "$repo"$'\t'"$identifier" "$found"; then
    echo "STALE in extensions.tsv: $key ($repo has no $identifier.c7s.zip in its latest release)"
    failed=1
  fi
done < <(grep -vE '^\s*(#|$)' "$manifest")

if ((failed == 0)); then
  echo "extensions.tsv matches the organization's latest releases ($(wc -l <"$found") archives)"
fi
exit "$failed"
