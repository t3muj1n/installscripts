#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check_hardware.sh - sweep the fleet's service processors for hardware faults.
# ---------------------------------------------------------------------------
#
#   ./check_hardware.sh                          # whole fleet, all six DCs
#   ./check_hardware.sh --dc atl --jobs 8        # one datacenter
#   ./check_hardware.sh --host atlhwe-lsf24      # a handful of named hosts
#   ./check_hardware.sh --dry-run                # enumerate, probe nothing
#
# This is the FLEET DRIVER. It owns no vendor knowledge: for each host it
# resolves the service processor name, decides HPE vs Lenovo from the
# unauthenticated Redfish service root, and hands the host to
# check_iml/check_hpe_iml.sh or check_iml/check_lenovo_iml.sh. Those two
# scripts own every detail of reading a log, and both emit through
# lib/iml_report.sh, so what this script concatenates is already guaranteed to
# share one 21-column contract.
#
# ---------------------------------------------------------------------------
# TWO OUTPUT FILES, AND EVERY HOST IS IN EXACTLY ONE OF THEM
# ---------------------------------------------------------------------------
#   findings.csv     21 columns, one row per finding. Only hosts that actually
#                    have faults appear, so a host may contribute many rows.
#   exceptions.csv   one row per host that contributed NO findings - which
#                    includes healthy hosts (status CLEAN) as well as every
#                    host that could not be read.
#
# The split is deliberate. "Unreadable" must never be mistaken for "healthy",
# and a host that silently fails to appear anywhere is the failure mode this
# layout exists to prevent. Because the two files partition the fleet,
#
#     hosts in findings.csv  +  rows in exceptions.csv  =  hosts attempted
#
# is an arithmetic identity, and the run summary checks it on every run. If it
# ever fails, something was dropped and the output is not trustworthy.
#
# ---------------------------------------------------------------------------
# THE EXCEPTION TAXONOMY IS NOT ONE "FAILED" BUCKET
# ---------------------------------------------------------------------------
# Collapsing these sends an operator hunting for a powered-off machine that is
# really a missing DNS record:
#
#   CLEAN                 read successfully, no qualifying faults
#   NO_SP_ENTRY           host is in .hosts but has no entry in .host-sps
#   NO_SP_DNS             the SP name does not resolve
#   SP_UNREACHABLE        resolves, but nothing answers (powered off, no route)
#   SP_HTTP_<code>        answers, but not with a Redfish service root
#   VENDOR_UNKNOWN        answers 200, but is neither HPE nor Lenovo
#   CREDENTIALS_REJECTED  reachable, but no configured credential was accepted
#   PROBE_TIMEOUT         exceeded --timeout seconds
#   PROBE_ERROR           the vendor script failed for some other reason
#
# A probe that pipes a failed curl straight into jq cannot tell the first four
# of these apart - it reports "unknown vendor" for all of them. So this script
# resolves DNS and captures the HTTP status itself, in that order, and only
# consults the body for a vendor once it knows a body was actually returned.
#
# ---------------------------------------------------------------------------
# CREDENTIAL ECONOMY AND LOCKOUT
# ---------------------------------------------------------------------------
# The fleet is credential-mixed. A cold run spends a failed login on every
# wrong candidate, and after a few rejections an iLO 401s EVERY login for a
# window - including the correct one. That means a sweep run too fast reports
# valid credentials as rejected. Two mitigations, both already in the libs:
# the learned credential map (tmp/credmap, labels only, never passwords) puts
# the winning credential first on the next run, and the retry pacing is
# max(ILO_AUTH_RETRY_DELAY, the SP's own published LoginFailureDelay).
# Warm the map from a pilot before sweeping the fleet.
#
# Credentials reach the workers through the ENVIRONMENT, never argv: argv is
# world-readable in ps, the environment is not readable across users. Only
# paths are ever forwarded on a child command line.
# ---------------------------------------------------------------------------

set -uo pipefail

# ---------------------------------------------------------------------------
# SCHEDULED-RUN HYGIENE: PATH and umask are established here, not inherited.
# ---------------------------------------------------------------------------
# cron hands a script PATH=/usr/local/bin:/usr/bin and nothing else; a systemd
# unit hands it even less. Inheriting that is the single most common reason a
# scheduled run behaves differently from an interactive one, so establish a
# known-good PATH up front and let the conf's EXTRA_PATH extend it.
#
# Matches run_inventory.sh on this same host deliberately: when two sweeps of
# the same fleet disagree, the toolchain must not be one of the variables.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

# cron and systemd default to umask 022, an interactive login here to 077. The
# cache, credential map and run logs must not become world-readable just
# because the run was scheduled rather than typed. The PUBLISHED copy is
# chmod'ed explicitly to PUBLISH_MODE and is unaffected by this.
umask 077

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
BASE_DIR="$(dirname "$SELF")"
LIB_DIR="${BASE_DIR}/lib"

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=lib/iml_report.sh
source "${LIB_DIR}/iml_report.sh"
# shellcheck source=lib/creds.sh
source "${LIB_DIR}/creds.sh"
# shellcheck source=lib/redfish.sh
source "${LIB_DIR}/redfish.sh"

PROG="$(basename "$SELF")"

