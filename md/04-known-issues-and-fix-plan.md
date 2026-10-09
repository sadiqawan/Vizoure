# 04 — Known Issues and Fix Plan

Consolidated from `md/02-rebrand-mechanics.md`, `md/03-install-upgrade-flows.md`, and
the Step 1 read. No scripts modified to produce this file.

## Issue table

| ID | Issue | File + lines | Impact | Severity | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| ISS-01 | `curl \| bash` with **no intermediate file at all** — Ubuntu autoinstall pipes `install-nms.sh` straight into `bash` during unattended provisioning | `packer/http/user-data:23` | Arbitrary code from a mutable `main`-branch URL executes as root with zero integrity check, zero non-empty check, and no retry visibility if the fetch is truncated mid-stream | Critical | Change to: `curl -sSL -o /tmp/install-nms.sh <url>`, verify `[ -s /tmp/install-nms.sh ]` + checksum/signature, then `sudo bash /tmp/install-nms.sh` | S |
| ISS-02 | Same direct `curl \| sudo bash` pipe in the Packer provisioner | `packer/ubuntu-server.pkr.hcl:67` | Same as ISS-01, but during VM image bake — a silently-truncated fetch could bake a half-configured "golden image" that then gets distributed as the OVA | Critical | Same fix pattern as ISS-01, applied to the `provisioner "shell" { inline = [...] }` block | S |
| ISS-03 | `apply-branding.sh` is downloaded to a file first (not a raw pipe) but then run with **no verification** — no `-f` on curl, no non-empty check, no checksum | `scripts/install-nms.sh:153–155`, `scripts/upgrade.sh:103–105` | An HTTP error page or truncated download can be written to `/tmp/apply-branding.sh` and executed as-is (see `md/03`) | High | Add `curl -fsSL`, then `[ -s /tmp/apply-branding.sh ] \|\| exit 1`, then a checksum/signature compare, before `bash` | S |
| ISS-04 | README's own quick-install, upgrade, and macOS-agent commands document the same unverified `curl -o` + `sudo bash` pattern for end users | `README.md:44–47` (install), `:139–141` (upgrade), `:114–117` (macOS agent) | Propagates the unsafe pattern to every operator who copies the docs verbatim | High | Update README examples once ISS-01–03's fix pattern is settled, so docs match scripts | S |
| ISS-05 | 5 DB rename statements exist in `install-nms.sh` but are missing from `upgrade.sh`: `usrgrp.name`, `users.name`/`surname`, `media_type.smtp_email`, the full 11-statement description-phrase heredoc, and one standalone description fix | `scripts/install-nms.sh:66–87` vs. `scripts/upgrade.sh` (absent) — full detail in `md/02-rebrand-mechanics.md` Known Issues | Any of these rows reset to Zabbix-branded text by a point-release upgrade is never fixed again | High | Move the full Layer‑1 rename set into one shared file/function both scripts call (see "Shared-code suggestion" below) | M |
| ISS-06 | Layer 3 JSON-RPC renames (5 host groups, default host, 2 dashboards + 1 map deleted, dashboard-widget JSON patch) have no equivalent step in `upgrade.sh` at all | `scripts/install-nms.sh:157–298` vs. `scripts/upgrade.sh` (absent) | Anything restored to a Zabbix default by an upgrade (e.g. a factory dashboard resurrected by a schema migration) is never re-branded | High | Factor the Layer 3 block into a callable step invoked from both scripts, made idempotent (see ISS-08) | M |
| ISS-07 | `install-nms.sh` is not idempotent: a re-run against an already-provisioned DB hard-aborts at the schema import (`set -eo pipefail`), before reaching its own "schema import failed" sanity check | `scripts/install-nms.sh:56–58` | A re-run after any earlier partial failure fails again at the same place with a confusing error, no guidance to drop the DB first | High | Guard the import with an existence check (e.g. query `information_schema.tables`) and skip/warn instead of blind-importing | M |
| ISS-08 | Step `[9/9]` is silently skipped on a second run because the first run already randomized the factory `Admin`/`zabbix` password — the script still `exit 0` | `scripts/install-nms.sh:170–173` (login), `:296–298` (warning + silent continue) | A re-run after a failure in steps 1–8 produces no host-group renames, no `admin` account, no dashboard cleanup — with success exit code | High | Persist an "already configured" marker (e.g. check if `admin` user already exists) and branch step 9's logic on that instead of relying on the old login failing | M |
| ISS-09 | `install-nms.sh` takes **no DB backup** anywhere, and permanently discards the original `Admin` account's password (`openssl rand -base64 24`, never logged/stored) | No backup exists in the file; discard at `scripts/install-nms.sh:292` | A failure or mistake after this point leaves no recovery path and no backup to restore from on a fresh install | Critical | Add a timestamped `mysqldump` backup before step 5 (mirroring `upgrade.sh` step 2), and persist the randomized password to a root-only file instead of discarding it | S |
| ISS-10 | No rollback/recovery mechanism in either script — no `trap`/`ERR` handler, no documented manual recovery procedure | Both scripts, entire file | Any mid-script failure leaves the system in an undefined, partially-configured state with no guided way back | High | Add a minimal `trap 'echo "FAILED at line $LINENO"' ERR` at minimum; document manual recovery steps per script in the README or a runbook | M |
| ISS-11 | ~~The vendored reference tree `zabbix-master/` is Zabbix **8.0.0rc2**...~~ **RESOLVED 2026-10-09 — version decision made.** Confirmed against a real install (test VM `<VM_IP>`): `dpkg -l` showed `zabbix-server-mysql`/`zabbix-agent`/etc. actually installed at `7.4.11`, not the `7.4.9` the repo's docs stated. Live research (`md/06`) found no security differentiator among `7.4.9`/`7.4.11`/`7.4.15` (all past the last relevant CVE fix, `7.4.6`), but `7.4.15` has real stability fixes `7.4.11` lacks. **Decision: pin `7.4.15`, fallback to `7.4.11` if branding breaks on it** — see `md/06`'s "DECISION" note. `zabbix-master/` itself is still pending replacement with the correctly pinned source (tracked separately as the implementation step, not re-opened here) | `zabbix-master/ui/include/defines.inc.php:16–18`; VM evidence: `dpkg -l \| grep zabbix` on `<VM_IP>`, 2026-10-09; version research in `md/06` | Resolved: the project now has a decided target version instead of floating on the `7.4` channel undecided | — | Remaining implementation step (tracked under the offline-install work, not this row): replace `zabbix-master/` with the pinned `7.4.15` source once downloaded | — |
| ISS-12 | README's macOS agent instructions reference a file that doesn't exist in the repo (`agent-packaging/macos/vizoure-agent-install.sh`); the real file is `package.sh` and does something different (builds a `.pkg` from a pre-existing binary, not an interactive installer) | `README.md:114–117` vs. actual `agent-packaging/macos/package.sh` | Following the README's macOS instructions literally 404s | Medium | Either write the missing installer script, or correct the README to document what `package.sh` actually requires/does | M (new script) / S (docs only) |
| ISS-13 | `CHANGELOG.md` and `README.md` give conflicting default credentials | `CHANGELOG.md:7` vs. `README.md:69–72` | Confusing/wrong for anyone referencing the changelog instead of the README | Medium | Correct `CHANGELOG.md` to match README's two separate credential pairs (web vs. OS login) | S |
| ISS-14 | Every rebrand-relevant script fetches from GitHub `main` unpinned, including at upgrade time — behavior isn't reproducible/pinned to the version being installed | `install-nms.sh:4`, `upgrade.sh:10`, `build-iso.sh:30`, `apply-branding.sh:9` (all `REPO_RAW=".../main/..."`) | An install of "7.4.9" run today vs. next month can silently pick up different branding logic if `main` has since changed | Medium | Pin `REPO_RAW` to a release tag (e.g. `v${VERSION}`) matching the version being installed; have `create-release.sh` cut that tag | M |
| ISS-15 | Hardcoded plaintext secrets throughout: DB password, OS password, web admin password, ESXi root password | `scripts/install-nms.sh:7–9`, `scripts/upgrade.sh:13`, `packer/variables.pkr.hcl` (`esxi_password`) | Stated as intentional for "internal use" (per README), but `create-release.sh` publishes some of these scripts as GitHub Release assets — a quasi-public artifact | Medium | Needs a policy decision before any code fix — see Open Questions | — |
| ISS-16 | Two parallel, inconsistent branding mechanisms: `branding/apply-branding.sh` (live) vs. `branding/branding-patch.sh` (unused, targets a nonexistent `zabbix-source` dir) | `branding/branding-patch.sh`, `branding/branding.conf` | Confusing for future maintainers — easy to edit the wrong one | Low | Archive/delete `branding-patch.sh` + `branding.conf` until the "Version 3 full source fork" roadmap item actually starts, or cross-reference their status in comments | S |
| ISS-17 | Multiple empty scaffold files with no tracked intent: `scripts/branding-patch.sh`, both `agent-packaging/*/build-notes.md`, `packer/README.md` | Listed in `md/01-repo-inventory.md` | Looks finished/present in a directory listing but contains nothing | Low | Populate with real content/TODO markers, or remove until needed | S |
| ISS-18 | `create-release.sh` calls `agent-packaging/linux/build-agent.sh` as a fallback to build the `.deb`, but that script is empty — the "build it if missing" promise is currently false | `scripts/create-release.sh:44–51` vs. `agent-packaging/linux/build-agent.sh` (empty) | The Linux agent `.deb` can never actually be built by this repo today | Medium | Implement `build-agent.sh`, or remove the misleading fallback + the README section that promises it | L (implement) / S (remove claim) |
| ISS-19 | `packer/index.html` is an unrelated, accidentally-saved copy of the public ubuntu.com marketing homepage | `packer/index.html` | Clutter/confusion; no functional impact since nothing references it | Low | Delete it | S |
| ISS-20 | `agent-packaging/windows/installer.wxs` and `agent-packaging/macos/package.sh` both assume pre-built custom binaries that nothing in this repo produces; `installer.wxs` also has a placeholder GUID and isn't wired into any script or the README's actual Windows flow | `agent-packaging/windows/installer.wxs`, `agent-packaging/macos/package.sh` | Orphaned scaffolding for a custom-binary pipeline that doesn't exist yet | Low | Complete the custom-binary build pipeline these depend on, or mark them clearly as future/unwired work | L (complete) / S (mark as future work) |
| ISS-21 | ~~This checkout is not a git repository~~ — **corrected 2026-10-09**: a real `.git` with `origin` already pointing at `github.com/sadiqawan/Vizoure.git`, on branch `main`, in sync with `origin/main`, existed one directory level inside this checkout (`Vizoure/.git`) all along. The original finding was a false negative — `git status` was only ever run from the parent folder (`D:\projects\vizoure-nms`), which doesn't detect a `.git` one level further down; the subfolder itself was never checked directly | `scripts/create-release.sh:92–93` (still references a separate build host's git state, which is a real but separate point — that part of the original finding stands) | The original "mismatch" impact doesn't apply to this checkout after all; `create-release.sh`'s own build-host assumption is still worth noting but is unrelated to whether *this* folder is a git repo | Low | No fix needed for this checkout specifically; `create-release.sh`'s build-host path assumption is already covered by `ISS-22` | — |
| ISS-22 | `/root/vizoure-nms-builde` (note the typo — "builde") is hardcoded across `create-release.sh`, `build-iso.sh`, `branding/branding-patch.sh` with no override | `scripts/create-release.sh:13`, `scripts/build-iso.sh` (relative paths assume this cwd), `branding/branding-patch.sh:7` | Fragile, single-machine assumption; no environment-variable override | Low | Parameterize via an environment variable, defaulting to the current hardcoded path | S |
| ISS-23 | No VM/host reset or teardown mechanism exists anywhere in this repo — nothing uninstalls the `zabbix-*` packages, drops the `vizoure` database, or reverts the Apache/PHP config changes `install-nms.sh` makes | No file — this is an absence, not a bug in an existing file | Between test runs (see `md/05-test-vm-workflow.md`, Rule A) there is no in-repo way to return a test host to a clean state; must rely entirely on external hypervisor snapshot/revert or a full OS reinstall | Low | Resolved operationally for now via hypervisor snapshot/revert (see `md/05`); a real teardown script remains a future nice-to-have, not required while the snapshot workflow is in place | M (if ever written) |
| ISS-24 | Real "Vizoure NMS Portal" infrastructure was found deployed directly on the test VM, entirely outside this repo and outside any script here: `/etc/apache2/conf-enabled/nms-proxy.conf` (reverse-proxies `/nms` → `127.0.0.1:5050`), a full Flask app at `/opt/vizoure-portal` (44MB incl. its own venv, `.env`/`.env.example`, `config/`, `core/`, `models/`, `services/`, `templates/`, `storage/` — owned by OS user `admin`), and an `enabled` systemd unit `vizoure-portal.service`. None of this is tracked in git anywhere (`/opt/vizoure-portal` has a local `.gitignore` but no `.git` — it was never its own repo either) | Discovered 2026-10-09 on test VM `<VM_IP>`: `/etc/apache2/conf-enabled/nms-proxy.conf`, `/opt/vizoure-portal/`, `/etc/systemd/system/vizoure-portal.service` (all now removed from that VM after backup — see `md/05`) | Confirms the portal work mentioned as "intentionally removed from the repo" wasn't just removed from git — a working prototype existed and ran outside version control entirely, with no record of it anywhere a future engineer would look. If this VM/its disk were ever lost without the backup taken on 2026-10-09, this prototype would be unrecoverable | Medium | Decide whether this portal code should be recovered from the VM backup (`vm-backups/pre-clean-backup-20261009-071153/opt-vizoure-portal.tar.gz`, outside this repo) and brought into its own tracked repository before any further portal work resumes, so it doesn't happen again | M |
| ISS-25 | `zabbix-master/` cannot serve as "the" pinned 7.4.x source for an offline/no-internet install (Rule B) as it currently stands — it's Zabbix's `master` dev branch at `8.0.0rc2`, not any 7.4 release, let alone the specific point release (`7.4.11`, per `ISS-11`'s VM evidence) actually being installed | `zabbix-master/ui/include/defines.inc.php:16–18` (restates `ISS-11`, called out separately here because the *implication* is different: `ISS-11` is about branding-patch validation, this one is about whether the tree is usable as an installable source base at all) | Any offline-install design that assumes "just build from `zabbix-master/`" is building the wrong version of Zabbix entirely — a non-trivial, possibly incompatible dev snapshot, not a stable release | High (specifically for Rule B / offline-install work; same root fact as `ISS-11` but blocks a different, larger piece of work) | Replace `zabbix-master/` with a pinned checkout of the actual 7.4.x release tag/tarball being targeted (see `md/06-offline-install-strategy.md` for how) before any offline-build work starts | M |

---

## Recommended fix order

**Batch 1 — Stop the bleeding (before touching anything else).**
`ISS-01, ISS-02, ISS-09, ISS-10`. Reason: these are the issues that turn any *other*
mistake — including mistakes made while fixing the issues below — into an
unrecoverable one (no verification before root code execution, no backup, no
rollback). Fix the safety net first so every subsequent change is made against a
system you can actually recover if a fix itself goes wrong.

**Batch 2 — Correctness drift between install and upgrade.**
`ISS-05, ISS-06, ISS-07, ISS-08`. Reason: this is where "just re-run the script to fix
it" currently either does nothing (silent skip), makes it worse (hard abort), or
quietly diverges from the fresh-install behavior (DB/API renames). Tackle together
since ISS-05/06 and ISS-07/08 share the same root cause (no shared, idempotent
"apply these changes" primitive) — see the shared-code suggestion below. Depends on
Batch 1 being done first, since iterating on fixes here is itself safer with a backup
and rollback path in place.

**Batch 3 — Supply-chain hardening (lower blast radius than Batch 1, same family).**
`ISS-03, ISS-04, ISS-14`. Reason: these already download-before-run, just without
verification or version pinning — same underlying mechanism (add a checksum/verify
step, pin to a tag) can fix all three together, and README (ISS-04) should only be
updated once the actual script-side fix (ISS-03) is settled.

**Batch 4 — Documentation/consistency cleanup.**
`ISS-11, ISS-12, ISS-13, ISS-21`. Reason: no runtime risk, but actively misleads
whoever reads the docs next; cheap, independent fixes — do whenever convenient,
no dependency on the batches above.

**Batch 5 — Scaffolding and orphaned-file housekeeping.**
`ISS-16, ISS-17, ISS-18, ISS-19, ISS-20, ISS-22`. Reason: zero functional impact
today. Several of these (`ISS-18`, `ISS-20`) are really "roadmap item not started
yet" rather than bugs — worth a product decision (keep as future scaffolding vs.
delete) more than a code fix. Lowest priority.

