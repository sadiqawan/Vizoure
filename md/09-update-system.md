# 09 — In-UI update system ("Vizoure updates")

Existing customers can see new Vizoure releases and upgrade from the web UI (Administration →
**Vizoure updates**, Super admin only), or offline by uploading a release package. This document is the
contract between the UI module, the root updater service and the release tooling. Tracked as ISS-36 in
`md/04`.

## 1. Architecture

```
 Browser ── Zabbix UI (www-data, PHP) ───────────────────────────────┐
   │  module  modules/vizoure-updates/                               │ reads only
   │  • page + poll (status)                       /var/lib/vizoure-updater/  (root-owned, 0644, no secrets)
   │  • check / upgrade / upload / config (POST,     state.json  history.jsonl  run/<id>/{status.json,log.txt}
   │    CSRF, Super admin only, audit-logged)                         │
   │         │ writes ONE small JSON request (or an uploaded package)  │
   ▼         ▼                                                         │
 /var/spool/vizoure-updater/{requests,uploads}   root:www-data 0730    │
   (www-data can create files, cannot list or read them)               │
         │  vizoure-updater.path  (PathExistsGlob requests/*.json)     │
         ▼                                                             │
 vizoure-updater.service  (root, oneshot, flock single-flight) ────────┘
   /usr/local/lib/vizoure-updater/vizoure-updater.py   (Python 3 standard library only)
   validate → download | copy upload → verify signature+checksum → safe extract →
   VIZOURE_REF=<tag> bash <extracted>/scripts/upgrade.sh <zabbix ver> [--branding-only]
 vizoure-updater-check.timer (6 h) → vizoure-updater-check.service → --check
   GitHub releases API: ETag, rate-limit aware, optional proxy
```

The web server (`www-data`) **never** runs `upgrade.sh`, `sudo` or any shell command, and never contacts the
network. Even "Check now" is just a request file that the root service picks up.

## 2. Files

| Where | What |
|---|---|
| `branding/modules/vizoure-updates/` | Frontend module (manifest.json, Module.php, actions/, views/, assets/css). Registered in the Zabbix `module` table; adds the menu entry under Administration (Super admin only). **No Zabbix core file is patched for the page itself.** |
| `branding/updater/vizoure-updater.py` | Root service. Installed to `/usr/local/lib/vizoure-updater/`. |
| `branding/updater/systemd/` | `vizoure-updater.service/.path`, `vizoure-updater-check.service/.timer` (installed to `/etc/systemd/system/`). |
| `branding/updater/allowed_signers` | Trusted release keys (ssh-keygen `allowed_signers` format). Installed to `/etc/vizoure/allowed_signers`. |
| `branding/VERSION` | The release this tree is, `vX.Y.Z-vzN`. `install-nms.sh` / `upgrade.sh` write it to `/etc/vizoure/version` **after a successful run** (the one place the installed version is recorded). |
| `/etc/vizoure/updater.conf` | `channel=stable|test`, `proxy=`. Written only by the root service (values re-validated). |
| `/var/lib/vizoure-updater/` | `state.json`, `history.jsonl`, `run/<id>/`, `releases/<tag>/` (last 3 verified packages, kept for re-install). |
| `/var/spool/vizoure-updater/` | `requests/`, `uploads/` (write-only for www-data). |
| `/var/backups/vizoure/` | Database backups (0700, last 5 kept). |
| `branding/header/…` + `layout.htmlpage.topheader.php` (V3) | Small "update available" badge in the top header, shown to Super admins when `state.json` reports an update. Reads the status file only. |
| `scripts/make-release-assets.sh`, `scripts/create-release.sh` | Produce / publish the signed release. |
| `scripts/dev/updater_tests/` | Dev-only unit tests (never shipped). |

## 3. Security model

