#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS — Complete Branding Application
# Run AFTER base Zabbix install completes
# ─────────────────────────────────────────────

REPO_RAW="https://raw.githubusercontent.com/sadiqawan/Vizoure/main"
UI="/usr/share/zabbix/ui"

echo "=== Applying Vizoure NMS Branding ==="

# ─────────────────────────────────────────────
# 1. LOGO + FAVICON
# ─────────────────────────────────────────────
echo "[1/11] Installing logo and favicon assets..."

mkdir -p "$UI/assets/img"

curl -sSL "${REPO_RAW}/branding/logos/logo.png" -o /tmp/vizoure-logo-raw.png
curl -sSL "${REPO_RAW}/branding/logos/favicon.png" -o /tmp/vizoure-favicon-raw.png
curl -sSL "${REPO_RAW}/branding/logos/favicon.ico" -o /tmp/vizoure-favicon.ico
curl -sSL "${REPO_RAW}/branding/logos/login-bg.png" -o "$UI/assets/img/login_background.png"

convert /tmp/vizoure-logo-raw.png -resize x40 "$UI/assets/img/logo.png"

convert /tmp/vizoure-favicon-raw.png -resize 32x32 -gravity center \
    -background none -extent 32x32 "$UI/assets/img/logo-compact.png"

cp /tmp/vizoure-favicon-raw.png "$UI/assets/img/favicon.png"

# favicon.ico must exist at BOTH locations
cp /tmp/vizoure-favicon.ico "$UI/assets/img/favicon.ico"
cp /tmp/vizoure-favicon.ico "$UI/favicon.ico"

# Touch icons
convert /tmp/vizoure-favicon-raw.png -resize 76x76   "$UI/assets/img/apple-touch-icon-76x76-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 120x120 "$UI/assets/img/apple-touch-icon-120x120-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 152x152 "$UI/assets/img/apple-touch-icon-152x152-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 180x180 "$UI/assets/img/apple-touch-icon-180x180-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 192x192 "$UI/assets/img/touch-icon-192x192.png"

echo "  Logo, favicon, touch-icons installed"

# ─────────────────────────────────────────────
# 2. LOGO SIZE CSS FIX
# ─────────────────────────────────────────────
echo "[2/11] Applying logo sizing CSS..."

cat >> "$UI/assets/styles/blue-theme.css" << 'CSSEOF'

.header-logo img, .sidebar-logo img {
    max-height: 40px !important;
    width: auto !important;
}
CSSEOF

# ─────────────────────────────────────────────
# 3. BRAND CONFIG
# ─────────────────────────────────────────────
echo "[3/11] Creating brand.conf.php..."

mkdir -p "$UI/local/conf"

cat > "$UI/local/conf/brand.conf.php" << 'PHPEOF'
<?php
return [
    'BRAND_LOGO' => 'assets/img/logo.png',
    'BRAND_LOGO_SIDEBAR' => 'assets/img/logo.png',
    'BRAND_LOGO_SIDEBAR_COMPACT' => 'assets/img/logo-compact.png',
    'BRAND_FOOTER' => [
        (new CLink('Vizoure NMS', 'https://github.com/sadiqawan/Vizoure'))
            ->addClass(ZBX_STYLE_GREY)
            ->addClass(ZBX_STYLE_LINK_ALT)
            ->setTarget('_blank')
    ],
    'BRAND_HELP_URL' => 'https://github.com/sadiqawan/Vizoure'
];
PHPEOF

chown www-data:www-data "$UI/local/conf/brand.conf.php"
echo "  Brand config active — Support/Integrations auto-removed"

# ─────────────────────────────────────────────
# 4. FOOTER COPYRIGHT
# ─────────────────────────────────────────────
echo "[4/11] Fixing footer copyright comment..."
sed -i 's/Zabbix SIA/Vizoure/' "$UI/app/partials/layout.htmlpage.footer.php" 2>/dev/null || true

# ─────────────────────────────────────────────
# 5. REMOVE HELP LINK FROM LOGIN PAGE
# ─────────────────────────────────────────────
echo "[5/11] Removing Help link from login page..."

