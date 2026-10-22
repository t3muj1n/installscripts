#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check_hpe_iml.sh - read one HPE iLO's Integrated Management Log over Redfish
#                    and report the hardware faults in it.
# ---------------------------------------------------------------------------
#
#   ./check_hpe_iml.sh atlhwe-lsf24-sp              # CSV of critical findings
#   ./check_hpe_iml.sh --report --warnings  <sp>    # readable, incl. warnings
#   ./check_hpe_iml.sh --days 90 <sp>               # only recent activity
#
# This is the SINGLE-HOST script. check_hardware.sh drives it across the fleet
# using the hostlist/*.hosts and hostlist/*.host-sps files; the Lenovo
# equivalent is check_lenovo_iml.sh. Keeping one host's logic here means it can
# be run by hand against a machine someone is standing in front of, which is
# how it gets trusted.
#
# ---------------------------------------------------------------------------
# WHAT COUNTS AS A FINDING
# ---------------------------------------------------------------------------
# The IML is cumulative and never rotates, so most of what is in it is history
# and noise. Three filters reduce it to things a technician would act on:
#
#   1. Severity != "OK"      - the top-level Redfish Severity, not the OEM one.
#   2. Repaired != true      - somebody already dealt with it.
#   3. Severity == "Critical" unless --warnings is given.
#
# There is deliberately NO default age cutoff. An unrepaired uncorrectable
# memory error matters whether it happened last night or last year, and a
# silent 90-day window would have reported the test host as healthy when it has
# a dead DIMM. Age is made visible instead, via the FirstSeen / LastSeen /
# AgeDays columns, and --days narrows it when you want only recent activity.
#
# ---------------------------------------------------------------------------
# WHY FINDINGS ARE GROUPED
# ---------------------------------------------------------------------------
# One physical fault produces an event storm. The test host logs 104 separate
# Class 5 / Code 4 entries, each a machine-check register dump differing only
# in its hex payload, from a single failing processor. Reporting those as 104
# findings buries the five things that actually need attention.
#
# Entries are therefore grouped by (Class, Code, Component), where Component is
# parsed out of the message text - "Processor 2, DIMM 1" and so on. That is the
# granularity at which a part gets replaced, which is what makes it the right
# grouping key: two bad DIMMs on one processor stay two findings, while 104
# register dumps from one CPU collapse into one.
#
# Entries reports how many IML records are in the group; Occurrences sums the
# OEM Count field, since iLO itself already coalesces some repeats.
# ---------------------------------------------------------------------------

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SELF")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="${BASE_DIR}/lib"

# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"
# The CSV column contract, IML_SEP and both renderers live here, shared with
# check_lenovo_iml.sh so the two vendors cannot drift apart.
# shellcheck source=../lib/iml_report.sh
source "${LIB_DIR}/iml_report.sh"
# shellcheck source=../lib/iml_map.sh
source "${LIB_DIR}/iml_map.sh"
# shellcheck source=../lib/creds.sh
source "${LIB_DIR}/creds.sh"
# shellcheck source=../lib/redfish.sh
source "${LIB_DIR}/redfish.sh"

PROG="$(basename "$SELF")"

# ---------------------------------------------------------------------------
# Defaults. Every one of these is overridable by the conf file, and the conf
# file is in turn overridden by the command line - see main().
#
# Written as VAR="${VAR:-default}" rather than VAR=default so an exported
# value survives. A plain assignment here would silently clobber anything the
# caller set in the environment.
# ---------------------------------------------------------------------------
CONF_FILE="${CONF_FILE:-${BASE_DIR}/check_hardware.conf}"
CREDS_FILE="${CREDS_FILE:-${BASE_DIR}/creds/ilo_creds}"
SSH_CRYPT="${SSH_CRYPT:-${BASE_DIR}/bin/ssh_crypt.sh}"
TMP_DIR="${TMP_DIR:-${BASE_DIR}/tmp}"
HOSTS_DIR="${HOSTS_DIR:-${BASE_DIR}/hostlist}"
SP_SUFFIX="${SP_SUFFIX:--sp}"
HOST_SUFFIX="${HOST_SUFFIX:-}"
INCLUDE_WARNINGS="${INCLUDE_WARNINGS:-0}"
INCLUDE_REPAIRED="${INCLUDE_REPAIRED:-0}"
ALL_CATEGORIES="${ALL_CATEGORIES:-0}"
HW_CATEGORIES="${HW_CATEGORIES:-Hardware Power}"
CREDMAP_DIR="${CREDMAP_DIR:-${BASE_DIR}/tmp/credmap}"
USE_CREDMAP="${USE_CREDMAP:-1}"
SINCE_DAYS="${SINCE_DAYS:-}"
SINCE_DATE="${SINCE_DATE:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-csv}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
PRINT_HEADER="${PRINT_HEADER:-1}"
EXTRA_PATH="${EXTRA_PATH:-}"

