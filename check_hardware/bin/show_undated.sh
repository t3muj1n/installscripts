#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# show_undated.sh - dump the RAW log records that carry no usable timestamp.
# ---------------------------------------------------------------------------
#
#   bin/show_undated.sh --conf atlvhwerptd01.conf atlhwe-int13
#   bin/show_undated.sh --conf atlvhwerptd01.conf --limit 2 --full atlhwe-int13
#
# These are the entries the age filter deliberately KEEPS regardless of
# --days/--since, on the reasoning that losing a real fault to a date problem
# would be worse than showing an extra row. Whether that reasoning holds
# depends on what the records actually are, which is what this prints.
#
# "No usable timestamp" means Created (and Oem.Hpe.Updated, where present) is
# absent, empty, or the zero value 0000-00-00T00:00:00Z that iLO writes when
# the event predates a clock being set.
#
# Credentials go through rf_try_credentials(), so nothing is handled in the
# open here.
# ---------------------------------------------------------------------------

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
BASE_DIR="$(dirname "$(dirname "$SELF")")"
LIB_DIR="${BASE_DIR}/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/creds.sh"
source "${LIB_DIR}/redfish.sh"

CONF_FILE="${BASE_DIR}/check_hardware.conf"
CREDS_FILE="${BASE_DIR}/creds/ilo_creds"
SSH_CRYPT="${SSH_CRYPT:-${BASE_DIR}/bin/ssh_crypt.sh}"
CREDMAP_DIR="${BASE_DIR}/tmp/credmap"
USE_CREDMAP=1
HOSTS_DIR="${BASE_DIR}/hostlist"
LIMIT=3
FULL=0
declare -a TARGETS=()

while (( $# )); do
  case "$1" in
    --conf)  CONF_FILE="$2"; shift 2 ;;
    --creds) CREDS_FILE="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --full)  FULL=1; shift ;;
    -*)      die "unknown option: $1" ;;
    *)       TARGETS+=("$1"); shift ;;
  esac
done

[[ -r "$CONF_FILE" ]] && source "$CONF_FILE"
[[ -n "${EXTRA_PATH:-}" ]] && PATH="${EXTRA_PATH}:${PATH}"
(( ${#TARGETS[@]} )) || die "name at least one host"

load_creds
creds_parse
(( $(creds_count) )) || die "no credentials loaded"

WORK="$(mktemp -d "${BASE_DIR}/tmp/undated.XXXXXX")" || die "cannot make a work dir"
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

for host in "${TARGETS[@]}"; do
  sp=""
  for f in "$HOSTS_DIR"/*.host-sps; do
    [[ -e "$f" ]] || continue
    for cand in "${host}-sp" "${host}-ipmi" "mp${host}" "$host"; do
      grep -qxF -- "$cand" "$f" 2>/dev/null && { sp="$cand"; break 2; }
    done
  done
  [[ -n "$sp" ]] || { log_warn "${host}: no SP entry"; continue; }

  creds_prefer_learned "$sp"
  vendor="$(rf_detect_vendor "$sp")"
  case "$vendor" in
    HPE)    logsvc="IML" ;;
    Lenovo) logsvc="PlatformLog" ;;
    *)      log_warn "${host}: vendor ${vendor}"; continue ;;
  esac

  if ! rf_try_credentials "$sp" "/redfish/v1/Systems/1" "${WORK}/sys"; then
    log_warn "${host}: ${RF_STATUS:-auth failed}"; continue
  fi
  user=""; pass=""
  for (( i = 0; i < ${#CRED_LABELS[@]}; i++ )); do
    if [[ "${CRED_LABELS[$i]}" == "$RF_CRED_LABEL" ]]; then
      user="${CRED_USERS[$i]}"; pass="${CRED_PASSES[$i]}"; break
    fi
  done

  raw="${WORK}/${host}.json"
  rf_get_collection "$user" "$pass" "$sp" \
    "/redfish/v1/Systems/1/LogServices/${logsvc}/Entries" "$raw" \
    || { log_warn "${host}: could not read ${logsvc}"; continue; }

  printf '\n========================================================================\n'
  printf 'HOST %s   (%s, %s)\n' "$host" "$sp" "$vendor"
  printf '========================================================================\n'

  jq -r --argjson limit "$LIMIT" --argjson full "$FULL" '
    def undated:
      ((.Oem.Hpe.Updated // "") == "" or ((.Oem.Hpe.Updated // "") | startswith("0000")))
      and ((.Created // "") == "" or ((.Created // "") | startswith("0000")));
    ([ .Members[]? ] ) as $all
    | ([ $all[] | select(undated) ]) as $u
    | "total log records      : \($all | length)",
      "records with NO date    : \($u | length)",
      "  of those, Severity!=OK: \([ $u[] | select(.Severity != "OK") ] | length)",
      "",
      ( [ $u[] | select(.Severity != "OK") ][0:$limit]
        | to_entries[]
        | "---------- undated record #\(.key + 1) ----------",
          ( if $full == 1 then (.value | tojson)
            else
              ( .value
                | "  Id            : \(.Id // "-")",
                  "  Created       : \(.Created // "<absent>")",
                  "  Updated(Oem)  : \(.Oem.Hpe.Updated // "<absent>")",
                  "  Severity      : \(.Severity // "-")",
                  "  EntryType     : \(.EntryType // "-")",
                  "  Class/Code    : \(.Oem.Hpe.Class // "-")/\(.Oem.Hpe.Code // "-")",
                  "  ClassDesc     : \(.Oem.Hpe.ClassDescription // "-")",
                  "  Categories    : \((.Oem.Hpe.Categories // []) | join(","))",
                  "  Count         : \(.Oem.Hpe.Count // "-")",
                  "  Repaired      : \(.Oem.Hpe.Repaired // "-")",
                  "  Message       : \(.Message // "-")",
                  "  RecommendedAct: \(.Oem.Hpe.RecommendedAction // "-")"
              )
            end )
      )
  ' < "$raw"
done
