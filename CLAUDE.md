# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**Vizoure NMS** is a rebranding/packaging/deployment layer on top of upstream **Zabbix 7.4.x**. It is not a
standalone application with its own source code — it is a collection of shell/PowerShell scripts, sed/python
text patches, and Packer templates that take an official Zabbix install and turn it into "Vizoure NMS" (new
logos, renamed strings in the DB and PHP/JS files, renamed services, `/vizoure` URL instead of `/zabbix`, etc).

All real work happens under this repo root (this file lives at that root, alongside
`README.md`, `scripts/`, `branding/`, etc. — there is no extra wrapper folder):

- `scripts/` — top-level operator-facing scripts: `install-nms.sh` (fresh install on Ubuntu 24.04),
  `upgrade.sh` (upgrade + re-brand), `build-iso.sh` (bake an autoinstall ISO), `create-release.sh` (publish a
  GitHub Release with the agent .deb + install/upgrade scripts).
- `branding/` — `apply-branding.sh` (the real, actively-used branding patcher — runs against an
  **already-installed** Zabbix tree at `/usr/share/zabbix/ui`), `branding.conf` (brand name variables),
  `branding-patch.sh` (an alternate, source-tree-based patcher — see "Two branding paths" below), `logos/`.
- `agent-packaging/` — per-OS agent installers: Linux `build-agent.sh` (currently empty/stub), Windows
  `vizoure-agent-install.ps1` (downloads the official Zabbix agent MSI and re-wraps it as a `Vizoure Agent`
  service), macOS `package.sh` (wraps the agent binary as a `.pkg` with a LaunchDaemon).
- `packer/` — Packer (`vmware-iso` builder) + Ubuntu `autoinstall` (`http/user-data`) config for
  producing an OVA; `ubuntu-server.pkr.hcl` just shells out to `install-nms.sh` as its provisioner.
- `zabbix-master/` — a **full, unmodified vendor copy of upstream Zabbix 7.4 source** (C server/agent,
  PHP frontend under `ui/`, templates, autotools build). It is **not** currently wired into any Vizoure build
  script — `install-nms.sh`/`upgrade.sh` install Zabbix from the official `repo.zabbix.com` apt packages, not
  by compiling this tree. Treat this directory as upstream reference/vendor code, not project code to maintain;
  if you need to check "what does stock Zabbix do here" this is the place to look, but changes here do not
  affect what `install-nms.sh` or `apply-branding.sh` produce.

There is no top-level build/lint/test tooling for the Vizoure layer itself (no package.json, Makefile, or CI
config) — these are standalone bash/PowerShell scripts, validated by running them (`bash -n script.sh` for a
quick syntax check) or by reading them, not by a test suite.

## Two branding paths — don't confuse them

There are two *different, inconsistent* mechanisms for applying "Zabbix → Vizoure" renames, and only one is
actually used:

1. **`branding/apply-branding.sh`** — the live one. It runs on a target server *after* the real Zabbix
   `.deb` packages are installed, and directly `sed`/Python-patches the installed PHP/JS files under
   `/usr/share/zabbix/ui`, drops in a `local/conf/brand.conf.php`, and rewrites `zabbix.php` references to
   `vizoure.php`. It's invoked from both `install-nms.sh` and `upgrade.sh` via
   `curl -sSL $REPO_RAW/branding/apply-branding.sh | bash`.
2. **`branding/branding-patch.sh`** — an unused, aspirational script for a future "build Zabbix from
   patched source" workflow (roadmap item "Version 3 — Full source fork"). It expects a `zabbix-source`
   checkout at `/root/vizoure-nms-builde/zabbix-source`, which doesn't exist in this repo (the vendored tree
   here is named `zabbix-master`). Nothing currently calls this script.

Database string renames (hosts/triggers/items/images/usrgrp names, etc.) are done separately with inline
`mysql -uroot -e "UPDATE ..."` statements directly in `install-nms.sh`/`upgrade.sh`, duplicated between the two
scripts — if you add a new rename, update both places.

## Scripts fetch themselves from GitHub `main`, not from disk

Nearly every script pulls *other* Vizoure scripts/assets over HTTPS from
`https://raw.githubusercontent.com/sadiqawan/Vizoure/main/...` (see `REPO_RAW` in `install-nms.sh`,
`upgrade.sh`; the hardcoded URL in `build-iso.sh`'s grub config). This means:

- A local edit to `branding/apply-branding.sh` or `packer/http/user-data` has **no effect** on an
  `install-nms.sh` run until it's pushed to `main` on GitHub — these scripts are not self-contained.
- Build-host scripts (`build-iso.sh`, `create-release.sh`, `branding-patch.sh`) additionally assume they run
  from `/root/vizoure-nms-builde` on a Linux box (note: "builde", not "builder" — a consistent typo across
  scripts, not something to silently "fix" without checking it isn't load-bearing elsewhere).

## Branding is applied in layers, each with its own renaming logic

1. **Apt packages** installed from `repo.zabbix.com` keep their stock `zabbix-*` package/binary names (README's
   "Technical Notes": "internal package names remain `zabbix-*` for apt compatibility"). Services are
   `zabbix-server`/`zabbix-agent`/`apache2`, not `vizoure-*`, on Linux.
2. **Database** rows are renamed via `UPDATE` statements (display `name`/`description` fields only — never the
   technical `host` identifier that agents use to connect, except where explicitly noted).
3. **Installed UI files** (`/usr/share/zabbix/ui/**`) are patched in place by `apply-branding.sh` — logos, CSS,
   dozens of individually-targeted `sed` replacements against specific PHP files (see the numbered `[n/11]`
   steps), and a `zabbix.php` → `vizoure.php` URL rewrite.
4. **Zabbix JSON-RPC API** calls (in `install-nms.sh` step `[9/9]`) rename default host groups/dashboards and
   create the `admin`/`<WEB_ADMIN_PASSWORD>` account after the frontend is already up.
5. Windows/macOS agents are rebranded purely at the packaging layer (service name, install path, config file) —
   the underlying binary is still the stock `zabbix_agentd`/`zabbix_agent2` executable downloaded from Zabbix's
   own CDN.

When adding a new branding fix, identify which of these layers it belongs to and follow the existing pattern in
that layer (e.g., a new UI string goes in `apply-branding.sh` as another targeted `sed`, not as a new generic
find-and-replace sweep — the script deliberately avoids blanket `zabbix→vizoure` substitution across the whole
UI tree because that breaks package-identifying strings, config paths, and upstream URLs).

## Credentials are intentionally hardcoded

DB passwords, the default `admin`/`<WEB_ADMIN_PASSWORD>` web login, OS login (`admin`/`<OS_PASSWORD>`), and ESXi build-host
credentials (`packer/variables.pkr.hcl`) are hardcoded in plaintext throughout these scripts. This
matches the README's stated scope ("for internal organizational use"), not an oversight — don't "fix" this
unprompted, and don't echo these values into logs/output beyond what the scripts already print.

## Working directory note

This directory (`D:\projects\vizoure-nms`) is not currently a git repository, even though
`scripts/create-release.sh` assumes a git remote exists (it runs `git tag -d`/`git push origin
:refs/tags/...` against `${BUILD_DIR}`, i.e. the separate `/root/vizoure-nms-builde` build host, not this
checkout). Don't assume `git` commands work here without checking first.
