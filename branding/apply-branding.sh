#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS — Complete Branding Application
# Run AFTER base Zabbix install completes
# ─────────────────────────────────────────────

# ISS-34: same ref variable as install-nms.sh/upgrade.sh (exported by them).
VIZOURE_REF="${VIZOURE_REF:-main}"
REPO_RAW="https://raw.githubusercontent.com/sadiqawan/Vizoure/${VIZOURE_REF}"
UI="/usr/share/zabbix/ui"

# ISS-30 fix (md/04): local-first, GitHub-fallback for every asset this
# script fetches (not just the new header files) — "local" means a
# "branding" sibling directory next to wherever this script itself was
# invoked from (e.g. /tmp/vizoure-branding/apply-branding.sh with
# /tmp/vizoure-branding/logos/ and /tmp/vizoure-branding/header/ alongside
# it, exactly what install-nms.sh/upgrade.sh now set up when run from a
# real repo checkout).
BRANDING_LOCAL_DIR="$(dirname "$(readlink -f "$0")")"

fetch_local_or_github() {
    local local_path="$1" repo_path="$2" dest="$3"
    if [ -f "$local_path" ]; then
        cp "$local_path" "$dest"
        echo "  $(basename "$dest"): copied from local checkout"
    else
        # -f: a 404 must fail the run, never be saved as the asset (set -e).
        curl -fsSL "${REPO_RAW}/${repo_path}" -o "$dest"
        echo "  $(basename "$dest"): fetched from GitHub (no local copy found)"
    fi
}

echo "=== Applying Vizoure NMS Branding ==="

# ─────────────────────────────────────────────
# 1. LOGO + FAVICON
# ─────────────────────────────────────────────
echo "[1/11] Installing logo and favicon assets..."

mkdir -p "$UI/assets/img"

fetch_local_or_github "$BRANDING_LOCAL_DIR/logos/logo.png" "branding/logos/logo.png" /tmp/vizoure-logo-raw.png
fetch_local_or_github "$BRANDING_LOCAL_DIR/logos/favicon.png" "branding/logos/favicon.png" /tmp/vizoure-favicon-raw.png
fetch_local_or_github "$BRANDING_LOCAL_DIR/logos/favicon.ico" "branding/logos/favicon.ico" /tmp/vizoure-favicon.ico
fetch_local_or_github "$BRANDING_LOCAL_DIR/logos/login-bg.png" "branding/logos/login-bg.png" "$UI/assets/img/login_background.png"

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
CSS_BLOCK='.header-logo img, .sidebar-logo img {
    max-height: 40px !important;
    width: auto !important;
}'
# Wait up to 30s for CSS files to be available (package unpack timing)
for i in $(seq 1 6); do
    if [ -f "$UI/assets/styles/blue-theme.css" ]; then
        break
    fi
    echo "  Waiting for CSS files... (${i}/6)"
    sleep 5
done
for THEME in blue-theme dark-theme hc-dark hc-light; do
    CSSFILE="$UI/assets/styles/${THEME}.css"
    if [ -f "$CSSFILE" ]; then
        echo "$CSS_BLOCK" >> "$CSSFILE"
        echo "  Applied logo CSS to ${THEME}.css"
    else
        echo "  WARNING: ${THEME}.css not found — skipping"
    fi
done

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

# Timeouts page "Zabbix agent" label
TIMEOUTS="$UI/app/views/administration.timeouts.edit.php"
if [ -f "$TIMEOUTS" ]; then
    sed -i "s/_('Zabbix agent'), 'timeout_zabbix_agent'/_('Vizoure Agent'), 'timeout_zabbix_agent'/" "$TIMEOUTS"
fi

# Queue overview "Zabbix internal" label
if [ -f "$ITEMS" ]; then
    sed -i "s/ITEM_TYPE_INTERNAL => _('Zabbix internal')/ITEM_TYPE_INTERNAL => _('Vizoure Internal')/" "$ITEMS"
fi

# Media type default email
MEDIATYPEHELPER="$UI/include/classes/helpers/CMediatypeHelper.php"
if [ -f "$MEDIATYPEHELPER" ]; then
    sed -i "s/'smtp_email' => 'zabbix@example.com'/'smtp_email' => 'noreply@vizoure.local'/g" "$MEDIATYPEHELPER"
fi

