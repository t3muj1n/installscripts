#!/usr/bin/env bash
# lib/lenovo_map.sh - Lenovo XCC PlatformLog event interpretation.
#
# The Lenovo analogue of lib/iml_map.sh, but the two logs are NOT the same
# shape and this file should not be read as a mirror of it:
#
#   HPE                              Lenovo XCC
#   -------------------------------  ------------------------------------
#   numeric Class + Code             CommonEventID string, e.g. FQXSPPU0002G
#   Oem.Hpe.ClassDescription         Oem.Lenovo.Source ("Processors","Power")
#   Oem.Hpe.Categories               (absent - derived from Source here)
#   Oem.Hpe.Repaired                 (absent - there is no repaired flag)
#   Oem.Hpe.Count                    (absent - repeats are separate records)
#   Oem.Hpe.RecommendedAction        (absent)
#
# So Lenovo findings carry no Class, always report Repaired=false, and have
# Occurrences equal to Entries. Those are honest gaps in the source data, not
# unimplemented features - do not "fix" them by inventing values.

# ---------------------------------------------------------------------------
# Oem.Lenovo.Source -> subsystem + category
#
# Category exists so the fleet CSV can be filtered the same way for both
# vendors. HPE supplies it; here it is derived, using the same vocabulary
# (Hardware / Power / Administration / Configuration / Firmware).
# ---------------------------------------------------------------------------
declare -gA LENOVO_SOURCE_MAP=(
  ["Processors"]="CPU|Hardware"
  ["Processor"]="CPU|Hardware"
  ["Memory"]="Memory|Hardware"
  ["Power"]="Power|Power"
  ["Cooling"]="Thermal|Hardware"
  ["Temperature"]="Thermal|Hardware"
  ["Fans"]="Thermal|Hardware"
  ["Storage"]="StorageDevice|Hardware"
  ["Drives"]="StorageDevice|Hardware"
  ["Network"]="Network|Hardware"
  ["System"]="SystemBoard|Hardware"
  ["Firmware"]="Firmware|Firmware"
  ["Audit"]="Maintenance|Administration"
  ["Security"]="Maintenance|Security"
  ["Configuration"]="SystemBoard|Configuration"
)

# ---------------------------------------------------------------------------
# CommonEventID -> subsystem|expected_severity|description
#
# Lenovo's CommonEventID is stable across firmware levels, which makes it the
# right grouping and lookup key. The trailing letter loosely tracks severity
# (I informational, G/J warning, L/M/N error) but that is a convention, not a
# guarantee - the payload's own Severity decides, exactly as on the HPE side.
#
# Only events actually observed are listed. An unknown ID still reports
# correctly from its message and Source; it just gets no Interpretation, and
# logs a debug line so this table can be extended.
# ---------------------------------------------------------------------------
declare -gA LENOVO_EVENT_MAP=(
  # --- Processors ---------------------------------------------------------
  ["FQXSPPU0002G"]="CPU|Warning|Processor is operating in a degraded state (throttled or partially disabled)"
  ["FQXSFPU0019N"]="CPU|Critical|Uncorrectable error detected on processor"
  ["FQXSPPU0009N"]="CPU|Critical|Processor has failed"
  ["FQXSPPU0016N"]="CPU|Critical|Processor over-temperature condition"

  # --- Power --------------------------------------------------------------
  ["FQXSPPW0002L"]="Power|Critical|Power supply has failed"
  ["FQXSPPW0003G"]="Power|Warning|Failure predicted on power supply"
  ["FQXSPPW0006I"]="Power|Warning|Power supply has lost input (cord unplugged or upstream power lost)"
  ["FQXSPPW0057J"]="Power|Warning|Power supply sensor transitioned from normal to non-critical"
  ["FQXSPPW0061M"]="Power|Critical|Power supply sensor transitioned to critical"
  ["FQXSPPW0104J"]="Power|Warning|Power redundancy lost - system is running non-redundant"

  # --- Memory -------------------------------------------------------------
  ["FQXSPMA0001I"]="Memory|Warning|Correctable memory error logged"
  ["FQXSPMA0002N"]="Memory|Critical|Uncorrectable memory error"
  ["FQXSPMA0009N"]="Memory|Critical|DIMM has been disabled"

  # --- Cooling ------------------------------------------------------------
  ["FQXSPFN0001M"]="Thermal|Critical|Fan failure"
  ["FQXSPCR0001M"]="Thermal|Critical|Over-temperature condition"
)

# lenovo_subsystem <source> <common_event_id>
# Prefer the event table, fall back to the Source map, then Other.
lenovo_subsystem() {
  local src="${1-}" ev="${2-}" rec
  if [[ -n "$ev" && -n "${LENOVO_EVENT_MAP[$ev]-}" ]]; then
    rec="${LENOVO_EVENT_MAP[$ev]}"
    printf '%s' "${rec%%|*}"
    return 0
  fi
  if [[ -n "$src" && -n "${LENOVO_SOURCE_MAP[$src]-}" ]]; then
    rec="${LENOVO_SOURCE_MAP[$src]}"
    printf '%s' "${rec%%|*}"
    return 0
  fi
  printf 'Other'
}

# lenovo_category <source>
# The Categories analogue. Unknown sources are treated as Hardware: the
# PlatformLog is the hardware event log, so defaulting to Hardware keeps an
# unrecognised source VISIBLE rather than silently filtering out a real fault.
# Administrative events live in AuditLog, which this tooling does not read.
lenovo_category() {
  local src="${1-}" rec
  if [[ -n "$src" && -n "${LENOVO_SOURCE_MAP[$src]-}" ]]; then
    rec="${LENOVO_SOURCE_MAP[$src]}"
    printf '%s' "${rec##*|}"
    return 0
  fi
  printf 'Hardware'
}

# lenovo_description <common_event_id>
lenovo_description() {
  local ev="${1-}" rec rest
  [[ -n "$ev" && -n "${LENOVO_EVENT_MAP[$ev]-}" ]] || return 0
  rec="${LENOVO_EVENT_MAP[$ev]}"
  rest="${rec#*|}"
  printf '%s' "${rest#*|}"
}

# lenovo_is_known <common_event_id>
lenovo_is_known() {
  local ev="${1-}"
  [[ -n "$ev" && -n "${LENOVO_EVENT_MAP[$ev]-}" ]]
}