# ---------------------------------------------------------------------------
# Defaults. VAR="${VAR:-default}" so an exported value survives; a plain
# assignment would clobber what the caller set.
# ---------------------------------------------------------------------------
CONF_FILE="${CONF_FILE:-${BASE_DIR}/check_hardware.conf}"
CREDS_FILE="${CREDS_FILE:-${BASE_DIR}/creds/ilo_creds}"
# lib/creds.sh references this one WITHOUT a :- default, so it has to be set
# here or the first encrypted load dies with "SSH_CRYPT: unbound variable"
# under set -u. Both vendor scripts define it for the same reason.
SSH_CRYPT="${SSH_CRYPT:-${BASE_DIR}/bin/ssh_crypt.sh}"
TMP_DIR="${TMP_DIR:-${BASE_DIR}/tmp}"
HOSTS_DIR="${HOSTS_DIR:-${BASE_DIR}/hostlist}"
# ---------------------------------------------------------------------------
# Hostlist regeneration from LSF. ON by default, matching run_inventory.sh's
# stage 1. The fleet spine has to track reality: left frozen, a scheduled sweep
# drifts silently - hosts added since the last manual regeneration are never
# checked at all, and decommissioned ones are reported unreachable forever,
# inflating the unreadable count. It also keeps this project and the inventory
# collector reading the SAME fleet, which is what makes their 1537/89 agreement
# mean anything. --no-generate skips it.
# ---------------------------------------------------------------------------
DO_GENERATE="${DO_GENERATE:-1}"
GENERATE_HOSTLIST="${GENERATE_HOSTLIST:-${BASE_DIR}/do_lsf_generate_hostlist}"
# The generator sources this itself. load_lsf_environment sources it as well so
# that lshosts/bhosts can be CHECKED before anything is generated - without
# that check a missing LSF client produces empty host lists and exit status 0.
# Note this is the pandora path the generator uses, not the /tool/lsf/conf one
# run_inventory.sh defaults to; keep it matching the generator.
LSF_PROFILE="${LSF_PROFILE:-/tool/pandora/etc/lsf/profile.lsf}"
EXPECTED_DCS="${EXPECTED_DCS:-atl caco dfdc pldc sadc syco}"
# Floors a generated hostlist must clear before it is allowed to replace the
# live one. MIN_HOSTS is an absolute bound; MIN_HOST_PERCENT compares against
# the CURRENT list, which is what catches a partial LSF answer - non-empty, so
# it passes every other check, but far too small to be the real fleet.
# MIN_HOST_PERCENT=0 disables the comparison for a genuine fleet reduction.
MIN_HOSTS="${MIN_HOSTS:-100}"
MIN_HOST_PERCENT="${MIN_HOST_PERCENT:-80}"
# Local run artifacts (reports/<tag>/findings.csv and friends).
REPORTS_DIR="${REPORTS_DIR:-${BASE_DIR}/reports}"
# Where the finished CSV is PUBLISHED for dashboards and other consumers.
# Empty means publish nothing. Deliberately separate from REPORTS_DIR: the run
# writes locally first and only copies once the file is complete, so a reader
# on the share can never catch a half-written file.
OUTPUT_DIR="${OUTPUT_DIR:-}"
PUBLISH_PREFIX="${PUBLISH_PREFIX:-vbu_hardware_errors}"
# Deliberately NOT derived from PUBLISH_PREFIX. The exceptions file has a
# different schema (6 columns, not 21), so a consumer globbing
# ${PUBLISH_PREFIX}_*.csv must not match it - it would hand a dashboard a
# complete, well-formed file of entirely the wrong shape, which is a worse
# failure than a partial read because nothing looks broken.
PUBLISH_EXCEPTIONS_PREFIX="${PUBLISH_EXCEPTIONS_PREFIX:-vbu_hardware_exceptions}"
PUBLISH_MODE="${PUBLISH_MODE:-664}"
PUBLISH_EXCEPTIONS="${PUBLISH_EXCEPTIONS:-0}"
NO_PUBLISH="${NO_PUBLISH:-0}"
CACHE_DIR="${CACHE_DIR:-}"
CREDMAP_DIR="${CREDMAP_DIR:-${BASE_DIR}/tmp/credmap}"
CHECK_DIR="${CHECK_DIR:-${BASE_DIR}/check_iml}"
JOBS="${JOBS:-24}"
HOST_TIMEOUT="${HOST_TIMEOUT:-120}"
HOST_SUFFIX="${HOST_SUFFIX:-}"
SP_SUFFIX="${SP_SUFFIX:--sp}"
INCLUDE_WARNINGS="${INCLUDE_WARNINGS:-0}"
INCLUDE_REPAIRED="${INCLUDE_REPAIRED:-0}"
ALL_CATEGORIES="${ALL_CATEGORIES:-0}"
USE_CREDMAP="${USE_CREDMAP:-1}"
SINCE_DAYS="${SINCE_DAYS:-}"
SINCE_DATE="${SINCE_DATE:-}"
EXTRA_PATH="${EXTRA_PATH:-}"
# Prefix for an auto-generated run tag, e.g. "prod-" -> prod-20261018-191106.
# Only applies when --run-tag was NOT given. See the note where it is used.
RUN_TAG_PREFIX="${RUN_TAG_PREFIX:-}"
# Where the run writes its own transcript. The script names the log after its
# own run tag, so a scheduled caller does not have to compute a tag in order to
# name a file - it can just run the script.
LOG_DIR="${LOG_DIR:-${TMP_DIR}/logs}"
LOG_FILE=""
# Delete LOCAL run artefacts older than this many days. 0 disables.
# A nightly run leaves ~8 MB of per-host cache, a ~150 KB report directory and
# a small log, so 90 days is roughly 750 MB - almost entirely cache.
# NOTHING on the published share is ever pruned; see prune_old_runs.
RETENTION_DAYS="${RETENTION_DAYS:-90}"
FRESH="${FRESH:-0}"
DRY_RUN="${DRY_RUN:-0}"
RUN_TAG="${RUN_TAG:-}"
DC_FILTER=""
HOST_FILTER=""
WORKER_REC=""
IS_WORKER=0

declare -A CLI_SET=()