# ZBX_DEFAULT_AGENT (browser tab title)
DEFINES="$UI/include/defines.inc.php"
if [ -f "$DEFINES" ]; then
    sed -i "s/define('ZBX_DEFAULT_AGENT', 'Zabbix')/define('ZBX_DEFAULT_AGENT', 'Vizoure')/" "$DEFINES"
fi

# PHP max_input_time fix
PHP_INI="/etc/php/8.3/apache2/php.ini"
if [ -f "$PHP_INI" ]; then
    sed -i 's/^max_input_time = 60/max_input_time = 300/' "$PHP_INI"
fi


# GUI page "Show warning if Zabbix server is down"
GUIEDIT="$UI/app/views/administration.gui.edit.php"
if [ -f "$GUIEDIT" ]; then
    sed -i "s/_('Show warning if Zabbix server is down')/_('Show warning if Vizoure server is down')/" "$GUIEDIT"
fi

# Item type "Zabbix trapper" -> "Vizoure Trapper"
if [ -f "$UI/include/items.inc.php" ]; then
    sed -i "s/ITEM_TYPE_TRAPPER => _('Zabbix trapper')/ITEM_TYPE_TRAPPER => _('Vizoure Trapper')/" \
        "$UI/include/items.inc.php"
fi

# Web scenario agent dropdown "Zabbix" -> "Vizoure"
HTTPTEST="$UI/include/httptest.inc.php"
if [ -f "$HTTPTEST" ]; then
    sed -i "s/ZBX_DEFAULT_AGENT => 'Zabbix'/ZBX_DEFAULT_AGENT => 'Vizoure'/" "$HTTPTEST"
fi
echo "  Additional UI strings and PHP config updated"
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


# Page header title fallback fix
PAGEHEADER="$UI/include/page_header.php"
if [ -f "$PAGEHEADER" ]; then
    sed -i "s/: _('Zabbix');/: '';/" "$PAGEHEADER"
fi

# CHtmlPageHeader Author meta tag
HTMLHEADER="$UI/include/classes/html/CHtmlPageHeader.php"
if [ -f "$HTMLHEADER" ]; then
    sed -i "s/content=\"Zabbix SIA\"/content=\"Vizoure\"/" "$HTMLHEADER"
fi

# ─────────────────────────────────────────────
# 14. TOP HEADER (replaces the sidebar)
# ─────────────────────────────────────────────
echo "[14/14] Installing horizontal top header..."

# ISS-30 fix (md/04): local-first, GitHub-fallback, same helper defined at
# the top of this script (now also used for the logo/favicon downloads).
fetch_local_or_github "$BRANDING_LOCAL_DIR/header/top-header.css" \
    "branding/header/top-header.css" "$UI/assets/styles/vizoure-top-header.css"
fetch_local_or_github "$BRANDING_LOCAL_DIR/header/top-header.js" \
    "branding/header/top-header.js" "$UI/js/vizoure-top-header.js"

# --- new partial: app/partials/layout.htmlpage.topheader.php ---
# Not fetched (local or GitHub) at all — written directly here, same pattern
# already used for local/conf/brand.conf.php above. Marker-guarded: only
# (re)written if missing or not yet carrying the marker, so a re-run doesn't
# need to touch it once it's current.
TOPHEADER_PHP="$UI/app/partials/layout.htmlpage.topheader.php"
# V3 marker: the partial gained the Super-admin "update available" badge (ISS-36),
# so a file carrying an older marker is rewritten.
if [ -f "$TOPHEADER_PHP" ] && grep -q "VIZOURE_TOPHEADER_PARTIAL_V3" "$TOPHEADER_PHP"; then
    echo "  layout.htmlpage.topheader.php already present — skipping"
else
    cat > "$TOPHEADER_PHP" << 'TOPHEADEREOF'
<?php
/* VIZOURE_TOPHEADER_PARTIAL_V3 — horizontal top header, replaces the sidebar.
 * Reuses the exact same menu.main / menu.user components as the stock
 * sidebar (CMenuHelper::getMainMenu()/getUserMenu(), registered once in
 * ZBase.php) — role filtering and active-page selection are inherited
 * automatically, nothing here re-implements them.
 *
 * @var CPartial $this
 * @var array $data
 */

$logo = (new CLink(
	[makeLogo(LOGO_TYPE_SIDEBAR), makeLogo(LOGO_TYPE_SIDEBAR_COMPACT)],
	CMenuHelper::getFirstUrl()
))->addClass(ZBX_STYLE_LOGO);

