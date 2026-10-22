# check_hardware

Read service-processor event logs across the fleet and report the hardware
faults in them. HPE iLO exposes its Integrated Management Log (IML) over
Redfish; Lenovo XCC exposes an equivalent as `PlatformLog`. One script per
vendor handles a single host, and `check_hardware.sh` drives them across all
six datacenters.

```
check_hardware/
  check_hardware.sh              fleet driver
  check_hardware.conf.example    copy to check_hardware.conf and edit
  atlvhwerptd01.conf             production conf for the collector host
  do_lsf_generate_hostlist       regenerate hostlist/ from LSF (CWD-relative;
                                 run it from the project root)
  bin/
    ssh_crypt.sh                 encrypt/decrypt a file against an RSA SSH key
    verify_lossless.sh           re-read SPs and prove no events were dropped
    show_undated.sh              dump the raw undated records for a host
  check_iml/
    check_hpe_iml.sh             one HPE host
    check_lenovo_iml.sh          one Lenovo host
  lib/
    common.sh                    logging, CSV, time helpers
    creds.sh                     ILO_CREDS loading, decryption, credential map
    redfish.sh                   authenticated Redfish GETs
    iml_report.sh                the shared CSV contract + both renderers
    iml_map.sh                   HPE Class/Code interpretation
    lenovo_map.sh                Lenovo CommonEventID interpretation
    HPE_IMO_classes_and_codes.txt  source document iml_map.sh encodes
  creds/
    ilo_creds.enc                encrypted sidecar, preferred when present
  hostlist/                      <dc>.hosts and <dc>.host-sps  (GENERATED)
  reports/<run-tag>/             findings.csv, exceptions.csv, summary.txt
  tmp/
    credmap/                     learned credential labels (never passwords)
    logs/                        run logs, <run-tag>.log
    fleet/<run-tag>/             per-host cache for resume
```

**Status: complete and running in production** on `atlvhwerptd01.amd.com`.
Both single-host checkers and the fleet driver are validated against the live
1626-host fleet; credentials are encrypted at rest. The systemd `--user`
timer units are the remaining work.

