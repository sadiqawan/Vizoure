#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────────
# Vizoure NMS — Upgrade Script
# Usage: sudo bash upgrade.sh [new_version]
# Example: sudo bash upgrade.sh 7.4.12
# ─────────────────────────────────────────────

REPO_RAW="https://raw.githubusercontent.com/sadiqawan/Vizoure/main"
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

rm -f /tmp/apply-branding.sh
curl -sSL "${REPO_RAW}/branding/apply-branding.sh" -o /tmp/apply-branding.sh
chmod +x /tmp/apply-branding.sh
bash /tmp/apply-branding.sh

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