// Server name is intentionally not rendered in the top bar (ISS-32).

$search_icon = (new CButtonIcon(ZBX_ICON_SEARCH, _('Search')))
	->addClass('js-search')
	->setAttribute('type', 'submit');

if (getRequest('search', '') === '') {
	$search_icon->setAttribute('disabled', '');
}

$search_form = (new CForm('get', 'zabbix.php'))
	->addClass(ZBX_STYLE_FORM_SEARCH)
	->addClass('submenu')
	->setAttribute('role', 'search')
	->addItem([
		(new CVar('action', 'search'))->removeId(),
		(new CTextBox('search', getRequest('search', ''), false, 255))
			->addClass(ZBX_STYLE_SEARCH)
			->setAttribute('aria-label', _('type here to search'))
			->disableAutocomplete(),
		$search_icon
	]);

$search_toggle = (new CButtonIcon(ZBX_ICON_SEARCH, _('Search')))
	->addClass('vz-search-toggle')
	->setAttribute('type', 'button')
	->setAttribute('aria-label', _('Search'))
	->setAttribute('aria-expanded', 'false');

// "Update available" badge (ISS-36): Super admin only. Reads the status file the ROOT updater writes;
// the web side never talks to GitHub.
$updates_badge = null;

if ((int) (CWebUser::$data['type'] ?? 0) === USER_TYPE_SUPER_ADMIN) {
	$vz_state = json_decode((string) @file_get_contents('/var/lib/vizoure-updater/state.json', false, null, 0,
		2097152), true
	);
	$vz_version = is_array($vz_state) ? (string) ($vz_state['update_available']['version'] ?? '') : '';

	if (preg_match('/^v\d+\.\d+\.\d+-vz\d+$/', $vz_version)) {
		$updates_badge = (new CLink(_('Updates'),
			(new CUrl('vizoure.php'))->setArgument('action', 'vizoure.updates.view')
		))
			->addClass('vz-updates-badge')
			->setAttribute('title', _s('Update available: %1$s', $vz_version))
			->setAttribute('aria-label', _s('Update available: %1$s', $vz_version));
	}
}

$hamburger = (new CTag('button', true, (new CTag('span', true))))
	->addClass('vz-hamburger')
	->setAttribute('type', 'button')
	->setAttribute('aria-label', _('Menu'))
	->setAttribute('aria-expanded', 'false')
	->setAttribute('aria-controls', 'vz-top-nav');

(new CTag('header', true))
	->addClass('vizoure-top-header')
	->setId('vizoure-top-header')
	->addItem([
		(new CDiv($logo))->addClass('vz-header-left'),
		(new CTag('nav', true, APP::Component()->get('menu.main')->addClass('menu-main')))
			->addClass('vz-header-nav')
			->setId('vz-top-nav')
			->setAttribute('role', 'navigation')
			->setAttribute('aria-label', _('Main navigation')),
		(new CDiv([
			$updates_badge,
			(new CDiv([$search_toggle, $search_form]))->addClass('vz-search'),
			(new CTag('nav', true, APP::Component()->get('menu.user')->addClass('menu-user')))
				->addClass('vz-header-user')
				->setAttribute('role', 'navigation')
				->setAttribute('aria-label', _('User menu'))
		]))->addClass('vz-header-right'),
		$hamburger
	])
	->show();
TOPHEADEREOF
    echo "  layout.htmlpage.topheader.php written"
fi

# --- patch app/views/layout.htmlpage.php: render the top header instead of
#     the sidebar. Marker-guarded; anchor-checked; fails loudly (not a
#     silent skip) if the expected original text isn't found, per the rule
#     that every core-file patch must do this from now on. ---
LAYOUT_VIEW="$UI/app/views/layout.htmlpage.php"
if grep -q "VIZOURE_TOPHEADER_PATCH" "$LAYOUT_VIEW"; then
    echo "  layout.htmlpage.php already patched — skipping"
elif grep -qF -- "new CPartial('layout.htmlpage.aside'" "$LAYOUT_VIEW"; then
    sed -i "s/new CPartial('layout.htmlpage.aside'/new CPartial('layout.htmlpage.topheader' \/* VIZOURE_TOPHEADER_PATCH *\//" "$LAYOUT_VIEW"
    echo "  layout.htmlpage.php patched to render the top header"