`hostlist/` is generated, not shipped — see
[Regenerating the host lists](#regenerating-the-host-lists).

---

# Running it

Every command below runs **on `atlvhwerptd01.amd.com`** as `z1_vbu_hwe_user`,
from the project root:

```bash
ssh z1_vbu_hwe_user@atlvhwerptd01.amd.com
cd /home/z1_vbu_hwe_user/scripts/check_hardware
```

Two things that are easy to get wrong:

- **Always pass `--conf atlvhwerptd01.conf`.** Without it `jq` is not on the
  PATH here (it lives in `/tool/pandora64/bin`, and the conf is what adds it),
  and the run dies with `missing required command(s): jq`.
- **Never set `HOST_SUFFIX` on this host.** Its `resolv.conf` already carries
  `search amd.com`, so a suffix would produce `...-sp.amd.com.amd.com`. The
  option exists only for sandboxes whose resolver lacks that search domain.

## The fleet sweep

```bash
# 7-day window across all 1626 hosts, 24 workers (~5 min warm)
./check_hardware.sh --conf atlvhwerptd01.conf --run-tag myrun --jobs 24 --days 7
```

Results land in `reports/myrun/`:

| file | contents |
|---|---|
| `findings.csv` | 21 columns, only hosts with faults inside the window |
| `exceptions.csv` | one row per host with no reported findings — includes healthy hosts (`CLEAN`), hosts whose findings carried no timestamp (`UNDATED_FINDINGS`), and every host that could not be read |
| `summary.txt` | counts, exception breakdown, per-datacenter table |

and the findings CSV is then **published** to the shared directory as
`vbu_hardware_errors_YYYY-MM-DD.csv`:

```
INFO  published : /proj/emu_share/tools/check_hardware/vbu_hardware_errors_2026-10-18.csv (… bytes, mode 664)
```

The run takes ~10 minutes if the credential map is cold and ~5 warm. That is
longer than a single SSH session is worth holding open, so launch it detached
and poll:

```bash
setsid nohup ./check_hardware.sh --conf atlvhwerptd01.conf \
    --jobs 24 --days 7 --fresh < /dev/null > /dev/null 2>&1 &

# progress, and the live transcript
tail -f tmp/logs/latest.log
ls tmp/fleet/$(basename $(readlink tmp/logs/latest.log) .log)/*.status | wc -l   # of 1626
```

**You do not have to invent a run tag or redirect the output.** With
`RUN_TAG_PREFIX="prod-"` in the conf, an unnamed run tags itself
`prod-YYYYmmdd-HHMMSS` and writes its own transcript to
`tmp/logs/<run-tag>.log`, with `tmp/logs/latest.log` always pointing at the
newest. `--run-tag` still overrides, and is taken verbatim with no prefix.

### Scheduled runs

The whole command for cron or a systemd unit is:

```bash
/home/z1_vbu_hwe_user/scripts/check_hardware/check_hardware.sh \
    --conf /home/z1_vbu_hwe_user/scripts/check_hardware/atlvhwerptd01.conf \
    --days 7 --fresh
```

No wrapper, no `TAG=`, no redirection. Three things make that safe:

- **The script sets its own `PATH`** —
  `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` — rather than
  inheriting cron's `/usr/local/bin:/usr/bin`. `EXTRA_PATH` from the conf is
  then *appended*. Do not use `bash -lc` to work around a PATH problem; it
  hides where PATH came from, and `.bash_profile` is not read by systemd.
- **The script sets `umask 077`**, so a scheduled run does not leave the cache,
  credential map and transcripts world-readable just because cron defaults to
  `022`. The published CSV is `chmod`ed to `PUBLISH_MODE` explicitly and is
  unaffected.
- **`--fresh` is mandatory.** The per-host cache has no age check, so without
  it a nightly run re-emits the previous results forever. It deliberately does
  not clear the credential map.

**Never set `RUN_TAG` in a conf** — only `RUN_TAG_PREFIX`. A fixed tag is
reused every night, and re-using a tag resumes from cache, so the job would
re-publish its first night's findings indefinitely while appearing to succeed.

### Retention

`RETENTION_DAYS=90` in the conf prunes local run artefacts at the end of each
run — `reports/<tag>/`, `tmp/fleet/<tag>/` and `tmp/logs/<tag>.log`. Set `0` to
keep everything. A nightly sweep leaves roughly 8 MB of per-host cache plus a
~150 KB report and a small log, so 90 days is about 750 MB, nearly all cache.

```bash
# see what would be pruned without pruning it
./check_hardware.sh --conf atlvhwerptd01.conf --dry-run

# keep everything for a one-off
RETENTION_DAYS=0 ./check_hardware.sh --conf atlvhwerptd01.conf --days 7
```

**Nothing on the published share is ever pruned.** Mind the naming collision
with `inventory_script`: there, `OUTPUT_DIR` is a local directory and the share
is `PUBLISH_DIR`, whereas here `OUTPUT_DIR` *is* the share. Porting that
project's prune verbatim would start deleting dated CSVs out from under
whatever reads them. Retiring a published file is a deliberate manual act.

Two further rails, since this is the only code in the tree that deletes
recursively: a directory is removed only if it contains the files this script
writes, so anything else parked in `reports/` is left alone rather than trusted
to a name pattern (`--run-tag` accepts any string); and the current run is
skipped explicitly, so a wrong clock or a mistyped `RETENTION_DAYS` cannot
delete the sweep that just finished.

### Publishing

`atlvhwerptd01.conf` sets `OUTPUT_DIR="/proj/emu_share/tools/check_hardware"`,
so a normal run publishes without any extra flag.

```bash
# publish somewhere else for a one-off
./check_hardware.sh --conf atlvhwerptd01.conf --days 7 --output-dir /some/other/dir

# run but keep the results local
./check_hardware.sh --conf atlvhwerptd01.conf --days 7 --no-publish

# also publish the exceptions file alongside the findings
./check_hardware.sh --conf atlvhwerptd01.conf --days 7 --publish-exceptions
```

**Why a dashboard cannot read a half-written file.** The run writes everything
into `reports/<tag>/` first and publishes only after the sweep has finished and
the summary is written. The copy itself lands on a dot-prefixed temporary name
*in the destination directory* and is then renamed into place; `rename(2)`
within one filesystem is atomic, so a reader polling the directory sees either
yesterday's file or the complete new one. A plain `cp` would not give that
guarantee — it writes incrementally while the destination is readable. This is
the same mechanism `inventory_script`'s `publish_csv` uses.

The temporary name is `.publish-<run-tag>.<pid>`, derived from the run rather
than from the destination filename, so it cannot match a consumer's glob however
that glob is written, and two overlapping runs cannot stage onto each other's
temporary file.

Published files are mode **664**, matching the sibling `vbu_inventory` files.
The collector's own umask would otherwise leave them `600` and unreadable by
anything else. The mode is set on the temporary file, before the rename, so the
file is never briefly visible at `600` under its real name.

The exceptions file publishes under its **own** prefix,
`vbu_hardware_exceptions_YYYY-MM-DD.csv`, not as a suffix on the findings
prefix. It carries a different schema (6 columns, not 21), so sharing the
findings prefix would let a consumer globbing `vbu_hardware_errors_*.csv` pick
it up and parse it as findings — a complete, well-formed file of the wrong
shape, which fails silently and so is worse than the partial read the atomic
rename exists to prevent.

A publish failure **warns but does not fail the run** — the local copy is
already safe, and a completed fleet sweep is not worth discarding over a
filesystem hiccup. A missing or read-only `--output-dir` is reported with its
actual cause rather than created, so a typo cannot scatter a directory across
the share.

`--reports-dir` moves the local per-run directory if you ever need it
elsewhere; `--output-dir` is only ever the publish destination.

### Narrower runs

```bash
# one datacenter        (atl caco dfdc pldc sadc syco)
./check_hardware.sh --conf atlvhwerptd01.conf --dc atl --days 7

# specific hosts
./check_hardware.sh --conf atlvhwerptd01.conf --host atlhwe-lsf24,atlhwe-lsf88 --days 7

# a list from a file, one host per line
./check_hardware.sh --conf atlvhwerptd01.conf --hosts-file tmp/pilot.hosts --days 7

# different windows
./check_hardware.sh --conf atlvhwerptd01.conf --days 30
./check_hardware.sh --conf atlvhwerptd01.conf --since 2026-09-01
./check_hardware.sh --conf atlvhwerptd01.conf                 # no window: all history

# widen what counts as a finding
./check_hardware.sh --conf atlvhwerptd01.conf --days 7 --warnings
./check_hardware.sh --conf atlvhwerptd01.conf --days 7 --all-categories
```

### `--dry-run` and `--fresh`

```bash
# enumerate hosts and resolve service processors, probe NOTHING
./check_hardware.sh --conf atlvhwerptd01.conf --dc caco --dry-run

# re-probe everything, discarding cached per-host results
./check_hardware.sh --conf atlvhwerptd01.conf --run-tag myrun --days 7 --fresh
```

`--fresh` deliberately does **not** clear the learned credential map
(`tmp/credmap/`). Re-learning which credential each SP takes would cost a
failed login on every host and risks tripping iLO lockout.

**The cache has no age check.** Re-running an existing `--run-tag` without
`--fresh` reuses every cached per-host result and completes in seconds — which
is exactly what you want when resuming an interrupted sweep, and exactly what
you do not want from a scheduled job. Any automated run needs `--fresh` or a
new run tag.

## One host at a time

Useful when someone is standing in front of a machine, and for checking
anything the fleet run reported.

```bash
# HPE
./check_iml/check_hpe_iml.sh    --conf atlvhwerptd01.conf --report atlhwe-lsf24
./check_iml/check_hpe_iml.sh    --conf atlvhwerptd01.conf --days 7 --report atlhwe-lsf24

# Lenovo
./check_iml/check_lenovo_iml.sh --conf atlvhwerptd01.conf --report atlhwe-lsf88

# CSV instead of the readable form
./check_iml/check_hpe_iml.sh    --conf atlvhwerptd01.conf --csv atlhwe-lsf24
```

Exit status is meaningful, so the fleet driver can branch without parsing. It
is the same for the single-host scripts and the driver:

| code | meaning |
|---|---|
| 0 | nothing found |
| 1 | warnings only |
| 2 | at least one critical finding |
| 3 | the log could not be read — **not** the same as healthy |

Both vendors emit the identical 21-column CSV, verified byte-identical, so the
files concatenate directly.

## Undated findings

iLO writes `0000-00-00T00:00:00Z` when an event is logged with no clock set.
Such a finding cannot be placed inside an age window, so **when `--days` or
`--since` is given it is suppressed from `findings.csv`** and the host instead
gets an `UNDATED_FINDINGS` row in `exceptions.csv` naming the count and
class/codes. With no window they are reported normally.

To see them for a host:

```bash
# the raw log records themselves
./bin/show_undated.sh --conf atlvhwerptd01.conf atlhwe-int13
./bin/show_undated.sh --conf atlvhwerptd01.conf --limit 5 --full atlhwe-int13

# or just re-run that host without a window
./check_iml/check_hpe_iml.sh --conf atlvhwerptd01.conf --report atlhwe-int13
```

Measured on this fleet: these are not recent. IML Ids are assigned in write
order, so an undated record can be bracketed between its nearest dated
neighbours, and every sampled block landed months or years back — one sat
between a dated 2021-09-17 and a dated 2022-07-28. They are overwhelmingly a
NIC link flapping on an unused OCP port.

## Checking a run

```bash
cd reports/myrun

# the accountability identity - every host in at least one file
grep accountability summary.txt

# column contract: findings must be 21 wide, zero ragged rows
python3 -c "
import csv,sys
for n in ('findings.csv','exceptions.csv'):
    r=list(csv.reader(open(n)))
    print(n, 'rows', len(r)-1, 'widths', sorted({len(x) for x in r}))
"

# why hosts could not be read
tail -n +2 exceptions.csv | awk -F'","' '{gsub(/"/,"",$5); print $5}' | sort | uniq -c | sort -rn
```

**Losslessness** — proves grouping dropped no events, by re-reading the logs
from the service processors and comparing against the CSV:

```bash
./bin/verify_lossless.sh --conf atlvhwerptd01.conf \
    --csv reports/myrun/findings.csv atlhwe-lsf24 atlhwe-lsf88

# --mutate undercounts by one deliberately; the check MUST fail.
# An assertion nobody has seen fail proves nothing.
./bin/verify_lossless.sh --conf atlvhwerptd01.conf \
    --csv reports/myrun/findings.csv --mutate atlhwe-lsf24
```

It **must** page with `rf_get_collection`. A single `?$top=2000` fetch reads
only the first page on an XCC and will accuse the driver of inventing hundreds
of events; the mismatch direction is the tell, since CSV > raw means the
verifier is under-fetching.

## Managing the credentials

Live file is `creds/ilo_creds.enc`, encrypted with direct RSA against this
host's `~/.ssh/id_rsa`. **It can only be decrypted here** — that is why it was
encrypted on the host rather than anywhere else. It is decrypted in memory on
every run; the plaintext is never written back to disk.

```bash
# 1. edit the plaintext (or restore it from wherever you keep it)
vi creds/ilo_creds

# 2. re-encrypt
./bin/ssh_crypt.sh encrypt -k ~/.ssh/id_rsa -p ~/.ssh/id_rsa.pub \
    -o ./creds/ilo_creds.enc ./creds/ilo_creds

# 3. prove a live run reads it, then remove the plaintext
./check_hardware.sh --conf atlvhwerptd01.conf --host atlhwe-lsf24 --days 7 --fresh
shred -u creds/ilo_creds
```

`./bin/ssh_crypt.sh edit` does all of that in one step — decrypt to a temp
file, open `$EDITOR`, re-encrypt — without the plaintext ever landing in
`creds/`.

```bash
# explicit, and what atlvhwerptd01.conf sets
./check_hardware.sh --conf atlvhwerptd01.conf --creds ./creds/ilo_creds.enc --days 7

# also works: naming the plaintext, because ${CREDS_FILE}.enc is preferred
# automatically when it exists
./check_hardware.sh --conf atlvhwerptd01.conf --creds ./creds/ilo_creds --days 7

./bin/ssh_crypt.sh check                       # key type, block limit, files present
./bin/ssh_crypt.sh -f creds/ilo_creds decrypt  # plaintext to stdout
```

Every run logs which file it used:

```
INFO  credentials: 4 candidate(s) (0 1 2 3)
INFO  creds      : encrypted at rest (./creds/ilo_creds.enc)
```

A **`WARN creds : PLAINTEXT on disk`** line instead means the run read an
unencrypted file. Once the plaintext is deleted that log line is the only way
to answer "was this run reading the encrypted file?" after the fact.

**Verified:** with the plaintext moved away entirely, a 3-host sweep produced
byte-identical findings — the absence of the plaintext is what makes that test
mean anything.

## Regenerating the host lists

**Every sweep regenerates `hostlist/` from LSF before enumerating it.** This is
on by default and matches `run_inventory.sh`'s stage 1. Pass `--no-generate` to
skip it.

```bash
check_hardware.sh --conf atlvhwerptd01.conf --days 7 --fresh    # regenerates
check_hardware.sh --conf atlvhwerptd01.conf --days 7 --no-generate
```

Regeneration is on by default because a frozen hostlist drifts silently: hosts
added since it was last written are never checked at all, and decommissioned
ones are reported unreachable on every run, inflating the unreadable count. It
also keeps this project and `inventory_script` reading the *same* fleet, which
is the only reason their agreement on readable/unreadable counts means
anything.

Reach for `--no-generate` when LSF is unavailable, when you want a sweep
reproduced against a known fixed list, or for a narrow `--host` / `--dc`
debugging run where rebuilding the whole 1626-host spine is wasted effort.

### Why it is not simply "run the generator"

`do_lsf_generate_hostlist` **exits 0 having written empty files when LSF is
unavailable**, so its exit status proves nothing. If it wrote straight to
`hostlist/`, one bad LSF morning would replace a good 1626-host spine with
nothing and the sweep that followed would report a fleet of zero — and publish
it. So the driver:

1. sources `LSF_PROFILE` and **refuses to continue** unless `lshosts` and
   `bhosts` are genuinely on `PATH` (on this host they are not present on a
   non-interactive SSH `PATH` without it);
2. runs the generator inside a `mktemp -d` **staging directory** — the
   generator writes `./hostlist` relative to its CWD, which is exactly what
   makes it containable;
3. **verifies** the result: every datacenter in `EXPECTED_DCS` present and
   non-empty, a matching `.host-sps` for each, at least `MIN_HOSTS` hosts, and
   at least `MIN_HOST_PERCENT` of what the current list holds;
4. only then **promotes** it, rotating the live directory to `hostlist.prev`.

If verification fails the run dies and **the live hostlist is untouched**. The
`.host-sps` check is not pedantry: a host present in `.hosts` but missing from
`.host-sps` is reported `NO_SP_ENTRY`, so a half-generation would turn the
entire fleet into `NO_SP_ENTRY` rows without ever looking unreachable.

### Running the generator by hand

```bash
cd <project root> && ./do_lsf_generate_hostlist   # writes ./hostlist
wc -l hostlist/*.hosts                            # expect 1626 across six files
```

**Its output is CWD-relative** — run it from anywhere else and you get a stray
`hostlist/` there, so `cd` to the project root first. That is a deliberate
trade for the staging behaviour above. Never trust its exit status; check the
files are non-empty and compare against the expected per-datacenter counts:
atl 620, caco 51, dfdc 315, pldc 339, sadc 139, syco 162.

Do not add `set -u` to it: `/tool/pandora/etc/lsf/profile.lsf` references
`AMDLSFCLUSTER` unguarded and dies under it — which is precisely how an empty
hostlist gets written with a successful exit status.

---

# Reference

## What counts as a finding

Four filters reduce a cumulative log to things worth acting on:

1. `Severity != "OK"`.
2. `Repaired != true` — HPE only; the XCC has no such flag.
3. `Severity == "Critical"` unless `--warnings`.
4. **Category is Hardware or Power** unless `--all-categories`.

Filter 4 earns its place. HPE reports *"Factory Root CA is about to expire"* as
**Critical**, and *"Time & Date Not Set"* as a warning. Neither means a part has
failed. On `atlhwe-lsf309` the category rule is the difference between a
critical alert and the truth, which is three power-supply warnings. An entry is
kept if it carries *at least one* wanted category, so `["Security","Hardware"]`
survives on the strength of `Hardware`.

Lenovo supplies no categories, so `check_lenovo_iml.sh` derives an equivalent
from `Oem.Lenovo.Source` — see `lib/lenovo_map.sh`. An unrecognised source
defaults to `Hardware`, deliberately: the PlatformLog *is* the hardware log, so
an unknown source should stay visible rather than be silently dropped.

**There is no default age cutoff.** The IML never rotates, so a fault stays
until someone marks it repaired. An unrepaired uncorrectable memory error is
still a dead DIMM whether it was logged last night or last year — a silent
90-day window would have reported the test host as healthy. Age is reported
instead, via `FirstSeen` / `LastSeen` / `AgeDays`; `--days` narrows on demand.

### Grouping

One physical fault produces an event storm. `atlhwe-lsf24` logs 104 separate
Class 5/4 records from one failing processor; `atlhwe-lsf88` logs the same
uncorrectable-processor error **499 times**. Entries are grouped by
**(Class, Code, Component)** on HPE and **(CommonEventID, Component)** on
Lenovo, where Component is parsed from the message text or `MessageArgs`.

That is the granularity at which a part gets replaced — two bad DIMMs on one
socket stay two findings, while 499 records from one CPU collapse into one.
`Entries` counts records; `Occurrences` sums HPE's `Count` field, since iLO
pre-coalesces some repeats. Lenovo has no such field, so the two are equal
there.

Leading zeros are stripped from component indices: one XCC writes
`processor 02` and another `processor 2` for the same socket, which would
otherwise produce two differently-named components in the fleet CSV.

### The age filter and its date parser

`jq`'s `fromdateiso8601` accepts only `YYYY-MM-DDTHH:MM:SSZ`, but this fleet's
firmware also emits `2023-08-07T11:48:35.553+00:00` — valid ISO 8601 that jq
rejects. An unparseable timestamp was treated as *keep*, so 131 findings on 93
hosts with a median true age of 223 days sailed through a 7-day window. **The
symptom was that a 7-day run returned more hosts than a 30-day one**, which a
narrower window can never legitimately do.

The fix is a shared `def epoch:` in both vendor scripts; **the two definitions
must stay byte-identical** or the vendors apply different age filters to one
CSV. When a date filter misbehaves, compare the *filter's* parser against the
*display* parser — they were different here, which is why `AgeDays` showed a
correct age on rows that should not have been present at all.

## Vendor differences that matter

| | HPE iLO | Lenovo XCC |
|---|---|---|
| log | `LogServices/IML` | `LogServices/PlatformLog` |
| identity | numeric `Class` + `Code` | `CommonEventID` (`FQXSPPU0002G`) |
| subsystem | `ClassDescription` | `Oem.Lenovo.Source` |
| categories | `Oem.Hpe.Categories` | absent — derived |
| repaired flag | yes | **no** |
| per-entry count | `Oem.Hpe.Count` | **no** |
| recommended action | sometimes | **no** |
| history limit | full log | **1024 entries, hard cap** |

The blank `Class`, `RecommendedAction` and `LearnMoreLink` columns on Lenovo
rows, and `Repaired` always reading `false`, are gaps in the source data — not
unimplemented features. Don't "fix" them by inventing values.

**The 1024-entry cap is real.** `Members@odata.count` reports 1024 and
`?$skip=1024` returns an empty collection. On `atlhwe-lsf171` that window
covered 2026-06-08 to 2026-10-14 while `TotalSequenceNumber` had reached
43,182 — far more history exists on the device than Redfish will hand over. So
a Lenovo `FirstSeen` may be the edge of the window rather than the true first
occurrence. The script warns when it sees exactly 1024.

### The Class integer is not globally unique

The same Class number means different things depending on which firmware
subsystem raised the event; only `ClassDescription` disambiguates:

| Class | ClassDescription | meaning |
|-------|------------------|---------|
| 10 | `UEFI` | BIOS namespace — codes 644 / 1120 / 1126 are **memory** faults |
| 10 | `Storage` | Smart Array controller |
| 11 | `Power` | **power supplies** |
| 11 | `Storage` | drives and energy pack |
| 50 | `UEFI` | Innovation Engine — code 547 is a memory training failure |
| 50 | `System Management` | ASR / recovery events |

`lib/iml_map.sh` does a two-level lookup — `<ClassDescription>:<class>/<code>`
first, then the bare pair — and the subsystem fallback consults
`ClassDescription` **before** the class integer. Getting that order wrong filed
every power-supply event on every Gen11 host as a storage device.

## Output contract

Two files, and **every host is in at least one of them**:

- `findings.csv` — 21 columns, one row per finding. Only hosts with faults.
- `exceptions.csv` — one row per host that contributed no findings, which
  includes healthy hosts (`CLEAN`) as well as every host that could not be read.

"Unreadable" must never be mistaken for "healthy", and a host that silently
fails to appear anywhere is the failure mode this layout exists to prevent.
Because the two files partition the fleet,

```
hosts in findings.csv + rows in exceptions.csv - hosts in both = hosts attempted
```

is an arithmetic identity, and `write_summary` asserts it on every run. A host
can be in both files when it has dated findings *and* suppressed undated ones.
If the identity ever fails, something was dropped and the output is not
trustworthy.

The exception taxonomy is deliberately not one "failed" bucket — collapsing
these sends an operator hunting for a powered-off machine that is really a
missing DNS record:

| status | meaning |
|---|---|
| `CLEAN` | read successfully, no qualifying faults |
| `UNDATED_FINDINGS` | has faults, but none could be placed in the window |
| `NO_SP_ENTRY` | host is in `.hosts` but has no entry in `.host-sps` |
| `NO_SP_DNS` | the SP name does not resolve |
| `SP_UNREACHABLE` | resolves, but nothing answers |
| `SP_HTTP_<code>` | answers, but not with a Redfish service root |
| `VENDOR_UNKNOWN` | answers 200, but is neither HPE nor Lenovo |
| `CREDENTIALS_REJECTED` | reachable, but no configured credential was accepted |
| `PROBE_TIMEOUT` | exceeded `--timeout` seconds |
| `PROBE_ERROR` | the vendor script failed for some other reason |

A probe that pipes a failed curl straight into jq cannot tell the first four
apart — it reports "unknown vendor" for all of them. So the driver resolves DNS
and captures the HTTP status itself, in that order, and only consults the body
for a vendor once it knows a body was returned.

## Credentials

One ordered list, tried in the order written:

```bash
ILO_CREDS=(
  "0:username:password"
  "1:username:password"
)
```

In `creds/ilo_creds` (mode 600) or the environment. No fleet default, no
per-datacenter override — the list is the whole statement of intent.

### The fleet is credential-mixed

Measured: the Gen11 hosts (`atlhwe-lsf309/315/316`) take credential **3**
(`Administrator`), the older atl hosts and both Lenovo machines take **0**, and
`mpcaq-jf37-cm3` takes **1**. No single ordering is right for everything.

So the winning credential **label** is cached per service processor under
`tmp/credmap/`, mirroring `inventory_script`'s production setting. Measured on
`atlhwe-lsf309`: **54s cold, 4s warm** — three failed logins become one
successful one. Only the label is ever written; the password stays in the
credentials file. Do not cache the credential itself, or that directory becomes
a secret store needing the same protection as `creds/`.

### Encryption scheme

Direct RSA, so the plaintext must fit one block (245 bytes for a 2048-bit key;
the file is 109). The key must be **classic PEM RSA** — OpenSSL cannot read the
modern OpenSSH container and ED25519 cannot be used at all, both caught up
front. A wrong key is **refused**: OpenSSL 3.x returns rc=0 and pseudorandom
bytes when PKCS#1 v1.5 unpadding fails, so `bin/ssh_crypt.sh` validates the
padding itself and fails before any byte reaches stdout.

### Lockout safety

After a few rejected logins an iLO answers 401 to *every* login for a window,
valid ones included. A list walked faster than that window locks itself out on
the wrong passwords and then reports the **correct** one as rejected —
indistinguishable from an unknown credential, and the most expensive false
negative this tooling can produce.

So: the first credential goes straight to the real fetch (no probe, no sleep —
zero failed logins on the happy path); candidates 2..N are gated behind a cheap
probe paced at `max(ILO_AUTH_RETRY_DELAY, the SP's published
LoginFailureDelay)`, read unauthenticated and free from `/redfish/v1/`. The
list advances **only** on a genuine 401/403 — a timeout means nothing is
listening and another password proves nothing. A published delay of 0 is a
floor to respect, not proof none applies. **Do not lower
`ILO_AUTH_RETRY_DELAY` to speed up a sweep.**

## Validation

Seven live machines, all passing, every run 4–10s with a warm credential map:

| host | vendor | exit | crit | warn | headline finding |
|---|---|---:|---:|---:|---|
| atlhwe-lsf24 | HPE | 2 | 4 | 3 | CPU 5/4 ×104 + DIMM failure P2 D1 |
| atlhwe-lsf309 | HPE | 1 | 0 | 3 | PSU not redundant, input power loss |
| atlhwe-lsf315 | HPE | 2 | 1 | 5 | fatal init error ×5, 3 degrading DIMMs |
| atlhwe-lsf316 | HPE | 2 | 1 | 3 | fatal init error, DIMM init failure ×6 |
| mpcaq-jf37-cm3 | HPE | 2 | 2 | 0 | UEFI 12647 ×3, NIC slot 10 |
| atlhwe-lsf171 | Lenovo | 2 | 4 | 9 | **both PSUs failed 2026-10-14**; both CPUs degraded |
| atlhwe-lsf88 | Lenovo | 2 | 4 | 3 | **uncorrectable CPU error ×499, still logging today** |

Checks performed:

- **Losslessness** — grouped `Entries` sum to exactly the raw non-OK count on
  both vendors (HPE 196, Lenovo 509), and `Occurrences` to the raw sum of OEM
  `Count` (440).
- **Mutation test** — undercounting each group by one made the losslessness
  check fail (189 ≠ 196), proving the assertion is live, not vacuous.
- **Credential exposure** — sampled `/proc` during a run, resolving
  `/proc/<pid>/exe` and requiring basename `curl`: **180 curl processes
  observed, 0 argv leaks**. The observation count is reported alongside the
  result, because an absence result proves nothing if nothing was running.
- **Encrypted path** — a fixture holding only `ilo_creds.enc`, no plaintext,
  produced identical findings.
- **Contract** — HPE and Lenovo headers byte-identical; 42 concatenated rows
  all 21 columns wide.
- **Exit codes** — critical → 2, warnings-only → 1, empty window → 0,
  unreachable SP → 3.

### Fleet cross-validation

The first unfiltered fleet sweep found **1537 readable / 89 unreadable** of
1626. `inventory_script`'s accepted baseline is **1537 ok / 88 unreachable /
1 auth_failed** — the same split, reached by an entirely separate code path.
That is the strongest available evidence that reachability determination is
correct. **Judge future runs against 1537 readable / 89 unreadable of 1626.**

**Transient drift is normal.** Hosts move between `CLEAN`, `SP_UNREACHABLE` and
`CREDENTIALS_REJECTED` between runs minutes apart, then re-probe clean on
demand. Judge a run by its final totals, never by a ±2 shuffle.

## Implementation notes

Targets **RHEL 7 / bash 4.2**, matching `inventory_script`. No namerefs, no
`wait -n`, and every possibly-empty array expansion is guarded, since bash 4.2
under `set -u` treats `"${arr[@]}"` on an empty declared array as unbound.

Traps found here, all of which produce *silently wrong* output rather than
errors — none caught by `bash -n`:

- **Tab cannot be a field separator.** Tab is IFS *whitespace*, so even with
  `IFS=$'\t'` bash collapses runs and drops empty fields, shifting every later
  column left. Internal streams use **ASCII 31**. This bit the first live run:
  a finding with no Component reported its `Entries` count in the Component
  column and its `LearnMoreLink` under `Repaired`.
- **jq's regex engine does not understand `\uXXXX` in a character class.**
  `gsub("[\\u0000-\\u001f]"; " ")` matches the literal characters `u`, `0`,
  `1`, `f` and the ranges between, quietly deleting letters from every message
  — `CPU` became empty, `Uncorrectable` became `x`.
- **`> /dev/stdout` is not a no-op redirect.** It reopens whatever fd 1 is, and
  silently produced no output on a direct run while the same command redirected
  to a file worked.
- **An `EXIT` trap cannot reference a `local`.** The trap runs after the
  function returns, so under `set -u` it dies with "unbound variable" and the
  work directory is never cleaned up. `WORK_DIR` is global for that reason.
- **The command line is parsed twice** — once to find `--conf`, once after
  sourcing it so the CLI still wins — and `--dc`/`--host` accumulate, so the
  second pass once doubled every filter value and swept each host twice. The
  output looked entirely plausible. `parse_args` resets the filters at entry to
  stay idempotent. **After any argument-parsing change, compare per-datacenter
  dry-run counts against `wc -l` of the `.hosts` files.**
- **`grep -c . file || echo 0` returns `"0\n0"` on an empty file** — grep prints
  `0` *and* exits non-zero, so the `||` fires too. Use `wc -l`.

Zero timestamps (`0000-00-00T00:00:00Z`) appear on roughly a sixth of entries
on every Gen11 host, typically for events logged before the clock was set.
They are normalised to empty rather than treated as a date, which would put a
1900s age in `AgeDays` and sort those rows to the top of any chronological view.

Secrets never reach a process argv: `/proc/<pid>/cmdline` is world-readable, so
credentials go to curl via `--config` fed from a process substitution, and
`printf` plus parameter expansion are builtins, so no child is exec'd holding
the secret.
