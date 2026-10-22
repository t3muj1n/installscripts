# Handoff — next session: the GitHub Actions workflow

The prompt to paste into a new chat is at the bottom. Everything above it is
the context that prompt refers to.

Rewritten 2026-10-18 at the end of session 3 as a single state document rather
than a pile of per-session deltas.

**Addendum 2026-10-19 (session 4):** no code changed. A reported `--days`
defect was investigated and **the filter is correct** — see "How to read the
output columns" below, which is the part that actually caused the confusion.

**Addendum 2026-10-20 (session 5):** hostlist regeneration from LSF was added
to the sweep and deployed. **The plan for scheduling changed: there will be no
systemd units.** Automation goes through **GitHub Actions**, the way
`inventory_script` does it.

---

## ★ Scheduling is GitHub Actions, NOT systemd — changed 2026-10-20

Earlier revisions of this file said the remaining work was
`check_hardware.service` / `.timer`. **That is no longer the plan and those
units were never written.** The user decided the nightly will be driven by a
GitHub Actions workflow on the self-hosted runner, mirroring
`inventory_script`'s `.github/workflows/inventory-run.yml`.

The consequence that matters day to day: **git is the source of truth and the
host is a deploy target.** Every workflow run rsyncs the repo over
`$DEPLOY_DIR` before running, so anything `scp`'d straight to the host is
temporary — it survives only until the next run, and only if no file of the
same name exists in git. The working sequence is: push changes to the host,
test them there, then commit and push to GitHub so the repo converges on what
was proven.

---

## Where things stand

**The project is complete and running against production.** No code work is
outstanding; what is left is the workflow plus two open decisions.

Deployed at `atlvhwerptd01.amd.com:/home/z1_vbu_hwe_user/scripts/check_hardware`.
**Local and server verified byte-identical at the end of session 5** (the six
files changed that session were md5-matched after pushing; everything else was
already identical) — but diff before pushing anyway.

| piece | state |
|---|---|
| `check_iml/check_hpe_iml.sh`, `check_lenovo_iml.sh` | done, validated |
| `lib/{common,creds,redfish,iml_report,iml_map,lenovo_map}.sh` | done |
| `check_hardware.sh` | done — fleet driver, schedule-ready |
| hostlist regeneration (`--no-generate`) | done — session 5, deployed + verified |
| `atlvhwerptd01.conf` | done — production conf, no literal paths |
| `doc/README.md` | done — **every command + all reference material** |
| `do_lsf_generate_hostlist` | done — at the tree root, CWD-relative |
| `bin/{ssh_crypt.sh,verify_lossless.sh,show_undated.sh}` | done |
| `creds/ilo_creds.enc` | done — encrypted on the host |
| `.github/workflows/…` | **NOT WRITTEN — the remaining work** |
| `check_hardware.service` / `.timer` | **ABANDONED — superseded by Actions** |

**Current production baseline** (`--days 7`, critical-only):
**1626 hosts in ~280s, 402 findings across 209 hosts, 1418 exceptions,
1537 readable / 89 unreadable**, accountability exact. Judge future runs
against that.

### Layout

**Changed 2026-10-19 (session 4): the docs moved into `doc/`.** `HANDOFF.md`,
`README.md` and `check_hardware.conf.example` are no longer at the tree root.
Nothing references them by path — checked with a grep across every `*.sh` and
`do_lsf_generate_hostlist` — so the move is documentation-only and breaks
no code. **Update any stale root-level path you see.**

**Changed 2026-10-20 (session 5): `do_lsf_generate_hostlist` moved back OUT of
`bin/` to the tree root**, and its output is CWD-relative again so the driver
can stage it. `bin/` now holds only `ssh_crypt.sh`, `show_undated.sh` and
`verify_lossless.sh`. **The sweep now regenerates `hostlist/` from LSF on every
run**, with `--no-generate` to skip — see README's "Regenerating the host
lists".