**Not batched — needs a decision first, not a fix:**
`ISS-15` (hardcoded secrets). See Open Questions.

---

## Shared-code suggestion

Should the DB renames (and arguably the Layer 3 JSON-RPC renames) live in one shared
artifact — e.g. `branding/db-renames.sql` plus a shared shell function — that both
`install-nms.sh` and `upgrade.sh` call, instead of each maintaining its own copy?

**Pros:**
- Eliminates the entire drift class (`ISS-05`) at the root: one file to edit, both
  callers automatically stay in sync — no more diffing two scripts to find what's
  missing.
- Makes future renames easy to audit: a single file's diff shows the whole history of
  what's been rebranded, instead of reconstructing it from two scripts that evolved
  independently.
- The individual `UPDATE ... REPLACE(...)` statements are already idempotent by
  construction (re-running a no-op `REPLACE` is harmless) — a shared file inherits
  that property for free, so calling it from both install and upgrade is low-risk.
- Could be versioned/tagged alongside a release (pairs naturally with the `ISS-14`
  tag-pinning fix), making "what renames shipped with version X" an answerable
  question.

**Cons:**
- Doesn't fully solve the problem on its own: the Layer 3 renames (dashboard/map
  JSON patch, lines ~242–282 of `install-nms.sh`) are Python/JSON-RPC, not SQL — a
  single `.sql` file can't express them, so this would really need **two** shared
  artifacts (a shared `.sql` for Layer 1, a shared script/function for Layer 3), not
  one.
