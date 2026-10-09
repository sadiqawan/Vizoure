# 06 — Offline Install Strategy (Rule B)

**Analysis only. No implementation.** Rule B: if `repo.zabbix.com` or upstream Zabbix's
GitHub is down or blocked, Vizoure must still install fully from this repo alone.

## Starting facts this analysis is built on

- `install-nms.sh`/`upgrade.sh` currently install Zabbix by adding `repo.zabbix.com`'s
  apt repo for the **`7.4` stable channel** (not a pinned point release) and letting
  apt pull whatever is currently latest in that channel. That's confirmed to be how
  we ended up with `7.4.11` on the test VM while every doc says `7.4.9` (`md/04`
  `ISS-11`) — the install has never actually been pinned to an exact version.
- `zabbix-master/` is Zabbix's `master` dev branch (`8.0.0rc2`), not any 7.4 release —
  it cannot be compiled as a stand-in for what's actually being installed today
  (`md/04` `ISS-11`/`ISS-25`). Any offline strategy has to start by fixing this, not
  by building on top of it as-is.
- The repo's own `.gitignore` already expects a vendored source tree named
  `zabbix-source/` (not `zabbix-master/`) — whoever vendored the current tree used
  the wrong name, most likely from a plain "download ZIP of the `master` branch" on
  GitHub, which is also why it's the wrong branch. Fixing the name and the branch is
  the same fix.
- `zabbix-master/` is currently local-only (just added to `.gitignore` in this
  session, `md/04` Part 3) — so "replace it" has zero git-history cost either way;
  there's nothing to rewrite.
- GitHub's practical limits that bound every option below: **100MB hard limit per
  file committed to git** (and anything over ~50MB gets a warning), **Git LFS** free
  tier is a separate, small quota (1GB storage + 1GB bandwidth/month on GitHub's free
  tier) better suited to a few tracked binaries than bulk package mirroring, and
  **GitHub Releases** assets (up to a few GB per file, no git-history bloat) — which
  is already the mechanism `create-release.sh` uses today for the agent `.deb`. Any
  option that ships large binaries should use Releases, not commit them into git.

## Scope clarification: two different "offline" scenarios

Rule B's literal wording only requires surviving `repo.zabbix.com`/Zabbix's GitHub
being down. But a truly offline install also depends on Ubuntu's own apt mirrors for
Apache, MySQL, and PHP (and, for a source build, a pile of `-dev`/compiler packages on
top of that). Both scenarios are analyzed below for each option, because the harder
one (Ubuntu mirrors *also* unreachable) changes the size/complexity picture a lot:

