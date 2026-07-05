# Vizoure NMS

<p align="center">
  <img src="branding/logos/logo.png" alt="Vizoure NMS" width="400"/>
</p>

**Vizoure NMS** is a fully rebranded network monitoring system built on top of Zabbix 7.4.x. It provides enterprise-grade infrastructure monitoring with complete Vizoure branding — no visible Zabbix references anywhere in the UI.

---

## Features

- ✅ One-command installation
- ✅ Complete Vizoure branding (UI, database, templates, dashboards)
- ✅ Custom admin credentials (`admin` / `Vizoure@123`)
- ✅ Automated upgrade workflow
- ✅ Linux monitoring agent (`.deb` package)
- ✅ URL rebranding (`/vizoure/vizoure.php`)
- ✅ Full compatibility with upstream Zabbix packages

---

## Quick Install

> **Requirements:** Ubuntu 24.04 LTS, 2 vCPU, 2GB RAM minimum

```bash
curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/install-nms.sh \
    -o /tmp/vizoure-install.sh
sudo bash /tmp/vizoure-install.sh
```

After installation:

| Item | Value |
|---|---|
| Web UI | `http://<server-ip>/vizoure` |
| Username | `admin` |
| Password | `Vizoure@123` |
| OS Login | `admin` / `AES@admin` |

---

## Install Linux Agent

Download the latest `.deb` from [Releases](https://github.com/sadiqawan/Vizoure/releases):

```bash
# Download
wget https://github.com/sadiqawan/Vizoure/releases/latest/download/vizoure-agent_7.4.9_amd64.deb

# Install
sudo dpkg -i vizoure-agent_7.4.9_amd64.deb
```

Configure the agent to point at your server:

```bash
sudo nano /etc/vizoure/vizoure_agentd.conf
```

Change these lines:
```
Server=<your-vizoure-server-ip>
ServerActive=<your-vizoure-server-ip>
Hostname=<this-host-name>
```

Restart:
```bash
sudo systemctl restart vizoure-agent
sudo systemctl status vizoure-agent
```

Then add the host in the Vizoure NMS web UI:
- **Data collection → Hosts → Create host**
- Interface: Agent → IP of the monitored host → Port 10050

---

## Upgrade

To upgrade to a new Zabbix version:

```bash
curl -sSL https://raw.githubusercontent.com/sadiqawan/Vizoure/main/scripts/upgrade.sh \
    -o /tmp/upgrade.sh
sudo bash /tmp/upgrade.sh 7.4.12
```

The upgrade script:
1. Backs up the database automatically
2. Updates Zabbix packages
3. Reapplies all Vizoure branding
4. Restarts services

---

## Publish a New Release

```bash
cd /root/vizoure-nms-builde
GITHUB_TOKEN=ghp_your_token bash scripts/create-release.sh 7.4.12
```

This builds the Linux agent `.deb`, packages all artifacts, and publishes to GitHub Releases automatically.

---

## Project Structure

```
Vizoure/
├── scripts/
│   ├── install-nms.sh        # One-command server installer
│   ├── upgrade.sh            # Upgrade to new version
│   └── create-release.sh     # Publish GitHub Release
├── branding/
│   ├── apply-branding.sh     # Applies all UI/file branding
│   ├── branding.conf         # Brand variables
│   └── logos/                # Logo, favicon assets
└── agent-packaging/
    ├── linux/
    │   └── build-agent.sh    # Builds Linux .deb agent
    ├── windows/
    │   └── installer.wxs     # WiX MSI source (requires Windows)
    └── macos/
        └── package.sh        # macOS .pkg source (requires macOS)
```

---

## Roadmap

- [x] Version 1 — Complete visual rebranding
- [x] Phase 4 — Linux agent packaging
- [x] Phase 6 — GitHub Releases
- [x] Phase 7 — Upgrade workflow
- [ ] Phase 5 — Automated VM image (Packer/ESXi)
- [ ] Version 2 — Windows & macOS agent packages
- [ ] Version 3 — Full source fork with custom protocol branding

---

## Technical Notes

- Built on **Zabbix 7.4.x** upstream apt packages
- Branding is surface-level (UI, database display names, labels)
- Internal package names remain `zabbix-*` for apt compatibility
- Compatible with all standard Zabbix agent configurations
- Database: MySQL/MariaDB with `vizoure` schema

---

## License

This project is for internal organizational use. The underlying Zabbix software is licensed under [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.html).
