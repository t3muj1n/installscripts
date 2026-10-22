#!/usr/bin/env bash
# lib/iml_map.sh - HPE IML Class/Code interpretation table.
#
# Encodes HPE_IMO_classes_and_codes.txt (kept alongside this file for
# reference) so a finding can be reported as a SUBSYSTEM and a plain-English
# description instead of two bare integers.
#
# ---------------------------------------------------------------------------
# THE CLASS INTEGER IS NOT GLOBALLY UNIQUE - READ THIS BEFORE EDITING
# ---------------------------------------------------------------------------
# The same Class number means different things depending on which firmware
# subsystem raised the event, and the payload's own ClassDescription string is
# the only thing that disambiguates it. Observed live on atlhwe-lsf24-sp:
#
#   Class 10 + ClassDescription "UEFI"  -> UEFI/BIOS namespace; codes 644,
#                                          1120 and 1126 are MEMORY faults.
#   Class 10 + ClassDescription "Storage"
#                                       -> Smart Array controller namespace;
#                                          code 8 is a controller lockup.
#   Class 50 + ClassDescription "UEFI"  -> Innovation Engine; code 547 is a
#                                          memory training failure.
#   Class 50 + "System Management"      -> ASR / recovery events.
#
# So lookup is two-level: the qualified key "<ClassDescription>:<class>/<code>"
# is tried first, then the bare "<class>/<code>". Never collapse these into one
# flat table - a Class 10 Code 644 reported as "storage controller" would send
# a technician to the wrong part.
#
# ---------------------------------------------------------------------------
# WHAT THE SEVERITY FIELD HERE IS FOR
# ---------------------------------------------------------------------------
# It is a CROSS-CHECK, not the source of truth. The payload's own top-level
# Redfish "Severity" decides whether something is reported; this column only
# lets the script log a DEBUG line when the firmware disagrees with the
# documented expectation, which is how an undocumented code gets noticed.
# Do not rewire the filter to read this table.

