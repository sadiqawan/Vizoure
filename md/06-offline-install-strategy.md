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
**Confirmed live (2026-10-09)** against `cdn.zabbix.com/zabbix/sources/stable/7.4/`:
the compressed source tarball is **~41–42MB** across the versions checked
(`7.4.9`: 43,490,201 bytes; `7.4.11`: 43,533,153 bytes; `7.4.15`: 44,301,259 bytes —
grows slightly release to release, as expected). Smaller than this doc originally
guessed. Still **should never be committed into git directly** (near the 100MB
single-file warning threshold, and git would keep every version forever) — belongs
in GitHub Releases as a downloadable asset, fetched by a vendor script into the
gitignored `zabbix-master/`/`zabbix-source/` directory, never into tracked history.

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
**Confirmed live (2026-10-09)** against `repo.zabbix.com`'s actual `noble` Packages
index: the 5 Zabbix `.deb`s (`zabbix-server-mysql`, `zabbix-agent`,
`zabbix-frontend-php`, `zabbix-sql-scripts`, `zabbix-apache-conf`) total only
**~19.8MB** at the current `7.4.15` (1.85MB + 0.30MB + 9.42MB + 8.21MB + 0.01MB), plus
the tiny `zabbix-release` bootstrap `.deb` (8.5KB). Far smaller than this doc
originally guessed (that earlier figure conflated total disk space *freed on the VM*,
which included MySQL/Apache/PHP's own footprint, with the much smaller Zabbix-only
download size). Each is well under the 100MB git limit regardless, but **still
shouldn't go into git** on principle (binary churn on every version bump) — GitHub
Releases, same as Option 1's tarball and exactly how `create-release.sh` already
ships the agent `.deb`. Scenario B's full Ubuntu-side dependency closure (apache2 +
mysql-server + the php8.3 extensions this project needs, measured directly via
`apt-get install --print-uris` on the test VM) is **52 packages totaling ~35.8MB** —
also much smaller than this doc originally guessed. **Combined total for a fully
self-contained offline package set (Scenario B): ~19.8MB + ~35.8MB ≈ 55.6MB.**

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
"snapshot the version we trust" workflow, same spirit as a container base image pin.
**Correction from this session's earlier draft:** `repo.zabbix.com` does **not**
actually drop old point releases — live-checked `noble`'s Packages index and found
every `7.4.x` release from `7.4.0` through the current `7.4.15` still listed
simultaneously (confirmed by version string, e.g. `7.4.9-1+ubuntu24.04` and
`7.4.11-1+ubuntu24.04` are both still present today). So there's no urgent
"grab it now before it disappears" pressure — but vendoring the exact `.deb`s used
is still the right call for genuine independence from `repo.zabbix.com` being
reachable *at all*, which is the actual Rule B scenario, and for guaranteed
reproducibility regardless of whether the vendor happens to keep old releases
forever.

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

1. **Zabbix's own source tarball** — **confirmed live (2026-10-09)** at
   `https://cdn.zabbix.com/zabbix/sources/stable/7.4/zabbix-<version>.tar.gz` (e.g.
   `zabbix-7.4.11.tar.gz`); returned `200 OK` for `7.4.9`, `7.4.11`, and `7.4.15`
   when checked. This is the URL `repo.zabbix.com`'s own `.sources` config points at
   conceptually (same `repo.zabbix.com`/`cdn.zabbix.com` family), so it shares fate
   with that infrastructure being reachable at all — see source 2 for a genuinely
   independent fallback.
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
  decision rather than a separate one. See the next section for the actual version
  recommendation.

## Version pinning recommendation (live research, 2026-10-09)

