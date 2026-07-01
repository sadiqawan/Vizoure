#!/bin/bash
set -e

# Load branding config
source "/root/vizoure-nms-builde/branding/branding.conf"

ZABBIX_SOURCE="/root/vizoure-nms-builde/zabbix-source"

echo "=== Vizoure NMS Branding Patch Starting ==="

# ─────────────────────────────────────────────
# 1. FRONTEND PHP — product name strings
# ─────────────────────────────────────────────
echo "[1/5] Patching frontend PHP strings..."

find "$ZABBIX_SOURCE/ui" -name "*.php" | while read file; do
    sed -i "s/Zabbix SIA/${BRAND_COMPANY}/g" "$file"
    sed -i "s/Zabbix/${BRAND_NAME}/g" "$file"
    sed -i "s/zabbix/${BRAND_NAME_LOWER}/g" "$file"
done

# ─────────────────────────────────────────────
# 2. SASS/CSS — colors and brand references
# ─────────────────────────────────────────────
echo "[2/5] Patching SASS/CSS..."

find "$ZABBIX_SOURCE/sass" -name "*.scss" | while read file; do
    sed -i "s/Zabbix/${BRAND_NAME}/g" "$file"
    sed -i "s/zabbix/${BRAND_NAME_LOWER}/g" "$file"
done

# ─────────────────────────────────────────────
# 3. AGENT SOURCE — binary/service name (C)
# ─────────────────────────────────────────────
echo "[3/5] Patching agent source strings..."

find "$ZABBIX_SOURCE/src/zabbix_agent" -name "*.c" | while read file; do
    sed -i "s/Zabbix Agent/${BRAND_NAME} Agent/g" "$file"
    sed -i "s/zabbix_agentd/${BRAND_AGENT_NAME}d/g" "$file"
    sed -i "s/zabbix_agent/${BRAND_AGENT_NAME}/g" "$file"
done

# ─────────────────────────────────────────────
# 4. CONFIG FILE TEMPLATES
# ─────────────────────────────────────────────
echo "[4/5] Patching config templates..."

find "$ZABBIX_SOURCE/conf" | while read file; do
    if [ -f "$file" ]; then
        sed -i "s/Zabbix/${BRAND_NAME}/g" "$file"
        sed -i "s/zabbix/${BRAND_NAME_LOWER}/g" "$file"
    fi
done

# ─────────────────────────────────────────────
# 5. LOGOS/IMAGES — replace with Vizoure logos
# ─────────────────────────────────────────────
echo "[5/5] Replacing logos..."
echo "  Logo replacement skipped (add your logos to branding/logos/ first)"

echo ""
echo "=== Branding patch complete ==="