# Value format:  subsystem|expected_severity|description
# subsystem is one of:
#   Memory Thermal Power SystemBoard CPU PCI POST OS StorageController
#   StorageDevice Network Maintenance Recovery Firmware Other
declare -gA IML_MAP=(
  # --- Class 1: Memory ----------------------------------------------------
  ["1/1"]="Memory|Warning|Corrected memory error threshold exceeded"
  ["1/2"]="Memory|Critical|Uncorrectable multi-bit memory error (causes system halt)"
  ["1/3"]="Memory|Warning|Memory configuration or population error"
  ["1/13"]="Memory|OK|Memory fast-fault tolerance active"
  ["1/17"]="Memory|Warning|Memory authentication failed (non-genuine HPE SmartMemory)"
  ["1/22"]="Memory|Warning|High-bandwidth memory (HBM) thermal throttle reached"

  # --- Class 2: Thermal ---------------------------------------------------
  ["2/1"]="Thermal|Warning|Environment threshold warning (temperature high)"
  ["2/2"]="Thermal|Critical|Over-temperature critical threshold exceeded"
  ["2/3"]="Thermal|Critical|Thermal system shutdown initiated"

  # --- Class 3: Power -----------------------------------------------------
  ["3/1"]="Power|Warning|Power supply redundancy lost"
  ["3/2"]="Power|Critical|Power supply general failure"
  ["3/3"]="Power|Warning|Input power loss / cord unplugged"
  ["3/4"]="Power|Critical|Power subsystem overcurrent / circuit fault"
  ["3/9"]="Power|Warning|Power supply firmware flash mismatch or upgrade failed"
  ["3/15"]="Power|Critical|Smart Storage Battery circuit failure"
  ["3/22"]="Power|Critical|Smart Storage Battery completely degraded / end of life"

  # --- Class 4: System board ----------------------------------------------
  ["4/1"]="SystemBoard|Critical|General system board / ASIC fault detected"
  ["4/2"]="SystemBoard|Critical|System ROM / SPI flash corruption"
  ["4/3"]="SystemBoard|Warning|CMOS battery failure"

  # --- Class 5: CPU -------------------------------------------------------
  ["5/1"]="CPU|Critical|Processor internal error (IERR)"
  ["5/2"]="CPU|Critical|Processor over-temperature / thermal trip"
  ["5/3"]="CPU|Critical|Uncorrectable machine check exception (MCE)"
  # The source document gives 5/4 as "processor interconnect link (QPI/UPI)
  # failure", which is Intel-centric and does NOT match what was observed.
  # On atlhwe-lsf24 (AMD, Gen10) every 5/4 entry is an "Uncorrectable Machine
  # Check Exception Extended Registers" record - the register-dump companion
  # that iLO writes alongside the 5/3 MCE, which is why the two appear in
  # near-equal numbers (104 and 82) over the same minutes. Described as what
  # it demonstrably is, with the documented reading kept as a secondary
  # possibility rather than dropped.
  ["5/4"]="CPU|Critical|Uncorrectable machine check exception - extended register dump (companion to Class 5/3; on Intel platforms this code is also documented as a QPI/UPI interconnect link failure)"
  ["5/14"]="CPU|Critical|Processor silicon root-of-trust validation failure"
  ["5/18"]="CPU|Warning|Processor TDP restriction applied due to configuration"
  ["5/25"]="CPU|OK|Autonomous crash dump (ACD) captured after crash"

  # --- Class 6: PCI -------------------------------------------------------
  ["6/1"]="PCI|Warning|PCI bus option ROM error"
  ["6/2"]="PCI|Critical|PCI bus master abort / fatal peripheral error"
  ["6/3"]="PCI|Critical|PCIe slot power fault"

  # --- Class 8: POST / revision status ------------------------------------
  ["8/1"]="POST|OK|POST configuration successful / baseline changed"
  ["8/2"]="POST|OK|Configuration / NVRAM reset to factory defaults"
  ["8/12"]="POST|OK|System platform certificate validation success"
  ["8/15"]="POST|OK|Security state changed (e.g. Production -> HighSecurity/FIPS)"

  # --- Class 9: Operating system ------------------------------------------
  ["9/1"]="OS|OK|Operating system boot commenced"
  ["9/2"]="OS|Critical|OS unexpected software halt / NMI"
  ["9/3"]="OS|Warning|Agentless Management Service (AMS) heartbeat lost"
  ["9/10"]="OS|OK|OS shutdown cleanly initiated by OS agent"
  ["9/14"]="OS|Critical|OS freeze detected by watchdog timer"

  # --- Class 10 (Storage namespace): array controllers --------------------
  ["Storage:10/1"]="StorageController|OK|Storage array controller status OK"
  ["Storage:10/2"]="StorageController|Warning|Storage array controller degraded performance"
  ["Storage:10/4"]="StorageController|Warning|Cache module battery / capacitor charge low"
  ["Storage:10/8"]="StorageController|Critical|Smart Array controller hardware lockup / fatal fault"
  ["Storage:10/16"]="StorageController|Critical|Storage controller cryptographic key error / secure boot validation failed"
  ["Storage:10/24"]="StorageController|OK|Sanitize / secure erase completed successfully"
  ["Storage:10/32"]="StorageController|Warning|Controller configuration signature mismatch (drive roaming)"

  # --- Class 10 (UEFI namespace): firmware-reported memory faults ---------
  # Same Class integer, entirely different subsystem. See the header note.
  ["UEFI:10/614"]="Firmware|Critical|Non-volatile memory (NVRAM) corruption detected; configuration settings restored to defaults"
  ["UEFI:10/625"]="Firmware|OK|System firmware updated / component authenticity validation event"
  ["UEFI:10/12755"]="Memory|Warning|Unsupported DIMM configuration - processor DIMM population rules violated"
  ["UEFI:10/644"]="Memory|Critical|Uncorrectable DIMM error found by early firmware diagnostics (fatal multi-bit error)"
  ["UEFI:10/1120"]="Memory|Warning|Individual DIMM correctable-error threshold exceeded (DIMM electrically degrading)"
  ["UEFI:10/1126"]="Memory|Warning|Memory channel cumulative correctable-error threshold exceeded"

  # --- Class 11 (Power namespace): power supplies -------------------------
  # Class 11 is ambiguous exactly like Class 10. With ClassDescription
  # "Storage" it is drives and the energy pack; with "Power" it is the PSUs.
  # Observed on atlhwe-lsf309/315/316 (Gen11), where filing these under the
  # class-integer default reported a power-supply event as a storage device.
  ["Power:11/54"]="Power|Warning|System power supplies are not redundant"
  ["Power:11/82"]="Power|Warning|Power supply input power loss or unplugged cord - verify the supply input"

  # --- Class 11 (Storage namespace): drives / energy pack -----------------
  ["11/36"]="StorageDevice|Critical|Physical drive failure"
  ["11/52"]="StorageDevice|Warning|Storage enclosure supply failure"
  ["11/86"]="StorageDevice|Warning|Smart Storage Energy Pack pre-failure state"
  ["11/102"]="StorageDevice|Warning|NVMe drive over-temperature warning"
  ["11/114"]="StorageDevice|Warning|SSD max endurance / wear-out limit reached"
  ["11/120"]="StorageDevice|Critical|Physical drive logical block provisioning space exhausted"

  # --- Class 13: Automatic Server Recovery --------------------------------
  # ClassDescription "ASR". Categorised Administration by the firmware, not
  # Hardware, so it is filtered out of the default view - but it means the
  # server locked up and was force-reset, which is worth seeing with
  # --all-categories when triaging an unexplained reboot.
  ["ASR:13/1"]="Recovery|Warning|Automatic Server Recovery triggered by system ROM - the server stopped responding and was reset"

  # --- Class 17: Network --------------------------------------------------
  ["17/1"]="Network|OK|Network link connection established"
  ["17/2"]="Network|Warning|Network adapter link down / redundancy lost"
  ["17/10"]="Network|OK|NIC connectivity transitioned back to healthy"
  ["17/11"]="Network|Warning|Network link speed/duplex negotiation mismatch"
  ["17/15"]="Network|Critical|SmartNIC / OCP3 adapter security validation failed"

  # --- Class 20: hardware fault / mezzanine -------------------------------
  ["20/1"]="SystemBoard|Critical|Hardware fault / mezzanine component critical fault"

  # --- Class 33: maintenance ----------------------------------------------
  ["33/1"]="Maintenance|OK|Integrated Management Log cleared manually"
  ["33/5"]="Maintenance|OK|iLO firmware flashing completed successfully"
  # Reported Critical by the firmware but categorised Security,Maintenance -
  # a certificate lifecycle task, not a hardware fault. Filtered out of the
  # default view by the category rule, which is the point of that rule.
  ["Maintenance:33/13"]="Maintenance|Critical|Factory root CA certificate is approaching expiry"

  # --- Class 50 (UEFI / Innovation Engine namespace) ----------------------
  ["UEFI:50/355"]="Firmware|Warning|System time and date are not set"
  ["UEFI:50/545"]="SystemBoard|Critical|Unknown fatal initialization error during early system initialization"
  ["UEFI:50/547"]="Memory|Warning|Innovation Engine: DIMM initialization / memory training failure, channel mapped out"

  # --- Class 50 (System Management namespace) -----------------------------
  ["50/1"]="Recovery|Warning|Automatic Server Recovery (ASR) initiated - server locked up and iLO forced a reboot"
  ["50/2"]="Recovery|OK|Graceful remote power cycle initiated"
  ["50/5"]="Recovery|OK|Server reset due to iLO configuration change rollout"
  ["50/547"]="Recovery|OK|Telemetry / health monitoring daemon restarted after an isolated internal fault"
)

