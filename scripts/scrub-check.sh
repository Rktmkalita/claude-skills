#!/usr/bin/env bash
# Fails if any publishable file contains a deny-listed term or a secret-shaped string.
#
# Deny-list: scripts/scrub-denylist.local.txt (gitignored, one extended regex per line, case-insensitive).
# Allow-list: scripts/scrub-allow.local.txt (gitignored, optional). Each line is a fixed string; any hit
#             whose "path:line:text" output contains it is treated as reviewed and ignored.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DENY="$REPO/scripts/scrub-denylist.local.txt"
ALLOW="$REPO/scripts/scrub-allow.local.txt"
SECRETS='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[bp]-[0-9A-Za-z-]+|ghp_[0-9A-Za-z]{36}|glpat-[0-9A-Za-z_-]{20}|(password|secret|token)["'\'' ]*[:=]["'\'' ]*[A-Za-z0-9+/=]{24,}'

if [ ! -s "$DENY" ]; then
  echo "error: $DENY is missing or empty. Refusing to run without a deny-list." >&2
  exit 2
fi

cd "$REPO"

# Publishable files: what git would track if in a repo, otherwise everything minus ignored names.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -t files < <(git ls-files -co --exclude-standard)
else
  mapfile -t files < <(find . -type f -not -path './.git/*' -not -name '*.local.txt' -not -name 'PLAN.md' | sed 's#^\./##')
fi

hits="$( { grep -nHiE -f "$DENY" -- "${files[@]}" || true; grep -nHiE -e "$SECRETS" -- "${files[@]}" || true; } | sort -u )"

if [ -n "$hits" ] && [ -s "$ALLOW" ]; then
  hits="$(printf '%s\n' "$hits" | grep -vF -f "$ALLOW" || true)"
fi

if [ -n "$hits" ]; then
  printf '%s\n' "$hits"
  echo "scrub-check: FAILED ($(printf '%s\n' "$hits" | wc -l) hit(s)) across ${#files[@]} file(s)" >&2
  exit 1
fi

echo "scrub-check: OK (${#files[@]} files scanned)"