| Threat | Control |
|---|---|
| Web user (www-data) or a PHP bug runs commands as root | UI only writes request files. The root service takes **no shell strings** from them; everything is validated and run as an argument list with a sanitised environment. |
| Non-admin uses the page | `checkPermissions()` = Super admin on every action; the menu item and the header badge are only built for Super admins. Tested with User and Admin roles (no menu item, every action "Access denied"). |
| CSRF | Every POST action requires Zabbix's per-action CSRF token; the read-only page is the only action without one. |
| Forged / replayed / oversized request | Strict schema (unknown keys rejected), `id` must be 32 hex chars and unused (`seen-requests.json`), timestamp within 10 min, ≤ 4 KB, opened with `O_NOFOLLOW`, must be a regular file owned by www-data. Every spool file is deleted whether valid or not. |
| Upgrade to something that is not a release | Target must match `^v\d+\.\d+\.\d+-vz\d+$`, appear in the release list **the root service fetched itself**, be newer than installed (no downgrades), and be visible on the configured channel. |
| Malicious or tampered package (online or uploaded) | `SHA256SUMS` must carry a valid `ssh-keygen -Y` signature (namespace `vizoure-release`) from a key in `/etc/vizoure/allowed_signers`, then the package hash must match. **No override exists in the UI.** `release.json` and `VERSION` are read from *inside* the verified package and must match the requested tag. |
| Tar tricks | Members must be regular files/dirs under `vizoure-nms-<tag>/`; absolute paths, `..`, links, devices rejected; member count and extracted size capped; extraction with the `data` filter into a root-only directory (uploads are copied there first, so no TOCTOU). |
| Source swap / SSRF | GitHub owner/repo are constants in the updater (not configurable). Downloads only from `https://github.com/sadiqawan/Vizoure/releases/download/<tag>/<asset>`; redirects only to GitHub hosts. |
| Credentials in logs | Log lines containing `pass`, `secret` or `token` are replaced; proxy URLs may not contain credentials. |
| Concurrent upgrades | `flock` single-flight; a second start exits. |
| Auditing | Every UI action is written to the Zabbix audit log (Administration → Audit log, resource "Module", `vizoure.updates`, details = event) by recording it through the module's `config`; the root service keeps the authoritative result in `history.jsonl` (who, when, from/to, source, mode, result, backup file). |

## 4. Release format

- **Tag:** `vX.Y.Z-vzN` — `X.Y.Z` is the Zabbix version, `N` the Vizoure revision (compare as 4 numbers).
- **Channels:** a GitHub Release with `prerelease=false` is **stable**; `prerelease=true` is **test**. The
  signed `release.json` repeats the channel and the updater re-checks it (a test package on the stable
  channel is rejected, even when uploaded by hand).
- **Assets** (produced by `scripts/make-release-assets.sh`):
  `vizoure-nms-<tag>-install.tar.gz`, `SHA256SUMS`, `SHA256SUMS.sig`, `release.json` (display copy).
  The tarball contains the top directory `vizoure-nms-<tag>/` with `scripts/`, `branding/` (header, updater,
  module, MANIFEST, VERSION), `CHANGELOG.md` and **`release.json`**:
  ```json
  {"version":"v7.4.15-vz2","core_version":"7.4.15","type":"full","channel":"stable","released":"2026-10-16T10:28:36Z"}
  ```
- **Release notes** shown in the UI are the GitHub release body, which `create-release.sh` builds from the
  `## <tag>` section of `CHANGELOG.md`.
- **Size:** the package must stay under 2 MB (PHP upload limit for the offline path); the script enforces it.
- **Signing:** `ssh-keygen -Y sign -U` through **ssh-agent**; the private key is never read by any script.
  `make-release-assets.sh --sign` stops with exit 3 if the agent has no matching key, and refuses to publish a
  signature that does not verify against `branding/updater/allowed_signers`.