# Fallback subsystem when a Class/Code pair is not in the table at all. Keyed
# on the class integer alone, so an unknown code still lands in roughly the
# right bucket rather than being reported as "Other".
declare -gA IML_CLASS_FALLBACK=(
  [1]="Memory"      [2]="Thermal"          [3]="Power"
  [4]="SystemBoard" [5]="CPU"              [6]="PCI"
  [8]="POST"        [9]="OS"               [10]="StorageController"
  [11]="StorageDevice" [17]="Network"      [20]="SystemBoard"
  [33]="Maintenance"   [50]="Recovery"
)

# ClassDescription -> subsystem. Consulted BEFORE the class-integer fallback,
# because the description is the thing that disambiguates an overloaded class
# number. Getting this order wrong filed a Class 11 + "Power" power-supply
# event as a storage device on every Gen11 host tested.
declare -gA IML_DESC_FALLBACK=(
  ["CPU"]="CPU"                   ["Processor"]="CPU"
  ["Memory"]="Memory"             ["UEFI"]="Firmware"
  ["Power"]="Power"               ["Thermal"]="Thermal"
  ["Environment"]="Thermal"       ["Temperature"]="Thermal"
  ["Storage"]="StorageController" ["Drive"]="StorageDevice"
  ["Network"]="Network"           ["ASR"]="Recovery"
  ["Maintenance"]="Maintenance"   ["System Management"]="Recovery"
  ["OS"]="OS"                     ["Operating System"]="OS"
  ["PCI"]="PCI"                   ["System Board"]="SystemBoard"
  ["Security"]="Maintenance"      ["Firmware"]="Firmware"
)

