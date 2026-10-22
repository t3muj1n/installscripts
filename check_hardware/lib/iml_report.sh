#!/usr/bin/env bash
# lib/iml_report.sh - the shared output contract for every IML checker.
#
# check_hpe_iml.sh and check_lenovo_iml.sh both emit through this file, and
# check_hardware.sh concatenates what they produce. That only works if the two
# vendors agree on the column names, their order, and the meaning of each one -
# so the header and both renderers live HERE, in one place, rather than being
# written out twice and drifting the first time one of them is edited.
#
# A vendor script's only job is to produce the ENRICHED STREAM described below.
# Everything downstream of that is vendor-neutral.

# ---------------------------------------------------------------------------
# THE FIELD SEPARATOR IS ASCII 31, NOT TAB
# ---------------------------------------------------------------------------
# Tab is an IFS WHITESPACE character. Even with IFS set to exactly $'\t', bash
# collapses a run of tabs into one delimiter, so an empty field in the middle
# of a record vanishes and every column after it shifts left by one. That is
# silent - the row still parses, it is just wrong from the empty field onward.
# It bit this project on its first live run, where a finding with no Component
# reported its Entries count in the Component column.
#
# ASCII 31 (US, unit separator) is not IFS whitespace, so empty fields survive.
IML_SEP=$'\x1f'

# ---------------------------------------------------------------------------
# The CSV column contract. NAMES AND ORDER ARE FIXED.
# Anything consuming the fleet file indexes by position.
# ---------------------------------------------------------------------------
CSV_HEADER=(
  Host SP Vendor Severity Category Subsystem Class ClassDescription Code Component
  Entries Occurrences FirstSeen LastSeen AgeDays Repaired EventIDs
  Message Interpretation RecommendedAction LearnMoreLink
)

# ---------------------------------------------------------------------------
# THE ENRICHED STREAM
# ---------------------------------------------------------------------------
# One line per finding, 18 IML_SEP-separated fields, in this order:
#
#   1 severity      Critical | Warning
#   2 categories    comma-joined; HPE reads them from the payload, Lenovo
#                   derives them from Oem.Lenovo.Source
#   3 subsystem     normalised bucket (CPU, Memory, Power, ...)
#   4 class         HPE: the numeric Class. Lenovo: empty - XCC has no
#                   numeric class, so the field is left blank rather than
#                   filled with something invented.
#   5 classdesc     HPE: ClassDescription. Lenovo: Oem.Lenovo.Source
#   6 code          HPE: numeric Code. Lenovo: CommonEventID (FQXSP...)
#   7 component     the failing part, e.g. "Processor 2 DIMM 1"
#   8 entries       number of log records in the group
#   9 occurrences   HPE: sum of Oem.Hpe.Count. Lenovo: same as entries, since
#                   XCC does not pre-coalesce repeats.
#  10 first_seen    ISO timestamp, or empty when unknown
#  11 last_seen     ISO timestamp, or empty when unknown
#  12 age_days      whole days since last_seen, or empty
#  13 repaired      "true"/"false". Lenovo has no repaired flag, so always
#                   "false" there - see check_lenovo_iml.sh.
#  14 eventids      space-separated, capped
#  15 action        vendor RecommendedAction, often empty
#  16 learnmore     vendor reference URL, often empty
#  17 interpretation  from the vendor's class/code table
#  18 message       representative message, LAST so any stray separator in it
#                   cannot shift a later column
# ---------------------------------------------------------------------------

emit_csv_header() { csv_row "${CSV_HEADER[@]}"; }

# emit_csv <host> <sp> <vendor> <enriched-file>
emit_csv() {
  local host="$1" sp="$2" vendor="$3" file="$4"
  local sev cats sub cls cdesc code comp ents occ first last age rep ids act link interp msg
  while IFS="$IML_SEP" read -r sev cats sub cls cdesc code comp ents occ first last age rep ids act link interp msg; do
    [[ -z "${cls}${code}" ]] && continue
    csv_row "$host" "$sp" "$vendor" "$sev" "$cats" "$sub" "$cls" "$cdesc" "$code" \
            "$comp" "$ents" "$occ" "$first" "$last" "$age" "$rep" "$ids" \
            "$msg" "$interp" "$act" "$link"
  done < "$file"
}

