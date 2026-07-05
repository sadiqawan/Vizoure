# Vizoure NMS

<p align="center">
  <img src="branding/logos/logo.png" alt="Vizoure NMS" width="400"/>
</p>

<p align="center">
  <strong>Enterprise Network Monitoring System</strong><br/>
  Fully branded network monitoring built on Zabbix 7.4.x
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-7.4.9-blue" alt="Version"/>
  <img src="https://img.shields.io/badge/platform-Ubuntu%2024.04-orange" alt="Platform"/>
  <img src="https://img.shields.io/badge/license-AGPL%20v3-green" alt="License"/>
</p>

---

## Overview

**Vizoure NMS** is a fully rebranded network monitoring system built on Zabbix 7.4.x. It provides enterprise-grade infrastructure monitoring with complete Vizoure branding — no visible Zabbix references anywhere in the UI, templates, dashboards, or agent interfaces.

### What's Included

| Component | Description |
|---|---|
| **Server** | Full Vizoure NMS server with web UI at `/vizoure` |
| **Linux Agent** | Native `.deb` package for Ubuntu/Debian |
| **Windows Agent** | PowerShell installer script |
| **macOS Agent** | Shell installer script |
| **OVA Image** | Pre-built VMware virtual machine |
| **ISO Image** | Bootable installer for bare metal / new VMs |

---

## Quick Start

### Option 1 — Install on Existing Ubuntu Server (Recommended)

> **Requirements:** Ubuntu 24.04 LTS, 2 vCPU, 2GB RAM minimum

```bash
curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/install-nms.sh \
    -o /tmp/vizoure-install.sh
sudo bash /tmp/vizoure-install.sh
```

### Option 2 — Deploy OVA (VMware/ESXi)

