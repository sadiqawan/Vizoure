# Vizoure NMS Changelog

Release notes for GitHub Releases come from the "## <tag>" sections below (see md/09-update-system.md).

## v7.4.15-vz2
- NEW: in-UI updates. Administration -> Vizoure updates (Super admin only) shows new releases with release notes, upgrades
  with one click (confirmation, live progress, history) or from an uploaded release package when offline.
  Update channels: stable and test. Releases must be signed (ssh-keygen -Y); unsigned or modified packages are rejected.
- NEW: "update available" badge in the top header for Super admins.
- NEW: root updater service (vizoure-updater); the web server never runs upgrades.
- CHANGED: database backups now live in /var/backups/vizoure (0700, last 5 kept), with a free-disk-space check first.
- CHANGED: upgrade.sh supports --branding-only (used by the updater only for signed Vizoure-only releases).
- Existing installs: run one CLI upgrade of this release to get the updater ("First-time update setup" in the README).

## v7.4.15-vz1
- NEW: top-header navigation replaces the sidebar (priority+ "More" menu, hover/keyboard dropdowns, hamburger below 1024px,
  all four themes, kiosk mode); legacy pages (Maps) use it too.
- NEW: install/upgrade use the local branding/ checkout first and fall back to GitHub (one VIZOURE_REF variable pins
  the tag/branch); the ISO, Packer build and release tarball carry branding/ including the header files.

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
