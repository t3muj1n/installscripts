#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check_lenovo_iml.sh - read one Lenovo XCC's PlatformLog over Redfish and
#                       report the hardware faults in it.
# ---------------------------------------------------------------------------
#
#   ./check_lenovo_iml.sh atlhwe-lsf171-sp            # CSV of critical findings
#   ./check_lenovo_iml.sh --report --warnings  <sp>   # readable, incl. warnings
#   ./check_lenovo_iml.sh --days 90 <sp>              # recent activity only
#
# The Lenovo half of the pair. check_hpe_iml.sh does HPE iLO; both emit the
# identical CSV contract through lib/iml_report.sh so check_hardware.sh can
# concatenate them.
#
# ---------------------------------------------------------------------------
# WHICH LOG, AND WHY
# ---------------------------------------------------------------------------
# An XCC publishes seven log services under /Systems/1/LogServices:
# PlatformLog, AuditLog, ActiveLog, MaintenanceLog, SaLog, SEL, DiagnosticLog.
#
# PlatformLog is the IML equivalent and the only one read here. Measured on
# atlhwe-lsf171 and atlhwe-lsf88: PlatformLog carries the severity-tagged
# hardware events; ActiveLog and SaLog were empty; SEL returned 404;
# MaintenanceLog and DiagnosticLog carry entries with no Severity at all.
# AuditLog is deliberately not read - it holds logins and configuration
# changes, not hardware faults.
#
# ---------------------------------------------------------------------------
# THE 1024-ENTRY CAP - A REAL LIMIT, NOT A BUG
# ---------------------------------------------------------------------------
# The XCC returns at most 1024 PlatformLog entries and will not page past
# them: Members@odata.count reports 1024, and "?$skip=1024" returns an empty
# collection. On atlhwe-lsf171 that window covered 2026-06-08 to 2026-10-14,
# while Oem.Lenovo.TotalSequenceNumber had reached 43182 - so considerably
# more history exists on the device than Redfish will hand over.
#
# Consequence: on a busy machine a finding may be older than it appears, and
# very old faults can age out of the window entirely. This is a property of
# the XCC, not something this script can work around, so it is reported rather
# than hidden - the run logs a warning when the cap is hit.
#
# ---------------------------------------------------------------------------
# WHAT LENOVO DOES NOT GIVE US
# ---------------------------------------------------------------------------
# No Repaired flag, no per-entry Count, no RecommendedAction, no numeric
# Class, no Categories. Those CSV columns are therefore blank, "false", or
# equal to Entries. They are gaps in the source data, not unimplemented
# features - see lib/lenovo_map.sh. --include-repaired is accepted for
# symmetry with the HPE script and has no effect here.
# ---------------------------------------------------------------------------

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SELF")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="${BASE_DIR}/lib"

# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=../lib/iml_report.sh
source "${LIB_DIR}/iml_report.sh"
# shellcheck source=../lib/lenovo_map.sh
source "${LIB_DIR}/lenovo_map.sh"
# shellcheck source=../lib/creds.sh
source "${LIB_DIR}/creds.sh"
# shellcheck source=../lib/redfish.sh
source "${LIB_DIR}/redfish.sh"

PROG="$(basename "$SELF")"

# Written as VAR="${VAR:-default}" so an exported value survives.
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
SINCE_DAYS="${SINCE_DAYS:-}"
SINCE_DATE="${SINCE_DATE:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-csv}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
PRINT_HEADER="${PRINT_HEADER:-1}"
EXTRA_PATH="${EXTRA_PATH:-}"
CREDMAP_DIR="${CREDMAP_DIR:-${BASE_DIR}/tmp/credmap}"
USE_CREDMAP="${USE_CREDMAP:-1}"
LENOVO_LOG="${LENOVO_LOG:-PlatformLog}"

TARGET=""
SP_OVERRIDE=""
HOST_NAME=""
SP_NAME=""
WORK_DIR=""

declare -A CLI_SET=()