- Both call sites need to agree on how the shared piece receives DB
  credentials/connection info — today each script just hardcodes them inline; a
  shared file needs those passed in (env vars or arguments), which is a slightly
  bigger refactor than it looks.
- Debugging shifts from "read one flat script top to bottom" to "read the script,
  then jump into the shared file" — a minor readability cost, though arguably
  debugging the *current* two-scripts-that-drifted situation is already worse.

No code is proposed here — this is a design question for you to decide before any
implementation work starts.

---

## Open questions ⚠️ needs confirmation

1. **`ISS-15` (secrets):** is the hardcoded-credentials pattern staying as
   "intentional, internal-use only," or should these move out of the scripts before
   any further GitHub Release is published? This gates whether `ISS-15` is a code fix
   or a documented, accepted risk.
2. **`ISS-14` (tag pinning):** should `install-nms.sh`/`upgrade.sh`/`apply-branding.sh`
   be pinned to release tags instead of `main`? If so, `create-release.sh` would need
   a new step to cut/push that tag before the install scripts can reference it —
   confirm this is in scope.
3. **`ISS-05`/`ISS-06` (install vs. upgrade drift):** is `upgrade.sh`'s current
   behavior (don't repeat the extra DB renames, don't touch Layer 3 at all) based on
   an assumption I haven't been told — e.g. "these rows never revert on a Zabbix
   point-release" — or should both scripts simply be reconciled to do the same work?
