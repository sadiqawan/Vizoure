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

echo "[4/9] Installing Vizoure NMS packages..."
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

echo "  Applying default branding renames to database..."
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET vendor_name = 'Vizoure' WHERE vendor_name = 'Zabbix' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.actions SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.triggers SET description = REPLACE(description, 'Zabbix', 'Vizoure') WHERE description LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.items SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.usrgrp SET name = 'Vizoure Administrators' WHERE name = 'Zabbix administrators';"
mysql -uroot -e "UPDATE ${DB_NAME}.users SET name='Vizoure', surname='Administrator' WHERE username='Admin';"
mysql -uroot -e "UPDATE ${DB_NAME}.media_type SET smtp_email = 'noreply@vizoure.local' WHERE smtp_email = 'zabbix@example.com';"
mysql -uroot -e "UPDATE ${DB_NAME}.images SET name = REPLACE(name, 'Zabbix', 'Vizoure') WHERE name LIKE '%Zabbix%';"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET host = REPLACE(host, 'Zabbix', 'Vizoure') WHERE host LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REGEXP_REPLACE(REGEXP_REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(description,'Zabbix Agent (zabbix-agent2)','Vizoure Agent (vizoure-agent2)'),'Zabbix Agent 2','Vizoure Agent 2'),'zabbix-agent2','vizoure-agent2'),'Zabbix agent 2','Vizoure agent 2'),'Zabbix agent','Vizoure agent'),'Zabbix HTTP agent','Vizoure HTTP agent'),'Zabbix SNMP agent','Vizoure SNMP agent'),'Zabbix SNMP Agent','Vizoure SNMP Agent'),'Zabbix Java Gateway','Vizoure Java Gateway'),'Zabbix Java gateway','Vizoure Java gateway'),'Zabbix Helm Chart','Vizoure Helm Chart'),'Zabbix Helm chart','Vizoure Helm chart'),'Zabbix IAM policy','Vizoure IAM policy'),'Zabbix 7.4 ','Vizoure 7.4 '),'Zabbix 7.4.','Vizoure 7.4.'),'Zabbix 7.4,','Vizoure 7.4,'),'Zabbix 7.4+','Vizoure 7.4+'),'Zabbix Documentation','Vizoure Documentation'),'Zabbix Event Priority','Vizoure Event Priority'),'Zabbix Event Source','Vizoure Event Source'),'Zabbix Event Status','Vizoure Event Status'),'Zabbix GitHub Webhook','Vizoure GitHub Webhook'),'Zabbix/7.4','Vizoure/7.4'),'the local Zabbix server','the local Vizoure server'),'the local Zabbix proxy','the local Vizoure proxy'),'the remote Zabbix server','the remote Vizoure server'),'the remote Zabbix proxy','the remote Vizoure proxy'),'Zabbix bulk data collection','Vizoure bulk data collection'),'New Zabbix Agent','New Vizoure Agent'),'You can discuss this template or leave feedback on our forum[^\n]*\n?',''),'https://www\\.zabbix\\.com/documentation[^\n]*\n?','') WHERE (description LIKE '%Zabbix%' OR description LIKE '%zabbix-agent2%') AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(description,'Zabbix server or Zabbix proxy','Vizoure server or Vizoure proxy'),'the Zabbix server or the Zabbix proxy','the Vizoure server or the Vizoure proxy'),'from Zabbix proxy or Zabbix server','from Vizoure proxy or Vizoure server'),'monitor Zabbix server metrics','monitor Vizoure server metrics'),'our Zabbix server/proxy','our Vizoure server/proxy'),'from Zabbix server/proxy','from Vizoure server/proxy'),'Zabbix server uses','Vizoure server uses'),'only Zabbix server can reach','only Vizoure server can reach'),'that only Zabbix server','that only Vizoure server'),'internal Zabbix metrics','internal Vizoure metrics'),'by Zabbix that work without','by Vizoure that work without'),'by Zabbix that works without','by Vizoure that works without'),'by Zabbix via HTTP','by Vizoure via HTTP'),'by Zabbix via ODBC','by Vizoure via ODBC'),'by Zabbix via','by Vizoure via'),'by Zabbix,','by Vizoure,'),'by Zabbix.','by Vizoure.'),'via Zabbix,','via Vizoure,'),'via Zabbix.','via Vizoure.'),'into Zabbix.','into Vizoure.'),'in Zabbix.','in Vizoure.'),'for Zabbix.','for Vizoure.'),'on Zabbix.','on Vizoure.'),'Zabbix currently supports','Vizoure currently supports'),'both Zabbix and the MSSQL','both Vizoure and the MSSQL'),'the Zabbix official repository','the Vizoure official repository'),'from Zabbix version 5.0','from Vizoure version 5.0'),'with Zabbix versions','with Vizoure versions'),'the Zabbix side.','the Vizoure side.'),'[Zabbix template operation]','[Vizoure template operation]') WHERE description LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REGEXP_REPLACE(REGEXP_REPLACE(description,'Generated by official (Vizoure|Zabbix) template tool[^\n]*\n?',''),'https://www\\.zabbix\\.com/forum[^\n]*\n?','') WHERE (description LIKE '%Generated by%' OR description LIKE '%zabbix.com/forum%') AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET host = REPLACE(host, 'Zabbix', 'Vizoure') WHERE host LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(description,'Zabbix Agent (zabbix-agent2)','Vizoure Agent (vizoure-agent2)'),'Zabbix Agent 2','Vizoure Agent 2'),'Zabbix HTTP agent','Vizoure HTTP agent'),'Zabbix SNMP agent','Vizoure SNMP agent'),'Zabbix SNMP Agent','Vizoure SNMP Agent'),'Zabbix Java Gateway','Vizoure Java Gateway'),'Zabbix Java gateway','Vizoure Java gateway'),'Zabbix Helm Chart','Vizoure Helm Chart'),'Zabbix Helm chart','Vizoure Helm chart'),'Zabbix IAM policy','Vizoure IAM policy'),'Zabbix 7.4 ','Vizoure 7.4 '),'Zabbix 7.4.','Vizoure 7.4.'),'Zabbix 7.4,','Vizoure 7.4,'),'Zabbix 7.4+','Vizoure 7.4+'),'Zabbix Documentation','Vizoure Documentation'),'Zabbix Event Priority','Vizoure Event Priority'),'Zabbix Event Source','Vizoure Event Source'),'Zabbix Event Status','Vizoure Event Status'),'Zabbix GitHub Webhook','Vizoure GitHub Webhook'),'Zabbix/7.4','Vizoure/7.4') WHERE description LIKE '%Zabbix%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(description,'the local Zabbix server','the local Vizoure server'),'the local Zabbix proxy','the local Vizoure proxy'),'the remote Zabbix server','the remote Vizoure server'),'the remote Zabbix proxy','the remote Vizoure proxy'),'Zabbix bulk data collection','Vizoure bulk data collection'),'New Zabbix Agent','New Vizoure Agent'),'Zabbix MySQL plugin','Vizoure MySQL plugin'),'Zabbix server or Zabbix proxy','Vizoure server or Vizoure proxy'),'Zabbix HTTP agent','Vizoure HTTP agent'),'by Zabbix.','by Vizoure.'),'via Zabbix.','via Vizoure.'),'zabbix-agent2','vizoure-agent2') WHERE description LIKE '%Zabbix%' OR description LIKE '%zabbix-agent2%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REGEXP_REPLACE(REGEXP_REPLACE(description,'You can discuss this template or leave feedback on our forum[^\n]*\n?',''),'Generated by official (Vizoure|Zabbix) template tool[^\n]*\n?','') WHERE (description LIKE '%forum%' OR description LIKE '%Generated by%') AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REGEXP_REPLACE(description,'https://www\\.zabbix\\.com/forum[^\n]*\n?','') WHERE description LIKE '%zabbix.com/forum%' AND status=3;"
mysql -uroot -e "UPDATE ${DB_NAME}.hosts SET description = REPLACE(description,'see the Zabbix server log','see the Vizoure server log') WHERE description LIKE '%see the Zabbix server log%' AND status=3;"
echo "  Database branding complete"

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

    RewriteEngine On
    RewriteBase /vizoure/

    RewriteCond %{THE_REQUEST} \s/vizoure/zabbix\.php [NC]
    RewriteRule ^zabbix\.php$ vizoure.php [R=301,QSA,L]

    <IfModule mod_php.c>
        php_value max_execution_time 300
        php_value memory_limit 128M
        php_value post_max_size 16M
        php_value upload_max_filesize 2M
    </IfModule>