python3 << 'PYEOF'
path = "/usr/share/zabbix/ui/include/views/general.login.php"
with open(path) as f:
    content = f.read()

old_block = """\t\t(new CDiv([
\t\t\t(new CLink(_('Help'), CBrandHelper::getHelpUrl()))
\t\t\t\t->setTarget('_blank')
\t\t\t\t->addClass(ZBX_STYLE_GREY)
\t\t\t\t->addClass(ZBX_STYLE_LINK_ALT),
\t\t\tCBrandHelper::isRebranded() ? null : [NBSP(), NBSP(), BULLET(), NBSP(), NBSP()],
\t\t\tCBrandHelper::isRebranded()
\t\t\t\t? null
\t\t\t\t: (new CLink(_('Support'), getSupportUrl(CWebUser::getLang())))
\t\t\t\t\t->setTarget('_blank')
\t\t\t\t\t->addClass(ZBX_STYLE_GREY)
\t\t\t\t\t->addClass(ZBX_STYLE_LINK_ALT)
\t\t]))->addClass(ZBX_STYLE_SIGNIN_LINKS)"""

new_block = "\t\t(new CDiv([]))->addClass(ZBX_STYLE_SIGNIN_LINKS)"

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(path, "w") as f:
        f.write(content)
    print("  Login Help/Support block removed")
else:
    print("  WARNING: login.php block pattern not found — skipped")
PYEOF

# ─────────────────────────────────────────────
# 6. REMOVE HELP FROM SIDEBAR MENU
# ─────────────────────────────────────────────
echo "[6/11] Removing Help from sidebar menu..."

python3 << 'PYEOF'
path = "/usr/share/zabbix/ui/include/classes/helpers/CMenuHelper.php"
with open(path) as f:
    content = f.read()

old_block = """\t\t$menu->add(
\t\t\t(new CMenuItem(_('Help')))
\t\t\t\t->setIcon(ZBX_ICON_HELP_CIRCLED)
\t\t\t\t->setUrl(new CUrl(CBrandHelper::getHelpUrl()))
\t\t\t\t->setTitle(_('Help'))
\t\t\t\t->setTarget('_blank')
\t\t);"""

if old_block in content:
    content = content.replace(old_block, "")
    with open(path, "w") as f:
        f.write(content)
    print("  Sidebar Help menu item removed")
else:
    print("  WARNING: CMenuHelper.php block pattern not found — skipped")
PYEOF

# ─────────────────────────────────────────────
# 7. BROWSER TITLE
# ─────────────────────────────────────────────
echo "[7/11] Setting browser title..."
DEFINES=$(find "$UI" -name "defines.inc.php" | head -1)
if [ -n "$DEFINES" ]; then
    sed -i "s/define('ZBX_TITLE'.*/define('ZBX_TITLE', 'Vizoure NMS');/" "$DEFINES"
fi

# ─────────────────────────────────────────────
# 8. SYSTEM INFO WIDGET LABELS
# ─────────────────────────────────────────────
echo "[8/11] Fixing System Information widget labels..."
SYSINFO="$UI/app/partials/administration.system.info.php"
if [ -f "$SYSINFO" ]; then
    sed -i "s/_('Zabbix server is running')/_('Vizoure NMS Server Status')/" "$SYSINFO"
    sed -i "s/_('Zabbix server version')/_('Vizoure NMS Version')/" "$SYSINFO"
    sed -i "s/_('Zabbix frontend version')/_('Vizoure Web Console Version')/" "$SYSINFO"
    echo "  System Info widget labels updated"
fi

# ─────────────────────────────────────────────
# 9. AVAILABILITY LABEL: ZBX → VIZ
# ─────────────────────────────────────────────
echo "[9/11] Fixing availability label ZBX -> VIZ..."
AVAILFILE="$UI/include/classes/html/CHostAvailability.php"
if [ -f "$AVAILFILE" ]; then
    sed -i "s/INTERFACE_TYPE_AGENT => 'ZBX'/INTERFACE_TYPE_AGENT => 'VIZ'/" "$AVAILFILE"
    echo "  Availability label updated to VIZ"
