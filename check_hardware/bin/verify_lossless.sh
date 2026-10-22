#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify_lossless.sh - prove the fleet CSV loses no events to grouping.
# ---------------------------------------------------------------------------
#
#   bin/verify_lossless.sh --conf atlvhwerptd01.conf \
#       --csv reports/pilot01/findings.csv atlhwe-lsf24 atlhwe-lsf88
#
# Findings are GROUPED - 104 machine-check register dumps from one failing CPU
# collapse into a single row. Grouping is where events go missing silently: a
# key that is wrong in some edge case drops a whole bucket, and the CSV still
# looks entirely reasonable afterwards. So the invariant is checked directly
# against the service processor:
#
#     sum(Entries) over a host's CSV rows  ==  number of raw log records that
#                                              pass the same filters
#
# Credentials are never handled here in the open: the fetch goes through
# rf_try_credentials() from lib/redfish.sh, which walks the parsed list itself.
#
# --mutate deliberately corrupts the comparison by one to show the assertion
# can actually fail. An invariant nobody has ever seen fail is not evidence.
# ---------------------------------------------------------------------------

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
BASE_DIR="$(dirname "$(dirname "$SELF")")"
LIB_DIR="${BASE_DIR}/lib"

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/iml_report.sh"
source "${LIB_DIR}/creds.sh"
source "${LIB_DIR}/redfish.sh"

CONF_FILE="${BASE_DIR}/check_hardware.conf"
CREDS_FILE="${BASE_DIR}/creds/ilo_creds"
SSH_CRYPT="${SSH_CRYPT:-${BASE_DIR}/bin/ssh_crypt.sh}"
CREDMAP_DIR="${BASE_DIR}/tmp/credmap"
USE_CREDMAP=1
HOSTS_DIR="${BASE_DIR}/hostlist"
CSV=""
MUTATE=0
HW_CATEGORIES="${HW_CATEGORIES:-Hardware Power}"
declare -a TARGETS=()

while (( $# )); do
  case "$1" in
    --conf)   CONF_FILE="$2"; shift 2 ;;
    --creds)  CREDS_FILE="$2"; shift 2 ;;
    --csv)    CSV="$2"; shift 2 ;;
    --mutate) MUTATE=1; shift ;;
    -*)       die "unknown option: $1" ;;
    *)        TARGETS+=("$1"); shift ;;
  esac
done

[[ -r "$CONF_FILE" ]] && source "$CONF_FILE"
[[ -n "$EXTRA_PATH" ]] && PATH="${EXTRA_PATH}:${PATH}"
[[ -n "$CSV" ]] || die "--csv is required"
(( ${#TARGETS[@]} )) || die "name at least one host"

load_creds
creds_parse
(( $(creds_count) )) || die "no credentials loaded"

WORK="$(mktemp -d "${BASE_DIR}/tmp/verify.XXXXXX")" || die "cannot make a work dir"
# An EXIT trap runs AFTER the function that declared a local has returned, so
# the work dir must be global or the trap dies on an unbound variable.
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

fail=0

for host in "${TARGETS[@]}"; do
  # Map host -> SP through the authoritative lists.
  sp=""; i=0; user=""; pass=""; logsvc=""
  for f in "$HOSTS_DIR"/*.host-sps; do
    [[ -e "$f" ]] || continue
    for cand in "${host}-sp" "${host}-ipmi" "mp${host}" "$host"; do
      grep -qxF -- "$cand" "$f" 2>/dev/null && { sp="$cand"; break 2; }
    done
  done
  [[ -n "$sp" ]] || { log_warn "${host}: no SP entry, skipping"; continue; }

  creds_prefer_learned "$sp"

  vendor="$(rf_detect_vendor "$sp")"
  case "$vendor" in
    HPE)    logsvc="IML" ;;
    Lenovo) logsvc="PlatformLog" ;;
    *)      log_warn "${host}: vendor ${vendor}, skipping"; continue ;;
  esac

  raw="${WORK}/${host}.json"

  # Authenticate once against a cheap resource to learn WHICH credential this
  # SP takes; rf_try_credentials publishes the winner in RF_CRED_LABEL.
  if ! rf_try_credentials "$sp" "/redfish/v1/Systems/1" "${WORK}/${host}.sys"; then
    log_warn "${host}: could not authenticate (${RF_STATUS:-?}), skipping"
    continue
  fi
  user=""; pass=""
  for (( i = 0; i < ${#CRED_LABELS[@]}; i++ )); do
    if [[ "${CRED_LABELS[$i]}" == "$RF_CRED_LABEL" ]]; then
      user="${CRED_USERS[$i]}"; pass="${CRED_PASSES[$i]}"; break
    fi
  done

  # rf_get_collection, NOT a single fetch with ?$top=N. XCC ignores $top and
  # pages the PlatformLog, so a one-shot request returns only the first page -
  # which made this check report 503 CSV entries against 5 "raw" ones and
  # accuse the driver of inventing events. The log is paginated; the verifier
  # has to follow Members@odata.nextLink exactly as the real scripts do, or it
  # is measuring its own fetch rather than the driver's grouping.
  if ! rf_get_collection "$user" "$pass" "$sp" \
        "/redfish/v1/Systems/1/LogServices/${logsvc}/Entries" "$raw"; then
    log_warn "${host}: could not read ${logsvc} (${RF_STATUS:-?}), skipping"
    continue
  fi

  # Count raw records passing EXACTLY the filters the default run applies:
  # severity Critical, not repaired, and categorised Hardware or Power.
  # Lenovo has no Repaired flag and no Categories, so those two clauses are
  # true by construction there rather than being invented.
  cats_re="$(printf '%s' "$HW_CATEGORIES" | tr ' ' '|')"
  rawcount="$(jq -r --arg cats "$cats_re" '
      [ .Members[]?
        | select((.Severity // "") == "Critical")
        | select((.Oem.Hpe.Repaired // false) != true)
        | select(
            (.Oem.Hpe.Categories // null) == null
            or ((.Oem.Hpe.Categories // []) | join(",") | test($cats))
          )
      ] | length' < "$raw" 2>/dev/null)" || rawcount=""
  [[ "$rawcount" =~ ^[0-9]+$ ]] || { log_warn "${host}: could not count raw entries"; continue; }

  # Sum the Entries column (column 11) for this host out of the fleet CSV.
  csvsum="$(python3 - "$CSV" "$host" <<'PY'
import csv, sys
path, host = sys.argv[1], sys.argv[2]
tot = 0
with open(path, newline='') as fh:
    r = csv.reader(fh)
    hdr = next(r)
    hi, ei = hdr.index('Host'), hdr.index('Entries')
    for row in r:
        if row[hi] == host:
            tot += int(row[ei] or 0)
print(tot)
PY
)"
  (( MUTATE )) && csvsum=$(( csvsum - 1 ))

  if [[ "$csvsum" == "$rawcount" ]]; then
    printf '  %-16s %-7s raw=%-5s csv=%-5s OK\n' "$host" "$vendor" "$rawcount" "$csvsum"
  else
    printf '  %-16s %-7s raw=%-5s csv=%-5s *** MISMATCH - events were lost ***\n' \
      "$host" "$vendor" "$rawcount" "$csvsum"
    fail=1
  fi
done

if (( MUTATE )); then
  (( fail )) && { printf '\nmutation check: the assertion FAILED as it should - it is live.\n'; exit 0; }
  printf '\nmutation check: *** the assertion still passed while mutated - it proves nothing ***\n'
  exit 1
fi

exit "$fail"