usage() {
  cat <<EOF
usage: ${PROG} [options] <host-or-sp>

Read a Lenovo XCC's PlatformLog over Redfish and report the hardware faults
recorded in it.

Target:
  <host-or-sp>        Service processor name (atlhwe-lsf171-sp) or the host
                      name, in which case ${SP_SUFFIX} is appended, or
                      hostlist/*.host-sps consulted when present.

Options:
  --sp NAME           Use this service processor name verbatim.
  --conf FILE         Configuration file (default: ${CONF_FILE})
  --creds FILE        Credentials file (default: ${CREDS_FILE})
  --warnings          Report Warning findings as well as Critical.
  --all-categories    Report every category, not just hardware faults.
  --include-repaired  Accepted for symmetry with the HPE script. The XCC has
                      no repaired flag, so this has NO EFFECT here.
  --days N            Only entries updated within the last N days.
  --since DATE        Only entries on or after DATE (any date(1) form).
  --log NAME          Log service to read (default: ${LENOVO_LOG}).
  --report            Human-readable output instead of CSV.
  --csv               CSV output (the default).
  --output FILE       Write to FILE instead of stdout.
  --no-header         Omit the CSV header line.
  --no-credmap        Do not read or write the learned credential map.
  --credmap-dir DIR   Learned credential map location (default: ${CREDMAP_DIR}).
  -v, --verbose       Debug logging on stderr.
  -h, --help          This text.

Exit status:
  0  no findings
  1  warnings only
  2  at least one critical finding
  3  the service processor could not be read - NOT the same as "healthy"
EOF
}

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
                   log_debug "--include-repaired has no effect on Lenovo XCC" ;;
      --all-categories) ALL_CATEGORIES=1; shift
                   (( record )) && CLI_SET[ALL_CATEGORIES]=1 ;;
      --days)      SINCE_DAYS="${2:-}";  shift 2 || die "--days needs a value"
                   (( record )) && CLI_SET[SINCE_DAYS]=1 ;;
      --since)     SINCE_DATE="${2:-}";  shift 2 || die "--since needs a value"
                   (( record )) && CLI_SET[SINCE_DATE]=1 ;;
      --log)       LENOVO_LOG="${2:-}";  shift 2 || die "--log needs a value"
                   (( record )) && CLI_SET[LENOVO_LOG]=1 ;;
      --report)    OUTPUT_FORMAT="report"; shift
                   (( record )) && CLI_SET[OUTPUT_FORMAT]=1 ;;
      --csv)       OUTPUT_FORMAT="csv"; shift
                   (( record )) && CLI_SET[OUTPUT_FORMAT]=1 ;;
      --output|-o) OUTPUT_FILE="${2:-}"; shift 2 || die "--output needs a value"
                   (( record )) && CLI_SET[OUTPUT_FILE]=1 ;;
      --no-header) PRINT_HEADER=0; shift
                   (( record )) && CLI_SET[PRINT_HEADER]=1 ;;
      --no-credmap) USE_CREDMAP=0; shift
                   (( record )) && CLI_SET[USE_CREDMAP]=1 ;;
      --credmap-dir) CREDMAP_DIR="${2:-}"; shift 2 || die "--credmap-dir needs a value"
                   (( record )) && CLI_SET[CREDMAP_DIR]=1 ;;
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

load_conf() {
  [[ -n "$CONF_FILE" && -r "$CONF_FILE" ]] || {
    [[ -n "$CONF_FILE" && -e "$CONF_FILE" ]] && log_warn "cannot read ${CONF_FILE}"
    return 0
  }
  log_debug "reading configuration ${CONF_FILE}"
  # shellcheck disable=SC1090
  source "$CONF_FILE"
}

_sp_to_host() {
  local s="$1"
  case "$s" in
    *-sp)   printf '%s' "${s%-sp}" ;;
    *-ipmi) printf '%s' "${s%-ipmi}" ;;
    *-xcc)  printf '%s' "${s%-xcc}" ;;
    *-mgmt) printf '%s' "${s%-mgmt}" ;;
    mp*)    printf '%s' "${s#mp}" ;;
    *)      printf '%s' "$s" ;;
  esac
}

resolve_sp() {
  local t="$TARGET" f base cand

  if [[ -n "$SP_OVERRIDE" ]]; then
    SP_NAME="$SP_OVERRIDE"; HOST_NAME="${t:-$SP_OVERRIDE}"; return 0
  fi
  [[ -n "$t" ]] || die "no target given; see --help"

  if [[ -d "$HOSTS_DIR" ]]; then
    for f in "$HOSTS_DIR"/*.host-sps; do
      [[ -e "$f" ]] || continue
      if grep -qxF -- "$t" "$f" 2>/dev/null; then
        SP_NAME="$t"; base="$(_sp_to_host "$t")"; HOST_NAME="$base"
        log_debug "${t} found in ${f##*/}"; return 0
      fi
    done
    for f in "$HOSTS_DIR"/*.host-sps; do
      [[ -e "$f" ]] || continue
      for cand in "${t}${SP_SUFFIX}" "${t}-sp" "${t}-ipmi" "mp${t}"; do
        if grep -qxF -- "$cand" "$f" 2>/dev/null; then
          SP_NAME="$cand"; HOST_NAME="$t"
          log_debug "${t} -> ${cand} via ${f##*/}"; return 0
        fi
      done
    done
  fi

  case "$t" in
    *-sp|*-ipmi|*-xcc|*-mgmt|mp*) SP_NAME="$t"; HOST_NAME="$(_sp_to_host "$t")" ;;
    *) SP_NAME="${t}${SP_SUFFIX}"; HOST_NAME="$t" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# The jq program: filter and group the PlatformLog.