fi

# ─────────────────────────────────────────────
# 10. SCATTERED UI STRINGS
# ─────────────────────────────────────────────
echo "[10/11] Fixing scattered UI strings..."

SCRIPTEDIT="$UI/app/views/administration.script.edit.php"
if [ -f "$SCRIPTEDIT" ]; then
    sed -i "s/_('Zabbix agent')/_('Vizoure Agent')/" "$SCRIPTEDIT"
    sed -i "s/_('Zabbix proxy or server')/_('Vizoure Proxy or Server')/" "$SCRIPTEDIT"
    sed -i "s/_('Zabbix server')/_('Vizoure Server')/" "$SCRIPTEDIT"
    sed -i "s/Global script execution on Zabbix server is disabled/Global script execution on Vizoure Server is disabled/" "$SCRIPTEDIT"
fi

ACTIONLOG="$UI/app/controllers/CControllerActionLogList.php"
if [ -f "$ACTIONLOG" ]; then
    sed -i "s/zbx_actionlog_export.csv/vizoure_actionlog_export.csv/" "$ACTIONLOG"
fi

PROBLEMVIEW="$UI/app/controllers/CControllerProblemView.php"
if [ -f "$PROBLEMVIEW" ]; then
    sed -i "s/zbx_problems_export.csv/vizoure_problems_export.csv/" "$PROBLEMVIEW"
fi

HOSTWIZARD="$UI/app/views/host.wizard.edit.php"
if [ -f "$HOSTWIZARD" ]; then
    sed -i "s/in Zabbix\\.'/in Vizoure NMS.'/" "$HOSTWIZARD"
fi

AUTHEDIT="$UI/app/views/administration.authentication.edit.php"
if [ -f "$AUTHEDIT" ]; then
    sed -i "s/_('Zabbix login form')/_('Vizoure login form')/" "$AUTHEDIT"
fi

echo "  Scattered UI strings updated"

# ─────────────────────────────────────────────
# 11. RESTART SERVICES
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# 11b. ADDITIONAL UI STRING FIXES
# ─────────────────────────────────────────────
echo "  Fixing additional UI strings..."

# Global scripts on Zabbix server (System Information page)
SYSINFO="$UI/app/partials/administration.system.info.php"
if [ -f "$SYSINFO" ]; then
    sed -i "s/_('Global scripts on Zabbix server')/_('Global scripts on Vizoure Server')/" "$SYSINFO"
fi

# Discovery action service type label
DISCOVERY="$UI/include/discovery.inc.php"
if [ -f "$DISCOVERY" ]; then
    sed -i "s/SVC_AGENT => _('Zabbix agent')/SVC_AGENT => _('Vizoure Agent')/" "$DISCOVERY"
fi

# Item type label (Latest data, Items list)
ITEMS="$UI/include/items.inc.php"
if [ -f "$ITEMS" ]; then
    sed -i "s/ITEM_TYPE_ZABBIX => _('Zabbix agent')/ITEM_TYPE_ZABBIX => _('Vizoure Agent')/" "$ITEMS"
fi

# ─────────────────────────────────────────────
# 12. URL REBRANDING: zabbix.php → vizoure.php
# ─────────────────────────────────────────────
echo "[12/12] Rebranding URLs: zabbix.php -> vizoure.php..."

# Create vizoure.php as the real entry point
cp "$UI/zabbix.php" "$UI/vizoure.php"

# Fix ZBase.php routing to accept vizoure.php as valid entry point
ZBASE="$UI/include/classes/core/ZBase.php"
if [ -f "$ZBASE" ]; then
    sed -i "s/(\$file === 'zabbix.php')/(\$file === 'zabbix.php' || \$file === 'vizoure.php')/" "$ZBASE"
    sed -i "s/redirect('zabbix.php?action=system.warning')/redirect('vizoure.php?action=system.warning')/" "$ZBASE"