TARGET=""
SP_OVERRIDE=""
HOST_NAME=""
SP_NAME=""
WORK_DIR=""

# CLI values are recorded separately so they can be re-applied after the conf
# file is sourced. Without this the conf would win, which is backwards.
declare -A CLI_SET=()

usage() {
  cat <<EOF
usage: ${PROG} [options] <host-or-sp>

Read an HPE iLO's Integrated Management Log over Redfish and report the
hardware faults recorded in it.

Target:
  <host-or-sp>        Service processor name (atlhwe-lsf24-sp) or the host
                      name (atlhwe-lsf24), in which case ${SP_SUFFIX} is
                      appended, or hostlist/*.host-sps consulted when present.

Options:
  --sp NAME           Use this service processor name verbatim.
  --conf FILE         Configuration file (default: ${CONF_FILE})
  --creds FILE        Credentials file (default: ${CREDS_FILE})
                      An encrypted FILE.enc sidecar is preferred when present.
  --warnings          Report Warning findings as well as Critical.
  --include-repaired  Also report entries already marked repaired.
  --all-categories    Report every category, not just hardware faults.
                      By default only entries HPE categorises as Hardware or
                      Power are reported, because the firmware marks things
                      like "Factory Root CA is about to expire" Critical even
                      though no part has failed.
  --no-credmap        Do not read or write the learned credential map.
  --credmap-dir DIR   Learned credential map location
                      (default: ${CREDMAP_DIR}). Stores the winning credential
                      LABEL per service processor, never a password.
  --days N            Only entries updated within the last N days.
  --since DATE        Only entries updated on or after DATE (any date(1) form).
  --report            Human-readable output instead of CSV.
  --csv               CSV output (the default).
  --output FILE       Write to FILE instead of stdout.
  --no-header         Omit the CSV header line.
  -v, --verbose       Debug logging on stderr.
  -h, --help          This text.

Credentials:
  Set ILO_CREDS in the credentials file or the environment, as an ordered list
  tried in the order written:

      ILO_CREDS=( "0:username:password" "1:username:password" )

Exit status:
  0  no findings
  1  warnings only
  2  at least one critical finding
  3  the service processor could not be read (unreachable, or every
     credential refused) - note this is NOT the same as "healthy"
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
  local record="${1:-0}"; shift || true
  local a
  while (( $# )); do
    a="$1"
    case "$a" in
      --sp)        SP_OVERRIDE="${2:-}"; shift 2 || die "--sp needs a value"
                   (( record )) && CLI_SET[SP_OVERRIDE]=1 ;;
      --conf)      CONF_FILE="${2:-}";   shift 2 || die "--conf needs a value" ;;
      --creds)     CREDS_FILE="${2:-}";  shift 2 || die "--creds needs a value"
                   (( record )) && CLI_SET[CREDS_FILE]=1 ;;
      --warnings)  INCLUDE_WARNINGS=1; shift
                   (( record )) && CLI_SET[INCLUDE_WARNINGS]=1 ;;
      --include-repaired) INCLUDE_REPAIRED=1; shift
                   (( record )) && CLI_SET[INCLUDE_REPAIRED]=1 ;;
      --all-categories) ALL_CATEGORIES=1; shift
                   (( record )) && CLI_SET[ALL_CATEGORIES]=1 ;;
      --no-credmap) USE_CREDMAP=0; shift
                   (( record )) && CLI_SET[USE_CREDMAP]=1 ;;
      --credmap-dir) CREDMAP_DIR="${2:-}"; shift 2 || die "--credmap-dir needs a value"
                   (( record )) && CLI_SET[CREDMAP_DIR]=1 ;;
      --days)      SINCE_DAYS="${2:-}";  shift 2 || die "--days needs a value"
                   (( record )) && CLI_SET[SINCE_DAYS]=1 ;;
      --since)     SINCE_DATE="${2:-}";  shift 2 || die "--since needs a value"
                   (( record )) && CLI_SET[SINCE_DATE]=1 ;;
      --report)    OUTPUT_FORMAT="report"; shift
                   (( record )) && CLI_SET[OUTPUT_FORMAT]=1 ;;
      --csv)       OUTPUT_FORMAT="csv"; shift
                   (( record )) && CLI_SET[OUTPUT_FORMAT]=1 ;;
      --output|-o) OUTPUT_FILE="${2:-}"; shift 2 || die "--output needs a value"
                   (( record )) && CLI_SET[OUTPUT_FILE]=1 ;;
      --no-header) PRINT_HEADER=0; shift
                   (( record )) && CLI_SET[PRINT_HEADER]=1 ;;
      -v|--verbose) VERBOSE=1; shift
                   (( record )) && CLI_SET[VERBOSE]=1 ;;
      -h|--help)   usage; exit 0 ;;
      --)          shift; break ;;
      -*)          die "unknown option: ${a}" ;;
      *)           TARGET="$a"; shift
                   (( record )) && CLI_SET[TARGET]=1 ;;
    esac
  done
}

# Re-apply the values that came from the command line, so they beat the conf
# file. parse_args is called twice: once to learn what the CLI said, then the
# conf is sourced, then again to put the CLI back on top.
load_conf() {
  [[ -n "$CONF_FILE" && -r "$CONF_FILE" ]] || {
    [[ -n "$CONF_FILE" && -e "$CONF_FILE" ]] && log_warn "cannot read ${CONF_FILE}"
    return 0
  }
  log_debug "reading configuration ${CONF_FILE}"
  # shellcheck disable=SC1090
  source "$CONF_FILE"
}

# ---------------------------------------------------------------------------
# Target resolution
# ---------------------------------------------------------------------------

# Work out which name to talk to. An explicit --sp wins. Otherwise, if the
# target already looks like a service processor name (it is present in a
# hostlist/*.host-sps file, or already carries the suffix) use it as-is;
# otherwise append the suffix.
#
# The host-sps files are consulted rather than assumed because the six
# datacenters use three different conventions (-sp, -ipmi, mp<host>). Guessing
# would time out against a name that never existed.
resolve_sp() {
  local t="$TARGET" f base cand

  if [[ -n "$SP_OVERRIDE" ]]; then
    SP_NAME="$SP_OVERRIDE"
    HOST_NAME="${t:-$SP_OVERRIDE}"
    return 0
  fi

  [[ -n "$t" ]] || die "no target given; see --help"

  # Does any datacenter's service-processor list contain this name verbatim?
  if [[ -d "$HOSTS_DIR" ]]; then
    for f in "$HOSTS_DIR"/*.host-sps; do
      [[ -e "$f" ]] || continue
      if grep -qxF -- "$t" "$f" 2>/dev/null; then
        SP_NAME="$t"
        base="$(_sp_to_host "$t")"
        HOST_NAME="$base"
        log_debug "${t} found in ${f##*/}"
        return 0
      fi
    done
    # Not an SP name - try to map the host name through the lists.
    for f in "$HOSTS_DIR"/*.host-sps; do
      [[ -e "$f" ]] || continue
      for cand in "${t}${SP_SUFFIX}" "${t}-sp" "${t}-ipmi" "mp${t}"; do
        if grep -qxF -- "$cand" "$f" 2>/dev/null; then
          SP_NAME="$cand"; HOST_NAME="$t"
          log_debug "${t} -> ${cand} via ${f##*/}"
          return 0
        fi
      done
    done
  fi

  # No host lists yet, or the name is in neither. Fall back to the suffix rule.
  case "$t" in
    *-sp|*-ipmi|*-ilo|*-mgmt|mp*)
      SP_NAME="$t"; HOST_NAME="$(_sp_to_host "$t")" ;;
    *)
      SP_NAME="${t}${SP_SUFFIX}"; HOST_NAME="$t" ;;
  esac
  return 0
}