# render_report <host> <sp> <vendor> <status> [enriched-file]
# Human-readable form of exactly the same findings. Reads the same enriched
# stream the CSV path consumes, so the two formats cannot disagree.
#
# With no file, or an empty one, this renders the "nothing found" block - which
# is why <status> matters: an unreadable service processor must never look like
# a clean bill of health.
render_report() {
  local host="$1" sp="$2" vendor="$3" status="$4" file="${5:-}"
  local crit=0 warn=0 line
  local -a rows=()

  if [[ -n "$file" && -r "$file" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && rows+=("$line")
    done < "$file"
  fi

  printf '%s\n' "========================================================================"
  printf 'Host : %s\n' "$host"
  printf 'SP   : %s   (vendor: %s, status: %s)\n' "$sp" "$vendor" "$status"
  printf 'Time : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
  printf '%s\n' "========================================================================"

  if (( ${#rows[@]} == 0 )); then
    case "$status" in
      ok)
        printf '\nNo hardware faults found.\n\n' ;;
      undated:*)
        # There ARE findings; they just carry no timestamp, so an age window
        # could not place them. Saying "no faults found" here would be a false
        # clean bill of health - the precise thing this tool exists to avoid.
        printf '\n%s finding(s) were found but carry NO TIMESTAMP, so the age\n' "${status#undated:}"
        printf 'window could not include them. This is NOT a clean result.\n'
        printf 'Re-run without --days/--since to see them.\n\n' ;;
      *)
        printf '\nThe event log could not be read - this is NOT a clean result.\n\n' ;;
    esac
    return 0
  fi

  local sev cats sub cls cdesc code comp ents occ first last age rep ids act link msg interp
  for line in "${rows[@]}"; do
    IFS="$IML_SEP" read -r sev cats sub cls cdesc code comp ents occ first last age rep ids act link interp msg <<< "$line"
    [[ "$sev" == "Critical" ]] && crit=$(( crit + 1 ))
    [[ "$sev" == "Warning"  ]] && warn=$(( warn + 1 ))

    printf '\n[%-8s] %s%s\n' "$sev" "$sub" "$( [[ -n "$comp" ]] && printf ' - %s' "$comp" )"
    if [[ -n "$cls" ]]; then
      printf '  Class/Code : %s/%s (%s)\n' "$cls" "$code" "${cdesc:-?}"
    else
      printf '  Event      : %s (%s)\n' "${code:-?}" "${cdesc:-?}"
    fi
    [[ -n "$cats" ]] && printf '  Category   : %s\n' "$cats"
    printf '  Seen       : %s entries, %s occurrences\n' "$ents" "$occ"
    printf '  First      : %s\n' "${first:-unknown}"
    printf '  Last       : %s%s\n' "${last:-unknown}" \
      "$( [[ -n "$age" ]] && printf '  (%s days ago)' "$age" )"
    [[ "$rep" == "true" ]] && printf '  Repaired   : yes\n'
    [[ -n "$interp" ]] && printf '  Meaning    : %s\n' "$interp"
    [[ -n "$act"    ]] && printf '  Action     : %s\n' "$act"
    printf '  Message    : %.160s%s\n' "$msg" "$( (( ${#msg} > 160 )) && printf '...' )"
    [[ -n "$ids"  ]] && printf '  Event IDs  : %s\n' "$ids"
    [[ -n "$link" ]] && printf '  Reference  : %s\n' "$link"
  done

  printf '\n%s\n' "------------------------------------------------------------------------"
  printf 'Summary: %d critical, %d warning (%d findings total)\n' \
    "$crit" "$warn" "${#rows[@]}"
  printf '%s\n\n' "------------------------------------------------------------------------"
}

# emit_findings <host> <sp> <vendor> <format> <print-header> <enriched-file> [status]
# The single exit point both vendor scripts use.
#
# <status> defaults to "ok" and only matters when there is nothing to render:
# pass "undated:<n>" when n findings were suppressed for having no timestamp,
# so the report says so instead of claiming the host is clean.
emit_findings() {
  local host="$1" sp="$2" vendor="$3" fmt="$4" hdr="$5" file="$6" status="${7:-ok}"
  if [[ "$fmt" == "report" ]]; then
    render_report "$host" "$sp" "$vendor" "$status" "$file"
  else
    (( hdr )) && emit_csv_header
    emit_csv "$host" "$sp" "$vendor" "$file"
  fi
}
