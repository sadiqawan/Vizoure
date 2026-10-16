#!/bin/bash
# Fails if branding/MANIFEST (what the standalone GitHub fallback downloads) and
# the files that apply-branding.sh actually needs under branding/ disagree.
# branding-patch.sh (unused source-tree patcher) and MANIFEST itself are exempt.
# Run before every copy to the VM and before every commit (see md/05).
set -eo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
cd "$ROOT/branding"
FAIL=0
LISTED=$(grep -v '^#' MANIFEST | grep -v '^$' | sort)
ACTUAL=$(find . -type f ! -name MANIFEST ! -name branding-patch.sh | sed 's#^\./##' | sort)
while IFS= read -r f; do [ -f "$f" ] || { echo "MANIFEST lists missing file: $f"; FAIL=1; }; done <<< "$LISTED"
while IFS= read -r f; do grep -qxF "$f" <<< "$LISTED" || { echo "file not in MANIFEST: $f"; FAIL=1; }; done <<< "$ACTUAL"
[ "$FAIL" -eq 0 ] && echo "check-manifest.sh: OK — $(wc -l <<< "$LISTED") files match." || { echo "check-manifest.sh: FAILED"; exit 1; }