</Directory>
APACHEEOF

a2enconf vizoure
a2enmod rewrite 2>/dev/null || true

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

    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"host.update","params":{"hostid":"10084","host":"Vizoure NMS Server","name":"Vizoure NMS Server"},"id":40}' \
        > /dev/null
    echo "  Renamed default host to Vizoure NMS Server"

    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"hostgroup.update","params":{"groupid":"4","name":"Vizoure NMS Servers"},"id":41}' \
        > /dev/null

    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"hostgroup.update","params":{"groupid":"5","name":"Discovered Devices"},"id":42}' \
        > /dev/null

    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"hostgroup.update","params":{"groupid":"2","name":"Linux Servers"},"id":43}' \
        > /dev/null

    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"hostgroup.update","params":{"groupid":"6","name":"Virtual Machines"},"id":44}' \
        > /dev/null
    echo "  Renamed default host groups"

    curl -s -X POST "$ZBX_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{"jsonrpc":"2.0","method":"dashboard.delete","params":["2","57"],"id":45}' \
        > /dev/null
    echo "  Removed default Zabbix dashboards"

    ZBX_TOKEN="$TOKEN" python3 << 'PYEOF'
import urllib.request, json, os

TOKEN = os.environ.get("ZBX_TOKEN")
URL = "http://localhost/vizoure/api_jsonrpc.php"

