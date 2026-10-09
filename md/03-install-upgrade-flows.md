# 03 — Install & Upgrade Flows

Operational detail for `scripts/install-nms.sh` and `scripts/upgrade.sh`.
No scripts were modified to produce this file — line numbers are citations only.

---

## `install-nms.sh`

### Preconditions

- **OS**: Ubuntu 24.04 LTS, assumed but never checked by the script. The Zabbix
  release package URL (`scripts/install-nms.sh:36`) hardcodes `+ubuntu24.04` in the
  filename — running this on any other Ubuntu/Debian version would 404 at that `wget`.
  ⚠️ needs confirmation: no `lsb_release`/`/etc/os-release` guard exists anywhere in
  the script.
- **Privileges**: must run as root (or equivalent) — uses `useradd`, `chpasswd`,
  `usermod -aG sudo`, `chage`, `apt`, `mysql -uroot`, writes to `/etc/apache2`,
  `/etc/zabbix`, `/etc/php`, calls `systemctl`. Not checked with an explicit `EUID`
  guard; it will simply fail partway through on permission errors if run unprivileged.
- **Packages assumed pre-existing**: none — the script installs its own prerequisites
  (`curl wget git python3`, `mysql-server`, `imagemagick`) as it goes.
- **Network access required to**: the system's configured apt mirrors, `repo.zabbix.com`,
  `raw.githubusercontent.com` (for `apply-branding.sh`), and `localhost` itself once
  Apache/Zabbix are up (for the JSON-RPC calls).
- **State assumed**: a **fresh** machine with no existing `vizoure`/`zabbix` MySQL
  database and no existing `/etc/zabbix` config. The script has no "already installed,
  skip ahead" logic — see Idempotency below.

### Step-by-step order of operations

| Step | Lines | What happens |
|---|---|---|
| `[1/9]` | 16–24 | Create (or just reset the password of) the OS user `admin`/`<OS_PASSWORD>`; `chage -d 0` forces a password change prompt at next login |
| `[2/9]` | 26–28 | `apt update && apt upgrade -y` (whole-system upgrade, not scoped to this install), then install `curl wget git python3` |
| `[3/9]` | 30–33 | Install `mysql-server`, start + enable it |
| `[4/9]` | 35–47 | Download and `dpkg -i` the Zabbix 7.4 release package for Ubuntu 24.04, `apt update`, install `zabbix-server-mysql`, `zabbix-frontend-php`, `zabbix-apache-conf`, `zabbix-sql-scripts`, `zabbix-agent`, then force-reinstall `zabbix-sql-scripts` and `zabbix-frontend-php` |
| `[5/9]` | 48–91 | Create DB/user/grants (`CREATE ... IF NOT EXISTS`), set `log_bin_trust_function_creators=1`, import `server.sql.gz` schema, verify with `SELECT 1 FROM hosts`, run the 10 single-line Layer-1 rename `UPDATE`s (lines 61–70), run the 11-statement description-phrase heredoc + 3 `REGEXP_REPLACE` cleanups (71–86), one more standalone description fix (87), reset `log_bin_trust_function_creators=0` (91) |
| `[6/9]` | 93–146 | `sed`-patch `/etc/zabbix/zabbix_server.conf` (DB password/name/user), disable any pre-existing Zabbix Apache conf, write a new `/etc/apache2/conf-available/vizoure.conf` (Alias `/vizoure`, rewrite rule for `zabbix.php`→`vizoure.php`, PHP tuning), `a2enconf vizoure`, `a2enmod rewrite`, write `/etc/zabbix/web/zabbix.conf.php` |
| `[7/9]` | 147–149 | `systemctl restart` + `enable` `zabbix-server zabbix-agent apache2` |
| `[8/9]` | 150–155 | Install `imagemagick python3 curl`, fetch **the latest** `branding/apply-branding.sh` from `raw.githubusercontent.com/.../main/...` (not from local disk), run it — this is Layer 2 of the rebrand, see `02-rebrand-mechanics.md` |
| `[9/9]` | 157–298 | Poll `http://localhost/vizoure/api_jsonrpc.php` for up to 120s; log in as the factory `Admin`/`zabbix` account; rename server name, 5 host groups, and the default host; create the `admin`/`<WEB_ADMIN_PASSWORD>` account; delete 2 default dashboards and 1 map; patch dashboard-widget JSON via an inline Python block; re-login as the new account and randomize the original `Admin` password |

### External dependencies and what breaks if unreachable

