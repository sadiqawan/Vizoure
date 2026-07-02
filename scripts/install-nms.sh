#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Vizoure NMS - Automated Install Script
# Base: Zabbix 7.4.9 on Ubuntu 24.04
# Usage: curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/install-nms.sh | sudo bash
# ─────────────────────────────────────────────

REPO_RAW="https://raw.githubusercontent.com/sadiqawan/Vizoure/main"
DB_NAME="vizoure"
DB_USER="vizoure"
DB_PASSWORD="AES@admin"
OS_USERNAME="admin"
OS_PASSWORD="AES@admin"
ZABBIX_VERSION="7.4"
UI="/usr/share/zabbix/ui"

echo "========================================="
echo "  Vizoure NMS Installation Starting..."
echo "========================================="

# ─────────────────────────────────────────────
# 1. OS USER
# ─────────────────────────────────────────────
echo "[1/9] Setting up OS user..."
if id "$OS_USERNAME" &>/dev/null; then
    echo "${OS_USERNAME}:${OS_PASSWORD}" | chpasswd
else
    useradd -m -s /bin/bash "$OS_USERNAME"
    echo "${OS_USERNAME}:${OS_PASSWORD}" | chpasswd
    usermod -aG sudo "$OS_USERNAME"
fi
chage -d 0 "$OS_USERNAME"
echo "  OS user ready"

# ─────────────────────────────────────────────
# 2. SYSTEM UPDATE
# ─────────────────────────────────────────────
echo "[2/9] Updating system..."
apt update -y && apt upgrade -y
apt install -y curl wget git python3

# ─────────────────────────────────────────────
# 3. MYSQL
# ─────────────────────────────────────────────
echo "[3/9] Installing MySQL..."
apt install -y mysql-server
systemctl start mysql
systemctl enable mysql

# ─────────────────────────────────────────────
# 4. ZABBIX REPO + PACKAGES
# ─────────────────────────────────────────────
echo "[4/9] Installing Zabbix packages..."
wget -q https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+ubuntu24.04_all.deb
dpkg -i zabbix-release_latest_${ZABBIX_VERSION}+ubuntu24.04_all.deb
apt update -y
apt install -y \
    zabbix-server-mysql \
    zabbix-frontend-php \
    zabbix-apache-conf \
    zabbix-sql-scripts \
    zabbix-agent

# ─────────────────────────────────────────────
# 5. DATABASE
# ─────────────────────────────────────────────
echo "[5/9] Setting up database..."
mysql -uroot <<SQLEOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '"'"'${DB_USER}'"'"'@'"'"'localhost'"'"' IDENTIFIED BY '"'"'${DB_PASSWORD}'"'"';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '"'"'${DB_USER}'"'"'@'"'"'localhost'"'"';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
SQLEOF

echo "  Importing schema..."
zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | \
    mysql --default-character-set=utf8mb4 -u${DB_USER} -p${DB_PASSWORD} ${DB_NAME}

mysql -uroot <<SQLEOF
SET GLOBAL log_bin_trust_function_creators = 0;
SQLEOF

# ─────────────────────────────────────────────
# 6. CONFIGURE ZABBIX SERVER
# ─────────────────────────────────────────────
echo "[6/9] Configuring server..."
sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^DBName=.*/DBName=${DB_NAME}/"               /etc/zabbix/zabbix_server.conf
sed -i "s/^DBUser=.*/DBUser=${DB_USER}/"               /etc/zabbix/zabbix_server.conf

# Apache config — /vizoure pointing to correct /ui path
ZABBIX_CONF=$(find /etc/apache2/conf-available -name "*zabbix*.conf" | head -1)
if [ -n "$ZABBIX_CONF" ]; then
    CONF_NAME=$(basename "$ZABBIX_CONF" .conf)
    a2disconf "$CONF_NAME" 2>/dev/null || true
fi

cat > /etc/apache2/conf-available/vizoure.conf << APACHEEOF
Alias /vizoure /usr/share/zabbix/ui

<Directory "/usr/share/zabbix/ui">
    Options FollowSymLinks
    AllowOverride None
    Require all granted

    <IfModule mod_php.c>
        php_value max_execution_time 300
        php_value memory_limit 128M
        php_value post_max_size 16M
        php_value upload_max_filesize 2M
        php_value max_input_time 300
        php_value always_populate_raw_post_data -1
    </IfModule>
</Directory>
APACHEEOF
a2enconf vizoure

# Frontend DB config — skip setup wizard
mkdir -p /etc/zabbix/web
cat > /etc/zabbix/web/zabbix.conf.php << PHPEOF
<?php
\$DB["TYPE"]           = "MYSQL";
\$DB["SERVER"]         = "localhost";
\$DB["PORT"]           = "0";
\$DB["DATABASE"]       = "${DB_NAME}";
\$DB["USER"]           = "${DB_USER}";
\$DB["PASSWORD"]       = "${DB_PASSWORD}";
\$DB["SCHEMA"]         = "";
\$DB["ENCRYPTION"]     = false;
\$DB["DOUBLE_IEEE754"] = true;
\$ZBX_SERVER           = "localhost";
\$ZBX_SERVER_PORT      = "10051";
\$ZBX_SERVER_NAME      = "Vizoure NMS";
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
PHPEOF