4. **`ISS-09` (backup + password discard):** should `install-nms.sh` gain a DB backup
   step mirroring `upgrade.sh`'s, and should the randomized `Admin` password be
   surfaced (logged to a root-only file, etc.) instead of discarded — or is
   permanently locking that factory account the intended hardening behavior?
5. **`ISS-12` (macOS agent):** is `package.sh` meant to become the real macOS
   installer (and the README should just be corrected to document it as-is), or is a
   proper `vizoure-agent-install.sh` for macOS still to be written and currently just
   missing?
6. **Batch 5 orphaned files (`ISS-16/17/18/19/20`):** treat these as "not started yet,
   leave alone until their roadmap item begins," or clean up/delete now as part of
   this documentation pass?
7. **Process:** do you want me to start implementing Batch 1 next, or continue
   documenting (e.g. a verification/test plan for how fixes would be checked) before
   any code changes begin?

---

## Proposed remaining `md/` files (names + purpose only — not created)

- **`md/05-secrets-and-credentials.md`** — full inventory of every hardcoded
  secret/credential in the repo, where each is used, and the decision needed before
  any fix (ties directly to `ISS-15` / Open Question 1).
- **`md/06-agent-packaging-status.md`** — per-OS (Linux/Windows/macOS) status of the
  agent build/install pipeline: what's real, what's a stub, what's orphaned
  (`ISS-17/18/20`), tracked in one place instead of scattered across the inventory.
- **`md/07-versioning-and-release-process.md`** — how version numbers flow today
  (hardcoded `7.4.9`/`7.4` literals, `create-release.sh` tag/release mechanics, the
  unpinned-`main` problem `ISS-14`) and what a real versioning scheme would need.
- **`md/08-test-and-verification-plan.md`** — there is no automated test suite for
  the Vizoure layer; a plan for how each script/fix would actually be verified before
  being trusted (manual VM smoke-test checklist, since no CI exists today).
- **`md/09-zabbix-master-vendor-tracking.md`** — clarify what the vendored
  `zabbix-master/` tree is actually for, resolve the 8.0.0rc2-vs-7.4.x mismatch
  (`ISS-11`), and decide whether to keep, re-vendor, or drop it.
- **`md/10-roadmap-gap-analysis.md`** — map the README's own roadmap checklist
  (Version 2/3 items) against what's actually implemented vs. stubbed, as a single
  source of truth for "what's next" separate from bug-fixing.