# Strip a known service-processor decoration to recover the host name. Best
# effort only - it is cosmetic, used to fill the Host column.
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
# The jq program that does the filtering and grouping.
#
# Kept in one place rather than scattered through shell pipelines: the
# component regexes and the grouping key are the two things most likely to
# need tuning when a new failure shape turns up, and they should be read
# together.
#
# ---------------------------------------------------------------------------
# THE FIELD SEPARATOR IS ASCII 31, NOT TAB - DO NOT "SIMPLIFY" THIS TO @tsv
# ---------------------------------------------------------------------------
# Tab is an IFS WHITESPACE character. Even with IFS set to exactly $'\t',
# bash collapses a run of tabs into a single delimiter, so an empty field in
# the middle of a record vanishes and every column after it shifts left by
# one. That is silent: the row still parses, it is just wrong from the empty
# field onwards. It bit this script on the very first live run, where a
# finding with no Component reported its Entries count in the Component
# column and its LearnMoreLink under Repaired.
#
# ASCII 31 (US, unit separator) is not IFS whitespace, so empty fields are
# preserved. It also cannot occur in a Redfish message, and tidy strips the
# whole C0 control range anyway as a second line of defence.
# ---------------------------------------------------------------------------

read -r -d '' IML_JQ <<'JQEOF'
# Pull the failing part out of the message text. Ordered most specific first:
# "Processor 2, DIMM 1" must not be caught by the bare "Processor 2" rule, or
# two failed DIMMs on one socket would collapse into a single finding.
def component:
  if . == null then ""
  elif test("Processor +[0-9]+,? +DIMM +[0-9]+"; "i") then
    (capture("Processor +(?<p>[0-9]+),? +DIMM +(?<d>[0-9]+)"; "i") | "Processor \(.p) DIMM \(.d)")
  elif test("Processor +[0-9]+,? +Channel +[A-Za-z0-9]+"; "i") then
    (capture("Processor +(?<p>[0-9]+),? +Channel +(?<c>[A-Za-z0-9]+)"; "i") | "Processor \(.p) Channel \(.c)")
  elif test("DIMM +[0-9]+"; "i") then
    (capture("DIMM +(?<d>[0-9]+)"; "i") | "DIMM \(.d)")
  elif test("Power Supply +(Bay +)?[0-9]+"; "i") then
    (capture("Power Supply +(Bay +)?(?<n>[0-9]+)"; "i") | "Power Supply \(.n)")
  elif test("(Physical +)?Drive +(Bay +)?[0-9]+"; "i") then
    (capture("(Physical +)?Drive +(Bay +)?(?<n>[0-9]+)"; "i") | "Drive \(.n)")
  elif test("Fan +[0-9]+"; "i") then
    (capture("Fan +(?<n>[0-9]+)"; "i") | "Fan \(.n)")
  elif test("Slot +[0-9]+"; "i") then
    (capture("Slot +(?<n>[0-9]+)"; "i") | "Slot \(.n)")
  elif test("Port +[0-9]+"; "i") then
    (capture("Port +(?<n>[0-9]+)"; "i") | "Port \(.n)")
  elif test("Processor +[0-9]+"; "i") then
    (capture("Processor +(?<p>[0-9]+)"; "i") | "Processor \(.p)")
  else "" end;