#
# Grouping key is (CommonEventID, Component), the Lenovo analogue of HPE's
# (Class, Code, Component). atlhwe-lsf88 logs the SAME uncorrectable-processor
# error 499 times; collapsing those to one finding with a count is the whole
# point, exactly as with the HPE machine-check storms.
#
# Component comes from MessageArgs when present - the XCC puts the failing
# part there as a clean token ("processor 2") rather than only in prose - and
# falls back to parsing the message text.
# ---------------------------------------------------------------------------
read -r -d '' LENOVO_JQ <<'JQEOF'
def tidy: (. // "")
  | gsub("[\\r\\n\\t]"; " ")
  | gsub("\u001f"; " ")
  | gsub(" +"; " ") | sub("^ +"; "") | sub(" +$"; "");

def ts: (. // "") | tidy | if startswith("0000") then "" else . end;

# ---------------------------------------------------------------------------
# epoch - parse an ISO 8601 timestamp that jq's own fromdateiso8601 refuses.
# ---------------------------------------------------------------------------
# Identical to the definition in check_hpe_iml.sh, and deliberately so: the
# two scripts must agree on what "within N days" means or the fleet CSV mixes
# two different age filters.
#
# This replaces an earlier inline workaround that stripped fractional seconds
# and "+00:00" only. It did not cover the bare "+00" offset the fleet actually
# emits ("2023-08-07T11:48:35.553+00"), so those entries still parsed as null
# and were kept by the fail-open clause below regardless of their real age.
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

# Title-case a leading bare token so "processor 2" and "Processor 2" group
# together; the XCC is inconsistent about this between message templates.
def titlecase_part:
  if . == null or . == "" then ""
  else (.[0:1] | ascii_upcase) + .[1:]
  end;

# Strip leading zeros from the index. One XCC writes "processor 02" and
# another "processor 2" for the same part, which would otherwise produce two
# differently-named components for the same socket in the fleet CSV.
# The guard keeps a bare "0" from becoming an empty string.
def denum: gsub("(?<w>[A-Za-z]) +0+(?<n>[0-9])"; "\(.w) \(.n)");

def component:
  . as $e
  | (($e.MessageArgs // []) | map(select(type == "string")) | join(" ") | tidy) as $args
  | (($e.Message // "") | tidy) as $m
  | if ($args | test("^(processor|cpu) *[0-9]+$"; "i")) then ($args | titlecase_part)
    elif ($m | test("Power Supply +[0-9]+"; "i")) then
      ($m | capture("Power Supply +(?<n>[0-9]+)"; "i") | "Power Supply \(.n)")
    elif ($m | test("PSU +[0-9]+"; "i")) then
      ($m | capture("PSU +(?<n>[0-9]+)"; "i") | "Power Supply \(.n)")
    elif ($m | test("DIMM +[0-9]+"; "i")) then
      ($m | capture("DIMM +(?<n>[0-9]+)"; "i") | "DIMM \(.n)")
    elif ($m | test("(processor|cpu) +[0-9]+"; "i")) then
      ($m | capture("(?<w>processor|cpu) +(?<n>[0-9]+)"; "i") | "Processor \(.n)")
    elif ($m | test("Drive +[0-9]+"; "i")) then
      ($m | capture("Drive +(?<n>[0-9]+)"; "i") | "Drive \(.n)")
    elif ($m | test("Fan +[0-9]+"; "i")) then
      ($m | capture("Fan +(?<n>[0-9]+)"; "i") | "Fan \(.n)")
    elif ($args != "") then ($args | titlecase_part)
    else "" end
  | denum;

[ .Members[]?
  | select(.Severity != "OK" and .Severity != null)
  | select($include_warnings == 1 or .Severity == "Critical")
  # The XCC has no repaired flag, so there is nothing to filter on here. An
  # entry stays until it ages out of the 1024-entry window.
  | . as $e
  | ($e.Created | ts) as $when
  | select(
      $since == "" or $when == "" or
      (($when | epoch) as $t
        | $t == null or $t >= ($since | tonumber))
    )
]
| group_by([(.Oem.Lenovo.CommonEventID // .OemLogEntryCode // "unknown"), (. | component)])
| map(
    (sort_by(.Created // "")) as $g
    | $g[0] as $first
    | {
        event:      ($first.Oem.Lenovo.CommonEventID // $first.OemLogEntryCode // "" | tidy),
        source:     ($first.Oem.Lenovo.Source // "" | tidy),
        severity:   (if ($g | map(.Severity) | index("Critical")) != null then "Critical"
                     elif ($g | map(.Severity) | index("Warning")) != null then "Warning"
                     else ($first.Severity // "") end),
        component:  ($first | component),
        entries:    ($g | length),
        first_seen: ($g | map(.Created | ts) | map(select(. != "")) | sort | (.[0] // "")),
        last_seen:  ($g | map(.Created | ts) | map(select(. != "")) | sort | (.[-1] // "")),
        eventids:   (($g | map(.Id | tostring))
                      | if length > 8 then (.[0:8] | join(" ")) + " +" + ((length - 8) | tostring) + " more"
                        else join(" ") end),
        # The failing FRU is Lenovo-specific and has no HPE counterpart; it is
        # appended to the message rather than given a column, so the shared CSV
        # contract stays identical across vendors.
        fru:        (($first.Oem.Lenovo.FailingFRU // []) | map(.FRUNumber // empty | tostring) | unique | join(",")),
        message:    ($first.Message | tidy)
      })
| sort_by(
    (if .severity == "Critical" then 0 elif .severity == "Warning" then 1 else 2 end),
    -(.entries)
  )
| .[]
| [ .event, .source, .severity, .component, .entries,
    .first_seen, .last_seen, .eventids, .fru, .message ]
| map(tostring | (. // ""))
| join("\u001f")
JQEOF

main() {
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

  creds_import_env
  load_creds
  creds_parse
  (( $(creds_count) )) || die "no credentials. Set ILO_CREDS in ${CREDS_FILE} (or .enc) or in the environment."
  creds_prefer_learned "$SP_NAME"

  WORK_DIR="$(mktemp -d "${TMP_DIR}/lenovoiml.XXXXXX")" || die "cannot create a work directory"
  local wd="$WORK_DIR"
  trap 'rm -rf "${WORK_DIR:-}" 2>/dev/null || true' EXIT

  local since_epoch=""
  if [[ -n "$SINCE_DATE" ]]; then
    since_epoch="$(date -d "$SINCE_DATE" +%s 2>/dev/null)" || die "--since: cannot parse '${SINCE_DATE}'"
  elif [[ -n "$SINCE_DAYS" ]]; then
    [[ "$SINCE_DAYS" =~ ^[0-9]+$ ]] || die "--days: '${SINCE_DAYS}' is not a number"
    since_epoch=$(( $(now_epoch) - SINCE_DAYS * 86400 ))
  fi

  # --- resolve the system id --------------------------------------------
  # XCC firmware varies: most answer /Systems/1, some use a word-shaped id
  # such as /Systems/Node.1, which is why this enumerates rather than assumes.
  local sys_id="" user="" pass=""
  if rf_try_credentials "$sp_target" "/redfish/v1/Systems/1" "${wd}/sys1.json"; then
    sys_id=1
  else
    if [[ "$RF_STATUS" == "auth_failed" || "$RF_STATUS" == "unreachable" || "$RF_STATUS" == "no_credentials" ]]; then
      log_error "${sp_target}: ${RF_STATUS}"
      [[ "$OUTPUT_FORMAT" == "report" ]] && render_report "$HOST_NAME" "$SP_NAME" "Lenovo" "$RF_STATUS"
      return 3
    fi
    log_debug "${sp_target}: /Systems/1 gave ${RF_STATUS}; enumerating /Systems"
    if ! rf_try_credentials "$sp_target" "/redfish/v1/Systems" "${wd}/systems.json"; then
      log_error "${sp_target}: ${RF_STATUS}"
      [[ "$OUTPUT_FORMAT" == "report" ]] && render_report "$HOST_NAME" "$SP_NAME" "Lenovo" "$RF_STATUS"
      return 3
    fi
    sys_id="$(jq -r '.Members[0]."@odata.id" // empty' "${wd}/systems.json" 2>/dev/null)"
    sys_id="${sys_id%/}"; sys_id="${sys_id##*/}"
  fi
  [[ -n "$sys_id" ]] || { log_error "${sp_target}: no ComputerSystem resource"; return 3; }

  local i
  for (( i = 0; i < ${#CRED_LABELS[@]}; i++ )); do
    if [[ "${CRED_LABELS[$i]}" == "$RF_CRED_LABEL" ]]; then
      user="${CRED_USERS[$i]}"; pass="${CRED_PASSES[$i]}"; break
    fi
  done
  log_debug "${sp_target}: system id ${sys_id}, credential '${RF_CRED_LABEL}'"
  creds_remember "$SP_NAME" "$RF_CRED_LABEL"

  if ! rf_get_collection "$user" "$pass" "$sp_target" \
        "/redfish/v1/Systems/${sys_id}/LogServices/${LENOVO_LOG}/Entries" "${wd}/log.json"; then
    log_error "${sp_target}: could not read ${LENOVO_LOG} (${RF_STATUS})"
    [[ "$OUTPUT_FORMAT" == "report" ]] && render_report "$HOST_NAME" "$SP_NAME" "Lenovo" "$RF_STATUS"
    return 3
  fi

  local total
  total="$(jq -r '.["Members@odata.count"] // (.Members|length)' "${wd}/log.json" 2>/dev/null)"
  log_info "${sp_target}: ${total} ${LENOVO_LOG} entries"
  # The cap is worth saying out loud: at 1024 the log is certainly truncated
  # and an apparently old "first seen" may simply be the edge of the window.
  if [[ "$total" == "1024" ]]; then
    log_warn "${sp_target}: ${LENOVO_LOG} returned exactly 1024 entries - the XCC caps the log here, so older events are not visible and FirstSeen may be the edge of the window, not the true first occurrence"
  fi

  jq -r \
     --argjson include_warnings "$INCLUDE_WARNINGS" \
     --arg     since            "${since_epoch}" \
     "$LENOVO_JQ" "${wd}/log.json" > "${wd}/findings.tsv" 2>"${wd}/jq.err" || {
    log_error "could not parse ${LENOVO_LOG}: $(head -3 "${wd}/jq.err" 2>/dev/null)"
    return 3
  }

  # --- enrich ------------------------------------------------------------
  local now; now="$(now_epoch)"
  local ev src sev comp ents first last ids fru msg
  local sub cat interp age
  local crit=0 warn=0 nfind=0
  local undated=0 undated_codes=""

  # Is an age window in effect? Suppression below applies ONLY then.
  local windowed=0
  [[ -n "$SINCE_DAYS" || -n "$SINCE_DATE" ]] && windowed=1

  : > "${wd}/enriched.tsv"
  while IFS="$IML_SEP" read -r ev src sev comp ents first last ids fru msg; do
    [[ -z "${ev}${msg}" ]] && continue

    # A finding with no usable timestamp cannot be placed inside the window.
    # Identical rule to check_hpe_iml.sh - the two vendors must agree or one
    # fleet CSV carries two different meanings of "within N days". The count
    # and class/codes go to UNDATED_COUNT_FILE so check_hardware.sh can report
    # the host in exceptions.csv rather than letting it read clean.
    #
    # In practice the XCC dates its PlatformLog entries reliably and this has
    # never fired on a Lenovo host in a fleet run - all 84 suppressed findings
    # in the first windowed sweep were HPE. It is here for symmetry and so the
    # behaviour cannot diverge later.
    if (( windowed )) && [[ -z "$last" ]]; then
      undated=$(( undated + 1 ))
      case ",${undated_codes}," in
        *",${ev},"*) : ;;
        *) undated_codes="${undated_codes:+${undated_codes},}${ev}" ;;
      esac
      continue
    fi

    cat="$(lenovo_category "$src")"
    # Same category rule as the HPE side, applied to the derived category.
    if (( ! ALL_CATEGORIES )); then
      case " ${HW_CATEGORIES} " in
        *" ${cat} "*) : ;;
        *) log_debug "filtered out ${ev} (category ${cat})"; continue ;;
      esac
    fi

    nfind=$(( nfind + 1 ))
    [[ "$sev" == "Critical" ]] && crit=$(( crit + 1 ))
    [[ "$sev" == "Warning"  ]] && warn=$(( warn + 1 ))

    sub="$(lenovo_subsystem "$src" "$ev")"
    interp="$(lenovo_description "$ev")"
    age="$(age_days "$last" "$now")"
    lenovo_is_known "$ev" || log_debug "undocumented Lenovo event ${ev} (${src}) - add it to lib/lenovo_map.sh"
    [[ -n "$fru" ]] && msg="${msg} [failing FRU ${fru}]"

    # Field order is the enriched-stream contract in lib/iml_report.sh.
    # class is EMPTY for Lenovo (no numeric class exists); occurrences equals
    # entries (no per-entry Count); repaired is always false (no such flag);
    # action and learnmore are empty (XCC supplies neither).
    printf '%s\n' "${sev}${IML_SEP}${cat}${IML_SEP}${sub}${IML_SEP}${IML_SEP}${src}${IML_SEP}${ev}${IML_SEP}${comp}${IML_SEP}${ents}${IML_SEP}${ents}${IML_SEP}${first}${IML_SEP}${last}${IML_SEP}${age}${IML_SEP}false${IML_SEP}${ids}${IML_SEP}${IML_SEP}${IML_SEP}${interp}${IML_SEP}${msg}" \
      >> "${wd}/enriched.tsv"
  done < "${wd}/findings.tsv"

  if [[ -n "$OUTPUT_FILE" ]]; then
    exec >"$OUTPUT_FILE" || die "cannot write ${OUTPUT_FILE}"
  fi
  local emit_status="ok"
  (( undated > 0 && nfind == 0 )) && emit_status="undated:${undated}"
  emit_findings "$HOST_NAME" "$SP_NAME" "Lenovo" "$OUTPUT_FORMAT" "$PRINT_HEADER" "${wd}/enriched.tsv" "$emit_status"

  log_info "${sp_target}: ${nfind} finding(s) - ${crit} critical, ${warn} warning"

  # Same contract as check_hpe_iml.sh: line 1 count, line 2 distinct event IDs.
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
