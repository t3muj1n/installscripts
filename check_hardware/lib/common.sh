#!/usr/bin/env bash
# lib/common.sh - shared helpers: logging, CSV quoting, value normalisation.
#
# Sourced by check_iml/check_hpe_iml.sh, check_iml/check_lenovo_iml.sh and
# check_hardware.sh. Not executable on its own.
#
# Carried over from the inventory_script project with the same conventions, so
# an operator who has read one tree can read the other. Targets bash 4.2 /
# RHEL 7: no namerefs, no `wait -n`, and every possibly-empty array expansion
# is guarded because `set -u` on 4.2 treats "${arr[@]}" on an empty declared
# array as an unbound variable.

# ---------------------------------------------------------------------------
# Logging. Everything goes to stderr so stdout stays clean for CSV data.
# ---------------------------------------------------------------------------

: "${VERBOSE:=0}"
: "${LOG_COLOR:=auto}"

_log_use_color() {
  case "$LOG_COLOR" in
    always) return 0 ;;
    never)  return 1 ;;
    *)      [[ -t 2 ]] ;;
  esac
}

_log() {
  local level="$1"; shift
  local color="" reset=""
  if _log_use_color; then
    reset=$'\033[0m'
    case "$level" in
      ERROR) color=$'\033[31m' ;;
      WARN)  color=$'\033[33m' ;;
      INFO)  color=$'\033[36m' ;;
      DEBUG) color=$'\033[90m' ;;
    esac
  fi
  printf '%s[%s] %-5s %s%s\n' \
    "$color" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" "$reset" >&2
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
log_debug() { [[ "$VERBOSE" -ge 1 ]] && _log DEBUG "$@"; return 0; }

die() { log_error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Value normalisation
# ---------------------------------------------------------------------------

# Strip a matched pair of surrounding double quotes (jq -r should already have
# done this, but raw jq output sometimes reaches here), collapse whitespace
# runs, and turn Redfish/jq "null" and friends into the empty string.
#
# Only a MATCHED pair is stripped. Trimming each end independently would
# corrupt a legitimate value that merely ends in a quote.
normalize() {
  local v="${1-}"
  if [[ ${#v} -ge 2 && "$v" == '"'*'"' ]]; then
    v="${v#\"}"; v="${v%\"}"
  fi
  # Parameter expansion rather than a tr|sed pipeline: this runs for every
  # field of every finding of every host, and the forks add up across a sweep.
  v="${v//$'\n'/ }"; v="${v//$'\r'/ }"; v="${v//$'\t'/ }"
  while [[ "$v" == *"  "* ]]; do v="${v//  / }"; done
  v="${v# }"; v="${v% }"
  case "$v" in
    null|NULL|None|N/A|n/a|-|unknown|Unknown|"Not Specified") v="" ;;
  esac
  printf '%s' "$v"
}

# ---------------------------------------------------------------------------
# CSV (RFC 4180)
# ---------------------------------------------------------------------------

# Quote a single field: wrap in double quotes, double any internal double
# quote. Newlines are already stripped by normalize().
csv_field() {
  local v="${1-}"
  v="${v//\"/\"\"}"
  printf '"%s"' "$v"
}

# Join the arguments into one CSV row.
csv_row() {
  local out="" first=1 f
  for f in "$@"; do
    if (( first )); then first=0; else out+=","; fi
    out+="$(csv_field "$f")"
  done
  printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------

now_epoch() { date +%s; }

# iso_to_epoch <iso8601>
# Convert a Redfish timestamp ("2025-06-29T22:03:00Z", sometimes with a
# numeric offset) to seconds since the epoch. Prints nothing if it cannot be
# parsed, so callers must treat empty as "unknown" rather than as zero.
iso_to_epoch() {
  local ts="${1-}" out
  [[ -z "$ts" ]] && return 0
  out="$(date -u -d "$ts" +%s 2>/dev/null)" || out=""
  # BSD date, in case this is ever run somewhere that is not Linux.
  if [[ -z "$out" ]]; then
    out="$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "${ts%%[Zz+]*}" +%s 2>/dev/null)" || out=""
  fi
  printf '%s' "$out"
}

# age_days <iso8601> [now_epoch]
# Whole days between the timestamp and now. Empty in, empty out.
age_days() {
  local ts="${1-}" ref="${2:-}" then_s
  then_s="$(iso_to_epoch "$ts")"
  [[ -z "$then_s" ]] && return 0
  [[ -z "$ref" ]] && ref="$(now_epoch)"
  printf '%s' "$(( (ref - then_s) / 86400 ))"
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

require_cmd() {
  local cmd missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    die "missing required command(s): ${missing[*]}"
  fi
}

# Resolve a target name to something DNS can answer, by appending the
# configured suffix when the bare name does not resolve on its own. In
# production the host's resolv.conf search domain makes this a no-op; in a
# sandbox without that search path the suffix is what makes the name work.
apply_host_suffix() {
  local name="${1-}" suffix="${2-}"
  [[ -z "$suffix" ]] && { printf '%s' "$name"; return 0; }
  [[ "$name" == *"$suffix" ]] && { printf '%s' "$name"; return 0; }
  printf '%s%s' "$name" "$suffix"
}
