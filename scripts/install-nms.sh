#!/bin/bash
set -e

DB_NAME="vizoure"
DB_USER="vizoure"
DB_PASSWORD="AES@admin"
OS_USERNAME="admin"
OS_PASSWORD="AES@admin"
ZABBIX_VERSION="7.4"

echo "=== Vizoure NMS Installation Starting ==="

# ─────────────────────────────────────────────
# 1. OS USER
# ─────────────────────────────────────────────
echo "[1/7] Setting up OS user..."
if id "$OS_USERNAME" &>/dev/null; then
    echo "${OS_USERNAME}:${OS_PASSWORD}" | chpasswd
else
    useradd -m -s /bin/bash "$OS_USERNAME"
    echo "${OS_USERNAME}:${OS_PASSWORD}" | chpasswd
    usermod -aG sudo "$OS_USERNAME"
fi
chage -d 0 "$OS_USERNAME"

# ─────────────────────────────────────────────
# 2. SYSTEM UPDATE
# ─────────────────────────────────────────────
echo "[2/7] Updating system..."
apt update -y && apt upgrade -y

# ─────────────────────────────────────────────
# 3. MYSQL
# ─────────────────────────────────────────────
echo "[3/7] Installing MySQL..."
apt install -y mysql-server
systemctl start mysql
systemctl enable mysql

# ─────────────────────────────────────────────
# 4. ZABBIX REPO + PACKAGES
# ─────────────────────────────────────────────
echo "[4/7] Installing Zabbix packages..."
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
echo "[5/7] Setting up database..."
mysql -uroot <<SQLEOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
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
# 6. CONFIGURE
# ─────────────────────────────────────────────
echo "[6/7] Configuring Vizoure NMS..."

# Zabbix server config
sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^DBName=.*/DBName=${DB_NAME}/"               /etc/zabbix/zabbix_server.conf
sed -i "s/^DBUser=.*/DBUser=${DB_USER}/"               /etc/zabbix/zabbix_server.conf

# Apache: detect from conf-available (more robust than conf-enabled)
echo "  Detecting Zabbix Apache config..."
ZABBIX_CONF=$(find /etc/apache2/conf-available -name "*zabbix*.conf" | head -1)
if [ -n "$ZABBIX_CONF" ]; then
    CONF_NAME=$(basename "$ZABBIX_CONF" .conf)
    a2disconf "$CONF_NAME" 2>/dev/null || true
    echo "  Disabled existing config: $CONF_NAME"
else
    echo "  No existing Zabbix Apache config found — skipping disable step"
fi

# Create dedicated Vizoure Apache config
cat > /etc/apache2/conf-available/vizoure.conf << 'APACHEEOF'
Alias /vizoure /usr/share/zabbix

<Directory "/usr/share/zabbix">
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

# Frontend config — skip setup wizard
mkdir -p /etc/zabbix/web
cat > /etc/zabbix/web/zabbix.conf.php << PHPEOF
<?php
\$DB['TYPE']           = 'MYSQL';
\$DB['SERVER']         = 'localhost';
\$DB['PORT']           = '0';
\$DB['DATABASE']       = '${DB_NAME}';
\$DB['USER']           = '${DB_USER}';
\$DB['PASSWORD']       = '${DB_PASSWORD}';
\$DB['SCHEMA']         = '';
\$DB['ENCRYPTION']     = false;
\$DB['DOUBLE_IEEE754'] = true;
\$ZBX_SERVER           = 'localhost';
\$ZBX_SERVER_PORT      = '10051';
\$ZBX_SERVER_NAME      = 'Vizoure NMS';
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
PHPEOF

# Safe branding — only known safe file
DEFINES=$(find /usr/share/zabbix -name "defines.inc.php" | head -1)
if [ -n "$DEFINES" ]; then
    sed -i "s/define('ZBX_TITLE'.*/define('ZBX_TITLE', 'Vizoure NMS');/" "$DEFINES"
    echo "  Browser title set to Vizoure NMS"
fi

# ─────────────────────────────────────────────
# 7. START SERVICES
# ─────────────────────────────────────────────
echo "[7/7] Starting services..."
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

# Wait for API to be actually ready — timeout after 2 minutes
echo "  Waiting for Vizoure API to become ready..."
if timeout 120 bash -c \
    'until curl -s http://localhost/vizoure/api_jsonrpc.php >/dev/null 2>&1; do sleep 2; done'; then
    echo "  API is ready."
else
    echo ""
    echo "  ERROR: API did not respond within 120 seconds."
    echo "  Check service status:"
    echo "    systemctl status zabbix-server"
    echo "    systemctl status apache2"
    exit 1
fi

# Change Admin password via API (correct method for Zabbix 7.4)
ZBX_URL="http://localhost/vizoure/api_jsonrpc.php"

TOKEN=$(curl -s -X POST "$ZBX_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
    | php -r "
        \$r = json_decode(file_get_contents('php://stdin'));
        echo isset(\$r->result) ? \$r->result : '';
    ")

if [ -n "$TOKEN" ]; then
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\":\"2.0\",
            \"method\":\"user.update\",
            \"params\":{\"userid\":\"1\",\"passwd\":\"AES@admin\"},
            \"auth\":\"${TOKEN}\",
            \"id\":2
        }" > /dev/null
    echo "  Admin password changed to AES@admin"
else
    echo ""
    echo "  WARNING: Could not authenticate with default Zabbix credentials."
    echo "  Change Admin password manually via the web UI after install."
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
