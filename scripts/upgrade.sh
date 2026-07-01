#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS — Upstream Upgrade Script
# Usage: bash scripts/upgrade.sh 7.4.10
# ─────────────────────────────────────────────

source /root/vizoure-nms-builde/branding/branding.conf

NEW_VERSION="$1"
ZABBIX_SOURCE="/root/vizoure-nms-builde/zabbix-source"
REPO_DIR="/root/vizoure-nms-builde"

# ─────────────────────────────────────────────
# VALIDATE INPUT
# ─────────────────────────────────────────────
if [ -z "$NEW_VERSION" ]; then
    echo "ERROR: No version specified."
    echo "Usage: bash scripts/upgrade.sh 7.4.10"
    exit 1
fi

echo "========================================="
echo "  Vizoure NMS Upgrade"
echo "  Current: ${BRAND_VERSION}"
echo "  Target:  ${NEW_VERSION}"
echo "========================================="
echo ""

# Confirm before proceeding
read -p "Proceed with upgrade to v${NEW_VERSION}? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Upgrade cancelled."
    exit 0
fi

# ─────────────────────────────────────────────
# 1. FETCH LATEST TAGS FROM UPSTREAM
# ─────────────────────────────────────────────
echo "[1/6] Fetching upstream Zabbix tags..."

cd "$ZABBIX_SOURCE"

# Add upstream remote if not already there
if ! git remote | grep -q "upstream"; then
    git remote add upstream https://github.com/zabbix/zabbix.git
    echo "  Added upstream remote"
fi

git fetch upstream --tags
echo "  Tags fetched"

# Verify the requested tag exists
if ! git tag | grep -q "^${NEW_VERSION}$"; then
    echo "  ERROR: Tag ${NEW_VERSION} not found in upstream."
    echo "  Available 7.4.x tags:"
    git tag | grep "^7.4" | sort
    exit 1
fi

echo "  Tag ${NEW_VERSION} confirmed available"

# ─────────────────────────────────────────────
# 2. CREATE NEW BRANCH FROM NEW TAG
# ─────────────────────────────────────────────
echo "[2/6] Creating new branch vizoure-nms-${NEW_VERSION}..."

cd "$ZABBIX_SOURCE"
git checkout "$NEW_VERSION"
git checkout -b "vizoure-nms-${NEW_VERSION}"

echo "  Branch vizoure-nms-${NEW_VERSION} created"

# ─────────────────────────────────────────────
# 3. REAPPLY BRANDING PATCH
# ─────────────────────────────────────────────
echo "[3/6] Reapplying Vizoure branding patch..."

bash "$REPO_DIR/branding/branding-patch.sh"

echo "  Branding patch applied"

# ─────────────────────────────────────────────
# 4. UPDATE VERSION IN BRANDING CONFIG
# ─────────────────────────────────────────────
echo "[4/6] Updating version in branding.conf..."

sed -i "s/BRAND_VERSION=.*/BRAND_VERSION=\"${NEW_VERSION}\"/" \
    "$REPO_DIR/branding/branding.conf"

# Update Packer variables
sed -i "s/vm_version.*=.*/  default = \"${NEW_VERSION}\"/" \
    "$REPO_DIR/packer/variables.pkr.hcl"
sed -i "s/vm_name.*=.*/  default = \"vizoure-nms-${NEW_VERSION}\"/" \
    "$REPO_DIR/packer/variables.pkr.hcl"

echo "  Version updated to ${NEW_VERSION}"

# ─────────────────────────────────────────────
# 5. COMMIT UPDATED CONFIG TO REPO
# ─────────────────────────────────────────────
echo "[5/6] Committing version bump..."

cd "$REPO_DIR"
git add branding/branding.conf packer/variables.pkr.hcl
git commit -m "Upgrade: Vizoure NMS ${BRAND_VERSION} → ${NEW_VERSION}"
git push origin main

echo "  Version bump committed and pushed"

# ─────────────────────────────────────────────
# 6. TRIGGER REBUILD
# ─────────────────────────────────────────────
echo "[6/6] Starting rebuild..."

echo ""
echo "  Next steps:"
echo "  1. Rebuild VM images:"
echo "     cd ${REPO_DIR}/packer"
echo "     packer build -var-file=variables.pkr.hcl ubuntu-server.pkr.hcl"
echo ""
echo "  2. Rebuild Linux agent:"
echo "     bash ${REPO_DIR}/agent-packaging/linux/build-agent.sh"
echo ""
echo "  3. Publish new release:"
echo "     bash ${REPO_DIR}/scripts/create-release.sh"
echo ""
echo "========================================="
echo "  Upgrade to v${NEW_VERSION} complete!"
echo "  Branding reapplied, version bumped."
echo "  Run the rebuild steps above to publish."
echo "========================================="