```
check_hardware.sh              fleet driver
atlvhwerptd01.conf             production conf  (STAYS at the root)
doc/     README.md             operations + reference  (RUNBOOK.md no longer exists)
         HANDOFF.md            this file
         check_hardware.conf.example
do_lsf_generate_hostlist       LSF -> hostlist/  (STAYS at the root)
bin/     ssh_crypt.sh, verify_lossless.sh, show_undated.sh
check_iml/   check_hpe_iml.sh, check_lenovo_iml.sh
lib/     *.sh + HPE_IMO_classes_and_codes.txt
creds/   ilo_creds.enc          (plaintext ilo_creds DELETED on the server 2026-10-19)
hostlist/                      GENERATED from LSF, not shipped
reports/<run-tag>/             findings.csv, exceptions.csv, summary.txt
tmp/     credmap/, logs/<run-tag>.log (+ latest.log), fleet/<run-tag>/ (cache)
```

**`atlvhwerptd01.conf` deliberately stayed at the root** — it is an operational
input passed as `--conf atlvhwerptd01.conf`, not documentation. Only the
`.example` template moved.

## Read these first, in this order

1. **`doc/README.md`** — every command *and* all reference material. Two traps
   it leads with: always pass `--conf atlvhwerptd01.conf` (it is what puts `jq`
   on PATH), and never set `HOST_SUFFIX` on that host.
2. Memory file **`check-hardware-fleet-driver`** — output contract, exception
   taxonomy, and the bugs found the hard way.

---

## How it is run

A scheduled run is the whole command, with no wrapper — no `TAG=`, no
redirection:

```bash
check_hardware.sh --conf <path>/atlvhwerptd01.conf --days 7 --fresh
```

Three things make that safe, all added in session 3:

