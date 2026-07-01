#!/bin/bash
set -e

VERSION="7.4.9"
PKG_ROOT="/tmp/vizoure-agent-pkg"

mkdir -p "$PKG_ROOT/usr/local/sbin"
mkdir -p "$PKG_ROOT/etc/vizoure"
mkdir -p "$PKG_ROOT/Library/LaunchDaemons"

cp /usr/local/sbin/vizoure_agentd "$PKG_ROOT/usr/local/sbin/"

cat > "$PKG_ROOT/Library/LaunchDaemons/com.vizoure.agent.plist" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vizoure.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/sbin/vizoure_agentd</string>
        <string>-c</string>
        <string>/etc/vizoure/vizoure_agentd.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLISTEOF

pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "com.vizoure.agent" \
    --version "$VERSION" \
    --install-location "/" \
    "vizoure-agent-${VERSION}.pkg"

echo "Package built: vizoure-agent-${VERSION}.pkg"
