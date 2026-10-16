#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────────
# Vizoure NMS — GitHub Release Creator (publishes what the in-UI updater consumes; see md/09-update-system.md)
#
# Usage: GITHUB_TOKEN=xxx [PRERELEASE=1] [RELEASE_TYPE=full|branding-only] bash create-release.sh
#
# The release tag comes from branding/VERSION (vX.Y.Z-vzN). PRERELEASE=1 publishes a TEST pre-release
# (channel "test"; customers on the default "stable" channel never see it).
# Assets: vizoure-nms-<tag>-install.tar.gz, SHA256SUMS, SHA256SUMS.sig (signed via ssh-agent: the script
# stops with exit 3 if the signing key is not loaded), release.json, plus the Linux agent .deb.
# ─────────────────────────────────────────────

BUILD_DIR="/root/vizoure-nms-builde"
TAG="$(tr -d '[:space:]' < "${BUILD_DIR}/branding/VERSION")"
echo "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+-vz[0-9]+$' || { echo "ERROR: branding/VERSION ('$TAG') is not vX.Y.Z-vzN"; exit 1; }
VERSION="$(echo "$TAG" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-vz[0-9]+$//')"
REPO="sadiqawan/Vizoure"
if [ "${PRERELEASE:-0}" = "1" ]; then CHANNEL="test"; PRERELEASE_JSON="true"; else CHANNEL="stable"; PRERELEASE_JSON="false"; fi
PACKAGES_DIR="${BUILD_DIR}/packages/linux"
DEB_FILE="${PACKAGES_DIR}/vizoure-agent_${VERSION}_amd64.deb"

echo "========================================="
echo "  Vizoure NMS Release Publisher"
echo "  Version: ${VERSION} (${TAG})"
echo "========================================="

# ─────────────────────────────────────────────
# 1. CHECK PREREQUISITES
# ─────────────────────────────────────────────
echo "[1/4] Checking prerequisites..."

if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN not set."
    echo "Usage: GITHUB_TOKEN=ghp_xxx bash create-release.sh 7.4.9"
    exit 1
fi

# Verify token works
REPO_CHECK=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${REPO}" | python3 -c \
    "import sys,json; r=json.load(sys.stdin); print(r.get('name','ERROR'))" 2>/dev/null)

if [ "$REPO_CHECK" != "Vizoure" ]; then
    echo "ERROR: Token invalid or repo not accessible. Got: $REPO_CHECK"
    exit 1
fi

# Build the Linux agent if not already built
if [ ! -f "$DEB_FILE" ]; then
    echo "  Linux agent .deb not found — building now..."
    bash "${BUILD_DIR}/agent-packaging/linux/build-agent.sh"
fi

if [ ! -f "$DEB_FILE" ]; then
    echo "ERROR: Could not find or build ${DEB_FILE}"
    exit 1
fi

echo "  Prerequisites OK"

# ─────────────────────────────────────────────
# 2. PREPARE RELEASE ASSETS
# ─────────────────────────────────────────────
echo "[2/4] Preparing release assets..."

RELEASE_DIR="/tmp/vizoure-release-${TAG}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Signed install tarball + SHA256SUMS(.sig) + release.json (exit 3 = signing key not in ssh-agent).
bash "${BUILD_DIR}/scripts/make-release-assets.sh" "$RELEASE_DIR" --type "${RELEASE_TYPE:-full}" --channel "$CHANNEL" --sign

cp "$DEB_FILE" "$RELEASE_DIR/"
( cd "$RELEASE_DIR" && sha256sum "$(basename "$DEB_FILE")" > SHA256SUMS.agent.txt )

echo "  Assets prepared:"
ls -lh "$RELEASE_DIR"

# ─────────────────────────────────────────────
# 3. CREATE GITHUB RELEASE
# ─────────────────────────────────────────────
echo "[3/4] Creating GitHub Release ${TAG}..."