fi

# Replace hardcoded zabbix.php in all JS files
grep -rln "'zabbix\.php'\|\"zabbix\.php\"" "$UI/js/" 2>/dev/null | \
    xargs sed -i "s/'zabbix\.php'/'vizoure.php'/g; s/\"zabbix\.php\"/\"vizoure.php\"/g" 2>/dev/null || true

grep -rln "'zabbix\.php'\|\"zabbix\.php\"" "$UI/widgets/" 2>/dev/null | \
    xargs sed -i "s/'zabbix\.php'/'vizoure.php'/g; s/\"zabbix\.php\"/\"vizoure.php\"/g" 2>/dev/null || true

# Replace hardcoded zabbix.php in all PHP files
grep -rln "zabbix\.php" "$UI/include/" 2>/dev/null | \
    grep "\.php$" | grep -v ".bak\|.po\|.mo" | \
    xargs sed -i "s/'zabbix\.php'/'vizoure.php'/g; s/\"zabbix\.php\"/\"vizoure.php\"/g; s/zabbix\.php?/vizoure.php?/g" 2>/dev/null || true

grep -rln "zabbix\.php" "$UI/app/" 2>/dev/null | \
    grep "\.php$" | grep -v ".bak" | \
    xargs sed -i "s/'zabbix\.php'/'vizoure.php'/g; s/\"zabbix\.php\"/\"vizoure.php\"/g; s/zabbix\.php?/vizoure.php?/g" 2>/dev/null || true

echo "  URL rebranding complete"


# ─────────────────────────────────────────────
# 13. ADDITIONAL SCATTERED LABELS
# ─────────────────────────────────────────────
echo "  Fixing additional scattered labels..."

# Zabbix agent (active) label
sed -i "s/ITEM_TYPE_ZABBIX_ACTIVE => _('Zabbix agent (active)')/ITEM_TYPE_ZABBIX_ACTIVE => _('Vizoure Agent (active)')/" \
    "$UI/include/items.inc.php" 2>/dev/null || true

# Connector protocol
sed -i "s/_('Zabbix Streaming Protocol v1.0')/_('Vizoure Streaming Protocol v1.0')/" \
    "$UI/app/views/connector.edit.php" 2>/dev/null || true

# Misc config + proxy vault labels
for FILE in "$UI/app/views/administration.miscconfig.edit.php" "$UI/app/views/proxy.edit.php"; do
    [ -f "$FILE" ] || continue
    sed -i "s/Zabbix server: secrets are retrieved/Vizoure Server: secrets are retrieved/g" "$FILE"
    sed -i "s/Zabbix server and proxy: secrets are retrieved/Vizoure Server and proxy: secrets are retrieved/g" "$FILE"
    sed -i "s/by Zabbix server and forwarded/by Vizoure Server and forwarded/g" "$FILE"
    sed -i "s/by both Zabbix server and proxies/by both Vizoure Server and proxies/g" "$FILE"
    sed -i "s/_('Zabbix server')/_('Vizoure Server')/g" "$FILE"
    sed -i "s/_('Zabbix server and proxy')/_('Vizoure Server and proxy')/g" "$FILE"
done

# CItemData descriptions
sed -i "s/Returns 1 - for Zabbix agent; 2 - for Zabbix agent 2/Returns 1 - for Vizoure Agent; 2 - for Vizoure Agent 2/" \
    "$UI/include/classes/data/CItemData.php" 2>/dev/null || true
sed -i "s/Version of Zabbix agent\. Returns string/Version of Vizoure Agent. Returns string/" \
    "$UI/include/classes/data/CItemData.php" 2>/dev/null || true

# Widget manifest.json author
find "$UI/widgets" -name "manifest.json" \
    -exec sed -i 's/"author": "Zabbix"/"author": "Vizoure"/' {} \; 2>/dev/null || true

echo "  Additional labels updated"

echo "[11/11] Restarting Apache..."
systemctl restart apache2

echo ""
echo "=== Vizoure NMS Branding Applied Successfully ==="
