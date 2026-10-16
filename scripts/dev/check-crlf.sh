#!/bin/bash
# Fails if any .sh/.php/.css/.js/.conf/.py/.json/systemd-unit/MANIFEST/VERSION file in the repo contains a CR (\r)
# byte. Written after this session hit the same CRLF-corruption bug twice
# via the Windows-side editing tooling, despite .gitattributes being in
# place. Run this before every copy to the VM and before every commit —
# see md/05-test-vm-workflow.md.
#
# Usage: bash scripts/dev/check-crlf.sh [path...]
#   No args: scans the whole repo (from this script's own location).
#   With args: scans only those paths (files or directories).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=("$REPO_ROOT")
fi

FAILED=0
CHECKED=0

check_file() {
    local f="$1"
    case "$f" in
        *.sh|*.php|*.css|*.js|*.conf|*.py|*.json|*/cli/vizoure|*.service|*.path|*.timer|MANIFEST|VERSION|allowed_signers) ;;
        *) return 0 ;;
    esac
    # Skip vendored/local-only trees even if somehow passed explicitly.
    case "$f" in
        */zabbix-master/*|*/zabbix-src-*/*) return 0 ;;
    esac

    CHECKED=$((CHECKED + 1))
    local cr_count
    cr_count=$(tr -d '\n' < "$f" | tr -cd '\r' | wc -c)
    if [ "$cr_count" -gt 0 ]; then
        echo "CRLF FOUND: $f ($cr_count CR bytes)"
        FAILED=1
    fi
}

for target in "${TARGETS[@]}"; do
    if [ -f "$target" ]; then
        check_file "$target"
    elif [ -d "$target" ]; then
        while IFS= read -r -d '' f; do
            check_file "$f"
        done < <(find "$target" \
            -path '*/zabbix-master' -prune -o \
            -path '*/zabbix-src-*' -prune -o \
            -path '*/.git' -prune -o \
            -type f -print0)
    fi
done

if [ "$FAILED" -eq 1 ]; then
    echo "check-crlf.sh: FAILED — $CHECKED files checked, CRLF found in at least one (see above)."
    exit 1
fi

echo "check-crlf.sh: OK — $CHECKED files checked, no CRLF found."