# _iml_lookup <class> <code> <class_description>
# Print the raw "subsystem|severity|description" record, or nothing.
# Tries the ClassDescription-qualified key first - see the header note on why
# that ordering is load-bearing.
_iml_lookup() {
  local class="${1-}" code="${2-}" desc="${3-}" key
  if [[ -n "$desc" ]]; then
    key="${desc}:${class}/${code}"
    [[ -n "${IML_MAP[$key]-}" ]] && { printf '%s' "${IML_MAP[$key]}"; return 0; }
  fi
  key="${class}/${code}"
  [[ -n "${IML_MAP[$key]-}" ]] && { printf '%s' "${IML_MAP[$key]}"; return 0; }
  return 1
}

# iml_subsystem <class> <code> <class_description>
# Print the subsystem bucket this event belongs to. Always prints something.
iml_subsystem() {
  local rec sub
  if rec="$(_iml_lookup "$@")"; then
    sub="${rec%%|*}"
    [[ -n "$sub" ]] && { printf '%s' "$sub"; return 0; }
  fi
  # Not in the table. The payload's ClassDescription is tried BEFORE the class
  # integer: the description is what disambiguates an overloaded class number,
  # so a Class 11 + "Power" event must become Power, not the StorageDevice the
  # bare class integer would give.
  local class="${1-}" desc="${3-}"
  if [[ -n "$desc" && -n "${IML_DESC_FALLBACK[$desc]-}" ]]; then
    printf '%s' "${IML_DESC_FALLBACK[$desc]}"; return 0
  fi
  if [[ -n "${IML_CLASS_FALLBACK[$class]-}" ]]; then
    printf '%s' "${IML_CLASS_FALLBACK[$class]}"; return 0
  fi
  printf 'Other'
}

# iml_description <class> <code> <class_description>
# Print the documented meaning of this Class/Code pair, or nothing when the
# pair is undocumented. Callers fall back to the payload's own Message.
iml_description() {
  local rec rest
  if rec="$(_iml_lookup "$@")"; then
    rest="${rec#*|}"          # strip subsystem
    printf '%s' "${rest#*|}"  # strip expected severity
  fi
}

# iml_expected_severity <class> <code> <class_description>
# Print the severity the documentation predicts, or nothing. Cross-check only.
iml_expected_severity() {
  local rec rest
  if rec="$(_iml_lookup "$@")"; then
    rest="${rec#*|}"
    printf '%s' "${rest%%|*}"
  fi
}

# iml_is_known <class> <code> <class_description>
# True when the pair is documented. Used to flag undocumented codes so the
# table can be extended rather than silently guessing.
iml_is_known() { _iml_lookup "$@" >/dev/null; }