- **The script sets its own `PATH`** (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`)
  rather than inheriting cron's, then **appends** `EXTRA_PATH`.
- **The script sets `umask 077`**, since cron and systemd default to `022`.
  The published copy is `chmod`ed to `PUBLISH_MODE` explicitly.
- **It names and logs itself.** `RUN_TAG_PREFIX="prod-"` in the conf makes an
  unnamed run tag itself `prod-YYYYmmdd-HHMMSS`, and it writes its own
  transcript to `tmp/logs/<run-tag>.log` with `latest.log` symlinked to the
  newest. `--run-tag` still overrides and is taken verbatim.

`start_logging` runs **before** `require_cmd` on purpose, so a scheduled run
dying on "jq not found" lands in the transcript rather than only cron mail.

**The run regenerates `hostlist/` from LSF first** (session 5), so the command
above needs no separate generation step. `--no-generate` skips it. See
"Hostlist regeneration" below and README's "Regenerating the host lists".

**Never set `RUN_TAG` itself in a conf** — only `RUN_TAG_PREFIX`. A fixed tag
is reused nightly, and re-using a tag resumes from the per-host cache, which
has no age check, so the job would re-publish night one's findings forever
while looking perfectly healthy.

**There is no lock.** Nothing stops a manual run overlapping a scheduled one:
48 workers against the SPs and both publishing to the same dated filename.
The CSV cannot be corrupted (atomic rename, last writer wins) but the doubled
auth load risks iLO lockout. A GitHub Actions `concurrency:` group only
serialises *workflow* runs — it cannot see a human running the script on the
host, which is the likelier collision. **Add a flock as part of the workflow
work** — `inventory_script` already has one at `tmp/run_inventory.lock`.

---

## Hostlist regeneration — added and deployed 2026-10-20 (session 5)

**Every sweep now regenerates `hostlist/` from LSF before enumerating it**,
matching `run_inventory.sh`'s stage 1. `--no-generate` skips it. Default ON.

It is on by default because a frozen spine drifts silently: hosts added since
it was last written are never checked at all, and decommissioned ones report
unreachable forever, inflating the unreadable count. It also keeps this project
and `inventory_script` reading the **same** fleet, which is the only reason
their agreement on 1537/89 means anything.

**Why it is not simply "call the generator".** `do_lsf_generate_hostlist`
**exits 0 having written empty files when LSF is unavailable**, so its exit
status proves nothing. Writing straight to `hostlist/` would let one bad LSF
morning replace a good 1626-host spine with nothing, and the sweep that
followed would report a fleet of zero and publish it. So the driver:

1. sources `LSF_PROFILE` and **refuses to continue** unless `lshosts` and
   `bhosts` are really on `PATH` (on this host they are absent from a
   non-interactive SSH `PATH` without it);
2. runs the generator inside a `mktemp -d` **staging directory**;
3. **verifies** — every `EXPECTED_DCS` datacenter present and non-empty, a
   matching `.host-sps` for each, at least `MIN_HOSTS`, and at least
   `MIN_HOST_PERCENT` of what the current list holds;
4. only then **promotes**, rotating the live directory to `hostlist.prev`.

On failure the run dies and **the live hostlist is untouched**. The
`.host-sps` check is not pedantry: a host in `.hosts` but missing from
`.host-sps` is reported `NO_SP_ENTRY`, so a half-generation would turn the
whole fleet into `NO_SP_ENTRY` rows without ever looking unreachable.

**`do_lsf_generate_hostlist` is CWD-relative on purpose** — it writes
`./hostlist` relative to wherever it is invoked, which is exactly what makes it
containable in a staging directory. The trade is that running it **by hand**
from anywhere but the project root leaves a stray `hostlist/` there. The driver
is immune because it always `cd`s first. It briefly resolved its output from
`${BASH_SOURCE[0]}/..` instead; at the tree root that pointed one level *above*
the project, so it would have written `~/scripts/hostlist` while the driver
read the stale in-project copy. Do not reintroduce that.

Conf knobs: `DO_GENERATE`, `LSF_PROFILE`, `EXPECTED_DCS`, `MIN_HOSTS`,
`MIN_HOST_PERCENT`.

---

## The decisions that are settled (do not silently revise)

- **Two output files, every host in at least one.** `findings.csv` holds only
  hosts with faults; `exceptions.csv` holds everything else *including healthy
  hosts* (`CLEAN`). The summary asserts
  `findings_hosts + exception_rows − both = total` on every run.
- **`JOBS=24`**, matching `inventory_script` on the same fleet.
- **Critical only, Hardware+Power categories only**, by default.
- **No default age cutoff** — but undated findings are suppressed when a
  window is given, and reported as `UNDATED_FINDINGS` rows in the exceptions
  file.
- **Credentials encrypted at rest**, bound by direct RSA to the host's
  `~/.ssh/id_rsa`. `--creds` accepts the `.enc` path directly.
- **Publish by atomic rename**, never a bare `cp`. Published name is
  `vbu_hardware_errors_YYYY-MM-DD.csv` — **underscore**, matching
  `vbu_inventory_2026-10-17.csv`. Do not reintroduce the hyphen.
- **The exceptions file has its own prefix**, `PUBLISH_EXCEPTIONS_PREFIX`
  (`vbu_hardware_exceptions`), *not* a suffix on the findings prefix — with an
  underscore separator that would be matched by a consumer's
  `vbu_hardware_errors_*.csv` glob, handing a dashboard a complete,
  well-formed file of the wrong schema (6 cols vs 21). That fails silently,
  which is worse than the partial read the atomic rename exists to prevent.
- **`RETENTION_DAYS=90`** prunes `reports/<tag>/`, `tmp/fleet/<tag>/` and
  `tmp/logs/<tag>.log` after publishing. **Nothing on the share is ever
  pruned.** `hostlist.prev` is not pruned either.
- **Regenerate the hostlist on every run**, `--no-generate` to skip — chosen
  2026-10-20 to match `inventory_script`'s spelling and default.
- **Scheduling is GitHub Actions**, not systemd, not cron — 2026-10-20.
- **Git**: the user handles `~/scripts` git exposure manually, outside Claude.
  Do not write `.gitignore` files or run `git add` there. Do not commit or push
  on the user's behalf; deploy to the host, let them test and push.

---

## Things that cost real time to learn

**`EXTRA_PATH` must be APPENDED, not prepended.** `/tool/pandora64/bin`
shadows ten core utilities — `date curl grep sed awk cut sort python3 openssl
xargs` — at different GNU versions (awk 5.0 vs 4.2, grep 2.28 vs 3.1, i.e.
*older*). Prepending had been silently swapping the whole toolchain underneath
a script validated against the system one, with the `date`-dependent age
filter most exposed. `jq` is the only thing genuinely missing.

**`OUTPUT_DIR` means the OPPOSITE thing in the two projects.** Here it **is**
`/proj/emu_share/...`; in `inventory_script` it is a local directory and the
share is `PUBLISH_DIR` — and its retention prunes `OUTPUT_DIR`. Porting that
verbatim would delete published CSVs out from under their consumers.

**The `--days` filter silently ignored its window.** `jq`'s `fromdateiso8601`
accepts only `YYYY-MM-DDTHH:MM:SSZ`, but this firmware also emits
`2023-08-07T11:48:35.553+00:00`. An unparseable timestamp was treated as
*keep*, so 131 findings on 93 hosts (median true age 223 days) sailed through
a 7-day window. **The symptom was a 7-day run returning MORE hosts than a
30-day one** — which a narrower window can never legitimately do. Fixed with a
shared `def epoch:` in both vendor scripts; **the two definitions must stay
byte-identical** or the vendors apply different age filters to one CSV. The
filter and the display used *different* parsers, which is why `AgeDays` showed
a correct age on rows that should not have been there.

**How to read the output columns — every one of these was asked in anger
(2026-10-19).** The `--days` filter was reported as broken twice in one
session; it was right both times, and the real answers are these:

- **`AgeDays` is measured from `LastSeen` — the NEWEST event in the group,
  never the oldest.** A fault logging continuously across a 3-day window reads
  **0, not 3** (`atlhwe-lsf185` DIMM 12: 117 entries spanning 10-16→10-19,
  `AgeDays=0`). It answers *"how long since this last happened"* — recency,
  not duration. Duration inside the window is `LastSeen − FirstSeen`.
- **It is whole 24h periods, integer-truncated, NOT calendar days.**
  `(now − LastSeen) / 86400` in `lib/common.sh`. An event at 23:00 yesterday
  still reads `0`.
- **A blank `AgeDays` is not a zero** — `age_days` prints nothing when a
  timestamp will not parse. Under a window those findings are suppressed into
  `UNDATED_FINDINGS` anyway, so blanks should not appear in a windowed run.
- **★ `FirstSeen` under a window is the WINDOW EDGE, not the onset.** The age
  filter runs per entry *before* `group_by`, so it clamps. In a `--days 3` run,
  4 of 26 rows had a `FirstSeen` within **50 minutes** of the cutoff. Never
  quote it as "when this DIMM started failing" — re-run that host **without**
  `--days` to get the true onset.
- **HPE only: `FirstSeen` can legitimately PREDATE the window.** The filter
  tests `Oem.Hpe.Updated // .Created` but the column displays `.Created`, and
  iLO coalesces repeats into one record. A record created on the 14th and still
  updated on the 18th correctly passes a 3-day window while showing the 14th.
  Intended. Lenovo cannot do this — it takes both ends from `.Created`.
- **`Entries` ≠ `Occurrences`.** Entries is distinct IML records, Occurrences
  is true event volume after iLO's own coalescing: `atlhwe-s14` shows 68 and
  **27792**.
- **`--days N` reaches back N×24h from NOW**, so `--days 3` on the 19th reaches
  the 16th, not the 15th. This gets miscounted.

**Check WHICH FILE before debugging the filter.** The first 2026-10-19 report
turned out to be **a stale CSV left open in Excel** — Excel does not reload a
file that changed on disk. Every run writes its own `reports/<tag>/findings.csv`,
so "the findings.csv" is ambiguous by design, and the share additionally holds
`vbu_hardware_errors_2026-10-18.csv` (a `--days 7` run, window back to the
11th) beside its stale hyphen-named twin. Confirm the run tag or the mtime
first. Also note `class0x0014code0x0005` in `LearnMoreLink` and small
`EventIDs` like `114 117` both misread as dates at a glance.

**Undated records are not recent.** iLO writes `0000-00-00T00:00:00Z` when an
event is logged with no clock set. IML `Id`s are assigned in write order, so
an undated record can be bracketed between its dated neighbours — every
sampled block landed months or years back. Overwhelmingly a NIC link flapping
on an unused OCP port, and all HPE; the Lenovo XCC dates its log reliably.
`bin/show_undated.sh` dumps the raw records.

**The command line is parsed twice** (once to find `--conf`, once after
sourcing it so the CLI still wins) and `--dc`/`--host` accumulate — the second
pass once doubled every filter and swept each host twice. The output looked
entirely plausible. **After any argument-parsing change, compare per-DC
`--dry-run` counts against `wc -l` of the `.hosts` files.**

**`grep -c . file || echo 0` returns `"0\n0"` on an empty file.** Use `wc -l`.

**★ The conf CLOBBERS an environment variable — env does NOT beat conf.**
Precedence here is *CLI beats conf*, achieved by parsing the command line again
after `load_conf`. An exported value has no such protection: the driver's
`VAR="${VAR:-default}"` runs first, then the conf is sourced over it. A
negative control that set `MIN_HOST_PERCENT=150` on the command line therefore
**did nothing at all** — the run verified 1626 and promoted as if the override
had never been written, which looks exactly like a passing test.

The five regeneration knobs have **no CLI flag**, so a plain assignment would
have made the conf the only place to change them — and the conf is deployed
from git, so a host edit is reverted by the next workflow run. They are
written as `DO_GENERATE="${DO_GENERATE:-1}"` and so on in
`atlvhwerptd01.conf`, deliberately unlike the plain `JOBS=24` lines around
them, which leaves an env override as the one-off escape hatch:

```bash
MIN_HOST_PERCENT=0 check_hardware.sh --conf atlvhwerptd01.conf --days 7 --fresh
```

**Before telling anyone to override a conf value with an environment variable,
check that the conf line uses the `:-` form. Most lines in that file do not.**

**Do not run `do_lsf_generate_hostlist` under `set -u`** —
`/tool/pandora/etc/lsf/profile.lsf` references `AMDLSFCLUSTER` unguarded and
dies, yielding an EMPTY hostlist while still exiting 0. Its exit status is
worthless; check the files. **`lshosts` and `bhosts` return largely disjoint
sets** (atl: 306 and 317, unioning to 620) — either number alone looks like
the fleet halved. Expected counts: atl 620, caco 51, dfdc 315, pldc 339,
sadc 139, syco 162 = **1626**.

---

## Verification that actually proved something

- **Losslessness.** `bin/verify_lossless.sh` re-reads each host's log and
  asserts `sum(Entries) == raw records passing the same filters`. It **must**
  page with `rf_get_collection`; a single `?$top=2000` fetch reads only the
  first page on an XCC. `--mutate` undercounts by one and the check must fail —
  an assertion never seen to fail proves nothing.
- **Cross-validation.** The sweep finds **1537 readable / 89 unreadable** of
  1626; `inventory_script`'s accepted baseline is **1537 ok / 88 unreachable /
  1 auth_failed**. Same split, entirely separate code path.
- **Encrypted-only negative control.** With `creds/ilo_creds` moved away
  entirely, a 3-host sweep produced a byte-identical findings md5.
- **Leak checks.** 0 password occurrences across CSVs, summary, worker stderr
  and credmap; 0 credential-bearing argv with **81 processes observed** — the
  observed count matters.
- **Cron-environment equivalence.** A full sweep under `env -i` with only
  `HOME`/`LOGNAME`/`PATH=/usr/bin:/bin`/`SHELL` was byte-identical to the
  interactive run once `Occurrences`/`LastSeen` were excluded.
- **`--warnings`, tested at fleet scale for the first time** (session 3):
  402 Critical + 700 Warning = 1102 rows from 216 hosts. All 402 critical
  finding identities appear in both runs and **no host lost findings**, so the
  flag is purely additive. But `UNDATED_FINDINGS` nearly doubles (68 → 127)
  and `CLEAN` drops 63, because many undated entries are warning-severity and
  get suppressed by the window. **Enabling `--warnings` in production would
  ~2.7× the published row count.**
- **Hostlist regeneration** (session 5). The gate was unit-tested against
  fixtures, 11 cases: all-empty, a missing datacenter, an empty datacenter, a
  **missing `.host-sps`**, under `MIN_HOSTS`, non-empty-but-620-of-1626, and no
  directory at all are each rejected; a healthy 1626 and normal churn
  (1543/1626 = 94%) are accepted. The controls are what make that mean
  something: the **same** 620-host list flips to accepted at
  `MIN_HOST_PERCENT=0`, and the 60-host list stays rejected by the 80% rule
  even after `MIN_HOSTS` is lowered — so the knobs, not luck, are doing the
  rejecting. A second 13-case test drove stage/verify/promote end to end with a
  stubbed generator and stubbed LSF, because **those failure branches are
  unreachable on the host, where LSF works**: good generation promoted and
  `hostlist.prev` holds exactly what it replaced; all-empty, partial and
  missing-datacenter each **die with the live hostlist byte-identical**;
  missing `lshosts`/`bhosts` refused before generating.
  On the host with real LSF the generator reproduced **1626
  (620/51/315/339/139/162)** inside a temp directory — proving containment —
  and a live run staged, verified, promoted and swept caco 51 in 10s with
  accountability `0 + 51 - 0 = 51 OK`. The regenerated list was `diff -r`
  **identical** to the pre-change backup, and no `/tmp/check_hardware-gen.*`
  was left behind. Host-side negative control: `MIN_HOST_PERCENT=150` aborts
  the run (exit 1) with the live hostlist byte-identical, and
  `MIN_HOST_PERCENT=0` then passes.

## Transient drift is normal — do not chase it

Hosts move between `CLEAN` / `SP_UNREACHABLE` / `CREDENTIALS_REJECTED` between
runs minutes apart, then re-probe clean on demand. Judge a run by its final
totals, never by a ±2 shuffle. Likewise, actively-logging hosts
(`atlhwe-s14`, `atlhwe-s11`, `atlhwe-lsf88`, `atlhwe-lsf211`) change
`Occurrences`/`LastSeen`/`EventIDs` between runs minutes apart — and counts can
go **down** when the sliding window drops their oldest events. When diffing two
runs, exclude the volatile columns or you will chase live data.

---

## What is left

1. **The GitHub Actions workflow** — the main work. Model it on
   `inventory_script`'s `.github/workflows/inventory-run.yml`, which solves
   this for the same account on the same host:
   - **Self-hosted runner labelled `atlvhwerptd01`.** `inventory-run.yml` uses
     `cron: '0 8 * * 1-6'` (UTC, Mon–Sat), `concurrency` group with no
     cancel-in-progress, `timeout-minutes: 130`, a `workflow_dispatch`
     `dry_run` boolean, and runs only from `refs/heads/main`. GitHub starts
     scheduled runs late, often by an hour.
   - **★ The deploy rsync must exclude `hostlist/`** — inventory's already
     does. The sweep regenerates it on the host, so letting git overwrite it
     would clobber the generated spine every run. Exclude `hostlist.prev/`,
     `creds/`, `tmp/`, `reports/` and `*.csv` for the same reason.
   - **`--fresh` is mandatory.** The per-host cache has no age check.
     `--fresh` deliberately does not clear the credential map.
   - **Do not use `bash -lc`** — the job must not depend on `.bash_profile`;
     `EXTRA_PATH` in the conf is the only thing putting `jq` on `PATH`.
   - **Pass `--conf` and let the conf own everything else.** inventory's
     workflow passes no `--output-dir` and no `--no-publish`, which makes the
     conf the single point of failure for publication — deliberate, and worth
     copying so there is one place to look.
   - **Add a flock** — see "There is no lock" above. A `concurrency:` group
     does not protect against a human running the script on the host.
   - If a job summary parses the transcript the way inventory's does, note
     that **renaming log lines silently blanks those rows**.
   - A sweep is ~280s warm. Prove the schedule actually fires rather than
     assuming it will.
2. **Decide the real age window.** 7 days was a starting guess. The user
   trialled `--days 3` twice on 2026-10-19, ~10h apart, both `--fresh
   --no-publish`:

   | run | rows / hosts |
   |---|---|
   | `--days 3` (critical only) | **22 / 13** |
   | `--days 3 --warnings` | **26 / 16** (22 Critical + 4 Warning) |

   Two things to weigh before settling this. The critical count was **22 in
   both runs**, which is the stability you want from a nightly. And
   **`--warnings` costs almost nothing at 3 days (+4 rows) but ~2.7× the rows
   at 7 days** (402→1102, see above) — so the warning noise is nearly all
   3-7 days old, and the two flags interact. Do not carry the 7-day
   `--warnings` conclusion over to a 3-day window. **Sanity-check that gap
   before relying on it**; it is a large swing from a single pair of runs.
3. **`--publish-exceptions` is UNRESOLVED.** The user is discussing with
   another engineer whether to publish the exceptions file at all and in what
   shape. **Do not decide this unilaterally.** Ideas already on the table:
   publish as-is; publish only the non-`CLEAN` rows; publish a small
   coverage manifest instead (date, hosts attempted, readable/unreadable by
   reason) so a dashboard can tell "fleet got healthier" from "collection half
   failed"; or add a `Status` column and collapse to one file (rejected for
   now — breaks the accepted 21-column contract).