### What's actually available right now
Live-checked `repo.zabbix.com`'s `7.4/stable` Packages index for `noble`: the
**current latest is `7.4.15-1+ubuntu24.04`**. Every point release back to `7.4.0` is
still listed in the same index (see the correction under Option 2's "Upgrades" above)
— `7.4.9-1+ubuntu24.04` and `7.4.11-1+ubuntu24.04` (the two reference points asked
about) are both still present today, not just `7.4.15`.

### Security comparison: `7.4.9` vs `7.4.11` vs `7.4.15`
Checked Zabbix's own release notes and third-party CVE trackers for the 7.4 branch.
Four CVEs turned up for the general 7.4.x era:

| CVE | Issue | Fixed in (7.4 branch) |
|---|---|---|
| CVE-2026-23919 | Server/proxy JS context reuse — data leak between hosts a non-super admin shouldn't see | `7.4.3` |
| CVE-2026-23920 | Host/event action script regex validation bypass via newline injection → shell command injection | `7.4.6` |
| CVE-2026-23921 | Blind SQL injection via API `sortfield` param → session/admin compromise | `7.4.6` |
| CVE-2026-1199 | Login-lockout counter miscounts simultaneous failed attempts, weakening brute-force protection | ⚠️ needs confirmation — exact 7.4-branch fixed-in version not found in this session's research |

**All three confirmed CVEs are already fixed by `7.4.6`** — meaning `7.4.9`, `7.4.11`,
and `7.4.15` are all equally safe from them; there is **no security reason to prefer
one over another** among these three specific candidates.

### Stability comparison
`7.4.15`'s own release notes (vs. `7.4.11`) list real operational bug fixes not
present in `7.4.11`: a fixed agent redirect loop in proxy groups when the server goes
offline, a fixed memory leak in item queries when expanding user macros, and a fixed
PHP 8.5 runtime error in the frontend. These are genuine reasons to prefer newer over
older, all else equal.

### What the branding scripts were actually tested against
This is the deciding factor. `7.4.9` is what the repo's docs *claim*, but it has
**never actually been installed or exercised by this project** — `install-nms.sh`
floats on the `7.4` channel, so nothing has ever pinned or verified against `7.4.9`
specifically. `7.4.15` is the newest and has real bug-fix advantages, but likewise
**has never been exercised against `apply-branding.sh`** in this project.
**`7.4.11` is the one version that has actually been installed and had
`apply-branding.sh`'s patches applied against it**, for real, on the test VM (the
branded `vizoure.conf`, `zabbix.conf.php`, and installed `/usr/share/zabbix` tree we
found and backed up on 2026-10-09 were all running on `7.4.11`).

### Recommendation: pin to `7.4.11`
Primary reason: it's the only one of the three with actual empirical evidence that
this project's branding scripts work against it. No security argument favors `7.4.15`
over it (same CVE-fix floor). The cost of **not** picking `7.4.15` is giving up three
real bug fixes (agent redirect loop, memory leak, PHP 8.5 compat) that don't appear to
affect this project's own usage pattern today (single-node install, PHP 8.3 not 8.5).

**Reasonable alternative, if you'd rather have the newest stability fixes**: pin to
`7.4.15` instead, accepting that `apply-branding.sh` would need a fresh
install-and-verify pass against it (per `md/05`'s workflow) before trusting it, since
it's never been exercised in this project. Not recommended as the default pick for
that reason alone, but not a bad choice if validated first.

**This is explicitly your call to make, per your own instruction — nothing has been
downloaded.**

### DECISION (2026-10-09): pin `7.4.15`, fallback `7.4.11`

The user chose **`7.4.15` as primary**, with **`7.4.11` as fallback if branding
breaks on it** — the inverse of this document's own recommendation above (which
favored `7.4.11` as primary, `7.4.15` as an unvalidated alternative). Decision stands
as given; the analysis above is left as-written for the reasoning trail, not revised
to match. Practical effect: `7.4.15` must now go through the validate-against-
`apply-branding.sh` step this document flagged as outstanding for it, with `7.4.11`
(already known-good from the 2026-10-09 VM evidence) as the documented fallback if
that validation fails. This resolves `md/04` `ISS-11`'s open "which version" question
— see that file for the corresponding update.

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

## Where the offline package set should live

**Proposal:** one GitHub Release per pinned Zabbix version (reusing
`create-release.sh`'s existing tag convention, e.g. `offline-7.4.11`, separate from
the product's own `v7.4.9`-style release tags so an offline-bundle refresh doesn't
need to cut a new product release), containing:
- The 6 Zabbix `.deb`s (`zabbix-release`, `zabbix-server-mysql`, `zabbix-agent`,
  `zabbix-frontend-php`, `zabbix-sql-scripts`, `zabbix-apache-conf`).
- The 52 Ubuntu dependency `.deb`s (Appendix below has the exact list).
- The source tarball (`zabbix-<version>.tar.gz`), for Option 1/3's build fallback.
- A `SHA256SUMS.txt` covering every file above, generated the same way
  `create-release.sh` already does for the agent `.deb` today (`sha256sum * >
  SHA256SUMS.txt`) — so the install script can verify each download against it before
  use, which also directly satisfies the checksum-verification fix this project
  already owes itself from `md/04`'s `ISS-01`–`ISS-04`.

