# Vizoure NMS

Internal Network Monitoring System based on Zabbix 7.4.9

## Quick Install (Fresh Ubuntu 24.04 VM)

```bash
curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/install-nms.sh | sudo bash
```

## Pre-built VM Images

Download from [GitHub Releases](https://github.com/sadiqawan/Vizoure/releases):

| Format | Use |
|--------|-----|
| `.ovf` | VMware ESXi |
| `.vmx` | VMware Workstation |
| `.iso` | Bootable installer |

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Web UI | Admin | AES@admin |
| OS | admin | AES@admin |

> ⚠️ Change all passwords on first login.
> Web UI: `http://<ip>/vizoure`

## Agent Packages

| Platform | Package |
|----------|---------|
| Linux (deb) | `vizoure-agent_7.4.9_amd64.deb` |
| Windows | `vizoure-agent-7.4.9.msi` |
| macOS | `vizoure-agent-7.4.9.pkg` |

## Upgrading

When a new Zabbix version is released:
```bash
bash scripts/upgrade.sh 7.4.10
```

## Structure
