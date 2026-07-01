#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS — GitHub Release Publisher
# Uploads build artifacts to GitHub Releases
# ─────────────────────────────────────────────

source /root/vizoure-nms-builde/branding/branding.conf

REPO="sadiqawan/Vizoure"
VERSION="${BRAND_VERSION}"
DIST_DIR="/root/vizoure-nms-builde/dist"
TAG="v${VERSION}"

echo "=== Creating Vizoure NMS Release ${TAG} ==="

# ─────────────────────────────────────────────
# 1. VERIFY ARTIFACTS EXIST
# ─────────────────────────────────────────────
echo "[1/4] Checking artifacts..."

MISSING=0

check_artifact() {
    if [ -f "$1" ]; then
        echo "  ✓ Found: $(basename $1)"
    else
        echo "  ✗ Missing: $1"
        MISSING=1
    fi
}

check_artifact "$DIST_DIR/ovf/${TAG}-vizoure-nms.ovf"
check_artifact "$DIST_DIR/vmx/${TAG}-vizoure-nms.vmx"
check_artifact "$DIST_DIR/iso/vizoure-nms-${VERSION}.iso"
check_artifact "/root/vizoure-nms-builde/packages/linux/vizoure-agent_${VERSION}_amd64.deb"

if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo "  ERROR: Some artifacts are missing. Run builds first:"
    echo "    Packer:  cd packer && packer build -var-file=variables.pkr.hcl ubuntu-server.pkr.hcl"
    echo "    Agent:   bash agent-packaging/linux/build-agent.sh"
    exit 1
fi

# ─────────────────────────────────────────────
# 2. CREATE CHECKSUMS
# ─────────────────────────────────────────────
echo "[2/4] Generating checksums..."

cd "$DIST_DIR"
sha256sum \
    ovf/${TAG}-vizoure-nms.ovf \
    vmx/${TAG}-vizoure-nms.vmx \
    iso/vizoure-nms-${VERSION}.iso \
    > SHA256SUMS.txt

echo "  Checksums written to SHA256SUMS.txt"

# ─────────────────────────────────────────────
# 3. CREATE RELEASE NOTES
# ─────────────────────────────────────────────
echo "[3/4] Preparing release notes..."

cat > /tmp/release-notes.md << NOTESEOF
## Vizoure NMS v${VERSION}

Base: Zabbix ${VERSION} | OS: Ubuntu 24.04 LTS

### Download Options

| File | Description |
|------|-------------|
| \`vizoure-nms-${VERSION}.ovf\` | Import into VMware ESXi |
| \`vizoure-nms-${VERSION}.vmx\` | Open in VMware Workstation |
| \`vizoure-nms-${VERSION}.iso\` | Bootable installer ISO |
| \`vizoure-agent_${VERSION}_amd64.deb\` | Linux agent package |

### Default Credentials
- **Web UI:** http://\<ip\>/vizoure
- **Username:** Admin
- **Password:** AES@admin
- **OS Login:** admin / AES@admin

> ⚠️ Change all passwords immediately after first login.

### Verify Download
\`\`\`bash
sha256sum -c SHA256SUMS.txt
\`\`\`
NOTESEOF

# ─────────────────────────────────────────────
# 4. PUBLISH TO GITHUB RELEASES
# ─────────────────────────────────────────────
echo "[4/4] Publishing to GitHub Releases..."

gh release create "$TAG" \
    --repo "$REPO" \
    --title "Vizoure NMS v${VERSION}" \
    --notes-file /tmp/release-notes.md \
    "$DIST_DIR/ovf/${TAG}-vizoure-nms.ovf" \
    "$DIST_DIR/vmx/${TAG}-vizoure-nms.vmx" \
    "$DIST_DIR/iso/vizoure-nms-${VERSION}.iso" \
    "/root/vizoure-nms-builde/packages/linux/vizoure-agent_${VERSION}_amd64.deb" \
    "$DIST_DIR/SHA256SUMS.txt"

echo ""
echo "========================================="
echo "  Vizoure NMS v${VERSION} Released!"
echo "========================================="
echo "  GitHub: https://github.com/${REPO}/releases/tag/${TAG}"
echo ""
echo "  Install on fresh VM:"
echo "  curl -sSL https://raw.githubusercontent.com/${REPO}/main/scripts/install-nms.sh | sudo bash"
echo "========================================="