usage() {
  cat <<EOF
usage: ${PROG} [options]

Sweep every service processor in hostlist/ for hardware faults, dispatching
each host to the HPE or Lenovo single-host checker according to what its
Redfish service root advertises.

Selection:
  --dc NAME[,NAME]    Only these datacenters (default: all found in
                      ${HOSTS_DIR})
  --host NAME[,NAME]  Only these hosts. Repeatable; also accepts a
                      comma-separated list. Implies no datacenter filter.
  --hosts-file FILE   Read host names from FILE, one per line.

Output:
  --reports-dir DIR   Where this run's own files land, under a per-run
                      subdirectory (default: ${REPORTS_DIR})
  --output-dir DIR    PUBLISH the finished findings CSV here, named
                      ${PUBLISH_PREFIX}_YYYY-MM-DD.csv. The file is staged
                      under a dot-prefixed temporary name in DIR and renamed
                      into place, so a dashboard reading this directory can
                      never see a partial file. Omit to publish nothing.
  --no-publish        Run normally but skip the publish step.
  --publish-exceptions
                      Also publish the exceptions file alongside, as
                      ${PUBLISH_EXCEPTIONS_PREFIX}_YYYY-MM-DD.csv. Worth
                      doing if anything consuming the findings needs to know
                      which hosts could not be read - findings alone cannot
                      distinguish "healthy" from "never answered". The
                      separate prefix is intentional: this file has a
                      different schema and must not match a glob written for
                      the findings file.
  --run-tag TAG       Name this run's output subdirectory. Default is
                      \${RUN_TAG_PREFIX}<timestamp>, with RUN_TAG_PREFIX set
                      in the conf (production uses "prod-", giving
                      prod-20261018-191106). Re-using a tag RESUMES that run
                      from cache, so a scheduled job must never pin one.
                      The run writes its transcript to
                      ${LOG_DIR}/<run-tag>.log and points latest.log at it.
  --warnings          Report Warning findings as well as Critical.
  --include-repaired  Also report entries already marked repaired.
  --all-categories    Report every category, not just hardware faults.
  --days N            Only entries updated within the last N days.
  --since DATE        Only entries updated on or after DATE.

Execution:
  --jobs N            Parallel workers (default: ${JOBS}).
  --timeout N         Per-host wall-clock limit in seconds (default:
                      ${HOST_TIMEOUT}). One dark SP cannot hold a worker slot
                      for an entire credential walk.
  --fresh             Discard cached per-host results and re-probe everything.
                      The cache has no age check, so without this a resumed
                      run re-emits what it already has.
  --no-generate       Do NOT regenerate the host lists from LSF; sweep the
                      existing ${HOSTS_DIR}
                      as it stands. Regeneration is ON by default: a frozen
                      hostlist means hosts added since it was last written are
                      never checked, and decommissioned ones are reported
                      unreachable forever. Use this when LSF is unavailable,
                      when re-running against a known hostlist, or for narrow
                      --host / --dc debugging where rebuilding the whole fleet
                      spine is wasted effort.
  --host-suffix S     Append S to service-processor names that do not already
                      end in it, for environments whose resolver has no
                      matching search domain. MUST be left unset in
                      production, where resolv.conf already supplies it.
  --cache-dir DIR     Per-host result cache (default: under ${TMP_DIR}).
  --credmap-dir DIR   Learned credential map (default: ${CREDMAP_DIR}).
  --no-credmap        Do not read or write the learned credential map.
  --dry-run           Enumerate hosts and resolve SPs, probe nothing.

Configuration:
  --conf FILE         Configuration file (default: ${CONF_FILE})
  --creds FILE        Credentials file (default: ${CREDS_FILE}).
                      An encrypted FILE.enc sidecar is preferred when present.
  -v, --verbose       Debug logging on stderr.
  -h, --help          This text.

Outputs:
  <output-dir>/<tag>/findings.csv     21 columns, hosts WITH faults only
  <output-dir>/<tag>/exceptions.csv   one row per host with no findings,
                                      including healthy hosts (CLEAN) and
                                      hosts whose findings carried no
                                      timestamp (UNDATED_FINDINGS)
  <output-dir>/<tag>/summary.txt      counts, per-datacenter breakdown

Age windows and undated entries:
  When --days or --since is given, a finding whose timestamp is missing or is
  the zero value 0000-00-00T00:00:00Z cannot be placed inside the window, so
  it is NOT reported in findings.csv. It is not discarded either: the host
  gets an UNDATED_FINDINGS row in exceptions.csv naming the count and the
  class/codes. With no window, undated findings are reported as normal.

Exit status:
  0  every host read, nothing found
  1  warnings only
  2  at least one critical finding
  3  nothing found, but at least one host could not be read
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
  local record="${1:-0}"; shift || true
  local a

  # --dc, --host and --hosts-file ACCUMULATE, and main() parses the whole
  # command line twice (once to find --conf, once after sourcing it so the
  # command line still wins). Without this reset the second pass appends every
  # value a second time: "--dc caco" became "caco,caco" and enumerated all 51
  # hosts twice. The run still looked plausible - just double the work and
  # double the rows - which is exactly the kind of failure that gets believed.
  # Resetting here makes parse_args idempotent over the same argv.
  DC_FILTER=""
  HOST_FILTER=""

  while (( $# )); do
    a="$1"
    case "$a" in
      --dc)          DC_FILTER="${DC_FILTER:+${DC_FILTER},}${2:-}"; shift 2 || die "--dc needs a value"
                     (( record )) && CLI_SET[DC_FILTER]=1 ;;
      --host)        HOST_FILTER="${HOST_FILTER:+${HOST_FILTER},}${2:-}"; shift 2 || die "--host needs a value"
                     (( record )) && CLI_SET[HOST_FILTER]=1 ;;
      --hosts-file)  _read_hosts_file "${2:-}"; shift 2 || die "--hosts-file needs a value"
                     (( record )) && CLI_SET[HOST_FILTER]=1 ;;
      --output-dir)  OUTPUT_DIR="${2:-}"; shift 2 || die "--output-dir needs a value"
                     (( record )) && CLI_SET[OUTPUT_DIR]=1 ;;
      --reports-dir) REPORTS_DIR="${2:-}"; shift 2 || die "--reports-dir needs a value"
                     (( record )) && CLI_SET[REPORTS_DIR]=1 ;;
      --no-publish)  NO_PUBLISH=1; shift
                     (( record )) && CLI_SET[NO_PUBLISH]=1 ;;
      --publish-exceptions) PUBLISH_EXCEPTIONS=1; shift
                     (( record )) && CLI_SET[PUBLISH_EXCEPTIONS]=1 ;;
      --run-tag)     RUN_TAG="${2:-}"; shift 2 || die "--run-tag needs a value"
                     (( record )) && CLI_SET[RUN_TAG]=1 ;;
      --jobs)        JOBS="${2:-}"; shift 2 || die "--jobs needs a value"
                     (( record )) && CLI_SET[JOBS]=1 ;;
      --timeout)     HOST_TIMEOUT="${2:-}"; shift 2 || die "--timeout needs a value"
                     (( record )) && CLI_SET[HOST_TIMEOUT]=1 ;;
      --fresh)       FRESH=1; shift
                     (( record )) && CLI_SET[FRESH]=1 ;;
      --no-generate) DO_GENERATE=0; shift
                     (( record )) && CLI_SET[DO_GENERATE]=1 ;;
      --cache-dir)   CACHE_DIR="${2:-}"; shift 2 || die "--cache-dir needs a value"
                     (( record )) && CLI_SET[CACHE_DIR]=1 ;;
      --credmap-dir) CREDMAP_DIR="${2:-}"; shift 2 || die "--credmap-dir needs a value"
                     (( record )) && CLI_SET[CREDMAP_DIR]=1 ;;
      --no-credmap)  USE_CREDMAP=0; shift
                     (( record )) && CLI_SET[USE_CREDMAP]=1 ;;
      --dry-run)     DRY_RUN=1; shift
                     (( record )) && CLI_SET[DRY_RUN]=1 ;;
      --warnings)    INCLUDE_WARNINGS=1; shift
                     (( record )) && CLI_SET[INCLUDE_WARNINGS]=1 ;;
      --include-repaired) INCLUDE_REPAIRED=1; shift
                     (( record )) && CLI_SET[INCLUDE_REPAIRED]=1 ;;
      --all-categories)   ALL_CATEGORIES=1; shift
                     (( record )) && CLI_SET[ALL_CATEGORIES]=1 ;;
      --days)        SINCE_DAYS="${2:-}"; shift 2 || die "--days needs a value"
                     (( record )) && CLI_SET[SINCE_DAYS]=1 ;;
      --since)       SINCE_DATE="${2:-}"; shift 2 || die "--since needs a value"
                     (( record )) && CLI_SET[SINCE_DATE]=1 ;;
      --host-suffix) HOST_SUFFIX="${2:-}"; shift 2 || die "--host-suffix needs a value"
                     (( record )) && CLI_SET[HOST_SUFFIX]=1 ;;
      --conf)        CONF_FILE="${2:-}"; shift 2 || die "--conf needs a value" ;;
      --creds)       CREDS_FILE="${2:-}"; shift 2 || die "--creds needs a value"
                     (( record )) && CLI_SET[CREDS_FILE]=1 ;;
      --worker)      IS_WORKER=1; WORKER_REC="${2:-}"; shift 2 || die "--worker needs a value" ;;
      -v|--verbose)  VERBOSE=1; shift
                     (( record )) && CLI_SET[VERBOSE]=1 ;;
      -h|--help)     usage; exit 0 ;;
      --)            shift; break ;;
      -*)            die "unknown option: ${a}" ;;
      *)             die "unexpected argument: ${a} (did you mean --host ${a}?)" ;;
    esac
  done
}

_read_hosts_file() {
  local f="${1:-}" line
  [[ -r "$f" ]] || die "cannot read hosts file: ${f}"
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line// /}"
    [[ -n "$line" ]] && HOST_FILTER="${HOST_FILTER:+${HOST_FILTER},}${line}"
  done < "$f"
}

load_conf() {
  [[ -r "$CONF_FILE" ]] || { log_debug "no conf file at ${CONF_FILE}"; return 0; }
  log_debug "sourcing ${CONF_FILE}"
  # shellcheck disable=SC1090
  source "$CONF_FILE" || die "failed to source ${CONF_FILE}"
}

# The command line must beat the conf file, and it does so by being parsed
# TWICE - once before load_conf to catch --conf itself, once after to restore
# everything the conf may have overwritten. See main().
#
# This is also why the parent forwards paths onto the worker's command line
# rather than relying on exported values: the worker re-sources the conf on
# startup, and the conf's own assignments would overwrite anything that
# arrived only through the environment.

# ---------------------------------------------------------------------------
# Hostlist regeneration from LSF
#
# Ported from run_inventory.sh's stage 1, and the SHAPE of it matters more than
# it looks. do_lsf_generate_hostlist EXITS 0 HAVING WRITTEN EMPTY FILES when
# LSF is unreachable - its exit status proves nothing at all. Generating
# straight onto hostlist/ would therefore let one bad LSF morning replace a
# good 1626-host spine with nothing, and the sweep that followed would
# cheerfully report a fleet of zero and publish it.
#
# So the order is: check the LSF client is really there, generate into a
# throwaway directory, verify what came out, and only then promote it over the
# live copy. The previous generation is kept as hostlist.prev so a suspicious
# result can be compared against what it replaced.
# ---------------------------------------------------------------------------