else
    echo "ERROR: Zabbix version mismatch, patch layout.htmlpage.php not applied"
    exit 1
fi

# --- patch app/partials/layout.htmlpage.header.php: load our CSS/JS on
#     every normal page. Same marker/anchor/loud-failure rule as above. ---
HEADER_PARTIAL="$UI/app/partials/layout.htmlpage.header.php"
if grep -q "VIZOURE_TOPHEADER_PATCH" "$HEADER_PARTIAL"; then
    echo "  layout.htmlpage.header.php already patched — skipping"
elif grep -qF -- "->addJsFile((new CUrl('js/browsers.js'))->getUrl())" "$HEADER_PARTIAL"; then
    sed -i "s#->addJsFile((new CUrl('js/browsers.js'))->getUrl())#->addJsFile((new CUrl('js/browsers.js'))->getUrl()) \/\/ VIZOURE_TOPHEADER_PATCH\n\t\t->addJsFile((new CUrl('js/vizoure-top-header.js'))->getUrl())\n\t\t->addCssFile((new CUrl('assets/styles/vizoure-top-header.css'))->getUrl())#" "$HEADER_PARTIAL"
    echo "  layout.htmlpage.header.php patched to load top-header.css/js"
else
    echo "ERROR: Zabbix version mismatch, patch layout.htmlpage.header.php not applied"
    exit 1
fi

# --- patch include/page_header.php: legacy-style pages (sysmaps.php, etc.)
#     bypass layout.htmlpage.php entirely and render the sidebar directly
#     from here (found 2026-10-16, ISS-32 — Maps still showed the old
#     sidebar). Two independent edits, each with its own idempotency check
#     (so a half-applied state can never be skipped) and its own anchor
#     check; fail loudly if an anchor is gone. ---
LEGACY_HEADER="$UI/include/page_header.php"

if grep -q "VIZOURE_TOPHEADER_PATCH" "$LEGACY_HEADER"; then
    echo "  page_header.php: partial swap already applied — skipping"
elif grep -qF -- "new CPartial('layout.htmlpage.aside'" "$LEGACY_HEADER"; then
    sed -i "s/new CPartial('layout.htmlpage.aside'/new CPartial('layout.htmlpage.topheader' \/* VIZOURE_TOPHEADER_PATCH *\//" "$LEGACY_HEADER"
    echo "  page_header.php: sidebar partial swapped for the top header"
else
    echo "ERROR: Zabbix version mismatch, patch include/page_header.php (partial swap) not applied"
    exit 1
fi

if grep -qF "vizoure-top-header.js" "$LEGACY_HEADER"; then
    echo "  page_header.php: CSS/JS load already applied — skipping"
elif grep -qF -- "->addJsFile((new CUrl('js/browsers.js'))->getUrl());" "$LEGACY_HEADER"; then
    sed -i "s#->addJsFile((new CUrl('js/browsers.js'))->getUrl());#->addJsFile((new CUrl('js/browsers.js'))->getUrl())\n\t\t->addJsFile((new CUrl('js/vizoure-top-header.js'))->getUrl())\n\t\t->addCssFile((new CUrl('assets/styles/vizoure-top-header.css'))->getUrl());#" "$LEGACY_HEADER"
    echo "  page_header.php: top-header.css/js load added"
else
    echo "ERROR: Zabbix version mismatch, patch include/page_header.php (CSS/JS load) not applied"
    exit 1
fi

# --- per-theme color blocks, appended to each theme's own compiled CSS,
#     using THAT theme's real extracted values (md/04 plan) — marker-guarded
#     so a re-run never duplicates (unlike the older logo-CSS step above,
#     logged as ISS-31 for Batch 2, left as-is for now). ---
append_theme_css() {
    local theme_file="$1" block="$2"
    if [ ! -f "$theme_file" ]; then
        echo "  WARNING: $theme_file not found — skipping top-header colors"
        return
    fi
    if grep -q "VIZOURE_TOPHEADER_CSS_V2" "$theme_file"; then
        echo "  $(basename "$theme_file"): top-header colors already present — skipping"
    else
        printf '%s\n' "$block" >> "$theme_file"
        echo "  $(basename "$theme_file"): top-header colors applied"
    fi
}