4. ~~**Delete `creds/ilo_creds`**~~ — **DONE on the server 2026-10-19.**
   `creds/` there now holds only `ilo_creds.enc` (365 B). The encrypted path
   had already been proven by a negative control, and runs log
   `creds : encrypted at rest (<path>)` as the only after-the-fact evidence of
   which file a run read — so watch for a `PLAINTEXT on disk` WARN reappearing.
   **The local working copy still has its own plaintext `creds/ilo_creds`**
   (109 B) and no `.enc`; that is expected, since the sidecar is RSA-bound to
   the server's `~/.ssh/id_rsa` and is undecryptable anywhere else. Deleting
   the local plaintext is the user's call.
5. Optional cleanup: `reports/warntest-20261018-200550/` holds the
   `--warnings` test output; retention clears it in 90 days.
6. **`hostlist.prev` now exists on the host** (created by the first
   regeneration, holding the 2026-10-18 generation). It is not pruned by
   `RETENTION_DAYS` and is rewritten on every run. Harmless; mentioned so it
   is not mistaken for litter.
7. Backup taken before the session-5 changes:
   `~/check_hardware.pre-generate-20261020.tar.gz` on the host (excludes
   `creds/`, `tmp/`, `reports/`).

---

## The prompt to paste into the new chat

```
We're continuing the check_hardware project in my check_hardware folder.

Read your memory files project_check_hardware.md and
project_check_hardware_fleet_driver.md first, then doc/HANDOFF.md and
doc/README.md. HANDOFF.md is the full state and the constraints that
matter; README.md has every command plus all the reference material.
The docs live in doc/ - they are not at the tree root, and neither is
check_hardware.conf.example. RUNBOOK.md no longer exists at all; it was
merged into README.md.

I've attached the SSH key for the production host. Set it up at ~/.ssh/id_rsa
(mode 600) and use the FQDN atlvhwerptd01.amd.com as z1_vbu_hwe_user - the
short hostname does not resolve. The project is deployed at
/home/z1_vbu_hwe_user/scripts/check_hardware. Local and server were verified
byte-identical at the end of the last session, but diff before pushing.

Short version: the fleet driver and both single-host vendor scripts are
finished and validated against the live 1626-host fleet. Credentials are
encrypted at rest. Every run now regenerates hostlist/ from LSF before it
sweeps (--no-generate skips it), staging and verifying the result before it
replaces the live copy. A run publishes vbu_hardware_errors_DATE.csv to
/proj/emu_share/tools/check_hardware by atomic rename, names and logs itself
(tmp/logs/<run-tag>.log + latest.log), sets its own PATH and umask so a
scheduled run behaves like an interactive one, and prunes local artefacts
older than RETENTION_DAYS=90. Baseline at --days 7: 1626 hosts in ~280s, 402
findings across 209 hosts, 1537 readable / 89 unreadable, accountability
exact. The whole scheduled command is just:

  check_hardware.sh --conf <path>/atlvhwerptd01.conf --days 7 --fresh

This session: write the GitHub Actions workflow that runs that nightly, on
the self-hosted runner, modelled on inventory_script's
.github/workflows/inventory-run.yml.

IMPORTANT - do NOT write systemd units. An older plan called for
check_hardware.service/.timer; that was dropped on 2026-10-20. Scheduling is
GitHub Actions, like inventory_script. Note what that implies: git is the
source of truth and the deploy rsync overwrites the host every run, so
anything you scp there is temporary. Deploy to
~/scripts/check_hardware, verify it works there, and leave the commit and
push to me - do not commit or push on my behalf.

Constraints that have already cost the sibling project time: the deploy rsync
MUST exclude hostlist/ (and hostlist.prev/, creds/, tmp/, reports/, *.csv),
or git will clobber the regenerated spine every run; --fresh is mandatory
because the per-host cache has no age check; and the job must not use
`bash -lc`, because EXTRA_PATH in the conf is the only thing putting jq on
PATH. There is still NO lock, so a manual run can overlap a scheduled one and
double the auth load against the iLOs - a concurrency group won't catch that,
so add a flock as part of this work.

Before writing the workflow, ask me about the schedule and about the age
window to bake in (7 days is a guess I want to revisit - I have since
trialled --days 3, numbers are in HANDOFF.md under "What is left").

Two things in HANDOFF.md worth reading before you touch anything related:
"How to read the output columns" - I reported --days as broken twice and it
was correct both times - and the note that the conf CLOBBERS environment
variables, which made a negative control silently pass.

Still open and NOT for you to decide alone: whether the nightly run should
publish the exceptions file (--publish-exceptions). I'm discussing that with
another engineer.
```