- **Scenario A (Rule B's literal ask):** Zabbix's own infrastructure is down; Ubuntu's
  package mirrors still work.
- **Scenario B (the harder, compounded case):** Ubuntu's mirrors are *also*
  unreachable — everything (OS packages included) has to come from this repo.

---

## Option 1 — Build from source (`zabbix-master/`, once correctly pinned)

### Steps
1. Vendor the correct source: fetch the exact 7.4.x release tag/tarball (see "Getting
   the exact pinned source" below) and replace `zabbix-master/`'s contents with it.
2. `./bootstrap.sh` (regenerates `configure` via `aclocal`/`autoconf`/`automake`) —
   this script already exists in the vendored tree.
3. `./configure --enable-server --enable-agent --with-mysql --with-net-snmp
   --with-libcurl --with-openssl` (flags approximate; exact set depends on which
   features `install-nms.sh` currently relies on — not verified here).
4. `make` (compiles `zabbix_server`, `zabbix_agentd`, `zabbix_get`, `zabbix_sender`).
5. `make install` (or manual copy to `/usr/sbin`, matching where the apt packages
   place these binaries today, so the rest of `install-nms.sh`/`apply-branding.sh`
   doesn't need to change).
6. Copy `ui/` (the PHP frontend — no build step, PHP is interpreted) to
   `/usr/share/zabbix/ui`, exactly where the apt package puts it today.
7. Import `database/mysql/*.sql` by hand (the apt package's `zabbix-sql-scripts`
   just ships these same files pre-packaged).

### Build time
Not measured in this repo. Reasoning from the codebase shape: Zabbix server is a
single moderate-sized C codebase that links against prebuilt system libraries (it
doesn't vendor/compile its own OpenSSL, cURL, etc.), so a full `server`+`agent` build
is realistically **single-digit minutes** on hardware like the test VM (2 vCPU), not
hours — closer to compiling a mid-sized C project than a browser or kernel. ⚠️ needs
confirmation: not actually timed.

### Repo size impact
A 7.4.x source tarball is in the same ballpark as the current `zabbix-master/`
(~390MB uncompressed; the tarball itself compresses to roughly 50–80MB — ⚠️ needs
confirmation on the exact figure for 7.4.x specifically). Either way, **this should
never be committed into git directly** (near/over the 100MB single-file limit even
compressed, and git would keep every version forever). It belongs in GitHub Releases
as a downloadable asset, fetched by a vendor script into the gitignored
`zabbix-master/`/`zabbix-source/` directory — never into tracked history.

### PHP/DB/OS dependencies
- **Scenario A** (Ubuntu mirrors fine): build-time needs `build-essential`,
  `autoconf`, `automake`, `pkg-config`, and `-dev` packages (`libmysqlclient-dev` or
  `libmariadb-dev`, `libpcre2-dev`, `libssl-dev`, `libxml2-dev`,
  `libcurl4-openssl-dev`, `zlib1g-dev`, optionally `libsnmp-dev`) — all from Ubuntu's
  own apt, unaffected by Zabbix being down. Runtime still needs Apache + PHP +
  PHP-MySQL extension, also from Ubuntu's apt, same as today.
- **Scenario B** (Ubuntu mirrors also down): every one of those `-dev` packages (plus
  their own transitive dependencies) and the full PHP/Apache/MySQL runtime stack
  would need to be vendored too — this option needs **strictly more** packages than
  Option 2 (dev headers and compilers, on top of the same runtime packages), so it is
  the worst option for Scenario B, not the best.

### Upgrades
Re-run the same build against a newer source tarball. No apt version metadata to
track — version tracking becomes "whatever tarball we vendored," which is exactly as
precise or imprecise as whoever maintains that vendoring discipline.

### Version pinned
Whatever source tarball is vendored — this is the one option where pinning is a
deliberate, explicit choice (you can't "accidentally" float to a newer version the
way the current apt-channel approach does).

---

## Option 2 — Bundle prebuilt `.deb` packages as a local apt repo

### Steps
1. On a machine with real access to `repo.zabbix.com`, download the exact `.deb`s
   `install-nms.sh` already installs (`zabbix-server-mysql`, `zabbix-agent`,
   `zabbix-frontend-php`, `zabbix-apache-conf`, `zabbix-sql-scripts`) for one pinned
   version — plus, for Scenario B, the full Apache/MySQL/PHP runtime dependency
   closure (`apt-get download $(apt-cache depends --recurse --no-recommends ... |
   grep ^\w)` or similar).
2. Publish the `.deb`s as GitHub Release assets (same mechanism `create-release.sh`
   already uses for the agent `.deb` today — no new infrastructure needed).
3. On install, a new script downloads that Release's assets into a local directory
   (e.g. `/tmp/vizoure-local-repo/`), runs `dpkg-scanpackages . /dev/null >
   Packages`, and adds a one-line local apt source:
   `deb [trusted=yes] file:///tmp/vizoure-local-repo/ ./`.
4. `apt-get update && apt-get install zabbix-server-mysql ...` then resolves entirely
   against the local directory instead of `repo.zabbix.com`.

### Build time
None — nothing is compiled. This is the fastest option by far (install time only,
no build step at all).

### Repo size impact
The 5 Zabbix `.deb`s alone are roughly the same size as what we saw purged from the
test VM (~105MB freed by removing them, per the Part 2 verification) — each
individual `.deb` is well under the 100MB git limit, but **still shouldn't go into
git** on principle (binary churn on every version bump). GitHub Releases again, same
as Option 1's tarball and exactly how `create-release.sh` already ships the agent
`.deb` — this option fits the repo's existing release mechanism with zero new
tooling. Scenario B's full dependency closure (mysql-server pulls in a large chain —
recall the stuck unattended-upgrade on the test VM queued ~140 packages for a routine
patch) could run several hundred MB to ~1GB; still fine as Release assets (not a git
concern), but meaningfully larger to maintain/update than just the 5 Zabbix packages.

### PHP/DB/OS dependencies
- **Scenario A:** trivial — apt still resolves Apache/PHP/MySQL from Ubuntu's own
  mirrors as normal; only the 5 Zabbix packages come from the local repo instead of
  `repo.zabbix.com`.
- **Scenario B:** every dependency (Apache, MySQL, PHP + extensions, and their own
  transitive deps) needs to be in the bundled local repo too. More packages than
  Option 1 needs for runtime, but no compiler/`-dev` packages at all — net, probably
  a comparable total package count to Option 1's Scenario B, just skewed toward
  runtime libs instead of dev headers.

### Upgrades
Re-download a newer set of `.deb`s from a reachable `repo.zabbix.com` periodically
(whenever it *is* reachable) and re-publish as a new Release — this is explicitly a
"snapshot the version we trust" workflow, same spirit as a container base image
pin. **Important practical constraint discovered during this analysis:** vendor apt
repos typically only keep the *current* point release of a channel in their live
pool — once `7.4.12` ships, `7.4.11`'s `.deb`s are likely to disappear from
`repo.zabbix.com` entirely. That means **grabbing today's `.deb`s now and parking
them in a Release is the only way to guarantee a specific point release stays
available**, regardless of the offline scenario — this is true even without Rule B,
just for reproducibility.

### Version pinned
Whatever `.deb`s were downloaded and published — same precision as Option 1, but
achieved without needing a compiler at all.

---

## Option 3 — Hybrid (prebuilt `.deb`s default, source build fallback)

### Steps
`install-nms.sh` (or a new wrapper) tries Option 2's local-repo path first; if that
local repo bundle is missing/stale/wrong-arch for the target machine, it falls back
to Option 1's build-from-source path using the same vendored, correctly-pinned
source tree.

### Build time
Same as Option 2 in the common case (no build — fast); same as Option 1 only on the
fallback path.

### Repo size impact
Needs **both** artifacts published (the `.deb` bundle and the source tarball) — more
total Release storage than either option alone, but each piece individually follows
the same "GitHub Releases, not git" rule already established above. No new size
category, just the sum of the other two.

### PHP/DB/OS dependencies
Same dependency story as whichever path actually runs for a given install — in the
common case that's Option 2's (simpler, runtime-only); the fallback path pulls in
Option 1's heavier dev-toolchain requirement only when it's actually needed (e.g. an
unsupported architecture, or a Zabbix-published `.deb` genuinely isn't available for
this exact OS point-release).

### Upgrades
Same re-snapshot discipline as Option 2 for the default path; Option 1's rebuild
discipline is a fallback that's exercised rarely, so it's less likely to silently rot
from disuse than if it were the *only* path (a real risk for Option 1 alone: a
build-only path that's rarely exercised tends to quietly break as the source tree
ages against a newer compiler/OS, and nobody notices until the day it's actually
needed).

### Version pinned
Both artifacts are pinned to the same version number by construction (published
together), so there's no drift between "the .deb path's version" and "the
source-build path's version" the way there could be if they were maintained as
fully separate, independently-updated efforts.

---

## Getting the exact pinned 7.4.x source and matching `.deb`s

Two independent sources, so a future outage of one doesn't block the other:

1. **Zabbix's own source tarball** — published per-version at a predictable CDN path
   under `cdn.zabbix.com`/`repo.zabbix.com` (exact URL for a given point release not
   verified live in this session — ⚠️ needs confirmation of the precise path at fetch
   time, e.g. via Zabbix's own "Downloads → Source code" page).
2. **Zabbix's upstream GitHub mirror** (`github.com/zabbix/zabbix`), tagged per
   release — a genuinely separate piece of infrastructure from `repo.zabbix.com`, so
   it survives a `repo.zabbix.com`-specific outage. ⚠️ needs confirmation of the exact
   tag-naming convention for 7.4.x point releases (not verified live in this session).
3. **The matching `.deb`s**: `repo.zabbix.com/zabbix/7.4/stable/ubuntu/pool/main/z/`
   — exactly the apt source we found already configured on the test VM
   (`/etc/apt/sources.list.d/zabbix.sources`, `Signed-By:
   /usr/share/keyrings/zabbix.gpg`). Fetch the *current* point release's `.deb`s now
   (today, while reachable) and publish them as a Release asset — per the point made
   under Option 2, waiting risks the exact version disappearing from the live pool
   once a newer point release ships.

Whichever route is used, the result should go into this repo's `.gitignore`d vendor
directory (and/or a GitHub Release), never committed as tracked git content — same
rule as everything else in this document.

## Should `zabbix-master/` be replaced?

**Yes.** As it stands it's actively misleading (claims to be "the" Zabbix source but
is the wrong branch entirely — `8.0.0rc2` dev, not any 7.4 release) and can't serve
as the base for Option 1 or Option 3 without being replaced first. Two sub-decisions,
not resolved here (analysis only):
- **Rename it to `zabbix-source/`** to match what the repo's own `.gitignore` already
  expects, rather than leaving the `zabbix-master` name (a leftover of however it was
  originally downloaded) — cheap, removes a standing point of confusion (`md/04`
  `ISS-16`-adjacent).
- **Pin to which exact point release?** `7.4.11` (what's actually on the test VM
  today) is the obvious current candidate, but that's a moving target every time
  `upgrade.sh` runs against a newer channel release — the pinning decision here is
  really the same open question as `md/04` `ISS-14` (should the whole project pin to
  an exact version instead of floating on the `7.4` channel?). Resolving that
  question first would make "which source tree to vendor" a trivial follow-on
  decision rather than a separate one.

## Recommendation: Option 3 (Hybrid)

**Reasons:**
- Option 2 alone is fast and proven — it's exactly what the project already does
  today (apt install), just against a local repo instead of `repo.zabbix.com`, so
  it inherits all of today's tested behavior with the smallest behavioral delta.
- Option 1 alone is strictly worse for the compounded Scenario B (needs *more*
  packages than Option 2, not fewer, once dev/compiler toolchain is counted) and
  carries real rot risk if it's the only path and rarely exercised.
- The hybrid costs only a bit more Release storage (both artifacts published) in
  exchange for: the fast/proven path by default, a genuine fallback for an
  architecture or OS combination the prebuilt `.deb`s don't cover, and both paths
  forced to stay version-synchronized because they're published together.
- It also directly produces the fix for `ISS-25`/`ISS-11`'s vendor-tree problem as a
  side effect — Option 3 can't be built at all until `zabbix-master/` is replaced
  with a correctly pinned source tree, so doing this work forces that fix to happen
  rather than leaving it as a separate, easy-to-defer task.

**Not recommended as a starting point:** Option 1 alone (strictly more offline-
dependency surface than Option 2, for no speed benefit in the common case) or Option 2
alone (zero fallback if a prebuilt package genuinely isn't available for some future
target environment — e.g. an architecture this repo doesn't anticipate today).
