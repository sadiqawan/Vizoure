#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────────
# Vizoure NMS — GitHub Release Creator
# Usage: GITHUB_TOKEN=xxx bash create-release.sh [version]
# Example: GITHUB_TOKEN=ghp_xxx bash create-release.sh 7.4.9
# ─────────────────────────────────────────────

VERSION="${1:-7.4.9}"
REPO="sadiqawan/Vizoure"
TAG="v${VERSION}"
BUILD_DIR="/root/vizoure-nms-builde"
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

RELEASE_DIR="/tmp/vizoure-release-${VERSION}"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cp "$DEB_FILE" "$RELEASE_DIR/"
cp "${BUILD_DIR}/scripts/install-nms.sh" "$RELEASE_DIR/vizoure-install-${VERSION}.sh"
cp "${BUILD_DIR}/scripts/upgrade.sh" "$RELEASE_DIR/vizoure-upgrade-${VERSION}.sh"

# Install tarball: scripts/ + branding/ (incl. branding/header/*) so a release can be
# installed local-first without reaching GitHub for branding assets.
bash "${BUILD_DIR}/scripts/dev/check-manifest.sh"
test -s "${BUILD_DIR}/branding/header/top-header.css" && test -s "${BUILD_DIR}/branding/header/top-header.js"
TARDIR="vizoure-nms-${VERSION}"
rm -rf "/tmp/${TARDIR}" && mkdir -p "/tmp/${TARDIR}"
cp -r "${BUILD_DIR}/scripts" "${BUILD_DIR}/branding" "/tmp/${TARDIR}/"
rm -rf "/tmp/${TARDIR}/scripts/dev"
tar -C /tmp -czf "$RELEASE_DIR/${TARDIR}-install.tar.gz" "${TARDIR}"
tar -tzf "$RELEASE_DIR/${TARDIR}-install.tar.gz" | grep -q "branding/header/top-header.css"

cd "$RELEASE_DIR"
sha256sum * > SHA256SUMS.txt

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

if [ -n "$EXISTING" ]; then
    echo "  Deleting existing release ${TAG}..."
    curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${REPO}/releases/${EXISTING}" > /dev/null
fi

# Delete existing tag
git -C "${BUILD_DIR}" tag -d "$TAG" 2>/dev/null || true
git -C "${BUILD_DIR}" push origin ":refs/tags/$TAG" 2>/dev/null || true

RELEASE_BODY="# Vizoure NMS ${VERSION}

Vizoure NMS is a fully rebranded network monitoring system based on Zabbix ${VERSION}.

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

Download \`vizoure-nms-${VERSION}-install.tar.gz\`, extract it and run \`sudo bash vizoure-nms-${VERSION}/scripts/install-nms.sh\` — branding (including the top header) is taken from the extracted copy.

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
    -d "{\"tag_name\":\"${TAG}\",\"name\":\"Vizoure NMS ${VERSION}\",\"body\":$(echo "$RELEASE_BODY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),\"draft\":false,\"prerelease\":false}")

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