- **Key rotation:** `allowed_signers` holds one line per trusted key. To rotate, publish a release signed with
  the *old* key whose `allowed_signers` lists the new key (installed by that upgrade); later releases are signed
  with the new one. Lost key = customers cannot take new releases from the UI until a package signed by a still-trusted
  key (or a CLI upgrade, which installs the repo's `allowed_signers`) replaces the list — keep an offline backup.

## 5. Flows

**Check** (timer every 6 h ± 15 min, or "Check now", min. 60 s apart): GitHub releases API with `If-None-Match`
(304s do not count against the rate limit), User-Agent set, optional proxy. On HTTP 403/429 the next check waits
until `X-RateLimit-Reset`. Failures are shown on the page together with the offline option.

**Upgrade from GitHub:** confirm dialog (backup, restart, downtime) → request → root validates → downloads the 3
assets → verifies → extracts → runs the package's own `scripts/upgrade.sh <zabbix ver>` with `VIZOURE_REF=<tag>`.

**Offline:** upload the three files (package, `SHA256SUMS`, `SHA256SUMS.sig`) → same verification and run, no
network needed (≤ 2 MB per file).

**Mode:** the *updater* decides. `--branding-only` (no Zabbix package/DB steps, only Apache restarted) is used only when the
signed `release.json` says `type: branding-only` **and** its `core_version` equals the installed core (Zabbix) version; otherwise
the full upgrade runs.

**Backups:** `upgrade.sh` checks free space first (estimated dump size + 512 MB) and aborts cleanly with nothing changed,
then dumps to `/var/backups/vizoure/`, verifies it with `gzip -t`, keeps the last 5, and prints
`VIZOURE_BACKUP_FILE=` which the updater records.

**UI progress / Apache restarts:** the page polls `status` every 2 s. While Apache is restarting the fetch fails; the page
shows "server is restarting", retries every 3 s for up to 15 minutes, then reloads on success.

## 6. Failure and recovery

- Any failure ends the run in `failed` with the error, the log, the backup path and recovery steps shown on the page.
- If the updater is killed or the machine reboots mid-run, `ExecStopPost`/the next start marks the run `interrupted`.
- Services stopped by the upgrade are **not** restarted automatically (a half-upgraded schema): the page says to run
  `sudo systemctl start zabbix-server zabbix-agent apache2` or simply re-run the upgrade (safe to repeat).
- Restore: `sudo systemctl stop zabbix-server && zcat <backup> | sudo mysql vizoure && sudo systemctl start zabbix-server`.
- Previous release: `releases/<tag>/` keeps the last 3 verified packages; extract one and run its `scripts/upgrade.sh`.
- There is no automatic rollback (ISS-10).

## 7. Bootstrap (first-time update setup)

Installs made before this feature do not have the module or the service. They take **one** CLI upgrade of a release that
contains it (README, "First-time update setup"); from then on updates run from the UI. Fresh installs, the ISO and the OVA
already contain it.

## 8. Publishing a release (runbook)

1. Set `branding/VERSION` (`vX.Y.Z-vzN`), add a `## vX.Y.Z-vzN` section to `CHANGELOG.md`, run `check-crlf.sh` and `check-manifest.sh`.
2. Load the signing key into ssh-agent (`ssh-add`), then `GITHUB_TOKEN=… [PRERELEASE=1] [RELEASE_TYPE=branding-only] bash scripts/create-release.sh`.
3. Test on a VM through the UI first (see `md/05`, "Update feature checklist"). Delete test pre-releases and tags afterwards.

## 9. Known limits

Direct SQL registers the module (ISS-37); audit goes through a module-config write (ISS-38); the log viewer hides any line containing
a credential word; the update page needs JavaScript; release notes are shown as plain text.

## 10. Release publication plan (the Releases page)

- Today the repository's **Latest** release is the legacy `v7.4.9` (no signed assets, not part of the update system; the updater
  ignores tags that do not match `vX.Y.Z-vzN`).
- **After this feature is merged:** publish `v7.4.15-vz2` (the first updater-capable release) as a signed **stable** release
  (`create-release.sh` without `PRERELEASE`), verify it on a clean VM through the UI, then mark it **Latest** (GitHub: Edit release ->
  "Set as the latest release").
- Mark `v7.4.9` as **legacy**: edit its notes to start with "Legacy release. It cannot be updated from the web UI. Use v7.4.15-vz2 or
  newer." (do not delete it: existing installs and links may refer to it). Do this only when `v7.4.15-vz2` is published.
- Test pre-releases (`PRERELEASE=1`) are never marked Latest and are deleted, with their tag, after testing.
- GitHub always attaches **Source code (zip/tar.gz)** to a release and this cannot be disabled. The release notes therefore start with a
  box telling customers to download only the 3 files (package, `SHA256SUMS`, `SHA256SUMS.sig`); the upload page recognises a
  source archive and says so; `.gitattributes` `export-ignore` keeps those archives free of `md/`, `scripts/dev/`, `packer/`.

## 11. Rejected versus failed

- **Rejected** (validation refused the request before anything on the server changed: wrong channel, not newer, bad signature,
  checksum mismatch, not a release package, download problem, or `upgrade.sh` refusing to start because the backup cannot be made):
  state `rejected`, shown as "Upload rejected - nothing was changed on the server" with the reason in plain words and how to fix it.
  No recovery steps, no log, no failure box. The PHP side already answers wrong-channel / not-newer / "Source code" archive before
  anything is queued, and the browser warns right after files are selected.
- **Failed / interrupted** (after `upgrade.sh` started): state `failed`/`interrupted`, recovery steps and the log are shown; the backup is kept.
- The page shows customers no upstream product name: the log is rewritten (`zabbix` -> `vizoure`), the unfiltered output is
  kept root-only in `run/<id>/log.raw.txt`, recovery uses `sudo vizoure start|stop|status`, and `release.json` uses the neutral key `core_version`.