# Delete existing release if it exists
EXISTING=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${REPO}/releases/tags/${TAG}" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('id',''))" 2>/dev/null)

if [ -n "$EXISTING" ] && [ "$PRERELEASE_JSON" = "false" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "ERROR: a release for ${TAG} already exists; installs are pinned to this tag. Bump branding/VERSION or set FORCE=1."
    exit 1
fi

if [ -n "$EXISTING" ]; then
    echo "  Deleting existing release ${TAG}..."
    curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${REPO}/releases/${EXISTING}" > /dev/null
fi

# Delete existing tag
git -C "${BUILD_DIR}" tag -d "$TAG" 2>/dev/null || true
git -C "${BUILD_DIR}" push origin ":refs/tags/$TAG" 2>/dev/null || true

# Release notes: the "## <tag>" section of CHANGELOG.md (shown in the in-UI updater).
NOTES="$(awk -v t="## ${TAG}" '$0==t{f=1;next} /^## /{f=0} f' "${BUILD_DIR}/CHANGELOG.md")"
[ -n "$NOTES" ] || NOTES="No release notes were written for this version."

RELEASE_BODY="# Vizoure NMS ${TAG}

${NOTES}

Vizoure NMS is a rebranded network monitoring system based on Zabbix ${VERSION}.
Channel: **${CHANNEL}**.

## Quick Install

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/${REPO}/${TAG}/scripts/install-nms.sh -o /tmp/vizoure-install.sh
sudo env VIZOURE_REF=${TAG} bash /tmp/vizoure-install.sh
\`\`\`

## Install Linux Agent

\`\`\`bash
wget https://github.com/${REPO}/releases/download/${TAG}/vizoure-agent_${VERSION}_amd64.deb
sudo dpkg -i vizoure-agent_${VERSION}_amd64.deb
\`\`\`

## Offline / local-first install

Download \`vizoure-nms-${TAG}-install.tar.gz\`, extract it and run \`sudo bash vizoure-nms-${TAG}/scripts/install-nms.sh\` — branding (including the top header) is taken from the extracted copy.

## Default Credentials
- **Web UI:** \`http://<server-ip>/vizoure\`
- **Username:** \`admin\`
- **Password:** \`Vizoure@123\`

## Upgrade
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/${REPO}/${TAG}/scripts/upgrade.sh -o /tmp/upgrade.sh
sudo env VIZOURE_REF=${TAG} bash /tmp/upgrade.sh ${VERSION}
\`\`\`"

RELEASE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${REPO}/releases" \
    -d "{\"tag_name\":\"${TAG}\",\"name\":\"Vizoure NMS ${TAG}\",\"body\":$(echo "$RELEASE_BODY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),\"draft\":false,\"prerelease\":${PRERELEASE_JSON}}")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('id','ERROR:'+str(r.get('message',''))))" 2>/dev/null)

if [[ "$RELEASE_ID" == ERROR* ]]; then
    echo "ERROR creating release: $RELEASE_ID"
    exit 1
fi

echo "  Release created (ID: ${RELEASE_ID})"

# ─────────────────────────────────────────────
# 4. UPLOAD ASSETS
# ─────────────────────────────────────────────
echo "[4/4] Uploading assets..."

UPLOAD_BASE="https://uploads.github.com/repos/${REPO}/releases/${RELEASE_ID}/assets"

for FILE in "$RELEASE_DIR"/*; do
    FILENAME=$(basename "$FILE")
    echo "  Uploading ${FILENAME}..."
    RESULT=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        "${UPLOAD_BASE}?name=${FILENAME}" \
        --data-binary "@${FILE}" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('name','ERROR:'+str(r.get('errors',''))))" 2>/dev/null)
    echo "    OK: $RESULT"
done

echo ""
echo "========================================="
echo "  Release Published Successfully!"
echo "  URL: https://github.com/${REPO}/releases/tag/${TAG}"
echo "========================================="
