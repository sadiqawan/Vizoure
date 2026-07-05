#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────────
# Vizoure NMS — GitHub Release Creator
# Usage: bash create-release.sh [version]
# Example: bash create-release.sh 7.4.9
# Requires: gh CLI authenticated
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

if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not installed. Install with:"
    echo "  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
    echo "  echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main' | sudo tee /etc/apt/sources.list.d/github-cli.list"
    echo "  sudo apt update && sudo apt install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "ERROR: gh CLI not authenticated. Run: gh auth login"
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

# Copy artifacts
cp "$DEB_FILE" "$RELEASE_DIR/"
cp "${BUILD_DIR}/scripts/install-nms.sh" "$RELEASE_DIR/vizoure-install-${VERSION}.sh"
cp "${BUILD_DIR}/scripts/upgrade.sh" "$RELEASE_DIR/vizoure-upgrade-${VERSION}.sh"

# Generate SHA256 checksums
cd "$RELEASE_DIR"
sha256sum * > SHA256SUMS.txt

echo "  Assets prepared:"
ls -lh "$RELEASE_DIR"

# ─────────────────────────────────────────────
# 3. CREATE RELEASE NOTES
# ─────────────────────────────────────────────
echo "[3/4] Creating release notes..."

NOTES_FILE="/tmp/vizoure-release-notes-${VERSION}.md"
cat > "$NOTES_FILE" << NOTESEOF
# Vizoure NMS ${VERSION}

Vizoure NMS is a fully rebranded network monitoring system based on Zabbix ${VERSION}.

## What's Included

| File | Description |
|---|---|
| \`vizoure-agent_${VERSION}_amd64.deb\` | Linux monitoring agent (Debian/Ubuntu) |
| \`vizoure-install-${VERSION}.sh\` | Full server installation script |
| \`vizoure-upgrade-${VERSION}.sh\` | Upgrade script from previous version |
| \`SHA256SUMS.txt\` | Checksums for all files |

## Quick Install

\`\`\`bash
# Install Vizoure NMS Server
curl -sSL https://raw.githubusercontent.com/${REPO}/main/scripts/install-nms.sh -o /tmp/vizoure-install.sh
sudo bash /tmp/vizoure-install.sh
\`\`\`

## Install Linux Agent

\`\`\`bash
# Download and install the monitoring agent
wget https://github.com/${REPO}/releases/download/${TAG}/vizoure-agent_${VERSION}_amd64.deb
sudo dpkg -i vizoure-agent_${VERSION}_amd64.deb
\`\`\`

## Default Credentials

- **Web UI:** \`http://<server-ip>/vizoure\`
- **Username:** \`admin\`
- **Password:** \`Vizoure@123\`

## Agent Configuration

Edit \`/etc/vizoure/vizoure_agentd.conf\` and set:
\`\`\`
Server=<your-vizoure-server-ip>
ServerActive=<your-vizoure-server-ip>
Hostname=<this-host-name>
\`\`\`

Then restart: \`sudo systemctl restart vizoure-agent\`

## Windows & macOS Agents

Windows (MSI) and macOS (PKG) agent packages are coming in a future release.

## Upgrade from Previous Version

\`\`\`bash
curl -sSL https://raw.githubusercontent.com/${REPO}/main/scripts/upgrade.sh -o /tmp/upgrade.sh
sudo bash /tmp/upgrade.sh ${VERSION}
\`\`\`
NOTESEOF

echo "  Release notes created"

# ─────────────────────────────────────────────
# 4. PUBLISH TO GITHUB RELEASES
# ─────────────────────────────────────────────
echo "[4/4] Publishing GitHub Release ${TAG}..."

cd "${BUILD_DIR}"

# Delete existing release/tag if it exists
gh release delete "$TAG" --yes 2>/dev/null || true
git tag -d "$TAG" 2>/dev/null || true
git push origin ":refs/tags/$TAG" 2>/dev/null || true

# Create the release
gh release create "$TAG" \
    --repo "$REPO" \
    --title "Vizoure NMS ${VERSION}" \
    --notes-file "$NOTES_FILE" \
    "${RELEASE_DIR}/vizoure-agent_${VERSION}_amd64.deb" \
    "${RELEASE_DIR}/vizoure-install-${VERSION}.sh" \
    "${RELEASE_DIR}/vizoure-upgrade-${VERSION}.sh" \
    "${RELEASE_DIR}/SHA256SUMS.txt"

echo ""
echo "========================================="
echo "  Release Published Successfully!"
echo "  URL: https://github.com/${REPO}/releases/tag/${TAG}"
echo "========================================="
