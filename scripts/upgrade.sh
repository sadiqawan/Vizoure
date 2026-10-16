#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────────
# Vizoure NMS — Upgrade Script
# Usage: sudo bash upgrade.sh [new_version]
# Example: sudo bash upgrade.sh 7.4.12
# ─────────────────────────────────────────────

# ISS-10 fix (md/04): no automatic rollback exists — this at least stops the
# script from leaving a silent, undiagnosed partial state (e.g. services left
# stopped). See README.md's "Recovery" section for the manual restore steps.
trap 'echo "ERROR: upgrade.sh failed at line $LINENO. A pre-upgrade backup should exist at ${BACKUP_FILE:-/tmp/vizoure-db-backup-*.sql.gz} — see README.md Recovery section before retrying." >&2' ERR

# Rule B / ISS-30 fix (md/04): same local-first logic as install-nms.sh.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" 2>/dev/null && pwd || echo "")"
REPO_ROOT_LOCAL=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../branding/apply-branding.sh" ]; then
    REPO_ROOT_LOCAL="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Single ref variable (ISS-34): branch or tag every GitHub fetch below uses
# (script, branding/ manifest, header files, logos). Default is main; set
# VIZOURE_REF=<tag-or-branch> to pin an install or to test a branch. Exported
# so apply-branding.sh (a child process) uses the very same ref.
VIZOURE_REF="${VIZOURE_REF:-main}"
export VIZOURE_REF
REPO_RAW="https://raw.githubusercontent.com/sadiqawan/Vizoure/${VIZOURE_REF}"
DB_NAME="vizoure"
DB_USER="vizoure"
DB_PASSWORD="AES@admin"
NEW_VERSION="${1:-}"

echo "========================================="
echo "  Vizoure NMS Upgrade"
echo "========================================="

if [ -z "$NEW_VERSION" ]; then
    echo "Usage: sudo bash upgrade.sh <new_version>"
    echo "Example: sudo bash upgrade.sh 7.4.12"
    exit 1
fi

echo "  Upgrading to Zabbix ${NEW_VERSION}..."
echo ""

# ─────────────────────────────────────────────
# 1. CHECK CURRENT VERSION
# ─────────────────────────────────────────────
echo "[1/6] Checking current version..."
CURRENT=$(dpkg -l zabbix-server-mysql 2>/dev/null | awk '/zabbix-server-mysql/{print $3}' | cut -d: -f2 | cut -d- -f1)
echo "  Current version: ${CURRENT:-unknown}"
echo "  Target version:  ${NEW_VERSION}"

# ─────────────────────────────────────────────
# 2. BACKUP DATABASE
# ─────────────────────────────────────────────
echo "[2/6] Backing up database..."
BACKUP_FILE="/tmp/vizoure-db-backup-$(date +%Y%m%d-%H%M%S).sql.gz"
mysqldump -u${DB_USER} -p${DB_PASSWORD} ${DB_NAME} | gzip > "$BACKUP_FILE"
echo "  Backup saved to: $BACKUP_FILE"

# ─────────────────────────────────────────────
# 3. STOP SERVICES
# ─────────────────────────────────────────────
echo "[3/6] Stopping services..."
systemctl stop zabbix-server zabbix-agent 2>/dev/null || true

# ─────────────────────────────────────────────
# 4. UPDATE ZABBIX PACKAGES
# ─────────────────────────────────────────────
echo "[4/6] Updating Zabbix packages..."
ZABBIX_VERSION=$(echo "$NEW_VERSION" | cut -d. -f1-2)

wget -q "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+ubuntu24.04_all.deb" \
    -O /tmp/zabbix-release-new.deb
dpkg -i /tmp/zabbix-release-new.deb
apt update -y -q

apt install -y \
    zabbix-server-mysql \
    zabbix-frontend-php \
    zabbix-apache-conf \
    zabbix-sql-scripts \
    zabbix-agent

# Force reinstall to ensure files are properly unpacked
apt install --reinstall -y zabbix-sql-scripts -q
apt install --reinstall -y zabbix-frontend-php -q

echo "  Packages updated to ${NEW_VERSION}"

# ─────────────────────────────────────────────
# 5. RUN DB UPGRADE + REBRANDING
# ─────────────────────────────────────────────
echo "[5/6] Upgrading database schema..."

# Zabbix handles schema upgrades automatically on server start
# But we need to reapply branding to any new DB entries

systemctl start zabbix-server
sleep 10  # Wait for schema upgrade to complete

echo "  Reapplying database branding..."
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET vendor_name = 'Vizoure' WHERE vendor_name = 'Zabbix' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET host = REPLACE(host, 'Zabbix', 'Vizoure') WHERE host LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.triggers SET description = REPLACE(description, 'Zabbix', 'Vizoure') WHERE description LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.items SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.actions SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.images SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%';"
echo "  Database branding updated"

# ─────────────────────────────────────────────
# 6. REAPPLY UI BRANDING
# ─────────────────────────────────────────────
echo "[6/6] Reapplying UI branding..."
systemctl restart apache2

rm -rf /tmp/vizoure-branding
if [ -n "$REPO_ROOT_LOCAL" ]; then
    echo "  Using local repo checkout at $REPO_ROOT_LOCAL/branding"
    cp -r "$REPO_ROOT_LOCAL/branding" /tmp/vizoure-branding
else
    # Standalone fallback (ISS-34): download the WHOLE branding/ set listed in
    # branding/MANIFEST (script + logos + header/*), not just apply-branding.sh.
    # curl -f + set -e: a missing file aborts loudly instead of installing a
    # "404: Not Found" page as a stylesheet.
    echo "  No local checkout found — fetching branding/ (ref ${VIZOURE_REF}) from GitHub"
    mkdir -p /tmp/vizoure-branding
    curl -fsSL "${REPO_RAW}/branding/MANIFEST" -o /tmp/vizoure-branding/MANIFEST
    while IFS= read -r BRANDING_FILE; do
        case "$BRANDING_FILE" in ""|\#*) continue ;; esac
        mkdir -p "/tmp/vizoure-branding/$(dirname "$BRANDING_FILE")"
        curl -fsSL "${REPO_RAW}/branding/${BRANDING_FILE}" -o "/tmp/vizoure-branding/${BRANDING_FILE}"
        test -s "/tmp/vizoure-branding/${BRANDING_FILE}"
    done < /tmp/vizoure-branding/MANIFEST
fi
chmod +x /tmp/vizoure-branding/apply-branding.sh
bash /tmp/vizoure-branding/apply-branding.sh

systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

echo ""
echo "========================================="
echo "  Vizoure NMS Upgrade Complete!"
echo "========================================="
echo "  Version: ${NEW_VERSION}"
echo "  Web UI:  http://$(hostname -I | awk '{print $1}')/vizoure"
echo "  Backup:  ${BACKUP_FILE}"
echo "========================================="