# Count hosts across every <dc>.hosts file in a directory. Blank and comment
# lines do not count. grep exits 1 on a zero count, which is not an error here.
count_hosts() {
  local dir="$1" total=0 f n
  for f in "$dir"/*.hosts; do
    [[ -f "$f" ]] || continue
    n=$(grep -cve '^[[:space:]]*$' -e '^[[:space:]]*#' "$f" 2>/dev/null) || n=0
    total=$(( total + n ))
  done
  printf '%s' "$total"
}

load_lsf_environment() {
  if [[ -n "$LSF_PROFILE" && -r "$LSF_PROFILE" ]]; then
    log_info "sourcing LSF profile: ${LSF_PROFILE}"
    # The LSF profile is not written with set -u in mind - it references
    # AMDLSFCLUSTER unguarded and dies under it. That death is precisely how an
    # empty hostlist gets written with a successful exit status, so the guard
    # is load-bearing, not defensive tidiness.
    set +u
    # shellcheck disable=SC1090
    . "$LSF_PROFILE"
    set -u
  elif [[ -n "$LSF_PROFILE" ]]; then
    log_warn "LSF profile not readable: ${LSF_PROFILE}"
  fi

  local missing="" cmd
  for cmd in lshosts bhosts; do
    command -v "$cmd" >/dev/null 2>&1 || missing="${missing} ${cmd}"
  done

  if [[ -n "$missing" ]]; then
    log_error "LSF client commands not found:${missing}"
    log_error "PATH is: ${PATH}"
    log_error "This is the failure a scheduled run is most likely to hit. The"
    log_error "generator does NOT fail when LSF is missing - it exits 0 having"
    log_error "written empty host lists. Point LSF_PROFILE at the profile that"
    log_error "puts lshosts/bhosts on PATH, or pass --no-generate."
    die "refusing to run the generator without a working LSF client"
  fi

  log_info "LSF client: $(command -v lshosts)"
}

# Returns 0 only if the staged hostlist is fit to replace the live one.
verify_generated_hostlists() {
  local dir="$1"
  local dc f n missing="" empty=""

  [[ -d "$dir" ]] || { log_error "generator produced no ${dir}"; return 1; }

  for dc in $EXPECTED_DCS; do
    f="${dir}/${dc}.hosts"
    if [[ ! -f "$f" ]]; then
      missing="${missing} ${dc}"
      continue
    fi
    n=$(grep -cve '^[[:space:]]*$' "$f" 2>/dev/null) || n=0
    (( n > 0 )) || empty="${empty} ${dc}"
    # .host-sps is not optional. build_worklist reads it for the service
    # processor name, and a host absent from it is reported NO_SP_ENTRY - so a
    # generation that produced .hosts but no .host-sps would turn the entire
    # fleet into NO_SP_ENTRY rows without ever looking unreachable.
    [[ -f "${dir}/${dc}.host-sps" ]] || missing="${missing} ${dc}.host-sps"
  done

  if [[ -n "$missing" ]]; then
    log_error "generated host lists are missing:${missing}"
    return 1
  fi
  if [[ -n "$empty" ]]; then
    log_error "generated host lists are empty for:${empty}"
    log_error "that is the signature of an LSF query that returned nothing"
    return 1
  fi

  local new_total
  new_total="$(count_hosts "$dir")"
  if (( new_total < MIN_HOSTS )); then
    log_error "generated only ${new_total} host(s), below the floor of ${MIN_HOSTS}"
    return 1
  fi

  if (( MIN_HOST_PERCENT > 0 )) && [[ -d "$HOSTS_DIR" ]]; then
    local old_total threshold
    old_total="$(count_hosts "$HOSTS_DIR")"
    if (( old_total > 0 )); then
      threshold=$(( old_total * MIN_HOST_PERCENT / 100 ))
      if (( new_total < threshold )); then
        log_error "generated ${new_total} host(s) but the current list has ${old_total}"
        log_error "that is below the ${MIN_HOST_PERCENT}% plausibility threshold of ${threshold}"
        log_error "if the fleet really did shrink, re-run with MIN_HOST_PERCENT=0"
        return 1
      fi
    fi
  fi

  log_info "generated host lists verified: ${new_total} host(s)"
  return 0
}

generate_hostlist() {
  log_info "regenerating host lists from LSF"

  [[ -f "$GENERATE_HOSTLIST" ]] \
    || die "missing host list generator: ${GENERATE_HOSTLIST}"
  [[ -x "$GENERATE_HOSTLIST" ]] \
    || die "host list generator is not executable: ${GENERATE_HOSTLIST}"

  load_lsf_environment

  local staging rc=0
  staging="$(mktemp -d "${TMPDIR:-/tmp}/check_hardware-gen.XXXXXX")" \
    || die "cannot create staging directory"
  log_info "staging in ${staging}"

  # The generator writes ./hostlist relative to its CWD, which is exactly what
  # lets it be contained here. Its exit status is logged but NOT trusted -
  # verification is the gate.
  ( cd "$staging" && "$GENERATE_HOSTLIST" ) || rc=$?
  (( rc == 0 )) || log_warn "host list generator exited ${rc}"

  if ! verify_generated_hostlists "${staging}/hostlist"; then
    rm -rf -- "$staging" 2>/dev/null || true
    die "host list generation failed verification; the live hostlist is untouched"
  fi

  # Promote. Rotate rather than overwrite, so the replaced generation is still
  # on disk if the new one later looks wrong.
  if [[ -d "$HOSTS_DIR" ]]; then
    rm -rf -- "${HOSTS_DIR}.prev" 2>/dev/null || true
    mv -- "$HOSTS_DIR" "${HOSTS_DIR}.prev" || die "cannot rotate ${HOSTS_DIR}"
  fi
  mv -- "${staging}/hostlist" "$HOSTS_DIR" || die "cannot promote host lists"
  rm -rf -- "$staging" 2>/dev/null || true

  log_info "promoted host lists to ${HOSTS_DIR}"
}

# ---------------------------------------------------------------------------
# Host enumeration
#
# The .hosts files are the authoritative spine: every host listed there is
# attempted exactly once and accounted for in the output. The .host-sps files
# supply the service-processor name, which is NOT derivable from the
# datacenter - three conventions are in use (<host>-sp, <host>-ipmi, mp<host>)
# and they do not partition cleanly by DC, so the file is consulted rather
# than guessed. A host with no entry there is reported NO_SP_ENTRY, not
# silently skipped.
# ---------------------------------------------------------------------------
declare -a WORK=()

build_worklist() {
  local f dc host sp
  local -a dcs=()
  local -A want_host=()
  local -A sp_of=()

  [[ -d "$HOSTS_DIR" ]] || die "no hostlist directory at ${HOSTS_DIR}"

  if [[ -n "$HOST_FILTER" ]]; then
    local h
    local IFS=','
    for h in $HOST_FILTER; do
      [[ -n "$h" ]] && want_host["$h"]=1
    done
  fi

  if [[ -n "$DC_FILTER" ]]; then
    local d
    local IFS=','
    for d in $DC_FILTER; do
      [[ -n "$d" ]] && dcs+=("$d")
    done
  else
    for f in "$HOSTS_DIR"/*.hosts; do
      [[ -e "$f" ]] || continue
      d="${f##*/}"; dcs+=("${d%.hosts}")
    done
  fi

  (( ${#dcs[@]} )) || die "no *.hosts files found in ${HOSTS_DIR}"

  for dc in "${dcs[@]}"; do
    local hf="${HOSTS_DIR}/${dc}.hosts"
    local sf="${HOSTS_DIR}/${dc}.host-sps"
    [[ -r "$hf" ]] || { log_warn "no host list for datacenter '${dc}' at ${hf}"; continue; }

    # Index this DC's service processors by the host name they decorate, so
    # the lookup below is a hash hit rather than a grep per host.
    sp_of=()
    if [[ -r "$sf" ]]; then
      while IFS= read -r sp; do
        sp="${sp%%#*}"; sp="${sp// /}"
        [[ -n "$sp" ]] || continue
        sp_of["$(_sp_to_host "$sp")"]="$sp"
      done < "$sf"
    else
      log_warn "no service-processor list for '${dc}' at ${sf}; every host there will be NO_SP_ENTRY"
    fi

    while IFS= read -r host; do
      host="${host%%#*}"; host="${host// /}"
      [[ -n "$host" ]] || continue
      if (( ${#want_host[@]} )); then
        [[ -n "${want_host[$host]:-}" ]] || continue
      fi
      sp="${sp_of[$host]:-}"
      WORK+=("${dc}|${host}|${sp}")
    done < "$hf"
  done

  # A --host that matched nothing is a typo, and silently sweeping zero hosts
  # while reporting success is the worst possible response to one.
  if (( ${#want_host[@]} )); then
    local found=0 rec
    for rec in "${WORK[@]+"${WORK[@]}"}"; do found=$(( found + 1 )); done
    (( found )) || die "none of the requested hosts are in ${HOSTS_DIR}"
    if (( found < ${#want_host[@]} )); then
      log_warn "requested ${#want_host[@]} host(s), matched ${found} in the host lists"
    fi
  fi
}

_sp_to_host() {
  local s="$1"
  case "$s" in
    *-sp)   printf '%s' "${s%-sp}" ;;
    *-ipmi) printf '%s' "${s%-ipmi}" ;;
    *-ilo)  printf '%s' "${s%-ilo}" ;;
    *-mgmt) printf '%s' "${s%-mgmt}" ;;
    mp*)    printf '%s' "${s#mp}" ;;
    *)      printf '%s' "$s" ;;
  esac
}

# ---------------------------------------------------------------------------
# The worker: one host, start to finish.
#
# Writes two artifacts into the cache directory and nothing to stdout, so
# parallel workers cannot interleave into each other's output:
#   <host>.csv     findings rows, headerless (may be absent or empty)
#   <host>.status  dc|host|sp|vendor|status|detail
# ---------------------------------------------------------------------------
run_worker() {
  local rec="$1"
  local dc="${rec%%|*}"; local rest="${rec#*|}"
  local host="${rest%%|*}"; local sp="${rest#*|}"

  local out_csv="${CACHE_DIR}/${host}.csv"
  local out_st="${CACHE_DIR}/${host}.status"

  # Resume: a completed host is skipped unless --fresh cleared the cache. The
  # cache has no age check, which is why --fresh exists.
  if [[ -s "$out_st" ]]; then
    log_debug "${host}: cached, skipping"
    return 0
  fi

  _worker_status() {
    printf '%s|%s|%s|%s|%s|%s\n' "$dc" "$host" "${sp:-}" "${1:-}" "$2" "${3:-}" > "$out_st"
  }

  # --- 1. is there a service processor at all? ---------------------------
  if [[ -z "$sp" ]]; then
    _worker_status "" NO_SP_ENTRY "no entry in ${dc}.host-sps"
    return 0
  fi

  local target
  target="$(apply_host_suffix "$sp" "$HOST_SUFFIX")"

  # --- 2. DNS, on its own ------------------------------------------------
  # Separated from the HTTP attempt deliberately: a name that does not resolve
  # and a machine that is powered off are different problems with different
  # owners, and a combined probe cannot tell them apart.
  if ! getent hosts "$target" >/dev/null 2>&1; then
    if ! host "$target" >/dev/null 2>&1 && ! nslookup "$target" >/dev/null 2>&1; then
      _worker_status "" NO_SP_DNS "${target} does not resolve"
      return 0
    fi
  fi

  # --- 3. the service root: HTTP status and body, in one fetch -----------
  # Unauthenticated, so this costs no login and cannot contribute to lockout.
  local body_f="${CACHE_DIR}/.${host}.root.$$"
  local code
  code="$(curl -s --insecure \
            --connect-timeout "${ILO_CONNECT_TIMEOUT:-10}" --max-time 25 --retry 0 \
            -H 'Accept: application/json' \
            -o "$body_f" -w '%{http_code}' \
            "https://${target}/redfish/v1/" 2>/dev/null)" || code="000"

  if [[ "$code" == "000" ]]; then
    rm -f "$body_f" 2>/dev/null || true
    _worker_status "" SP_UNREACHABLE "${target} resolved but did not answer"
    return 0
  fi
  if [[ "$code" != "200" ]]; then
    rm -f "$body_f" 2>/dev/null || true
    _worker_status "" "SP_HTTP_${code}" "service root returned HTTP ${code}"
    return 0
  fi

  # --- 4. vendor, from a body we know we actually have -------------------
  local vendor
  vendor="$(jq -r 'if (.Vendor // "") != "" then .Vendor
                   elif (.Oem.Hpe // null) != null then "HPE"
                   elif (.Oem.Lenovo // null) != null then "Lenovo"
                   elif ((.Product // "") | test("ProLiant"; "i")) then "HPE"
                   elif ((.Product // "") | test("ThinkSystem"; "i")) then "Lenovo"
                   else "unknown" end' < "$body_f" 2>/dev/null)" || vendor="unknown"
  rm -f "$body_f" 2>/dev/null || true

  local script
  case "$vendor" in
    HPE|hpe|Hewlett*) vendor="HPE";    script="${CHECK_DIR}/check_hpe_iml.sh" ;;
    Lenovo|lenovo)    vendor="Lenovo"; script="${CHECK_DIR}/check_lenovo_iml.sh" ;;
    *)
      _worker_status "${vendor}" VENDOR_UNKNOWN "service root advertises neither HPE nor Lenovo"
      return 0 ;;
  esac
  [[ -x "$script" ]] || { _worker_status "$vendor" PROBE_ERROR "missing checker ${script##*/}"; return 0; }

  # --- 5. hand the host to the vendor checker ----------------------------
  # Paths on argv, credentials in the environment. --sp is passed verbatim so
  # the checker does not redo the host-sps lookup this script already did.
  local -a argv=(
    "$script" --sp "$sp" --no-header --csv --output "$out_csv"
    --conf "$CONF_FILE" --creds "$CREDS_FILE"
    --credmap-dir "$CREDMAP_DIR"
  )
  (( USE_CREDMAP ))       || argv+=( --no-credmap )
  (( INCLUDE_WARNINGS ))  && argv+=( --warnings )
  (( INCLUDE_REPAIRED ))  && argv+=( --include-repaired )
  (( ALL_CATEGORIES ))    && argv+=( --all-categories )
  [[ -n "$SINCE_DAYS" ]]  && argv+=( --days "$SINCE_DAYS" )
  [[ -n "$SINCE_DATE" ]]  && argv+=( --since "$SINCE_DATE" )
  (( VERBOSE ))           && argv+=( -v )
  argv+=( "$host" )

  # Where the checker reports findings it suppressed for having no timestamp.
  # A file rather than a log line, so this does not break when a message is
  # reworded. Cleared first: a stale file from an earlier run would otherwise
  # be read as this run's result.
  local undated_f="${CACHE_DIR}/${host}.undated"
  rm -f "$undated_f" 2>/dev/null || true
  export UNDATED_COUNT_FILE="$undated_f"

  local rc=0
  timeout "$HOST_TIMEOUT" bash "${argv[@]}" >/dev/null 2>>"${CACHE_DIR}/${host}.err" || rc=$?
  unset UNDATED_COUNT_FILE

  # --- 6. translate the checker's exit code ------------------------------
  # Its contract: 0 clean, 1 warnings, 2 critical, 3 unreadable. We already
  # proved the SP answers HTTP 200, so a 3 here means the log itself could not
  # be read - in practice every credential was refused.
  case "$rc" in
    0)   _worker_status "$vendor" CLEAN "" ;;
    1)   _worker_status "$vendor" WARNINGS "" ;;
    2)   _worker_status "$vendor" CRITICAL "" ;;
    3)   _worker_status "$vendor" CREDENTIALS_REJECTED "no configured credential accepted" ;;
    124) _worker_status "$vendor" PROBE_TIMEOUT "exceeded ${HOST_TIMEOUT}s" ;;
    *)   _worker_status "$vendor" PROBE_ERROR "checker exited ${rc}" ;;
  esac

  # A checker that exited non-zero may still have written a partial file.
  [[ -f "$out_csv" && ! -s "$out_csv" ]] && rm -f "$out_csv" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Collection: turn the per-host artifacts into the two output files.
# ---------------------------------------------------------------------------
collect_results() {
  local findings="${RUN_DIR}/findings.csv"
  local exceptions="${RUN_DIR}/exceptions.csv"
  local st dc host sp vendor status detail

  emit_csv_header > "$findings"
  csv_row Host SP Datacenter Vendor Status Detail > "$exceptions"

  local n_find_hosts=0 n_find_rows=0 n_exc=0
  local n_clean=0 n_warn=0 n_crit=0 n_unread=0
  local n_undated_hosts=0 n_both=0

  # Per-datacenter tallies, accumulated here where the facts are rather than
  # reconstructed from the CSVs afterwards by parsing quoted fields.
  DC_SEEN=""
  declare -gA DC_TOTAL=() DC_CRIT=() DC_WARN=() DC_CLEAN=() DC_UNREAD=() DC_UNDATED=()

  local rec rest
  for rec in "${WORK[@]+"${WORK[@]}"}"; do
    rest="${rec#*|}"; host="${rest%%|*}"
    st="${CACHE_DIR}/${host}.status"

    if [[ ! -s "$st" ]]; then
      # No artifact at all: the worker never ran or died outright. This must
      # still produce a row - a missing host is exactly what this file exists
      # to make impossible.
      dc="${rec%%|*}"; sp="${rest#*|}"
      csv_row "$host" "$sp" "$dc" "" "NO_RESULT" "worker produced no result" >> "$exceptions"
      n_exc=$(( n_exc + 1 )); n_unread=$(( n_unread + 1 ))
      continue
    fi

    IFS='|' read -r dc host sp vendor status detail < "$st"

    # Findings the checker suppressed because they carry no timestamp and a
    # window was in effect. These must never just vanish: a host whose only
    # findings were undated would otherwise read CLEAN, which is the exact
    # failure this output layout exists to prevent.
    local und_n=0 und_codes=""
    if [[ -s "${CACHE_DIR}/${host}.undated" ]]; then
      { IFS= read -r und_n; IFS= read -r und_codes; } < "${CACHE_DIR}/${host}.undated" || true
      und_n="${und_n//[^0-9]/}"; und_n="${und_n:-0}"
    fi

    local csv="${CACHE_DIR}/${host}.csv"
    local rows=0
    # wc -l, not `grep -c . || echo 0`: grep exits non-zero when the count is
    # zero, so the || fires AFTER grep has already printed "0" and the
    # substitution becomes the two-line string "0\n0", which then blows up the
    # arithmetic below. Caught by testing the empty case specifically.
    [[ -s "$csv" ]] && rows="$(wc -l < "$csv" 2>/dev/null)"
    rows="${rows//[^0-9]/}"; rows="${rows:-0}"

    if (( rows > 0 )); then
      cat "$csv" >> "$findings"
      n_find_hosts=$(( n_find_hosts + 1 ))
      n_find_rows=$(( n_find_rows + rows ))
    fi

    if (( und_n > 0 )); then
      # Reported whether or not the host also has dated findings, so the
      # suppressed ones are never invisible. A host CAN therefore appear in
      # both files - rare, and counted in n_both so the summary's
      # accountability line stays exact rather than quietly off by one.
      csv_row "$host" "$sp" "$dc" "$vendor" "UNDATED_FINDINGS" \
        "${und_n} finding(s) with no timestamp, excluded by the age window${und_codes:+ (${und_codes})}" \
        >> "$exceptions"
      n_exc=$(( n_exc + 1 ))
      n_undated_hosts=$(( n_undated_hosts + 1 ))
      (( rows > 0 )) && n_both=$(( n_both + 1 ))
    elif (( rows == 0 )); then
      csv_row "$host" "$sp" "$dc" "$vendor" "$status" "$detail" >> "$exceptions"
      n_exc=$(( n_exc + 1 ))
    fi

    [[ -n "${DC_TOTAL[$dc]:-}" ]] || DC_SEEN="${DC_SEEN} ${dc}"
    DC_TOTAL[$dc]=$(( ${DC_TOTAL[$dc]:-0} + 1 ))

    # A host whose findings were ALL suppressed exited the checker as 0 and so
    # carries status CLEAN. Counting it as clean would be a lie - it has
    # findings, they just could not be placed in the window.
    if (( und_n > 0 && rows == 0 )); then
      status="UNDATED_FINDINGS"
    fi

    case "$status" in
      CLEAN)            n_clean=$((  n_clean  + 1 )); DC_CLEAN[$dc]=$((  ${DC_CLEAN[$dc]:-0}  + 1 )) ;;
      WARNINGS)         n_warn=$((   n_warn   + 1 )); DC_WARN[$dc]=$((   ${DC_WARN[$dc]:-0}   + 1 )) ;;
      CRITICAL)         n_crit=$((   n_crit   + 1 )); DC_CRIT[$dc]=$((   ${DC_CRIT[$dc]:-0}   + 1 )) ;;
      UNDATED_FINDINGS) DC_UNDATED[$dc]=$(( ${DC_UNDATED[$dc]:-0} + 1 )) ;;
      *)                n_unread=$(( n_unread + 1 )); DC_UNREAD[$dc]=$(( ${DC_UNREAD[$dc]:-0} + 1 )) ;;
    esac
  done

  R_FIND_HOSTS=$n_find_hosts; R_FIND_ROWS=$n_find_rows; R_EXC=$n_exc
  R_CLEAN=$n_clean; R_WARN=$n_warn; R_CRIT=$n_crit; R_UNREAD=$n_unread
  R_UNDATED=$n_undated_hosts; R_BOTH=$n_both
}