def call(method, params, req_id=1):
    payload = json.dumps({"jsonrpc":"2.0","method":method,"params":params,"id":req_id}).encode()
    req = urllib.request.Request(URL, data=payload, headers={
        "Content-Type":"application/json",
        "Authorization":f"Bearer {TOKEN}"
    })
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)

result = call("dashboard.get", {
    "output": ["dashboardid","name"],
    "selectPages": ["dashboard_pageid","name","display_period","widgets"],
    "dashboardids": ["1"]
}, 1)

dashboard = result["result"][0]
changed = False

for page in dashboard["pages"]:
    for widget in page["widgets"]:
        if widget.get("type") == "gauge" and widget.get("name") == "Zabbix server":
            widget["name"] = "Memory Utilization"
            changed = True
        if widget.get("type") == "svggraph":
            for field in widget.get("fields", []):
                if field.get("name") in ("ds.0.hosts.0","ds.1.hosts.0") and field.get("value") == "Zabbix server":
                    field["value"] = "Vizoure NMS Server"
                    changed = True

if changed:
    call("dashboard.update", {"dashboardid": dashboard["dashboardid"], "pages": dashboard["pages"]}, 2)
    print("  Dashboard widget names/references updated")
else:
    print("  No widget changes needed")
PYEOF

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
        echo "  Old default account disabled"
    fi
else
    echo "  WARNING: Could not login — change Admin password manually"
fi

echo ""
echo "========================================="
echo "  Vizoure NMS Installation Complete!"
echo "========================================="
echo "  Web UI:   http://$(hostname -I | awk '{print $1}')/vizoure"
echo "  Username: admin"
echo "  Password: Vizoure@123"
echo "  OS Login: admin / AES@admin  (Linux login only)"
echo "========================================="