| Dependency | Used at | If unreachable |
|---|---|---|
| Ubuntu apt mirrors | steps 2–4, 8 | `apt`/`wget` fails, script aborts (`set -eo pipefail`) at that line |
| `repo.zabbix.com` | step 4, line 36 | `wget -q` fails silently on output but still returns non-zero → `dpkg -i` on a missing/partial file aborts the script |
| `raw.githubusercontent.com` | step 8, line 153 (and again inside `apply-branding.sh` itself for logos) | `curl -sSL` has **no `-f` flag**, so an HTTP error page (e.g. GitHub down, rate-limited, or `main` branch missing the file) can be written to `/tmp/apply-branding.sh` as if it succeeded, and the script then executes whatever that response body was. ⚠️ needs confirmation — this looks like a real gap, not just a documentation note: a network hiccup here doesn't cleanly abort, it can run garbage. |
| `localhost` Zabbix API | step 9 | Script polls for 120s, then prints Zabbix server status and `exit 1` — this one **does** fail cleanly |

### Idempotency — safe to re-run?

**No, not as a whole.** Specifically:
- Steps `[1/9]`–`[4/9]`: effectively idempotent (OS user creation branches on
  existence; `apt install`/`dpkg -i` are no-ops on already-installed packages).
- Step `[5/9]`: **not idempotent**. `CREATE DATABASE/USER IF NOT EXISTS` are safe, but
  the schema import (`zcat server.sql.gz | mysql ... ${DB_NAME}`, lines 56–57) has no
  "already imported" guard. On a second run against a DB that already has Zabbix's
  tables, the import emits `CREATE TABLE`-already-exists errors; under `set -eo
  pipefail` this aborts the script **immediately at that line**, before it even
  reaches the "schema import failed" sanity check on line 58, and well before any of
  the branding/API steps that follow. A second run on an un-cleaned system fails fast
  here rather than silently re-doing work.
- The Layer‑1 rename `UPDATE`s (lines 61–87) are individually idempotent
  (`REPLACE()` on a string that no longer contains "Zabbix" is a harmless no-op) —
  moot in practice since step `[5/9]` aborts before reaching them on a re-run.
- Step `[6/9]`: idempotent. The Apache conf and `zabbix.conf.php` heredocs fully
  overwrite their targets each run; `a2enconf`/`a2enmod` on an already-enabled
  module/conf are harmless.
- Step `[8/9]` (`apply-branding.sh`): mostly idempotent by construction — the Python
  exact-block-match patches (login page, sidebar menu) print a `WARNING: ... pattern
  not found — skipped` and continue on a second run, because the pattern they're
  looking for was already changed the first time. The `zabbix.php`→`vizoure.php`
  `ZBase.php` sed similarly no-ops once already patched. The image/CSS/file-copy steps
  just overwrite again. See `02-rebrand-mechanics.md` for the full step list.
