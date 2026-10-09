# 08 — Folder Structure Proposal

**Proposal only. Nothing has been moved.** Written per instruction to untangle the
current messy layout: `md/` living inside `Vizoure/` (fine, that's git's actual root),
two differently-named vendor source trees (`zabbix-master/`, `zabbix-src-7.4.15/`)
sitting *inside* the git root relying on `.gitignore` to stay untracked, and
`offline-7.4.15/`/`vm-backups/` as flat siblings with no room to grow.

## Why change anything
The `zabbix-master/` vs `zabbix-source/` naming mismatch earlier this session was a
near-miss: a 390MB tree sat inside the git root, excluded only because `.gitignore`
happened to list its exact name. Any future vendor folder with a name nobody thought
to add to `.gitignore` would risk being staged by a careless `git add -A`. Moving
large, never-tracked local artifacts *outside* the git root entirely removes that
risk class structurally, instead of relying on remembering to list every name.

## Proposed repo tree (`Vizoure/` — what's committed to `origin/main`)
No structural change here — this part of the layout is already correct; listed for
completeness since the task asked for "one tree for the repo."

```
Vizoure/                      ← git root (origin/main)
├── .gitattributes            ← new this session (LF enforcement)
├── .gitignore                ← simplified — see below
├── CHANGELOG.md
├── CLAUDE.md
├── README.md
├── agent-packaging/
├── branding/
├── md/                       ← 00–08 and growing
├── packer/
└── scripts/
```

## Proposed local-only tree (outside git, this machine only)

```
D:\projects\vizoure-nms\           ← container folder, not itself a repo
├── Vizoure\                       ← the git repo (above)
├── zabbix-vendor\                 ← NEW: moved OUT of Vizoure/, never git-tracked
│   ├── master-8.0.0rc2\           ← renamed from zabbix-master/ — the wrong-branch
│   │                                 tree (ISS-11/ISS-25); keep only as a labeled
│   │                                 "do not use for version checks" reference, or
│   │                                 delete — your call, not decided here
│   └── 7.4.15\                    ← renamed from zabbix-src-7.4.15/ — the correctly
│                                     pinned source, real candidate for Option 1/3
│                                     of md/06's offline-build work
├── offline-packages\              ← renamed from offline-7.4.15/, now versioned
│   └── 7.4.15\                    ← so a future 7.4.16 bundle doesn't need a new
│       ├── debs\                    top-level folder or to overwrite this one
│       ├── source\
│       └── SHA256SUMS.txt
└── vm-backups\                    ← unchanged, already correctly placed
    └── pre-clean-backup-20261009-071153\
```

| Folder | One-line purpose |
|---|---|
| `Vizoure/` | The git repository — everything here is tracked, reviewed, pushed |
| `zabbix-vendor/` | Local-only reference/build-source trees for Zabbix itself — never tracked, never has been, now also never *inside* the tracked tree |
| `offline-packages/` | Locally-assembled offline install bundles (`.deb`s + source tarball + checksums) per pinned version, built for `md/06`'s Rule B work, not yet published as a GitHub Release |
| `vm-backups/` | Point-in-time backups taken before destructive VM operations (Part 1/Part 2 cleanup, etc.) — sensitive, stays local, never touches git |

## `.gitignore` changes
Remove the three vendor-tree lines entirely (`zabbix-source/`, `zabbix-master/`,
`zabbix-src-7.4.15/`) — once those trees live outside `Vizoure/`, there's nothing
inside the repo root for them to match, and the file stops needing to track every
vendor-folder name that's ever existed:

```diff
 dist/
-zabbix-source/
-zabbix-master/
-zabbix-src-7.4.15/
 build/
 *.deb
 *.msi
 *.pkg
 *.iso
 *.vmx
 *.ovf
 *.ova
 packer/secrets.pkr.hcl
```

## What would actually move (not done yet — proposal only)
- `Vizoure/zabbix-master/` → `D:\projects\vizoure-nms\zabbix-vendor\master-8.0.0rc2\`
- `Vizoure/zabbix-src-7.4.15/` → `D:\projects\vizoure-nms\zabbix-vendor\7.4.15\`
- `D:\projects\vizoure-nms\offline-7.4.15\` → `D:\projects\vizoure-nms\offline-packages\7.4.15\`
- `D:\projects\vizoure-nms\vm-backups\` — stays exactly where it is

## `git status`, grouped by the commit each change logically belongs to

Current `git status --short` (nothing committed or pushed since `f61d502`):
```
A  .gitattributes
M  .gitignore
M  README.md
 M md/04-known-issues-and-fix-plan.md
 M md/05-test-vm-workflow.md
M  packer/http/user-data
M  packer/ubuntu-server.pkr.hcl
MM scripts/install-nms.sh
M  scripts/upgrade.sh
?? md/07-lessons-learned.md
```
(First column = staged, second = unstaged. `scripts/install-nms.sh` shows `MM`
because it has a staged Batch-1 change *and* a further unstaged idempotency change
on top of that — see commits B and C below.)

| Proposed commit | Files | What it contains |
|---|---|---|
| **A — "fix: normalize line endings, add .gitattributes"** | `.gitattributes` (new); the line-ending-normalization portion of files already pushed in `5948092`/`f61d502` (no longer shows in `git status` since those are already committed — this row is a correction note, not a pending change) | The CRLF fix from earlier this session — already committed and pushed; listed here only so the history reads coherently |
| **B — "fix: Batch 1 — curl verification (ISS-01/02), DB backup + password persistence (ISS-09), ERR traps (ISS-10)"** | `packer/http/user-data`, `packer/ubuntu-server.pkr.hcl`, `README.md`, `scripts/upgrade.sh`, the **staged** portion of `scripts/install-nms.sh` | The first round of fixes, syntax-checked and live-tested on the VM before the `ISS-26` incident was found |
| **C — "fix: ISS-07/ISS-08 — make install-nms.sh idempotent"** | the **unstaged** portion of `scripts/install-nms.sh` (DB-state classification, always-run API step with login fallback) | The rewrite just completed this turn, pulled forward from Batch 2 per your instruction — not yet tested on the VM as of this proposal being written |
| **D — unclear/misc, needs a decision** | `.gitignore`'s one pending line (`zabbix-src-7.4.15/`) | This line belongs to the *offline-install* work (Part 3 of an earlier turn), not Batch 1 — it got staged incidentally by a broad `git add -A` during Batch-1 prep. If the folder-structure move above happens, this line gets deleted again anyway rather than committed. Recommend: drop it from any commit (don't commit this line at all) rather than inventing a commit for a one-line change that's about to be reverted |
| **E — "docs: ISS-26/27/28 incident write-up + md/05 process fixes"** | `md/04-known-issues-and-fix-plan.md`, `md/05-test-vm-workflow.md` | The browser-bug root-cause findings and the authenticated-session-walk / destructive-re-run-test rules added in response |
| **F — "docs: session lessons learned"** | `md/07-lessons-learned.md` (untracked) | This session's honest retrospective |
| **G — "docs: folder structure proposal"** | `md/08-folder-structure-proposal.md` (this file, untracked, not yet in `git status` output above since it didn't exist when that snapshot was taken) | This proposal |

**Not proposing any commit yet** — per instruction, nothing is committed or pushed
until the VM re-run test passes and you've checked the browser yourself.
