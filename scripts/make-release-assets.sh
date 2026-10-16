#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────────
# Vizoure NMS — build the signed release assets the in-UI updater consumes (md/09-update-system.md)
#
# Usage: bash scripts/make-release-assets.sh <outdir> [--type full|branding-only] [--channel stable|test]
#                                            [--sign] [--key <public-key-file>] [--allowed-signers <file>]
#                                            [--test-keyfile <private-key-file>]   (TESTS ONLY: throwaway keys)
#
# Produces in <outdir>:
#   vizoure-nms-<version>-install.tar.gz   scripts/ + branding/ (incl. header + updater + module) + release.json
#   SHA256SUMS                             checksum of the tarball
#   SHA256SUMS.sig                         with --sign: ssh-keygen -Y signature, namespace "vizoure-release"
#   release.json                           copy of the metadata inside the tarball (display only)
#
# SIGNING NEVER READS A PRIVATE KEY FILE: it uses ssh-agent (ssh-keygen -Y sign -U with the PUBLIC key
# file). If the agent has no matching key this script stops with exit code 3: load it yourself with
# `ssh-add <your private key>` and re-run.
# ─────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUTDIR="${1:-}"
shift || true
TYPE="full"
CHANNEL="stable"
SIGN=false
PUBKEY="${VIZOURE_SIGNING_PUBKEY:-$HOME/vizoure-keys/vizoure-release-signing.pub}"
SIGNERS="$REPO_DIR/branding/updater/allowed_signers"
TEST_KEYFILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --sign) SIGN=true; shift ;;
        --key) PUBKEY="$2"; shift 2 ;;
        --allowed-signers) SIGNERS="$2"; shift 2 ;;
        --test-keyfile) TEST_KEYFILE="$2"; SIGN=true; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[ -n "$OUTDIR" ] || { sed -n 3,20p "$0"; exit 1; }
case "$TYPE" in full|branding-only) ;; *) echo "ERROR: --type must be full or branding-only"; exit 1 ;; esac
case "$CHANNEL" in stable|test) ;; *) echo "ERROR: --channel must be stable or test"; exit 1 ;; esac

VERSION="$(tr -d '[:space:]' < "$REPO_DIR/branding/VERSION")"
echo "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+-vz[0-9]+$' \
    || { echo "ERROR: branding/VERSION ('$VERSION') must look like v7.4.15-vz2"; exit 1; }
ZBX_VERSION="$(echo "$VERSION" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-vz[0-9]+$/\1/')"
TOP="vizoure-nms-${VERSION}"
TARBALL="${TOP}-install.tar.gz"

bash "$REPO_DIR/scripts/dev/check-crlf.sh" | tail -1
bash "$REPO_DIR/scripts/dev/check-manifest.sh" | tail -1
for f in branding/header/top-header.css branding/header/top-header.js branding/updater/vizoure-updater.py \
         branding/modules/vizoure-updates/manifest.json; do
    [ -s "$REPO_DIR/$f" ] || { echo "ERROR: $f missing"; exit 1; }
done

mkdir -p "$OUTDIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$TOP"
cp -r "$REPO_DIR/scripts" "$REPO_DIR/branding" "$STAGE/$TOP/"
rm -rf "$STAGE/$TOP/scripts/dev"
[ -f "$REPO_DIR/CHANGELOG.md" ] && cp "$REPO_DIR/CHANGELOG.md" "$STAGE/$TOP/"

cat > "$STAGE/$TOP/release.json" <<EOF
{
  "version": "$VERSION",
  "zabbix_version": "$ZBX_VERSION",
  "type": "$TYPE",
  "channel": "$CHANNEL",
  "released": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

rm -f "$OUTDIR/$TARBALL" "$OUTDIR/SHA256SUMS" "$OUTDIR/SHA256SUMS.sig" "$OUTDIR/release.json"
# relative output path from inside OUTDIR: avoids tar treating "C:/..." as a remote host on Windows shells
OUTDIR="$(cd "$OUTDIR" && pwd)"
( cd "$OUTDIR" && tar -C "$STAGE" --sort=name --owner=0 --group=0 --numeric-owner -czf "$TARBALL" "$TOP" )
cp "$STAGE/$TOP/release.json" "$OUTDIR/release.json"

# The package must be uploadable through the UI (PHP upload limit is 2 MB per file).
SIZE=$(wc -c < "$OUTDIR/$TARBALL")
[ "$SIZE" -lt 2097152 ] || { echo "ERROR: $TARBALL is $SIZE bytes; the UI upload limit is 2 MB"; exit 1; }
# (list first, then grep: "tar | grep -q" would trip pipefail via SIGPIPE)
LISTING="$( cd "$OUTDIR" && tar -tzf "$TARBALL" )"
grep -q "$TOP/branding/header/top-header.css" <<< "$LISTING"
grep -q "$TOP/branding/modules/vizoure-updates/manifest.json" <<< "$LISTING"

( cd "$OUTDIR" && sha256sum "$TARBALL" > SHA256SUMS )
echo "  $TARBALL ($SIZE bytes), SHA256SUMS written"

if [ "$SIGN" = true ]; then
    if [ -n "$TEST_KEYFILE" ]; then
        # throwaway test key given explicitly; never used for real releases
        SIGN_CMD=(ssh-keygen -Y sign -f "$TEST_KEYFILE" -n vizoure-release SHA256SUMS)
    else
        [ -f "$PUBKEY" ] || { echo "ERROR: public key file not found: $PUBKEY"; exit 1; }
        SIGN_CMD=(ssh-keygen -Y sign -U -f "$PUBKEY" -n vizoure-release SHA256SUMS)
    fi
    if ! ( cd "$OUTDIR" && "${SIGN_CMD[@]}" ) 2>"$STAGE/sign.err"; then
        cat "$STAGE/sign.err" >&2
        echo "" >&2
        echo "SIGNING KEY NOT AVAILABLE: the ssh-agent has no key matching $PUBKEY." >&2
        echo "Load your release signing key yourself (ssh-add <private key>) and run this again." >&2
        rm -f "$OUTDIR/SHA256SUMS.sig"
        exit 3
    fi
    # Refuse to publish something the updater would reject: verify against the shipped signers.
    ( cd "$OUTDIR" && ssh-keygen -Y verify -f "$SIGNERS" -I vizoure-release -n vizoure-release \
        -s SHA256SUMS.sig < SHA256SUMS ) >/dev/null \
        || { echo "ERROR: the signature does not verify against $SIGNERS (is the key listed there?)"; rm -f "$OUTDIR/SHA256SUMS.sig"; exit 4; }
    echo "  SHA256SUMS.sig written and verified against allowed_signers"
fi

echo "Release assets ready in $OUTDIR (version $VERSION, type $TYPE, channel $CHANNEL)"
