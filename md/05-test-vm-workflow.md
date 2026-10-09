# 05 — Test VM Workflow (Rule A)

Standing procedure for every change from now on, per your instruction.

**Status as of 2026-10-09: this procedure has now been run once, for real**, against
test VM `<VM_IP>` (SSH key auth set up, VM cleaned to a fresh-Ubuntu baseline,
snapshotted by the user). See "VM cleanup executed on 2026-10-09" and "Expected
baseline state" below for exactly what that run did and where it left the VM. The
rest of this file remains the standing procedure for every future change.

The earlier git blocker here is resolved: a real `.git` (origin already pointing at
`github.com/sadiqawan/Vizoure.git`, in sync with `origin/main`) turned out to already
exist inside this repo — the original "not a git repository" finding was a false
negative from checking one directory level too high (see `md/04` `ISS-21`). Step 5's
commit/push is therefore only gated on your explicit approval each time, not on any
missing git setup.

---

## Credential handling (applies for the lifetime of this rule, not just once)

- VM IP, username, password are received in chat and used **only** for that session's
  SSH/API calls. They are never written to any file in this repo — not to a `md/`
  file, not to a script, not to a commit message, not to a log file saved to disk.
- If any command output would echo a password back (e.g. a verbose SSH flag, a `curl
  -u user:pass` in a script that gets logged), that output is redacted before being
  shown to you or saved anywhere.
- First action after first successful login: generate/use an SSH keypair and switch
  the VM to key auth, per your instruction to "recommend switching to SSH key auth
  after first login" — this is a recommendation to make to you, not something done
  without asking, since it changes how you access the VM yourself.
- Nothing about the VM's credentials goes into memory (the persistent
  `~/.claude/.../memory/` files) either — only the *existence and purpose* of this
  workflow does, never the secrets.

---

## Step-by-step procedure

### Step 0 — Pre-checks (read-only, every time, before any install/upgrade)

Run before touching anything, report the results, then wait:

| Check | Command (run over SSH) | Why |
|---|---|---|
| OS version | `lsb_release -a` or `cat /etc/os-release` | `install-nms.sh` hardcodes `+ubuntu24.04` in its Zabbix package URL (see `md/03`, `ISS` risk) — confirm the VM actually matches before assuming the script will work |
| Disk space | `df -h /` | Zabbix + MySQL + packages need real room; a near-full disk fails mid-install in a confusing way |
| RAM | `free -h` | README states 2GB minimum |
| CPU | `nproc` | README states 2 vCPU minimum |
| Network — can it reach apt mirrors | `curl -sI http://archive.ubuntu.com \| head -1` | `install-nms.sh` step `[2/9]`/`[4/9]` depend on this |
| Network — can it reach `repo.zabbix.com` | `curl -sI https://repo.zabbix.com \| head -1` | Required for the Zabbix release package download; see Rule B for what happens if this is unreachable |
| Network — can it reach `github.com`/`raw.githubusercontent.com` | `curl -sI https://raw.githubusercontent.com \| head -1` | Required for `apply-branding.sh`/branding assets fetch (same files flagged under `ISS-01`–`ISS-04` in `md/04`) |
| Open ports already in use | `sudo ss -tulpn` | Catch a conflict (e.g. something already on 80/3306/10050/10051) before install, not after a confusing failure |
| Existing Zabbix/MySQL state | `dpkg -l \| grep -i zabbix`, `mysql -uroot -e "SHOW DATABASES;"` (if reachable) | Confirms the VM is actually clean before a fresh-install test — `install-nms.sh` is not idempotent against a non-clean DB (`ISS-07` in `md/04`) |

Report all of the above to you before proceeding to Step 1.

### Step 1 — Make the change locally
Normal edit in this working copy, same as any other task. No VM involvement yet.

### Step 2 — Copy the change to the VM
Two sub-cases, pick based on what changed:
- **A single script changed** (e.g. just `install-nms.sh`): write it to `/tmp/` on
  the VM via `scp` (or `ssh ... 'cat > /tmp/x.sh'`), matching Rule A's "write to /tmp
  first" instruction exactly.
- **Multiple files changed** (e.g. a script plus a branding asset): `rsync -av
  --exclude '.git' ./ vmuser@VM:/tmp/vizoure-src/` (run from the repo root) so the
  VM has a consistent tree, then run the relevant script from inside
  `/tmp/vizoure-src/`.

Either way, nothing is run automatically — this step only places files.