1. Download `vizoure-nms-7.4.9.ova` from [Releases](https://github.com/sadiqawan/Vizoure/releases)
2. In ESXi/vSphere: **Create/Register VM → Deploy OVF/OVA**
3. Follow the wizard — VM is pre-configured and ready

### Option 3 — Boot from ISO (Bare Metal / New VM)

1. Download `vizoure-nms-7.4.9.iso` from [Releases](https://github.com/sadiqawan/Vizoure/releases)
2. Boot your server/VM from the ISO
3. Select **"Install Vizoure NMS (Automated)"** — fully unattended install
4. Wait 15-20 minutes — system reboots into a fully configured Vizoure NMS

---

## Default Credentials

| Item | Value |
|---|---|
| **Web UI** | `http://<server-ip>/vizoure` |
| **Username** | `admin` |
| **Password** | `Vizoure@123` |
| **OS Username** | `admin` |
| **OS Password** | `AES@admin` |

---

## Agent Installation

### Linux (Ubuntu/Debian)

```bash
# Download latest release
wget https://github.com/sadiqawan/Vizoure/releases/latest/download/vizoure-agent_7.4.9_amd64.deb

# Install
sudo dpkg -i vizoure-agent_7.4.9_amd64.deb

# Configure server IP
sudo nano /etc/vizoure/vizoure_agentd.conf
# Set: Server=<your-vizoure-server-ip>
# Set: ServerActive=<your-vizoure-server-ip>
# Set: Hostname=<this-host-name>

# Restart
sudo systemctl restart vizoure-agent
sudo systemctl status vizoure-agent
```

### Windows (Run PowerShell as Administrator)

```powershell
# Set execution policy (one time)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Download and install
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sadiqawan/Vizoure/main/agent-packaging/windows/vizoure-agent-install.ps1" `
    -OutFile "$env:TEMP\vizoure-agent-install.ps1"

& "$env:TEMP\vizoure-agent-install.ps1" -Server <your-vizoure-server-ip>
```

### macOS (Run with sudo)

```bash
curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/agent-packaging/macos/vizoure-agent-install.sh \
    -o /tmp/vizoure-agent-install.sh
sudo bash /tmp/vizoure-agent-install.sh <your-vizoure-server-ip>
```

### After Installing an Agent

1. Go to `http://<server-ip>/vizoure` → login with `admin` / `Vizoure@123`
2. **Data collection → Hosts → Create host**
3. Fill in:
   - **Host name:** your machine name
   - **Host groups:** `Linux Servers` or `Windows Servers`
   - **Interfaces:** Agent → IP of monitored machine → Port `10050`
4. **Templates tab:** Select `Windows by Vizoure agent` or `Linux by Vizoure agent`
5. Click **Add**

Data appears in **Monitoring → Latest data** within 1-2 minutes.

---

## Upgrade

To upgrade to a new Zabbix version:

```bash
curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/upgrade.sh \
    -o /tmp/upgrade.sh
sudo bash /tmp/upgrade.sh 7.4.12
```

The upgrade script automatically:
1. Backs up the database to `/tmp/vizoure-db-backup-<date>.sql.gz`
2. Updates all Zabbix packages
3. Reapplies complete Vizoure branding
4. Restarts all services

---

## Build Artifacts

### Build Linux Agent (.deb)

```bash
cd /root/vizoure-nms-builde
bash agent-packaging/linux/build-agent.sh
# Output: packages/linux/vizoure-agent_7.4.9_amd64.deb
```

### Build Custom ISO

```bash
cd /root/vizoure-nms-builde
bash scripts/build-iso.sh 7.4.9
# Output: dist/vizoure-nms-7.4.9.iso
```

### Export OVA from ESXi

```bash
cd /root/vizoure-nms-builde
mkdir -p dist
ovftool --noSSLVerify --acceptAllEulas --diskMode=thin --compress=9 \
    "vi://root:<password>@<esxi-ip>/vizoure-nms-7.4.9" \
    "dist/vizoure-nms-7.4.9.ova"
```

### Publish GitHub Release

```bash
cd /root/vizoure-nms-builde
GITHUB_TOKEN=ghp_your_token bash scripts/create-release.sh 7.4.9
```

---

## Project Structure

```
Vizoure/
├── scripts/
│   ├── install-nms.sh          # One-command server installer
│   ├── upgrade.sh              # Upgrade to new Zabbix version
│   ├── build-iso.sh            # Build bootable ISO
│   └── create-release.sh       # Publish GitHub Release
├── branding/
│   ├── apply-branding.sh       # Applies all UI/file/DB branding
│   ├── branding.conf           # Brand variables
│   └── logos/                  # Logo, favicon, login background
├── agent-packaging/
│   ├── linux/
│   │   └── build-agent.sh      # Builds Linux .deb agent from source
│   ├── windows/
│   │   └── vizoure-agent-install.ps1   # Windows PowerShell installer
│   └── macos/
│       └── vizoure-agent-install.sh    # macOS shell installer
└── packer/
    ├── ubuntu-server.pkr.hcl   # Packer template (future automation)
    └── http/
        └── user-data           # Ubuntu autoinstall config
```

---

## Branding Coverage

| Area | Status |
|---|---|
| Web UI (logo, favicon, colors) | ✅ Complete |
| Browser tab title | ✅ Complete |
| Login page | ✅ Complete |
| Sidebar menu (Support/Integrations/Help removed) | ✅ Complete |
| System Information labels | ✅ Complete |
| Dashboard widgets | ✅ Complete |
| Template names (360 templates) | ✅ Complete |
| Template vendor names | ✅ Complete |
| Template descriptions | ✅ Complete |
| Trigger descriptions (467) | ✅ Complete |
| Item names (83) | ✅ Complete |
| Host/host group names | ✅ Complete |
| User groups | ✅ Complete |
| Media type defaults | ✅ Complete |
| Image names | ✅ Complete |
| Availability badge (ZBX→VIZ) | ✅ Complete |
| URL (zabbix.php→vizoure.php) | ✅ Complete |
| Queue overview labels | ✅ Complete |
| Timeout/proxy labels | ✅ Complete |
| Script execution labels | ✅ Complete |
| CSV export filenames | ✅ Complete |
| Module authors | ✅ Complete |
| PHP config (max_input_time) | ✅ Complete |

---

## Roadmap

- [x] Version 1 — Complete visual rebranding
- [x] Phase 4 — Linux/Windows/macOS agent packages
- [x] Phase 5 — OVA export + bootable ISO
- [x] Phase 6 — GitHub Releases automation
- [x] Phase 7 — Upgrade workflow
- [ ] Version 2 — Full custom MSI/PKG agent builds with Vizoure branding
- [ ] Version 2 — Packer automated VM image builds
- [ ] Version 3 — Full source fork with custom binary names

---

## Technical Notes

- Built on **Zabbix 7.4.x** upstream apt packages (Ubuntu)
- Branding is surface-level — internal package names remain `zabbix-*` for apt compatibility
- All DB renames use display `name` field, not technical `host` identifiers
- Compatible with all standard Zabbix agent/proxy/template configurations
- Database: MySQL with `vizoure` schema
- Web: Apache with `/vizoure` alias, PHP 8.3

---

## License

This project is for internal organizational use. The underlying Zabbix software is licensed under [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).

Zabbix is a registered trademark of Zabbix SIA. This project is not affiliated with or endorsed by Zabbix SIA.
