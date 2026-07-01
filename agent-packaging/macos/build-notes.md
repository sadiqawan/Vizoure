# Vizoure NMS macOS Agent Build

## Requirements
- macOS 12+ with Xcode Command Line Tools
- Homebrew: brew install openssl pcre

## Build Steps
1. cd zabbix-source
2. ./bootstrap.sh
3. ./configure --prefix=/usr/local \
               --sysconfdir=/etc/vizoure \
               --enable-agent \
               --with-openssl=$(brew --prefix openssl)
4. make -j$(sysctl -n hw.ncpu) src/zabbix_agent/zabbix_agentd
5. cp src/zabbix_agent/zabbix_agentd /usr/local/sbin/vizoure_agentd
6. Run: bash agent-packaging/macos/package.sh

## Output
vizoure-agent-7.4.9.pkg
