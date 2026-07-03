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
# 1. LOGO + FAVICON — download from repo
# ─────────────────────────────────────────────
echo "[1/8] Installing logo and favicon assets..."

mkdir -p "$UI/assets/img"

curl -sSL "${REPO_RAW}/branding/logos/logo.png" -o /tmp/vizoure-logo-raw.png
curl -sSL "${REPO_RAW}/branding/logos/favicon.png" -o /tmp/vizoure-favicon-raw.png
curl -sSL "${REPO_RAW}/branding/logos/favicon.ico" -o /tmp/vizoure-favicon.ico
curl -sSL "${REPO_RAW}/branding/logos/login-bg.png" -o "$UI/assets/img/login_background.png"

# Resize header/sidebar logo to proper height (avoids oversized banner bug)
convert /tmp/vizoure-logo-raw.png -resize x40 "$UI/assets/img/logo.png"

# Build a proper square compact icon for collapsed sidebar
convert /tmp/vizoure-favicon-raw.png -resize 32x32 -gravity center \
    -background none -extent 32x32 "$UI/assets/img/logo-compact.png"

cp /tmp/vizoure-favicon-raw.png "$UI/assets/img/favicon.png"

# CRITICAL: favicon.ico must exist at BOTH locations —
# UI root (actual served path: href="favicon.ico" resolves relative to /vizoure/)
# AND assets/img (used by some internal references)
cp /tmp/vizoure-favicon.ico "$UI/assets/img/favicon.ico"
cp /tmp/vizoure-favicon.ico "$UI/favicon.ico"

# Touch icons (mobile/bookmark)
convert /tmp/vizoure-favicon-raw.png -resize 76x76   "$UI/assets/img/apple-touch-icon-76x76-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 120x120 "$UI/assets/img/apple-touch-icon-120x120-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 152x152 "$UI/assets/img/apple-touch-icon-152x152-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 180x180 "$UI/assets/img/apple-touch-icon-180x180-precomposed.png"
convert /tmp/vizoure-favicon-raw.png -resize 192x192 "$UI/assets/img/touch-icon-192x192.png"

echo "  Logo, favicon, touch-icons installed"

# ─────────────────────────────────────────────
# 2. LOGO SIZE CSS FIX
# ─────────────────────────────────────────────
echo "[2/8] Applying logo sizing CSS..."

cat >> "$UI/assets/styles/blue-theme.css" << 'CSSEOF'

.header-logo img, .sidebar-logo img {
    max-height: 40px !important;
    width: auto !important;
}
CSSEOF

# ─────────────────────────────────────────────
# 3. BRAND CONFIG — activates Zabbix's built-in
#    rebranding system (removes Support/Integrations
#    from sidebar + login page automatically)
# ─────────────────────────────────────────────
echo "[3/8] Creating brand.conf.php..."

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
# 4. FOOTER COPYRIGHT (comment block, cosmetic)
# ─────────────────────────────────────────────
echo "[4/8] Fixing footer copyright comment..."
sed -i 's/Zabbix SIA/Vizoure/' "$UI/app/partials/layout.htmlpage.footer.php" 2>/dev/null || true

# ─────────────────────────────────────────────
# 5. REMOVE HELP LINK FROM LOGIN PAGE
# ─────────────────────────────────────────────
echo "[5/8] Removing Help link from login page..."

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
    print("  WARNING: login.php block pattern not found (Zabbix version may differ) — skipped")
PYEOF

# ─────────────────────────────────────────────
# 6. REMOVE HELP FROM SIDEBAR MENU
# ─────────────────────────────────────────────
echo "[6/8] Removing Help from sidebar menu..."

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
echo "[7/8] Setting browser title..."
DEFINES=$(find "$UI" -name "defines.inc.php" | head -1)
if [ -n "$DEFINES" ]; then
    sed -i "s/define('ZBX_TITLE'.*/define('ZBX_TITLE', 'Vizoure NMS');/" "$DEFINES"
fi

# ─────────────────────────────────────────────
# 8. RESTART SERVICES
# ─────────────────────────────────────────────
echo "[8/8] Restarting Apache..."
systemctl restart apache2

echo ""
echo "=== Vizoure NMS Branding Applied Successfully ==="

# ─────────────────────────────────────────────
# 9. SYSTEM INFO WIDGET LABELS
# ─────────────────────────────────────────────
echo "[9/9] Fixing System Information widget labels..."

SYSINFO="$UI/app/partials/administration.system.info.php"
if [ -f "$SYSINFO" ]; then
    sed -i "s/_('Zabbix server is running')/_('Vizoure NMS Server Status')/" "$SYSINFO"
    sed -i "s/_('Zabbix server version')/_('Vizoure NMS Version')/" "$SYSINFO"
    sed -i "s/_('Zabbix frontend version')/_('Vizoure Web Console Version')/" "$SYSINFO"
    echo "  System Info widget labels updated"
fi
