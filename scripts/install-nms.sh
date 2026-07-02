#!/bin/bash
set -e

REPO_RAW="https://raw.githubusercontent.com/sadiqawan/Vizoure/main"
DB_NAME="vizoure"
DB_USER="vizoure"
DB_PASSWORD="AES@admin"
OS_USERNAME="admin"
OS_PASSWORD="AES@admin"
ZABBIX_VERSION="7.4"

echo "========================================="
echo "  Vizoure NMS Installation Starting..."
echo "========================================="

echo "[1/9] Setting up OS user..."
if id "$OS_USERNAME" &>/dev/null; then
    echo "${OS_USERNAME}:${OS_PASSWORD}" | chpasswd
else
    useradd -m -s /bin/bash "$OS_USERNAME"
    echo "${OS_USERNAME}:${OS_PASSWORD}" | chpasswd
    usermod -aG sudo "$OS_USERNAME"
fi
chage -d 0 "$OS_USERNAME"

echo "[2/9] Updating system..."
apt update -y && apt upgrade -y
apt install -y curl wget git python3

echo "[3/9] Installing MySQL..."
apt install -y mysql-server
systemctl start mysql
systemctl enable mysql

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

echo "[5/9] Setting up database..."
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql -uroot -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 1;"
mysql -uroot -e "FLUSH PRIVILEGES;"

echo "  Importing schema..."
zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | \
    mysql --default-character-set=utf8mb4 -u${DB_USER} -p${DB_PASSWORD} ${DB_NAME}

mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

echo "[6/9] Configuring server..."
sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
sed -i "s/^DBName=.*/DBName=${DB_NAME}/"               /etc/zabbix/zabbix_server.conf
sed -i "s/^DBUser=.*/DBUser=${DB_USER}/"               /etc/zabbix/zabbix_server.conf

ZABBIX_CONF=$(find /etc/apache2/conf-available -name "*zabbix*.conf" | head -1)
if [ -n "$ZABBIX_CONF" ]; then
    CONF_NAME=$(basename "$ZABBIX_CONF" .conf)
    a2disconf "$CONF_NAME" 2>/dev/null || true
fi

cat > /etc/apache2/conf-available/vizoure.conf << 'APACHEEOF'
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

echo "[7/9] Applying Vizoure branding..."

apt install -y imagemagick python3 curl

curl -sSL "${REPO_RAW}/branding/apply-branding.sh" -o /tmp/apply-branding.sh
chmod +x /tmp/apply-branding.sh
bash /tmp/apply-branding.sh

echo "[8/9] Starting services..."
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

echo "[9/9] Configuring via API..."
ZBX_URL="http://localhost/vizoure/api_jsonrpc.php"

echo "  Waiting for API..."
if timeout 120 bash -c \
    "until curl -s $ZBX_URL >/dev/null 2>&1; do sleep 2; done"; then
    echo "  API ready"
else
    echo "  ERROR: API not responding after 120s"
    systemctl status zabbix-server --no-pager
    exit 1
fi

TOKEN=$(curl -s -X POST "$ZBX_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result',''))" 2>/dev/null)
if [ -n "$TOKEN" ]; then
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"settings.update","params":{"server_name":"Vizoure NMS"},"id":3}' \
        > /dev/null
    echo "  Server name set to Vizoure NMS"
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"hostgroup.update","params":{"groupid":"1","name":"Vizoure Servers"},"id":4}' \
        > /dev/null
    echo "  Default group renamed to Vizoure Servers"
    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"user.create","params":{"username":"admin","passwd":"Vizoure@123","roleid":"3","usrgrps":[{"usrgrpid":"7"}]},"id":10}' \
        > /dev/null
    echo "  Created admin/Vizoure@123 account"
    NEWTOKEN=$(curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"admin","password":"Vizoure@123"},"id":11}' \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result',''))" 2>/dev/null)
    if [ -n "$NEWTOKEN" ]; then
        curl -s -X POST "$ZBX_URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $NEWTOKEN" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.update\",\"params\":{\"userid\":\"1\",\"passwd\":\"$(openssl rand -base64 24)\"},\"id\":12}" \
            > /dev/null
        echo "  Old Admin/zabbix account disabled"
    fi
else
    echo "  WARNING: Could not login — change Admin password manually"
fi

echo ""
echo "========================================="
echo "  Vizoure NMS Installation Complete!"
echo "========================================="
echo "  Web UI:   http://$(hostname -I | awk '{print $1}')/vizoure"
echo "  Username: Admin"
echo "  Password: AES@admin"
echo "  OS Login: admin / AES@admin"
echo "========================================="