- Step `[9/9]`: **not idempotent, and fails without crashing.** The first run ends by
  randomizing the original `Admin`/`zabbix` account's password (line ~292,
  `openssl rand -base64 24`, discarded — not logged or saved anywhere). A second run's
  `user.login` as `Admin`/`zabbix` (line 170–173) will then return an empty token, hit
  the `else` branch at line 296 ("WARNING: Could not login — change Admin password
  manually"), and **silently skip the entire rest of step 9** — no host group renames,
  no new `admin` account (if it somehow didn't get created the first time), no
  dashboard/map cleanup. The script still exits 0.

### Backups / what's destructive

- **No backup is taken at any point in this script.** It assumes a fresh machine with
  nothing worth preserving.
- Destructive, unrecoverable-by-the-script actions:
  - `apt upgrade -y` (line 27) — whole-system package upgrade, not scoped to Zabbix;
    affects unrelated installed software with no snapshot taken first.
  - `dashboard.delete` on ids `["2","57"]` and `map.delete` on id `["1"]` (lines
    232–240) — stock default dashboards/map are deleted outright, not archived.
  - Randomizing the original `Admin` account's password (line 292) with a value that
    is never displayed, logged, or stored — this **permanently locks out** the factory
    `Admin`/`zabbix` login going forward; the only account left is the new
    `admin`/`<WEB_ADMIN_PASSWORD>`. ⚠️ needs confirmation whether this is the intended
    "security hardening" behavior or should at least log the generated password
    somewhere recoverable.

### Rollback / recovery if it fails midway

**None exists in the script.** There is no trap/cleanup handler, no "undo" path, and no
documentation (in `README.md` or `CHANGELOG.md`) describing manual recovery. Practical
recovery is entirely manual and depends on which step failed:
- Failure in steps 1–4: re-running the script is close to safe (see Idempotency).
- Failure in step 5 (schema import) on a re-run: operator must manually
  `DROP DATABASE vizoure;` (or otherwise clear the partially-imported schema) before
  re-running, or the script will keep aborting at the same line.
- Failure in step 9 after the `Admin` password was already randomized: the operator is
  left with no way to log in as `Admin`, and if `user.create` for the new `admin`
  account didn't complete first, **no admin account may exist at all** — recovery
  would require direct DB access (e.g. resetting a password hash in the `users` table)
  which this script provides no helper for.
⚠️ needs confirmation: whether an undocumented manual-recovery runbook exists outside
this repo.

### Flowchart

```
install-nms.sh
  │
  ├─[1/9]─ OS user admin/<OS_PASSWORD> (create or reset)
  ├─[2/9]─ apt update/upgrade + curl,wget,git,python3
  ├─[3/9]─ mysql-server install + start/enable
  ├─[4/9]─ zabbix-release .deb (repo.zabbix.com) ── FAILS HARD if unreachable
  │         └─ apt install zabbix-server-mysql, frontend-php, apache-conf,
  │                         sql-scripts, agent (+ forced reinstall x2)
  ├─[5/9]─ CREATE DATABASE/USER ──> import server.sql.gz ── FAILS HARD on re-run
  │         └─ sanity SELECT check ── fails hard if schema broken
  │         └─ Layer-1 DB renames (10 UPDATEs + 11-stmt heredoc + 1 more)
  ├─[6/9]─ patch zabbix_server.conf, write vizoure.conf (Apache), zabbix.conf.php
  ├─[7/9]─ restart/enable zabbix-server, zabbix-agent, apache2
  ├─[8/9]─ curl apply-branding.sh from GitHub main ── NO -f, silent-garbage risk
  │         └─ run it (Layer 2 rebrand — see 02-rebrand-mechanics.md)
  └─[9/9]─ poll API up to 120s ── exits 1 cleanly if API never comes up
            └─ login Admin/zabbix ── if this fails (e.g. 2nd run), SKIP REST, exit 0 anyway
            └─ rename settings, 5 host groups, default host
            └─ create admin/<WEB_ADMIN_PASSWORD>
            └─ delete 2 dashboards + 1 map
            └─ patch dashboard widget JSON (Python/urllib)
            └─ re-login as admin, randomize original Admin password (unrecoverable)
  │
  ▼
done — no backup taken, no rollback path
```

---

## `upgrade.sh`

### Preconditions

- Must be run on a machine where `install-nms.sh` (or an equivalent setup) has
  already run: it assumes `zabbix-server-mysql` is installed, the `vizoure` MySQL
  database and `vizoure`/`<DB_PASSWORD>` MySQL credentials already exist and are
  **unchanged since install** (the password is hardcoded at line 13, not read from
  `/etc/zabbix/zabbix_server.conf` or anywhere else — if an operator changed the DB
  password after install, this script's `mysqldump` auth fails immediately, before
  anything destructive happens).
- Root privileges (same reasoning as `install-nms.sh`: `mysqldump`, `apt`, `systemctl`,
  `dpkg -i`).
- Requires a version argument: `bash upgrade.sh <new_version>` (e.g. `7.4.12`); exits 1
  immediately with a usage message if omitted (lines 20–24).
- Network access to `repo.zabbix.com` and `raw.githubusercontent.com`, same as install.

### Step-by-step order of operations

| Step | Lines | What happens |
|---|---|---|
| `[1/6]` | 32–35 | Reads the currently-installed `zabbix-server-mysql` version via `dpkg -l` (cosmetic — printed, not used for any branching logic) |
| `[2/6]` | 40–43 | `mysqldump` the whole `vizoure` DB, gzip it to `/tmp/vizoure-db-backup-<timestamp>.sql.gz` |
| `[3/6]` | 48–49 | `systemctl stop zabbix-server zabbix-agent` (errors suppressed with `\|\| true`) |
| `[4/6]` | 54–73 | Download+`dpkg -i` the **new** version's Zabbix release package, `apt update`, install the same 5 `zabbix-*` packages as install does, force-reinstall `sql-scripts`/`frontend-php` |
| `[5/6]` | 78–94 | `systemctl start zabbix-server`, **sleep 10s** (comment: "wait for schema upgrade to complete" — Zabbix's own server process does the DB schema migration on first start of a new version), then re-run 7 of the 10 Layer-1 rename `UPDATE`s (see `02-rebrand-mechanics.md` Known Issues for exactly which ones are missing) |
| `[6/6]` | 99–108 | `systemctl restart apache2`, fetch the latest `apply-branding.sh` from GitHub `main` and run it, then restart+enable `zabbix-server zabbix-agent apache2` again |

### External dependencies and what breaks if unreachable

Same two as install: `repo.zabbix.com` (step 4 — `wget` failure aborts the script
before anything is stopped for good, since services were already stopped at step 3;
they are **not restarted** until step 5/6, so a failure here leaves monitoring down)
and `raw.githubusercontent.com` (step 6 — same no-`-f` silent-garbage risk as install).

### Idempotency — safe to re-run?

- Step `[1/6]`: idempotent (read-only).
- Step `[2/6]`: idempotent in effect but **not safe to rely on** — each run creates a
  new timestamped backup file; old ones are never cleaned up (disk fills over repeated
  upgrades, in `/tmp`).
- Step `[3/6]`: idempotent (`stop` on an already-stopped service is a no-op,
  errors suppressed).
- Step `[4/6]`: idempotent for the same reason as install step 4 (apt/dpkg are
  no-ops on already-current packages) — but re-running with the **same** version
  argument just reinstalls the same packages; nothing prevents accidentally
  "upgrading" to an older version than currently installed (no version comparison
  against the value read in step 1).
- Step `[5/6]`: the `UPDATE` statements are idempotent (safe no-ops on a second run);
  the 10-second `sleep` is a fixed guess, not a poll-until-ready check — ⚠️ needs
  confirmation whether Zabbix's schema migration is guaranteed to finish in 10s for
  larger databases, since nothing checks `systemctl status zabbix-server` or queries
  `DB_VERSION_SUPPORTED` before proceeding.
- Step `[6/6]`: idempotent, same reasoning as install step 8 (`apply-branding.sh`'s own
  patches are self-guarding).

### Backups / what's destructive

- **This script does take a backup** (step 2, full `mysqldump | gzip`) before touching
  anything — the one meaningful difference from `install-nms.sh`'s "no backup at all."
- Destructive-but-expected: stopping `zabbix-server`/`zabbix-agent` (step 3) — monitoring
  is offline from step 3 until step 5/6 restarts it. If step 4 (package install) fails
  partway, services stay stopped with no automatic restart.
- No equivalent of install's dashboard/map deletion or `Admin` password randomization —
  `upgrade.sh` doesn't touch Layer 3 at all (see `02-rebrand-mechanics.md`).

### Rollback / recovery if it fails midway

- **Backup exists** at `/tmp/vizoure-db-backup-<timestamp>.sql.gz`, but the script
  never prints or documents the restore command, and nothing restores it
  automatically on failure. Manual recovery would be approximately:
  `gunzip -c <backup> | mysql -u<user> -p<pass> vizoure`, then re-install the
  previous package version and restart services — none of which is in the script or
  the README. ⚠️ needs confirmation whether this manual procedure is documented
  anywhere outside this repo.
- If the script dies between step 3 (services stopped) and step 5/6 (services
  restarted), **monitoring stays down** with no alert, trap, or automatic restart —
  an operator would need to notice and manually `systemctl start zabbix-server
  zabbix-agent`.
- No `trap`/`ERR` handler exists anywhere in the script.

### Flowchart

```
upgrade.sh <new_version>
  │
  ├─[1/6]─ read current dpkg version (cosmetic only)
  ├─[2/6]─ mysqldump + gzip → /tmp/vizoure-db-backup-<ts>.sql.gz   ← ONLY backup in either script
  ├─[3/6]─ stop zabbix-server, zabbix-agent            ← monitoring now OFFLINE
  ├─[4/6]─ new zabbix-release .deb (repo.zabbix.com) ── FAILS HARD if unreachable,
  │         └─ apt install/reinstall zabbix-* packages    services stay stopped if this fails
  ├─[5/6]─ start zabbix-server, sleep 10s (fixed guess, not polled)
  │         └─ re-run 7 of 10 Layer-1 DB renames (subset — see 02-rebrand-mechanics.md)
  └─[6/6]─ restart apache2
            └─ curl apply-branding.sh from GitHub main ── same silent-garbage risk as install
            └─ run it (Layer 2 rebrand)
            └─ restart + enable zabbix-server, zabbix-agent, apache2  ← monitoring back ONLINE
  │
  ▼
done — backup exists on disk, but restore is manual and undocumented
```