# ---------------------------------------------------------------------------
# Publishing
# ---------------------------------------------------------------------------
# The run writes everything into reports/<tag>/ first and only copies a
# finished file out to the shared directory. That ordering is the whole point:
# a dashboard polling the share must never be able to open a file that is
# still being written.
#
# Copying alone does not achieve that - cp writes incrementally, so a reader
# can open the destination mid-copy and get a truncated CSV. So the copy lands
# on a dot-prefixed temporary name in the SAME directory and is then renamed
# into place. rename(2) within one filesystem is atomic: a reader sees either
# the old file or the complete new one, never a partial.
#
# Returns non-zero on failure but never aborts the run - the local copy is
# already safe on disk, and losing the publish step is not worth discarding a
# completed fleet sweep over.
publish_file() {
  local src="$1" dest_name="$2"
  local dest="${OUTPUT_DIR}/${dest_name}"
  # The temporary name is derived from the RUN TAG, not from dest_name. Two
  # reasons: it cannot collide with a consumer's glob however that glob is
  # written, and two runs overlapping on the same share cannot stage onto each
  # other's temporary file.
  local tmp="${OUTPUT_DIR}/.publish-${RUN_TAG}.$$"

  [[ -r "$src" ]] || { log_warn "publish: ${src} is missing"; return 1; }

  if ! cp -f -- "$src" "$tmp" 2>/dev/null; then
    log_warn "publish: cannot write to ${OUTPUT_DIR} (${dest_name} not published)"
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi
  # Mode before the rename, so the file is never briefly visible at the
  # collector's restrictive umask once it appears under its real name.
  chmod "$PUBLISH_MODE" "$tmp" 2>/dev/null \
    || log_warn "publish: ${dest_name} left at the umask default, not ${PUBLISH_MODE}"
  if ! mv -f -- "$tmp" "$dest" 2>/dev/null; then
    log_warn "publish: could not move into place as ${dest}"
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi

  local bytes; bytes="$(wc -c < "$dest" 2>/dev/null || echo '?')"
  log_info "published : ${dest} (${bytes} bytes, mode ${PUBLISH_MODE})"
  return 0
}