This reuses 100% of the repo's existing release mechanism — no new infrastructure,
no Git LFS, nothing committed to git history.

---

## Appendix — exact package manifest (captured live, 2026-10-09)

### Zabbix packages (current latest, `7.4.15-1+ubuntu24.04`, from `repo.zabbix.com`'s `noble` Packages index)

| Package | Size |
|---|---|
| `zabbix-release` (bootstrap) | 8,524 B |
| `zabbix-server-mysql` | 1,848,088 B |
| `zabbix-agent` | 300,936 B |
| `zabbix-frontend-php` | 9,416,412 B |
| `zabbix-sql-scripts` | 8,212,628 B |
| `zabbix-apache-conf` | 9,140 B |
| **Total** | **~19.8MB** |

### Ubuntu-side dependency closure (52 packages — `apache2`, `mysql-server`, `php8.3` + extensions; sizes via `apt-get install --print-uris` on the test VM, 2026-10-09, Ubuntu 24.04/noble)

| Package | Size (bytes) |
|---|---|
| apache2 | 90,238 |
| apache2-bin | 1,337,886 |
| apache2-data | 163,290 |
| apache2-utils | 99,904 |
| libapache2-mod-php8.3 | 1,850,334 |
| libapr1t64 | 107,650 |
| libaprutil1-dbd-sqlite3 | 11,246 |
| libaprutil1-ldap | 9,120 |
| libaprutil1t64 | 92,674 |
| libcgi-fast-perl | 10,300 |
| libcgi-pm-perl | 184,594 |
| libclone-perl | 10,728 |
| libencode-locale-perl | 11,568 |
| libevent-core-2.1-7t64 | 91,942 |
| libevent-pthreads-2.1-7t64 | 7,988 |
| libfcgi0t64 | 27,030 |
| libfcgi-bin | 11,154 |
| libfcgi-perl | 21,684 |
| libhtml-parser-perl | 86,028 |
| libhtml-tagset-perl | 11,274 |
| libhtml-template-perl | 60,152 |
| libhttp-date-perl | 10,564 |
| libhttp-message-perl | 78,240 |
| libio-html-perl | 15,870 |
| liblua5.4-0 | 166,226 |
| liblwp-mediatypes-perl | 20,102 |
| libmecab2 | 200,902 |
| libprotobuf-lite32t64 | 238,492 |
| libtimedate-perl | 33,972 |
| liburi-perl | 88,040 |
| mecab-ipadic | 6,717,648 |
| mecab-ipadic-utf8 | 4,384 |
| mecab-utils | 4,804 |
| mysql-client-8.0 | 22,446 |
| mysql-client-core-8.0 | 2,739,738 |
| mysql-common | 6,746 |
| mysql-server | 9,524 |
| mysql-server-8.0 | 1,442,602 |
| mysql-server-core-8.0 | 17,489,224 |
| php8.3-bcmath | 16,614 |
| php8.3-cli | 1,915,292 |
| php8.3-common | 741,968 |
| php8.3-curl | 40,314 |
| php8.3-gd | 31,160 |
| php8.3-ldap | 33,578 |
| php8.3-mbstring | 511,980 |
| php8.3-mysql | 126,660 |
| php8.3-opcache | 371,548 |
| php8.3-readline | 13,458 |
| php8.3-xml | 126,062 |
| php-common | 13,910 |
| ssl-cert | 17,826 |
| **Total (52 packages)** | **~35.8MB (37,546,678 B)** |

Notably the single largest item is `mysql-server-core-8.0` (~16.7MB); `mecab-ipadic`
(~6.4MB, a Japanese-language dictionary pulled in transitively) is the second
largest and somewhat surprising — it's not something Vizoure needs directly, it
rides in via the dependency chain. ⚠️ needs confirmation exactly which package pulls
it in, if a leaner closure is ever wanted.

### Source tarball (for Option 1/3's build fallback)

| Version | Size |
|---|---|
| `7.4.9` | 43,490,201 B (~41.5MB) |
| `7.4.11` | 43,533,153 B (~41.5MB) |
| `7.4.15` | 44,301,259 B (~42.3MB) |

### Grand total for a fully self-contained offline package set
~19.8MB (Zabbix) + ~35.8MB (Ubuntu runtime deps) + ~42MB (source tarball, for the
Option 1/3 fallback path) ≈ **~98MB total** — comfortably small, well within a single
GitHub Release.