# Collapse runs of whitespace and trim; keeps the representative message on
# one line for TSV and CSV.
# NOTE: jq's regex engine is Oniguruma, which does NOT understand \uXXXX
# inside a character class. Writing "[\\u0000-\\u001f]" there does not match
# the C0 controls - it matches the literal characters u, 0, 1, f and the
# ranges between them, which quietly deletes letters and digits out of every
# message. ("CPU" became "", "Uncorrectable" became "x".) Escape sequences
# that Oniguruma does know are listed explicitly instead, and the unit
# separator is passed as a real character by jq's own string parsing, where
# the regex engine sees it as a harmless literal.
def tidy: (. // "")
  | gsub("[\\r\\n\\t]"; " ")
  | gsub("\u001f"; " ")
  | gsub(" +"; " ") | sub("^ +"; "") | sub(" +$"; "");

# Redfish timestamps on these iLOs are sometimes the all-zero placeholder
# "0000-00-00T00:00:00Z" - seen on roughly a sixth of the entries on every
# Gen11 host tested, typically for events logged before the clock was set.
# It is not a date: reporting it as one would put a 1900s age in AgeDays and
# make the row sort to the top of any chronological view. Normalised to empty,
# which every consumer here already treats as "unknown".
def ts: (. // "") | tidy | if startswith("0000") then "" else . end;

# ---------------------------------------------------------------------------
# epoch - parse an ISO 8601 timestamp that jq's own fromdateiso8601 refuses.
# ---------------------------------------------------------------------------
# fromdateiso8601 accepts ONLY "YYYY-MM-DDTHH:MM:SSZ". iLO firmware also emits
# fractional seconds and a numeric offset - "2023-08-07T11:48:35.553+00" is a
# real value out of this fleet - and those are perfectly valid ISO 8601 that
# jq simply rejects.
#
# That mattered because the age filter below treats an unparseable timestamp
# as "keep", so every entry in that format survived --days regardless of its
# real age. On a --days 7 fleet sweep it added 93 hosts whose newest event was
# a median of 223 days old, and the run therefore reported MORE hosts than a
# 30-day window did - which is how it was noticed.
#
# Returns null only when the value genuinely cannot be read, so the deliberate
# fail-open for undated entries is preserved.
def epoch:
  . as $raw
  | if ($raw // "") == "" then null
    else
      ($raw | capture("^(?<body>[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2})(?<frac>\\.[0-9]+)?(?<zone>Z|z|[+-][0-9]{2}:?[0-9]{2}|[+-][0-9]{2})?$")) as $m
      | if $m == null then null
        else
          ((($m.body | sub(" "; "T")) + "Z") | try fromdateiso8601 catch null) as $base
          | if $base == null then null
            else
              (if (($m.zone // "") | ascii_downcase | . == "" or . == "z") then 0
               else
                 ($m.zone | sub(":"; "")) as $z
                 | ((($z[1:3] | tonumber) * 3600)
                    + (if ($z | length) >= 5 then (($z[3:5] | tonumber) * 60) else 0 end)) as $off
                 | (if ($z[0:1] == "-") then (0 - $off) else $off end)
               end) as $offs
              | $base - $offs
            end
        end
    end;

[ .Members[]?
  | select(.Severity != "OK")
  | select($include_repaired == 1 or (.Oem.Hpe.Repaired != true))
  | select($include_warnings == 1 or .Severity == "Critical")
  # Category filter. HPE tags every entry, and the tags are the only reliable
  # way to tell a failed part from an administrative notice: "Factory Root CA
  # is about to expire" is reported Critical but carries Security,Maintenance,
  # and "Time & Date Not Set" carries Administration. Neither means hardware
  # has failed. Keeping an entry requires at least one wanted category, so a
  # mixed tag like ["Security","Hardware"] is kept on the strength of Hardware.
  | select($all_categories == 1 or
           (((.Oem.Hpe.Categories // []) - ($wanted_categories | split(" "))) | length)
             < ((.Oem.Hpe.Categories // []) | length))
  # Age filter. Uses Updated when the firmware supplies it, since that is when
  # the fault was last seen; falls back to Created. A missing or genuinely
  # unreadable timestamp is KEPT, never dropped - losing a real fault to a
  # date-format quirk would be worse than showing one extra row.
  #
  # Parsing goes through epoch, not fromdateiso8601: the builtin rejects valid
  # ISO 8601 with fractional seconds or a numeric offset, and every such entry
  # then fell through the "unreadable" clause above and ignored the window.
  | . as $e
  | (($e.Oem.Hpe.Updated // $e.Created // "") | ts) as $when
  | select(
      $since == "" or $when == "" or
      (($when | epoch) as $t
        | $t == null or $t >= ($since | tonumber))
    )
]
| group_by([.Oem.Hpe.Class, .Oem.Hpe.Code, (.Message | component)])
| map(
    (sort_by(.Created // "")) as $g
    | $g[0] as $first
    | {
        class:      ($first.Oem.Hpe.Class // ""),
        code:       ($first.Oem.Hpe.Code // ""),
        classdesc:  ($first.Oem.Hpe.ClassDescription // "" | tidy),
        # A group can in principle mix severities; the worst one wins, since
        # that is what decides whether a technician is dispatched.
        severity:   (if ($g | map(.Severity) | index("Critical")) != null then "Critical"
                     elif ($g | map(.Severity) | index("Warning")) != null then "Warning"
                     else ($first.Severity // "") end),
        component:  ($first.Message | component),
        # Union across the group, so a category present on any member shows.
        categories: (($g | map(.Oem.Hpe.Categories // []) | add // []) | unique | join(",")),
        entries:    ($g | length),
        # iLO coalesces some repeats itself, so Count is the true occurrence
        # tally and length is only the number of log records.
        occurrences:($g | map(.Oem.Hpe.Count // 1) | add),
        first_seen: ($g | map(.Created | ts) | map(select(. != "")) | sort | (.[0] // "")),
        last_seen:  ($g | map((.Oem.Hpe.Updated // .Created) | ts) | map(select(. != "")) | sort | (.[-1] // "")),
        repaired:   (if ($g | map(.Oem.Hpe.Repaired) | index(false)) != null then "false" else "true" end),
        # Capped: a 104-entry group would otherwise emit an unusable column.
        eventids:   (($g | map(.Oem.Hpe.EventNumber // .Id | tostring))
                      | if length > 8 then (.[0:8] | join(" ")) + " +" + ((length - 8) | tostring) + " more"
                        else join(" ") end),
        action:     ($first.Oem.Hpe.RecommendedAction // "" | tidy),
        learnmore:  ($first.Oem.Hpe.LearnMoreLink // "" | tidy),
        message:    ($first.Message | tidy)
      })
| sort_by(
    (if .severity == "Critical" then 0 elif .severity == "Warning" then 1 else 2 end),
    -(.entries)
  )
| .[]
| [ .class, .code, .classdesc, .severity, .repaired, .component, .categories,
    .entries, .occurrences, .first_seen, .last_seen, .eventids,
    .action, .learnmore, .message ]
| map(tostring | (. // ""))
| join("\u001f")
JQEOF

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  # CLI first (to learn it), then conf, then CLI again (so it wins).
  parse_args 1 "$@"
  load_conf
  parse_args 0 "$@"

  [[ -n "$EXTRA_PATH" ]] && PATH="${EXTRA_PATH}:${PATH}"
  require_cmd curl jq date

  umask 077
  mkdir -p "$TMP_DIR" 2>/dev/null || die "cannot create ${TMP_DIR}"

  resolve_sp
  local sp_target
  sp_target="$(apply_host_suffix "$SP_NAME" "$HOST_SUFFIX")"
  log_debug "target host=${HOST_NAME} sp=${SP_NAME} dialling=${sp_target}"

  # --- credentials -------------------------------------------------------
  creds_import_env
  load_creds
  creds_parse
  if (( $(creds_count) == 0 )); then
    die "no iLO credentials. Set ILO_CREDS in ${CREDS_FILE} (or .enc) or in the environment."
  fi
  log_debug "$(creds_count) credential(s) available"
  # Rotate the credential this SP is known to take to the front. Must happen
  # after creds_parse, which rebuilds the arrays from scratch.
  creds_prefer_learned "$SP_NAME"

  # --- work area ---------------------------------------------------------
  # WORK_DIR is GLOBAL on purpose. An EXIT trap runs after main() has already
  # returned, by which point a `local wd` no longer exists - under `set -u`
  # that makes the trap itself die with "wd: unbound variable", and the
  # directory is never cleaned up.
  WORK_DIR="$(mktemp -d "${TMP_DIR}/hpeiml.XXXXXX")" || die "cannot create a work directory"
  local wd="$WORK_DIR"
  # Credentials are in memory, never on disk here, but the fetched IML names
  # hardware - clean up regardless of how we exit. Failure to remove is not
  # worth a diagnostic: some mounts (a OneDrive-backed working copy, for one)
  # permit write but not unlink, and the run itself has still succeeded.
  trap 'rm -rf "${WORK_DIR:-}" 2>/dev/null || true' EXIT

  # --- resolve the age cutoff -------------------------------------------
  local since_epoch=""
  if [[ -n "$SINCE_DATE" ]]; then
    since_epoch="$(date -d "$SINCE_DATE" +%s 2>/dev/null)" \
      || die "--since: cannot parse '${SINCE_DATE}'"
  elif [[ -n "$SINCE_DAYS" ]]; then
    [[ "$SINCE_DAYS" =~ ^[0-9]+$ ]] || die "--days: '${SINCE_DAYS}' is not a number"
    since_epoch=$(( $(now_epoch) - SINCE_DAYS * 86400 ))
  fi

  # --- fetch -------------------------------------------------------------
  # One credential walk resolves the system id; the IML fetch then reuses the
  # credential that worked, so a host costs no more failed logins than it must.
  local sys_id="" user="" pass=""
  if ! rf_try_credentials "$sp_target" "/redfish/v1/Systems/1" "${wd}/sys1.json"; then
    # /Systems/1 is conventional but not guaranteed. Only worth a second look
    # if the SP is actually talking to us.
    if [[ "$RF_STATUS" == "auth_failed" || "$RF_STATUS" == "unreachable" || "$RF_STATUS" == "no_credentials" ]]; then
      log_error "${sp_target}: ${RF_STATUS}"
      [[ "$OUTPUT_FORMAT" == "report" ]] && render_report "$HOST_NAME" "$SP_NAME" "HPE" "$RF_STATUS"
      return 3
    fi
    log_debug "${sp_target}: /Systems/1 gave ${RF_STATUS}; enumerating /Systems"
    if ! rf_try_credentials "$sp_target" "/redfish/v1/Systems" "${wd}/systems.json"; then
      log_error "${sp_target}: ${RF_STATUS}"
      [[ "$OUTPUT_FORMAT" == "report" ]] && render_report "$HOST_NAME" "$SP_NAME" "HPE" "$RF_STATUS"
      return 3
    fi
    sys_id="$(jq -r '.Members[0]."@odata.id" // empty' "${wd}/systems.json" 2>/dev/null)"
    sys_id="${sys_id%/}"; sys_id="${sys_id##*/}"
  else
    sys_id=1
  fi
  [[ -n "$sys_id" ]] || { log_error "${sp_target}: no ComputerSystem resource"; return 3; }

  # Reuse the winning credential rather than walking the list again.
  local i
  for (( i = 0; i < ${#CRED_LABELS[@]}; i++ )); do
    if [[ "${CRED_LABELS[$i]}" == "$RF_CRED_LABEL" ]]; then
      user="${CRED_USERS[$i]}"; pass="${CRED_PASSES[$i]}"; break
    fi
  done
  log_debug "${sp_target}: system id ${sys_id}, credential '${RF_CRED_LABEL}'"
  # Remember the winner keyed on the SP NAME, not the dialled FQDN, so the map
  # is stable whether or not HOST_SUFFIX is in play.
  creds_remember "$SP_NAME" "$RF_CRED_LABEL"

  if ! rf_get_collection "$user" "$pass" "$sp_target" \
        "/redfish/v1/Systems/${sys_id}/LogServices/IML/Entries/" "${wd}/iml.json"; then
    log_error "${sp_target}: could not read the IML (${RF_STATUS})"
    [[ "$OUTPUT_FORMAT" == "report" ]] && render_report "$HOST_NAME" "$SP_NAME" "HPE" "$RF_STATUS"
    return 3
  fi

  local total
  total="$(jq -r '.["Members@odata.count"] // (.Members|length)' "${wd}/iml.json" 2>/dev/null)"
  log_info "${sp_target}: ${total} IML entries"

  # --- filter and group --------------------------------------------------
  jq -r \
     --argjson include_warnings  "$INCLUDE_WARNINGS" \
     --argjson include_repaired  "$INCLUDE_REPAIRED" \
     --argjson all_categories    "$ALL_CATEGORIES" \
     --arg     wanted_categories "$HW_CATEGORIES" \
     --arg     since             "${since_epoch}" \
     "$IML_JQ" "${wd}/iml.json" > "${wd}/findings.tsv" 2>"${wd}/jq.err" || {
    log_error "could not parse the IML: $(head -3 "${wd}/jq.err" 2>/dev/null)"
    return 3
  }

  # --- enrich and emit ---------------------------------------------------
  # The class/code table lives in bash, so enrichment happens here rather than
  # in jq: subsystem, the documented meaning, and the age in days.
  local now; now="$(now_epoch)"
  local cls code cdesc sev rep comp cats ents occ first last ids act link msg
  local sub interp age expected
  local crit=0 warn=0 nfind=0
  local undated=0 undated_codes=""

  # Is an age window in effect? Suppression below applies ONLY then.
  local windowed=0
  [[ -n "$SINCE_DAYS" || -n "$SINCE_DATE" ]] && windowed=1

  : > "${wd}/enriched.tsv"
  while IFS="$IML_SEP" read -r cls code cdesc sev rep comp cats ents occ first last ids act link msg; do
    [[ -z "${cls}${code}" ]] && continue

    # ----------------------------------------------------------------------
    # A finding with no usable timestamp cannot be placed inside the window,
    # so when one is requested it is SUPPRESSED here rather than reported.
    #
    # Why this is the right call, measured rather than assumed: iLO writes
    # 0000-00-00T00:00:00Z when an event is logged with no clock set, and
    # those records are not recent. IML Ids are assigned in write order, so an
    # undated record can be bracketed between its nearest dated neighbours -
    # and across every host sampled, that bracket landed months or years back
    # (one block sat between a dated 2021-09-17 and a dated 2022-07-28). They
    # are overwhelmingly a NIC link flapping on an unused OCP port.
    #
    # They are NOT discarded: the count and the class/codes go to
    # UNDATED_COUNT_FILE, and check_hardware.sh turns that into an
    # UNDATED_FINDINGS row in exceptions.csv, so a host whose only findings are
    # undated still appears in the output rather than silently reading clean.
    #
    # With no window this does nothing, and undated findings report as before.
    # ----------------------------------------------------------------------
    if (( windowed )) && [[ -z "$last" ]]; then
      undated=$(( undated + 1 ))
      case ",${undated_codes}," in
        *",${cls}/${code},"*) : ;;
        *) undated_codes="${undated_codes:+${undated_codes},}${cls}/${code}" ;;
      esac
      continue
    fi

    nfind=$(( nfind + 1 ))
    [[ "$sev" == "Critical" ]] && crit=$(( crit + 1 ))
    [[ "$sev" == "Warning"  ]] && warn=$(( warn + 1 ))

    sub="$(iml_subsystem "$cls" "$code" "$cdesc")"
    interp="$(iml_description "$cls" "$code" "$cdesc")"
    age="$(age_days "$last" "$now")"

    # An undocumented Class/Code is worth knowing about: it means the table in
    # lib/iml_map.sh needs extending, and until it is, this finding is only as
    # good as its raw message.
    if ! iml_is_known "$cls" "$code" "$cdesc"; then
      log_debug "undocumented Class/Code ${cls}/${code} (${cdesc:-?}) - add it to lib/iml_map.sh"
      interp=""
    else
      expected="$(iml_expected_severity "$cls" "$code" "$cdesc")"
      if [[ -n "$expected" && -n "$sev" && "$expected" != "$sev" ]]; then
        log_debug "Class ${cls}/${code}: firmware says ${sev}, table expects ${expected}"
      fi
    fi

    printf '%s\n' "${sev}${IML_SEP}${cats}${IML_SEP}${sub}${IML_SEP}${cls}${IML_SEP}${cdesc}${IML_SEP}${code}${IML_SEP}${comp}${IML_SEP}${ents}${IML_SEP}${occ}${IML_SEP}${first}${IML_SEP}${last}${IML_SEP}${age}${IML_SEP}${rep}${IML_SEP}${ids}${IML_SEP}${act}${IML_SEP}${link}${IML_SEP}${interp}${IML_SEP}${msg}" \
      >> "${wd}/enriched.tsv"
  done < "${wd}/findings.tsv"

  # Render. Both formats read the same enriched stream so they cannot drift.
  #
  # Redirect only when an output file was actually requested. An unconditional
  # "> ${OUTPUT_FILE:-/dev/stdout}" looks tidier but is not equivalent:
  # /dev/stdout is a real reopen of whatever fd 1 happens to be, and that
  # silently produces nothing when fd 1 is something that cannot be reopened
  # that way. Observed here - a direct run printed no rows while the same
  # command redirected to a file worked.
  if [[ -n "$OUTPUT_FILE" ]]; then
    exec >"$OUTPUT_FILE" || die "cannot write ${OUTPUT_FILE}"
  fi
  # Tell the renderer when findings exist but were suppressed for having no
  # timestamp, so an empty report does not read as a clean bill of health.
  local emit_status="ok"
  (( undated > 0 && nfind == 0 )) && emit_status="undated:${undated}"
  emit_findings "$HOST_NAME" "$SP_NAME" "HPE" "$OUTPUT_FORMAT" "$PRINT_HEADER" "${wd}/enriched.tsv" "$emit_status"

  log_info "${sp_target}: ${nfind} finding(s) - ${crit} critical, ${warn} warning"

  # Hand the suppressed-undated tally to the caller through a file rather than
  # a log line: check_hardware.sh needs this per host, and scraping it out of
  # stderr would break the first time a log message is reworded.
  # Line 1 is the count, line 2 the distinct class/codes.
  if (( undated )); then
    log_info "${sp_target}: ${undated} finding(s) with no timestamp suppressed by the age window"
    if [[ -n "${UNDATED_COUNT_FILE:-}" ]]; then
      printf '%s\n%s\n' "$undated" "$undated_codes" > "$UNDATED_COUNT_FILE" 2>/dev/null || true
    fi
  fi

  (( crit )) && return 2
  (( warn )) && return 1
  return 0
}

main "$@"