append_theme_css "$UI/assets/styles/blue-theme.css" '
/* VIZOURE_TOPHEADER_CSS_V2 (blue-theme — real values from .sidebar/.menu-main in this file) */
.vizoure-top-header { background: #0a466a; }
.vizoure-top-header .menu-main > li > a, .vizoure-top-header .menu-user > li > a, .vizoure-top-header .vz-search-toggle, .vizoure-top-header .vz-more > a { color: #ebeef0; }
.vizoure-top-header .menu-main > li > a:hover, .vizoure-top-header .menu-main > li > a:focus,
.vizoure-top-header .menu-user > li > a:hover, .vizoure-top-header .menu-user > li > a:focus, .vizoure-top-header .vz-search-toggle:hover, .vizoure-top-header .vz-search-toggle:focus, .vizoure-top-header .vz-more > a:hover, .vizoure-top-header .vz-more > a:focus { background: #092637; color: #ffffff; }
.vizoure-top-header .menu-main > li.is-selected > a { background: #0a3c5b; border-bottom-color: #87d1ff; color: #ffffff; }
.vizoure-top-header .menu-main [class^="zi-"]::before, .vizoure-top-header .menu-main [class*=" zi-"]::before,
.vizoure-top-header .menu-user [class^="zi-"]::before, .vizoure-top-header .menu-user [class*=" zi-"]::before, .vizoure-top-header .vz-search-toggle::before { color: #8cb2ca; }
.vizoure-top-header .submenu { background: #051620; }
.vizoure-top-header .submenu a { background: #0e354d; color: #ebeef0; }
.vizoure-top-header .submenu a:hover, .vizoure-top-header .submenu a:focus { background: #092637; color: #ffffff; }
.vizoure-top-header .submenu > li.is-selected > a { background: #0b2d42; color: #ffffff; }
.vizoure-top-header .vz-hamburger { color: #ebeef0; }'

append_theme_css "$UI/assets/styles/dark-theme.css" '
/* VIZOURE_TOPHEADER_CSS_V2 (dark-theme — real values from .sidebar/.menu-main in this file) */
.vizoure-top-header { background: #454545; }
.vizoure-top-header .menu-main > li > a, .vizoure-top-header .menu-user > li > a, .vizoure-top-header .vz-search-toggle, .vizoure-top-header .vz-more > a { color: #f2f2f2; }
.vizoure-top-header .menu-main > li > a:hover, .vizoure-top-header .menu-main > li > a:focus,
.vizoure-top-header .menu-user > li > a:hover, .vizoure-top-header .menu-user > li > a:focus, .vizoure-top-header .vz-search-toggle:hover, .vizoure-top-header .vz-search-toggle:focus, .vizoure-top-header .vz-more > a:hover, .vizoure-top-header .vz-more > a:focus { background: #0e0e0e; color: #ffffff; }
.vizoure-top-header .menu-main > li.is-selected > a { background: #202020; border-bottom-color: #c5c5c5; color: #ffffff; }
.vizoure-top-header .menu-main [class^="zi-"]::before, .vizoure-top-header .menu-main [class*=" zi-"]::before,
.vizoure-top-header .menu-user [class^="zi-"]::before, .vizoure-top-header .menu-user [class*=" zi-"]::before, .vizoure-top-header .vz-search-toggle::before { color: #9c9c9c; }
.vizoure-top-header .submenu { background: #0d0f11; }
.vizoure-top-header .submenu a { background: #2b2b2b; color: #f2f2f2; }
.vizoure-top-header .submenu a:hover, .vizoure-top-header .submenu a:focus { background: #0e0e0e; color: #ffffff; }
.vizoure-top-header .submenu > li.is-selected > a { background: #1c1c1c; color: #ffffff; }
.vizoure-top-header .vz-hamburger { color: #f2f2f2; }'

append_theme_css "$UI/assets/styles/hc-dark.css" '
/* VIZOURE_TOPHEADER_CSS_V2 (hc-dark — real values from .sidebar/.menu-main in this file) */
.vizoure-top-header { background: #ffffff; }
.vizoure-top-header .menu-main > li > a, .vizoure-top-header .menu-user > li > a, .vizoure-top-header .vz-search-toggle, .vizoure-top-header .vz-more > a { color: #000000; }
.vizoure-top-header .menu-main > li > a:hover, .vizoure-top-header .menu-main > li > a:focus,
.vizoure-top-header .menu-user > li > a:hover, .vizoure-top-header .menu-user > li > a:focus, .vizoure-top-header .vz-search-toggle:hover, .vizoure-top-header .vz-search-toggle:focus, .vizoure-top-header .vz-more > a:hover, .vizoure-top-header .vz-more > a:focus { background: #1a1a1a; color: #ffffff; }
.vizoure-top-header .menu-main > li.is-selected > a { background: #ffffff; border-bottom-color: #0c0c0c; color: #000000; }
.vizoure-top-header .menu-main [class^="zi-"]::before, .vizoure-top-header .menu-main [class*=" zi-"]::before,
.vizoure-top-header .menu-user [class^="zi-"]::before, .vizoure-top-header .menu-user [class*=" zi-"]::before, .vizoure-top-header .vz-search-toggle::before { color: #000000; }
.vizoure-top-header .submenu { background: #f3f3f3; }
.vizoure-top-header .submenu a { background: #cccccc; color: #000000; }
.vizoure-top-header .submenu a:hover, .vizoure-top-header .submenu a:focus { background: #1a1a1a; color: #ffffff; }
.vizoure-top-header .submenu > li.is-selected > a { background: #0c0c0c; color: #ffffff; }
.vizoure-top-header .vz-hamburger { color: #000000; }'

append_theme_css "$UI/assets/styles/hc-light.css" '
/* VIZOURE_TOPHEADER_CSS_V2 (hc-light — real values from .sidebar/.menu-main in this file) */
.vizoure-top-header { background: #000000; }
.vizoure-top-header .menu-main > li > a, .vizoure-top-header .menu-user > li > a, .vizoure-top-header .vz-search-toggle, .vizoure-top-header .vz-more > a { color: #ffffff; }
.vizoure-top-header .menu-main > li > a:hover, .vizoure-top-header .menu-main > li > a:focus,
.vizoure-top-header .menu-user > li > a:hover, .vizoure-top-header .menu-user > li > a:focus, .vizoure-top-header .vz-search-toggle:hover, .vizoure-top-header .vz-search-toggle:focus, .vizoure-top-header .vz-more > a:hover, .vizoure-top-header .vz-more > a:focus { background: #e6e6e6; color: #000000; }
.vizoure-top-header .menu-main > li.is-selected > a { background: #000000; border-bottom-color: #f3f3f3; color: #ffffff; }
.vizoure-top-header .menu-main [class^="zi-"]::before, .vizoure-top-header .menu-main [class*=" zi-"]::before,
.vizoure-top-header .menu-user [class^="zi-"]::before, .vizoure-top-header .menu-user [class*=" zi-"]::before, .vizoure-top-header .vz-search-toggle::before { color: #ffffff; }
.vizoure-top-header .submenu { background: #0d0d0d; }
.vizoure-top-header .submenu a { background: #333333; color: #ffffff; }
.vizoure-top-header .submenu a:hover, .vizoure-top-header .submenu a:focus { background: #e6e6e6; color: #000000; }
.vizoure-top-header .submenu > li.is-selected > a { background: #f3f3f3; color: #000000; }
.vizoure-top-header .vz-hamburger { color: #ffffff; }'

echo "  Top header installed"

# ─────────────────────────────────────────────
# 15. VIZOURE UPDATER + "Vizoure updates" MODULE (ISS-36)
# ─────────────────────────────────────────────
# The web UI (www-data) only writes upgrade REQUESTS into a spool directory; a root systemd
# service (vizoure-updater) validates and performs them. See md/09-update-system.md.
echo "[15/15] Installing the Vizoure updater and the updates module..."

command -v ssh-keygen >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
    || apt-get install -y -q openssh-client python3

VZ_STAGE="$(mktemp -d)"
if [ -f "$BRANDING_LOCAL_DIR/MANIFEST" ]; then
    VZ_MANIFEST="$BRANDING_LOCAL_DIR/MANIFEST"
else
    curl -fsSL "${REPO_RAW}/branding/MANIFEST" -o "$VZ_STAGE/MANIFEST"
    VZ_MANIFEST="$VZ_STAGE/MANIFEST"
fi
while IFS= read -r VZ_F; do
    case "$VZ_F" in updater/*|modules/*) ;; *) continue ;; esac
    mkdir -p "$VZ_STAGE/$(dirname "$VZ_F")"
    fetch_local_or_github "$BRANDING_LOCAL_DIR/$VZ_F" "branding/$VZ_F" "$VZ_STAGE/$VZ_F"
done < "$VZ_MANIFEST"
for VZ_NEED in updater/vizoure-updater.py updater/allowed_signers modules/vizoure-updates/manifest.json \
        modules/vizoure-updates/Module.php modules/vizoure-updates/actions/UpdatesBase.php; do
    [ -s "$VZ_STAGE/$VZ_NEED" ] || [ "$VZ_NEED" = "updater/allowed_signers" ] || {
        echo "ERROR: $VZ_NEED missing from branding/ (incomplete release package); updates module not installed"
        exit 1
    }
done

# --- frontend module (clean replace, so removed files never linger) ---
rm -rf "$UI/modules/vizoure-updates"
mkdir -p "$UI/modules"
cp -r "$VZ_STAGE/modules/vizoure-updates" "$UI/modules/vizoure-updates"
chown -R root:root "$UI/modules/vizoure-updates"
find "$UI/modules/vizoure-updates" -type d -exec chmod 755 {} +
find "$UI/modules/vizoure-updates" -type f -exec chmod 644 {} +

# --- register the module in Zabbix (idempotent; Zabbix reads enabled modules from the `module` table) ---
VZ_DB="vizoure"
VZ_MODID="$(mysql -uroot -N -e "SELECT moduleid FROM ${VZ_DB}.module WHERE id='vizoure.updates'" 2>/dev/null || true)"
if [ -z "$VZ_MODID" ]; then
    VZ_NEXT="$(mysql -uroot -N -e "SELECT COALESCE(MAX(moduleid),0)+1 FROM ${VZ_DB}.module")"
    mysql -uroot -e "INSERT INTO ${VZ_DB}.module (moduleid,id,relative_path,status,config) VALUES (${VZ_NEXT},'vizoure.updates','modules/vizoure-updates',1,'[]')"
    echo "  module registered (moduleid ${VZ_NEXT})"
else
    mysql -uroot -e "UPDATE ${VZ_DB}.module SET relative_path='modules/vizoure-updates', status=1 WHERE id='vizoure.updates'"
    echo "  module already registered (moduleid ${VZ_MODID}) - ensured enabled"
fi

# --- root updater service ---
install -d -m 0755 /usr/local/lib/vizoure-updater /etc/vizoure /var/lib/vizoure-updater /var/lib/vizoure-updater/run \
    /var/spool/vizoure-updater
install -d -m 0700 /var/backups/vizoure
# www-data may CREATE files here but not list/read them; the root service treats every file as hostile.
install -d -o root -g www-data -m 0730 /var/spool/vizoure-updater/requests /var/spool/vizoure-updater/uploads

# atomic replace (new inode): safe even if the updater is the process running this very script
install -m 0755 "$VZ_STAGE/updater/vizoure-updater.py" /usr/local/lib/vizoure-updater/.vizoure-updater.py.new
mv -f /usr/local/lib/vizoure-updater/.vizoure-updater.py.new /usr/local/lib/vizoure-updater/vizoure-updater.py
install -m 0644 "$VZ_STAGE/updater/allowed_signers" /etc/vizoure/.allowed_signers.new
mv -f /etc/vizoure/.allowed_signers.new /etc/vizoure/allowed_signers
[ -f /etc/vizoure/updater.conf ] || install -m 0644 "$VZ_STAGE/updater/updater.conf" /etc/vizoure/updater.conf

for VZ_UNIT in vizoure-updater.service vizoure-updater.path vizoure-updater-check.service vizoure-updater-check.timer; do
    install -m 0644 "$VZ_STAGE/updater/systemd/$VZ_UNIT" "/etc/systemd/system/$VZ_UNIT"
done
systemctl daemon-reload
systemctl enable vizoure-updater.path vizoure-updater-check.timer >/dev/null 2>&1
# start (never restart: this script may be running inside vizoure-updater.service itself)
systemctl start vizoure-updater.path vizoure-updater-check.timer
# first status report right away (the page would otherwise say "unknown" until the timer fires); never fatal
systemctl start --no-block vizoure-updater-check.service || true
rm -rf "$VZ_STAGE"
echo "  Vizoure updater installed"

echo "[11/11] Restarting Apache..."
systemctl restart apache2

echo ""
echo "=== Vizoure NMS Branding Applied Successfully ==="