publish_results() {
  local stamp; stamp="$(date '+%Y-%m-%d')"

  if (( NO_PUBLISH )); then
    log_info "--no-publish: results stay in ${RUN_DIR}"
    return 0
  fi
  if [[ -z "$OUTPUT_DIR" ]]; then
    log_debug "no --output-dir set; nothing published"
    return 0
  fi
  if [[ ! -d "$OUTPUT_DIR" ]]; then
    # Deliberately not created: a typo in --output-dir should be an error, not
    # a new directory in the wrong place on a shared filesystem.
    log_warn "publish: ${OUTPUT_DIR} does not exist; nothing published"
    return 1
  fi
  # Checked up front rather than inferred from a failed cp, so an unmounted or
  # read-only share reports the actual cause instead of "cannot write".
  if [[ ! -w "$OUTPUT_DIR" ]]; then
    log_warn "publish: ${OUTPUT_DIR} is not writable; nothing published"
    return 1
  fi

  publish_file "${RUN_DIR}/findings.csv" "${PUBLISH_PREFIX}_${stamp}.csv"
  (( PUBLISH_EXCEPTIONS )) && \
    publish_file "${RUN_DIR}/exceptions.csv" "${PUBLISH_EXCEPTIONS_PREFIX}_${stamp}.csv"
  return 0
}

