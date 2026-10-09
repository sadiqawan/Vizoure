# 01 — Repo Inventory

Factual map of every path in the repo outside `Vizoure/zabbix-master/` (the vendored
Zabbix source — covered separately in a later file), plus the top of that tree. Status
column: **used** = referenced/invoked by another script in the repo; **unused** =
present but nothing calls or builds it; **empty** = zero-byte file.

## Vizoure/ root

| Path | Status | What it is |
|---|---|---|
| `Vizoure/README.md` | used (human-facing) | Main product doc: install options, default creds, agent install, branding coverage table, roadmap |
| `Vizoure/CHANGELOG.md` | used (human-facing) | Single entry, v7.4.9 "Initial Release" |

## Vizoure/scripts/

| Path | Status | What it is |
|---|---|---|
| `install-nms.sh` | used | Fresh-install entry point. Sets up OS user, MySQL, apt-installs Zabbix packages, imports schema, runs DB rebrand UPDATEs, writes Apache/PHP config, calls `branding/apply-branding.sh`, calls JSON-RPC API to rename defaults + create `admin` account |
| `upgrade.sh` | used | Backs up DB, upgrades Zabbix apt packages, re-runs a **subset** of the DB rebrand UPDATEs, re-runs `apply-branding.sh` |
| `build-iso.sh` | used (by operator, manually) | Extracts a stock Ubuntu ISO, injects `packer/http/user-data`, rewrites GRUB menu, repacks ISO |
| `create-release.sh` | used (by operator, manually) | Publishes a GitHub Release; calls `agent-packaging/linux/build-agent.sh` as a fallback if the `.deb` is missing; assumes it runs from `/root/vizoure-nms-builde` |
| `branding-patch.sh` | **empty** | 0 bytes. Distinct from `branding/branding-patch.sh` below — name collision, not the same file |

## Vizoure/branding/

| Path | Status | What it is |
|---|---|---|
| `apply-branding.sh` | used | The live UI branding patcher. Runs against an **already apt-installed** Zabbix tree at `/usr/share/zabbix/ui`: logos/favicons, CSS tweak, `local/conf/brand.conf.php`, ~20 targeted `sed`/Python patches against specific installed PHP files, `zabbix.php`→`vizoure.php` rewrite. Invoked from `install-nms.sh` and `upgrade.sh` via `curl \| bash` from GitHub `main`, not from local disk |
| `branding-patch.sh` | unused | Patches a hypothetical source checkout at `/root/vizoure-nms-builde/zabbix-source` (a path that doesn't exist in this repo) using `branding.conf` vars. Nothing calls it |
| `branding.conf` | used only by the unused script above | Brand name/version/package-prefix variables (`BRAND_NAME=Vizoure`, `BRAND_VERSION=7.4.9`, `BRAND_AGENT_NAME=vizoure_agent`, etc.) |
| `logos/favicon.ico` | used | Installed by `apply-branding.sh` |
| `logos/favicon.png` | used | Installed by `apply-branding.sh` |
| `logos/login-bg.png` | used | Installed by `apply-branding.sh` |
| `logos/logo.png` | used | Installed by `apply-branding.sh` |

## Vizoure/agent-packaging/

| Path | Status | What it is |
|---|---|---|
| `linux/build-agent.sh` | **empty** | 0 bytes, but `create-release.sh` calls it as a fallback |
| `windows/vizoure-agent-install.ps1` | used (README-documented) | Downloads the **official** Zabbix agent MSI from `cdn.zabbix.com`, installs it, replaces the resulting `Zabbix Agent` service with one named `Vizoure Agent` pointed at a Vizoure config file. Binary itself stays stock `zabbix_agentd.exe` |
| `windows/installer.wxs` | unused / orphaned | WiX MSI definition for a *custom* `vizoure_agentd.exe`/`.conf` package that nothing in the repo builds. Placeholder GUID (`PUT-YOUR-UNIQUE-GUID-HERE`). Not referenced by any script or the README's Windows instructions |
| `windows/build-notes.md` | **empty** | 0 bytes |
| `macos/package.sh` | unused / orphaned | Builds a `.pkg` + LaunchDaemon from a pre-existing `/usr/local/sbin/vizoure_agentd` binary that no build step in this repo produces |
| `macos/build-notes.md` | **empty** | 0 bytes |

## Vizoure/packer/

| Path | Status | What it is |
|---|---|---|
| `ubuntu-server.pkr.hcl` | used (operator-run) | Packer `vmware-iso` template; provisions a VM by `curl \| bash`-ing `install-nms.sh` from GitHub, exports OVF via `ovftool` against a hardcoded ESXi host |
| `variables.pkr.hcl` | used (by the template above) | Packer variables — hardcoded ESXi host IP and **plaintext root password** |
| `http/user-data` | used (by `build-iso.sh` and the Packer template) | Ubuntu `autoinstall` cloud-init config |
| `http/meta-data` | used (by `build-iso.sh`) | Empty/placeholder cloud-init metadata file (touched, not authored) |
| `README.md` | **empty** | 0 bytes |
| `index.html` | **orphaned / mistaken file** | Not a Packer file. It's a saved copy of the public `ubuntu.com` marketing homepage (~5000 lines: Cloudinary image URLs, Google Tag Manager, Usabilla embed, "Ubuntu 26.04 LTS" copy). Unrelated to this project; appears to have been saved into the wrong folder by accident |

## Vizoure/zabbix-master/ (top level only — vendored, not inventoried file-by-file here)

| Path | Status | What it is |
|---|---|---|
| `zabbix-master/` | reference only, not built by any script here | Full unmodified upstream Zabbix source (C server/agent under `src/`, PHP frontend under `ui/`, `templates/`, autotools build via `configure.ac`/`Makefile.am`/`bootstrap.sh`). **Version drift:** `ui/include/defines.inc.php` reports `ZABBIX_VERSION = '8.0.0rc2'` — this is a snapshot of Zabbix's `master` (dev) branch, not the 7.4.9 release branch that `install-nms.sh` actually installs via apt. See `00-project-objective.md`. |

## Repo root

| Path | Status | What it is |
|---|---|---|
| `CLAUDE.md` | used (agent-facing) | Guidance file for Claude Code sessions in this repo, written in an earlier session |
| `md/` | this folder | Documentation being built in this task |

## Not present

- No `.git` directory — this checkout is not a git repository (see `00-project-objective.md`, open items).
- No portal code anywhere in the repo — confirmed absent, consistent with it having been intentionally removed per the task brief.
