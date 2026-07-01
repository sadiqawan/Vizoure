# Vizoure NMS Changelog

## v7.4.9 — Initial Release
- Base: Zabbix 7.4.9
- Ubuntu 24.04 LTS
- Web UI at /vizoure
- Default credentials: Admin / AES@admin
- Linux agent .deb package
- VMX + OVF + ISO build pipeline
- Automated install via curl

## Upgrade Process
When a new Zabbix version is released:
```bash
bash scripts/upgrade.sh <new_version>
# Example:
bash scripts/upgrade.sh 7.4.10
```