write_summary() {
  local total="${#WORK[@]}"
  local summary="${RUN_DIR}/summary.txt"
  # A host with dated findings AND suppressed undated ones is in both files,
  # so it would otherwise be counted twice here. Subtracting the overlap keeps
  # this an exact identity instead of an approximation that drifts.
  local accounted=$(( R_FIND_HOSTS + R_EXC - R_BOTH ))

  {
    printf 'check_hardware run %s\n' "$RUN_TAG"
    printf 'finished   : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'hosts       : %d attempted\n' "$total"
    printf '\n'
    printf 'findings.csv   : %d row(s) from %d host(s)\n' "$R_FIND_ROWS" "$R_FIND_HOSTS"
    printf 'exceptions.csv : %d row(s)\n' "$R_EXC"
    printf '\n'
    printf 'accountability : %d + %d - %d both = %d of %d %s\n' \
      "$R_FIND_HOSTS" "$R_EXC" "$R_BOTH" "$accounted" "$total" \
      "$( (( accounted == total )) && printf 'OK' || printf '*** MISMATCH - hosts were dropped ***' )"
    printf '\n'
    printf 'by status:\n'
    printf '  critical            %d\n' "$R_CRIT"
    printf '  warnings            %d\n' "$R_WARN"
    printf '  clean               %d\n' "$R_CLEAN"
    printf '  undated findings    %d\n' "$R_UNDATED"
    printf '  unreadable          %d\n' "$R_UNREAD"
    printf '\n'
    printf 'exception breakdown:\n'
    if [[ -s "${RUN_DIR}/exceptions.csv" ]]; then
      # Field 5 is Status. Every field is quoted by csv_row, so splitting on
      # '","' is safe here even though it would not be for arbitrary CSV.
      tail -n +2 "${RUN_DIR}/exceptions.csv" \
        | awk -F'","' '{gsub(/"/,"",$5); print $5}' \
        | sort | uniq -c | sort -rn \
        | awk '{printf "  %-22s %s\n", $2, $1}'
    fi
    printf '\n'
    printf 'by datacenter:\n'
    printf '  %-8s %7s %8s %7s %7s %7s %10s\n' \
      dc total critical warning clean undated unreadable
    local d
    for d in $DC_SEEN; do
      printf '  %-8s %7d %8d %7d %7d %7d %10d\n' "$d" \
        "${DC_TOTAL[$d]:-0}" "${DC_CRIT[$d]:-0}" "${DC_WARN[$d]:-0}" \
        "${DC_CLEAN[$d]:-0}" "${DC_UNDATED[$d]:-0}" "${DC_UNREAD[$d]:-0}"
    done
  } > "$summary"

  cat "$summary" >&2
  R_ACCOUNTED=$accounted
}

# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------
# Prunes LOCAL run artefacts older than RETENTION_DAYS: reports/<tag>/,
# tmp/fleet/<tag>/ and tmp/logs/<tag>.log.
#
# ** THE PUBLISHED SHARE IS NEVER TOUCHED. ** Note the trap: in this project
# OUTPUT_DIR *is* /proj/emu_share/..., whereas in the sibling inventory_script
# OUTPUT_DIR is a local directory and the share is PUBLISH_DIR. The same name
# means opposite things in the two trees, so porting its prune verbatim would
# start deleting dated CSVs out from under whatever consumes them. Retention
# here is deliberately confined to paths beneath this project.
#
# Two further rails, because this is the only code in the tree that deletes
# recursively:
#   - a directory is removed only if it CONTAINS THE FILES THIS SCRIPT WRITES.
#     Anything else parked in reports/ is left alone rather than trusted to a
#     name pattern, which cannot be relied on when --run-tag takes any string.
#   - the current run is skipped explicitly. A wrong clock or a mistyped
#     RETENTION_DAYS must never be able to delete the sweep that just finished.
prune_old_runs() {
  (( RETENTION_DAYS > 0 )) || { log_debug "retention disabled"; return 0; }

  local d n_rep=0 n_cache=0 n_log=0
  local verb="removed"; (( DRY_RUN )) && verb="would remove"

  # reports/<tag>/ - keep only directories holding this script's own output.
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    [[ "$d" == "$RUN_DIR" ]] && continue
    [[ -f "${d}/summary.txt" || -f "${d}/findings.csv" ]] || continue
    (( DRY_RUN )) || rm -rf -- "$d" 2>/dev/null || continue
    n_rep=$(( n_rep + 1 ))
  done < <(find "$REPORTS_DIR" -mindepth 1 -maxdepth 1 -type d \
             -mtime "+${RETENTION_DAYS}" 2>/dev/null)

  # tmp/fleet/<tag>/ - the per-host cache, and much the largest of the three.
  # CACHE_DIR has already been extended to include the run tag by this point,
  # so prune its PARENT.
  local cache_root="${CACHE_DIR%/*}"
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    [[ "$d" == "$CACHE_DIR" ]] && continue
    # A cache dir holds per-host .status files; nothing else should.
    compgen -G "${d}/*.status" >/dev/null 2>&1 || continue
    (( DRY_RUN )) || rm -rf -- "$d" 2>/dev/null || continue
    n_cache=$(( n_cache + 1 ))
  done < <(find "$cache_root" -mindepth 1 -maxdepth 1 -type d \
             -mtime "+${RETENTION_DAYS}" 2>/dev/null)

  # tmp/logs/<tag>.log - regular files only, so latest.log (a symlink) is never
  # a candidate.
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    [[ "$d" == "$LOG_FILE" ]] && continue
    (( DRY_RUN )) || rm -f -- "$d" 2>/dev/null || continue
    n_log=$(( n_log + 1 ))
  done < <(find "$LOG_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.log' \
             -mtime "+${RETENTION_DAYS}" 2>/dev/null)

  # Pruning the target leaves latest.log dangling, which is worse than absent:
  # `tail -f tmp/logs/latest.log` would fail with a confusing error.
  if [[ -L "${LOG_DIR}/latest.log" && ! -e "${LOG_DIR}/latest.log" ]]; then
    (( DRY_RUN )) || rm -f -- "${LOG_DIR}/latest.log" 2>/dev/null || true
    log_debug "removed dangling latest.log"
  fi

  if (( n_rep || n_cache || n_log )); then
    log_info "retention  : ${verb} ${n_rep} report dir(s), ${n_cache} cache dir(s), ${n_log} log(s) older than ${RETENTION_DAYS}d"
  else
    log_debug "retention  : nothing older than ${RETENTION_DAYS}d"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Run transcript
# ---------------------------------------------------------------------------
# From here on, stdout and stderr go to BOTH the console and the run log, so
# the on-disk transcript and whatever cron mails out say the same thing. The
# log is named after the run tag, which is what lets a scheduled caller invoke
# the script with no arguments at all instead of computing a tag, exporting it,
# and redirecting by hand.
#
# Workers are skipped deliberately: 24 of them inherit this stdout already, so
# their output is captured by the parent's tee. Letting each one open the same
# file would interleave 24 writers on one descriptor.
#
# A log directory that cannot be created WARNS rather than aborting - losing
# the transcript is not a reason to skip a fleet sweep.
start_logging() {
  (( IS_WORKER )) && return 0
  (( DRY_RUN ))   && return 0

  if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    log_warn "cannot create ${LOG_DIR}; console only, no transcript"
    return 0
  fi
  LOG_FILE="${LOG_DIR}/${RUN_TAG}.log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  # Relative target, so the symlink survives the tree being moved or copied.
  ln -sfn "${RUN_TAG}.log" "${LOG_DIR}/latest.log" 2>/dev/null || true
  log_info "log        : ${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  parse_args 1 "$@"
  load_conf
  parse_args 1 "$@"

  # APPENDED, not prepended. /tool/pandora64/bin on this host shadows ten core
  # utilities - date, curl, grep, sed, awk, cut, sort, python3, openssl, xargs -
  # with different GNU versions (awk 5.0 vs 4.2, grep 2.28 vs 3.1, and so on).
  # Prepending silently swapped the whole toolchain underneath a script written
  # and validated against the system one; the age filter in particular leans on
  # `date` semantics. Appending keeps system binaries authoritative and lets
  # EXTRA_PATH supply only what is genuinely missing, which here is jq alone.
  # run_inventory.sh appends for exactly this reason - keep the two in step.
  [[ -n "$EXTRA_PATH" ]] && PATH="${PATH}:${EXTRA_PATH}"
  export PATH
  # The vendor checkers read HOST_SUFFIX from their environment - they have no
  # flag for it - so it must be exported, not merely set.
  export HOST_SUFFIX

  : "${CACHE_DIR:=${TMP_DIR}/fleet}"

  if (( IS_WORKER )); then
    # The worker inherits credentials through the environment; everything it
    # needs on argv was forwarded by the parent.
    creds_import_env
    creds_parse
    run_worker "$WORKER_REC"
    return $?
  fi

  # RUN_TAG_PREFIX comes from the conf and only ever labels an AUTO-GENERATED
  # tag; an explicit --run-tag is taken verbatim. The timestamp is always
  # appended, which is the point: a conf cannot pin RUN_TAG to a fixed string,
  # because reusing a tag re-reads the per-host cache (which has no age check)
  # and a scheduled job would then re-emit yesterday's findings forever.
  [[ -n "$RUN_TAG" ]] || RUN_TAG="${RUN_TAG_PREFIX}$(date '+%Y%m%d-%H%M%S')"
  RUN_DIR="${REPORTS_DIR}/${RUN_TAG}"
  CACHE_DIR="${CACHE_DIR}/${RUN_TAG}"

  start_logging

  # Deliberately AFTER start_logging. A scheduled run that dies here - jq not
  # on PATH is the realistic case - is precisely the one whose error has to
  # reach the transcript rather than only an unread cron mail.
  require_cmd curl jq timeout

  # Regenerate the fleet spine BEFORE enumerating it, so the sweep reflects
  # what LSF says the fleet is today rather than whatever was last written by
  # hand. Deliberately after start_logging, so a failure here - a missing LSF
  # client being the realistic one - lands in the transcript.
  if (( DO_GENERATE )); then
    if (( DRY_RUN )); then
      log_info "dry run: would regenerate host lists with ${GENERATE_HOSTLIST}"
      log_info "dry run: would verify the result and promote it over ${HOSTS_DIR}"
      log_info "dry run: host counts below are from the EXISTING hostlist"
    else
      generate_hostlist
    fi
  else
    log_info "--no-generate: sweeping the existing host lists in ${HOSTS_DIR}"
  fi

  build_worklist
  local total="${#WORK[@]}"
  (( total )) || die "no hosts to check"

  if (( DRY_RUN )); then
    log_info "dry run: ${total} host(s) would be checked"
    local rec dc host sp
    for rec in "${WORK[@]}"; do
      dc="${rec%%|*}"; rest="${rec#*|}"; host="${rest%%|*}"; sp="${rest#*|}"
      printf '%-10s %-24s %s\n' "$dc" "$host" "${sp:-<NO SP ENTRY>}"
    done
    # Previewed here too, so --dry-run answers "what would this run delete?"
    # as well as "what would it check". Retention is the only destructive thing
    # the script does, which makes it the part most worth being able to inspect
    # without committing to it.
    prune_old_runs
    return 0
  fi

  mkdir -p "$RUN_DIR" "$CACHE_DIR" || die "cannot create output directories"
  (( USE_CREDMAP )) && { mkdir -p "$CREDMAP_DIR" 2>/dev/null || true; }
  # Not used by this script - run logs are produced by shell redirection in the
  # documented detached-launch pattern and by the systemd unit. Created here so
  # that `> tmp/logs/$TAG.log` cannot fail on a fresh checkout. Best effort: a
  # read-only tree is not a reason to refuse to run.
  mkdir -p "${TMP_DIR}/logs" 2>/dev/null || true

  if (( FRESH )); then
    log_info "--fresh: discarding cached per-host results"
    # Deliberately NOT the credential map: re-learning which password each SP
    # takes would cost a failed login on every host and risks lockout.
    rm -f "${CACHE_DIR}"/*.status "${CACHE_DIR}"/*.csv "${CACHE_DIR}"/*.err \
          "${CACHE_DIR}"/*.undated 2>/dev/null || true
  fi

  load_creds
  creds_parse
  local ncred; ncred="$(creds_count)"
  (( ncred )) || log_warn "no credentials loaded; every host will report CREDENTIALS_REJECTED"
  log_info "credentials: ${ncred} candidate(s) (${CRED_LABELS[*]+${CRED_LABELS[*]}})"
  # Record WHICH file they came from and whether it was encrypted. Once the
  # plaintext is deleted, this log line is the only thing that can answer
  # "was that run actually reading the encrypted file?" after the fact.
  if [[ -n "${CREDS_SOURCE:-}" ]]; then
    if (( CREDS_ENCRYPTED )); then
      log_info "creds      : encrypted at rest (${CREDS_SOURCE})"
    else
      log_warn "creds      : PLAINTEXT on disk (${CREDS_SOURCE}) - encrypt it with ssh_crypt.sh"
    fi
  fi
  creds_export_env

  log_info "checking ${total} host(s) with ${JOBS} parallel worker(s), ${HOST_TIMEOUT}s per host"
  log_info "run tag ${RUN_TAG}; results under ${RUN_DIR}"

  # Paths are forwarded on the child command line because the child re-sources
  # the conf file on startup, and the conf's own assignments would otherwise
  # overwrite the exported values. Paths only - a credential on argv would be
  # visible to every user on the box via ps.
  local -a fwd=( --conf "$CONF_FILE" --creds "$CREDS_FILE"
                 --cache-dir "$CACHE_DIR" --credmap-dir "$CREDMAP_DIR"
                 --timeout "$HOST_TIMEOUT" )
  (( USE_CREDMAP ))      || fwd+=( --no-credmap )
  (( INCLUDE_WARNINGS )) && fwd+=( --warnings )
  (( INCLUDE_REPAIRED )) && fwd+=( --include-repaired )
  (( ALL_CATEGORIES ))   && fwd+=( --all-categories )
  [[ -n "$SINCE_DAYS" ]] && fwd+=( --days "$SINCE_DAYS" )
  [[ -n "$SINCE_DATE" ]] && fwd+=( --since "$SINCE_DATE" )
  [[ -n "$HOST_SUFFIX" ]] && fwd+=( --host-suffix "$HOST_SUFFIX" )
  (( VERBOSE ))          && fwd+=( -v )

  local started; started="$(now_epoch)"
  printf '%s\n' "${WORK[@]}" \
    | xargs -P "$JOBS" -I CHREC bash "$SELF" "${fwd[@]}" --worker CHREC
  local elapsed=$(( $(now_epoch) - started ))

  collect_results
  write_summary
  # Publish only after collect_results and write_summary have returned, so the
  # file that leaves this machine is a finished one.
  publish_results
  # Last, so a retention problem can never cost a completed sweep its output.
  prune_old_runs
  log_info "swept ${total} host(s) in ${elapsed}s"

  # Exit status mirrors the single-host contract, worst-first.
  (( R_CRIT ))   && return 2
  (( R_WARN ))   && return 1
  (( R_UNREAD )) && return 3
  return 0
}

main "$@"