# ─────────────────────────────────────────────
# 7. BRANDING
# ─────────────────────────────────────────────
echo "[7/9] Applying Vizoure branding..."

# Wait for UI files to be available
sleep 2

# Browser title
DEFINES=$(find /usr/share/zabbix/ui -name "defines.inc.php" | head -1)
if [ -n "$DEFINES" ]; then
    sed -i "s/define('ZBX_TITLE'.*/define('ZBX_TITLE', 'Vizoure NMS');/" "$DEFINES"
fi

# Download and install logo files from repo
mkdir -p /usr/share/zabbix/ui/assets/img

curl -sSL "${REPO_RAW}/branding/logos/logo.png" \
    -o /usr/share/zabbix/ui/assets/img/logo.png

curl -sSL "${REPO_RAW}/branding/logos/favicon.png" \
    -o /usr/share/zabbix/ui/assets/img/favicon.ico

curl -sSL "${REPO_RAW}/branding/logos/favicon.png" \
    -o /usr/share/zabbix/ui/assets/img/favicon.png

curl -sSL "${REPO_RAW}/branding/logos/login-bg.png" \
    -o /usr/share/zabbix/ui/assets/img/login_background.png

# Remove Zabbix SIA copyright + Help/Support from login page
LOGIN_FILE=$(find /usr/share/zabbix/ui/app/views -name "*login*" 2>/dev/null | head -1)
if [ -n "$LOGIN_FILE" ]; then
    sed -i "/Zabbix SIA/d" "$LOGIN_FILE"
    sed -i "/2001.*$(date +%Y)/d" "$LOGIN_FILE"
    sed -i "/Help.*Support/d" "$LOGIN_FILE"
    sed -i "s/Zabbix/Vizoure/g" "$LOGIN_FILE"
fi

# Remove Help/Support/Integrations from sidebar
for f in $(find /usr/share/zabbix/ui/app/views -name "*.php" 2>/dev/null); do
    sed -i "/\'Support\'/d" "$f"
    sed -i "/\'Integrations\'/d" "$f"
    sed -i "/\'Help\'/d" "$f"
done

# Replace Zabbix in include/locale files only (safe)
find /usr/share/zabbix/ui/include -name "*.php" | while read f; do
    sed -i "s/Zabbix SIA/Vizoure/g" "$f"
done

echo "  Branding applied"

# ─────────────────────────────────────────────
# 8. START SERVICES
# ─────────────────────────────────────────────
echo "[8/9] Starting services..."
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

# ─────────────────────────────────────────────
# 9. POST-INSTALL API CONFIGURATION
# ─────────────────────────────────────────────
echo "[9/9] Configuring via API..."

ZBX_URL="http://localhost/vizoure/api_jsonrpc.php"

echo "  Waiting for API..."
if timeout 120 bash -c \
    "until curl -s $ZBX_URL >/dev/null 2>&1; do sleep 2; done"; then
    echo "  API ready"
else
    echo "  ERROR: API not responding after 120s"
    echo "  Check: systemctl status zabbix-server apache2"
    exit 1
fi

# Login with default password
TOKEN=$(curl -s -X POST "$ZBX_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result',''))" 2>/dev/null)

if [ -n "$TOKEN" ]; then
    # Change Admin password
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.update\",\"params\":{\"userid\":\"1\",\"passwd\":\"AES@admin\"},\"auth\":\"${TOKEN}\",\"id\":2}" \
        > /dev/null
    echo "  Admin password → AES@admin"

    # Set server name
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"settings.update\",\"params\":{\"server_name\":\"Vizoure NMS\"},\"auth\":\"${TOKEN}\",\"id\":3}" \
        > /dev/null
    echo "  Server name → Vizoure NMS"

    # Rename default host group
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.update\",\"params\":{\"groupid\":\"1\",\"name\":\"Vizoure Servers\"},\"auth\":\"${TOKEN}\",\"id\":4}" \
        > /dev/null
    echo "  Default group → Vizoure Servers"
else
    echo "  WARNING: Could not login with default password"
    echo "  Change Admin password manually after install"
fi

echo ""
echo "========================================="
echo "  Vizoure NMS Installation Complete!"
echo "========================================="
echo "  Web UI:   http://$(hostname -I | awk '{print $1}')/vizoure"
echo "  Username: Admin"
echo "  Password: AES@admin"
echo ""
echo "  OS Login: admin / AES@admin"
echo "  NOTE: OS password change required on first login"
echo "========================================="