### Step 3 — Run the install/upgrade on the VM and verify
Run the script explicitly as `sudo bash /tmp/<file>.sh` (never piped — consistent with
fixing `ISS-01`–`ISS-04` from `md/04`, so this workflow doesn't reintroduce the exact
pattern we're trying to eliminate). Then work through the verification checklist:

| Check | Command | Expected |
|---|---|---|
| Services running | `sudo systemctl status zabbix-server zabbix-agent apache2 mysql --no-pager` | All `active (running)` |
| Web UI loads | `curl -sI http://localhost/vizoure/` (from the VM) and `curl -sI http://<VM-IP>/vizoure/` (from here) | `HTTP/1.1 200` or a redirect to the login page, not a timeout/500 |
| API responds | `curl -s -X POST http://<VM-IP>/vizoure/api_jsonrpc.php -H "Content-Type: application/json-rpc" -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}'` | A JSON `result` with a version string, confirming the JSON-RPC endpoint from `md/02` Layer 3 is actually reachable before trying any authenticated call |
| Branding applied — title | `curl -s http://<VM-IP>/vizoure/ \| grep -io '<title>[^<]*'` | Contains "Vizoure NMS", not "Zabbix" |
| Branding applied — login page | `curl -s http://<VM-IP>/vizoure/ \| grep -ci zabbix` | `0` (no leftover "Zabbix" string in the rendered login page) |
| Branding applied — favicon | `curl -sI http://<VM-IP>/vizoure/favicon.ico` **and** `curl -s http://<VM-IP>/vizoure/favicon.ico \| md5sum` compared against `branding/logos/favicon.ico`'s own md5 | `200` AND matching md5 — `200` alone is not enough, it returns `200` for the *stock* Zabbix favicon too |
| DB renames applied | `mysql -uroot -e "SELECT name FROM vizoure.usrgrp WHERE name LIKE '%Administrator%';"` | Returns "Vizoure Administrators", confirms Layer 1 from `md/02` ran |
| Admin account | `curl ... user.login` with `admin`/`<WEB_ADMIN_PASSWORD>` (per `md/02` Layer 3) | Returns a valid auth token |
| Agent reporting | `sudo zabbix_get -s 127.0.0.1 -k agent.ping` (or check **Monitoring → Latest data** in the UI) | `1` |
| **Page title never says "Warning" or "Zabbix"** | `curl -s <url> \| grep -io '<title>[^<]*'` on **every** page checked below, not just the login page | Never `Warning [refreshed every 30 sec.]` — that exact title is Zabbix's own router-failure/system-warning fallback view, not a real page, and HTTP still returns `200` for it (⚠️ added 2026-10-09 after an incident where this exact gap let a fully broken install pass every curl check below) |

### Authenticated session walk — mandatory, added 2026-10-09

**Why:** every check above can return `HTTP/1.1 200` and a plausible-looking title/favicon on the *login* page while the authenticated app underneath is completely broken — this is exactly what happened on 2026-10-09 (see `md/04` `ISS-26`): the login page looked fine, but every post-login route served Zabbix's generic "Warning"/router-failure view instead of real content, and a plain `curl -sI` check never logs in, so it never saw it.

**Verified working as a catch, 2026-10-09**: run against two full install→re-run cycles after the `ISS-07`/`ISS-08`/`ISS-26`/`ISS-29` fixes — all 4 pages (dashboard/hosts/problems/maps) came back with correct titles and zero fallback-page matches on every one of the 4 checks across both cycles. Note the blanket `grep -ci "warning\|page not found"` count is **not** reliable on its own — Zabbix's UI legitimately uses "warning" as a severity-level CSS class name (`.warning-bg`, `msg-warning`) on real pages, producing false positives. Use the precise check instead: `grep -c "Warning \[refreshed every"` for the exact fallback-page title string.

Do this with a real cookie jar, not just `user.login` via the JSON-RPC API (that only proves the *API* works, not the *web frontend's* routing):

```bash
COOKIEJAR=/tmp/vz-verify-cookies.txt
rm -f "$COOKIEJAR"
# 1. Log in through the actual web form (not the API)
curl -s -c "$COOKIEJAR" -b "$COOKIEJAR" -L "http://<VM-IP>/vizoure/index.php" \
    -d "name=admin&password=<WEB_ADMIN_PASSWORD>&enter=Sign+in" -o /tmp/login.html
# 2. Dashboard — the exact route that broke on 2026-10-09
curl -s -c "$COOKIEJAR" -b "$COOKIEJAR" "http://<VM-IP>/vizoure/vizoure.php?action=dashboard.view" -o /tmp/dash.html
# 3-5. At least 3 more authenticated pages
curl -s -c "$COOKIEJAR" -b "$COOKIEJAR" "http://<VM-IP>/vizoure/vizoure.php?action=host.view" -o /tmp/hosts.html
curl -s -c "$COOKIEJAR" -b "$COOKIEJAR" "http://<VM-IP>/vizoure/vizoure.php?action=problem.view" -o /tmp/problems.html
curl -s -c "$COOKIEJAR" -b "$COOKIEJAR" "http://<VM-IP>/vizoure/sysmaps.php" -o /tmp/maps.html
# Check EVERY one of the 4 saved files, not just HTTP status:
for f in dash hosts problems maps; do
    echo "--- $f ---"
    grep -io '<title>[^<]*' "/tmp/$f.html"
    grep -ci "warning\|page not found" "/tmp/$f.html"
done
```
Expected: each page's title reflects the actual page (e.g. "Dashboard", "Hosts", "Problems"), not "Warning"; the `warning\|page not found` grep count is `0` for all four. Any non-zero count or a "Warning" title means the authenticated app is broken even though every earlier HTTP-status-only check passed.

### Never leave a destructive test mid-way — added 2026-10-09
If a test deliberately re-runs `install-nms.sh`/`upgrade.sh` against an already-installed system (e.g. to exercise a non-idempotency code path on purpose, as done for `ISS-09`/`ISS-10`'s verification), **and it fails or aborts partway through** (expected — `ISS-07` means a second run is not idempotent), **do not leave the VM in that half-modified state.** Specifically: `apt install --reinstall` steps (present in both scripts) restore package-shipped files to stock content — including files `apply-branding.sh` has already patched (`ZBase.php`, `favicon.ico`, etc.) — and if the script then aborts before reaching its own branding re-application step, those files stay reverted with no error or warning shown anywhere. This is exactly what happened on 2026-10-09 (`md/04` `ISS-26`). Either:
- Ask the user to revert the hypervisor snapshot before any further testing, or
- Run a full clean re-install (not just the one script step that needs re-testing) to put the branding back, and re-verify with the authenticated session walk above before considering the VM usable again.
Never assume a partially-failed deliberate test left the system otherwise intact just because the specific error you were testing for occurred as expected.

### Step 4 — Show you the verification output
Every command's actual output goes to you verbatim (redacting nothing except
credentials per the handling rules above) — not a summary claiming "it worked."

### Step 5 — Wait for your explicit approval, then commit and push
No `git commit`/`git push` happens until you say so in this chat. Once approved:
`git add`/`git commit` locally, then `git push` to `origin main` (the remote is
already configured and in sync — see the status note at the top of this file).

---

## Resetting the VM to a clean state between tests

Three options, in order of preference — which one applies depends on the VM's
hypervisor, which I don't know yet:

1. **Snapshot/revert — this is the active method for this VM.** The user has already
   taken a hypervisor snapshot of the clean Ubuntu install, before any Vizoure
   install/upgrade has touched it. Procedure: when a clean state is needed before the
   next test cycle, I ask the user to revert it (the user controls the hypervisor —
   this is not something run from inside the VM or from this chat's tool access), and
   wait for confirmation it's been reverted before running Step 0's pre-checks again.
   ⚠️ needs confirmation: which hypervisor the snapshot lives on (not required for
   this workflow to function, since the user does the revert manually either way).
2. **Rebuild from the autoinstall ISO.** `scripts/build-iso.sh` +
   `packer/http/user-data` already produce an unattended-install image. If
   snapshotting isn't available, tearing down and re-provisioning the VM from that
   ISO is the next-best clean slate — slower (full OS install each time) but uses
   infrastructure this repo already has.
3. **In-place teardown script.** Not available — tracked as `ISS-23` in `md/04`. No
   uninstall/teardown script exists anywhere in this repo; neither `install-nms.sh`
   nor any other script removes the `zabbix-*` packages, drops the `vizoure`
   database, or reverts the Apache/PHP config changes. Not needed for now since
   option 1 (snapshot/revert) is the active method for this VM.

---

## Expected baseline state

What "clean" means for this specific VM (`<VM_IP>`), as of the 2026-10-09
snapshot — Step 0's pre-checks should compare against this, not against a theoretical
blank Ubuntu install:

- Ubuntu 24.04.4 LTS, kernel as shipped by the base image.
- Only port 22 (SSH) listening externally; `udp/tcp 53` and `udp 68/546` are local
  `systemd-resolved`/`systemd-networkd` stubs, not externally reachable, and are
  expected on any stock Ubuntu box.
- No `zabbix*`/`mysql*`/`mariadb*`/`apache*`/`php*` packages installed.
- **The `vizourenms` OS user (UID 1000) is present and must stay.** Per the user: this
  is the account created by the Ubuntu Server installer itself, not by any Vizoure
  script — it's part of a normal fresh install and serves as a fallback login. Do not
  remove it, its home directory, or its `.ssh/` during any future cleanup.
- Root SSH key auth is set up (this session's key); root password auth is still
  enabled server-side (not disabled, since changing sshd config wasn't authorized).
- `snmpd` is **not** present — it was removed (initially by an unintended
  `autoremove --purge`, then confirmed-intentional per the user) and confirmed to have
  no relationship to any Vizoure script.
- Nothing under `/opt/`, no `nms-proxy.conf` — the portal prototype described in
  `md/04` `ISS-24` was backed up and removed; it is not part of this baseline.

## VM cleanup executed on 2026-10-09 (for reference, not a procedure to repeat verbatim)

What actually happened to bring `<VM_IP>` from a stuck, partially-broken prior
install to the baseline above — kept here as a record, since some of it was
improvised in response to what was actually found on the box, not planned in advance:

1. **Backup first.** `tar.gz` of `/var/lib/mysql` (raw files, DB not started),
   `/etc/zabbix` + the Apache/MySQL config + the branded `/usr/share/zabbix` tree,
   `/root/.bash_history` + the leftover release `.deb` (archived, never read), and a
   filtered `dpkg -l`. Copied off the VM to `vm-backups/pre-clean-backup-20261009-071153/`
   (outside this repo), with `sha256sum` verified identical on both sides.
2. **Found the VM wasn't actually clean to start with** — a prior Vizoure install was
   present and partially broken (MySQL down for 2 days). Root cause turned out to be
   an unattended-upgrade run from 2026-10-07 whose post-upgrade service-restart batch
   had `zabbix-server`/`mysql`'s restart jobs "canceled," leaving `unattended-upgrades`
   hung holding the dpkg lock for 2 days straight. Cleared by terminating the stuck
   process tree (`dpkg --audit` was clean throughout — safe to do) before any purge
   could proceed.
3. **Also found, backed up separately, and removed** (not anticipated going in):
   `/opt/vizoure-portal` (a real Flask app, 44MB) and its `vizoure-portal.service`
   systemd unit, plus `/etc/apache2/conf-enabled/nms-proxy.conf` which reverse-proxied
   to it — see `md/04` `ISS-24`. Backed up to the same `vm-backups/` folder before
   removal.
4. Purged `zabbix-*`, `mysql-*`, `apache2*`, `php*` packages; removed `/etc/zabbix`,
   `/etc/mysql`, `/usr/share/zabbix`, `/var/log/zabbix`, the zabbix apt
   `.sources`/keyring files, a dangling `zabbix-server.service` systemd symlink dpkg
   left behind, a stray release `.deb` in `/home/admin`, and a `zabbix_server` crash
   dump.
5. **Mistake made and corrected mid-task:** an initial `apt-get autoremove --purge -y`
   also removed `snmpd`/`libsnmp-base` despite being told to leave it — it had been
   marked as an orphaned auto-installed dependency. Flagged immediately; the user
   confirmed afterward that removal was fine (not a Vizoure dependency either way).
6. Verified clean (package list empty, only port 22 listening, disk free went from
   8.4G → 10G), then the user took a hypervisor snapshot of this exact state. **That
   snapshot is now the reset point** — see option 1 under "Resetting the VM to a clean
   state" below.

## Flowchart

```
                 ┌───────────────────────────┐
                 │ Step 0: Pre-checks (RO)    │
                 │ OS/disk/RAM/net/ports/     │
                 │ existing-state             │
                 └─────────────┬─────────────┘
                               │ report to user
                               ▼
                 ┌───────────────────────────┐
                 │ Step 1: Edit locally       │
                 └─────────────┬─────────────┘
                               ▼
                 ┌───────────────────────────┐
                 │ Step 2: Copy to VM         │
                 │ (scp/rsync → /tmp)         │
                 └─────────────┬─────────────┘
                               ▼
                 ┌───────────────────────────┐
                 │ Step 3: sudo bash /tmp/x.sh│
                 │ + verification checklist   │
                 │ (services/UI/API/branding/ │
                 │  DB/admin-login/agent)     │
                 └─────────────┬─────────────┘
                               ▼
                 ┌───────────────────────────┐
                 │ Step 4: Show raw output    │
                 │ to user (no summarizing)   │
                 └─────────────┬─────────────┘
                               ▼
                      ┌────────┴────────┐
                      │ User approves?  │
                      └───┬─────────┬───┘
                      no  │         │ yes
          ┌───────────────┘         └───────────────┐
          ▼                                          ▼
 ┌─────────────────────┐                  ┌───────────────────────┐
 │ Fix, repeat from     │                  │ Step 5: commit + push │
 │ Step 1 or Step 2     │                  │ (to origin main)      │
 └─────────────────────┘                  └───────────────────────┘
          (between test cycles: revert VM snapshot, or
           rebuild from autoinstall ISO, or — not yet
           available — run a teardown script)
```
