#!/usr/bin/env bash
# lib/redfish.sh - authenticated Redfish GETs against a service processor.
#
# Vendor-neutral: the HPE and Lenovo checkers both use these helpers and
# differ only in which resource paths they ask for.
#
# Sets the global RF_STATUS after a fetch, using the vocabulary the
# inventory_script project settled on:
#
#   ok            a 200 with a JSON body
#   unreachable   nothing answered at all (connect timeout, no route, powered off)
#   auth_failed   the SP answered but refused every credential
#   http_<code>   it answered with something else

: "${ILO_CONNECT_TIMEOUT:=10}"
: "${ILO_MAX_TIME:=60}"
: "${ILO_RETRIES:=1}"
# Seconds to wait between credential attempts. See the block comment in
# rf_try_credentials - this default is deliberately large.
: "${ILO_AUTH_RETRY_DELAY:=15}"

RF_STATUS=""
RF_CRED_LABEL=""
RF_HTTP_CODE=""

# _rf_curl_config <user> <pass>
# Emit a curl config stanza carrying the credentials, for use via --config.
#
# This exists so the password never appears in any process's argv. Passing
# -u "user:pass" puts the secret in /proc/<pid>/cmdline, which is world
# readable - any other user on the box can see it with a plain ps. printf and
# parameter expansion are bash builtins, so no child is ever exec'd holding
# the secret.
_rf_curl_config() {
  local esc="${1}:${2}"
  # curl unescapes \\ and \" inside a double-quoted config value, so both have
  # to be doubled on the way in or a password containing either is corrupted.
  esc="${esc//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  printf 'user = "%s"\n' "$esc"
}

# rf_get <user> <pass> <sp> <path> <outfile>
# GET a Redfish path into <outfile>. Prints nothing. Sets RF_HTTP_CODE.
# Returns 0 only on a 200 with a parseable JSON body.
rf_get() {
  local user="$1" pass="$2" sp="$3" path="$4" out="$5" code

  # --location: older iLO firmware answers collection URIs with a 308 redirect
  # to the same URI plus a trailing slash, and without following it those hosts
  # yield nothing. curl drops credentials on a redirect to a DIFFERENT host
  # unless --location-trusted is given, which it deliberately is not, so this
  # cannot leak the password somewhere unexpected. --max-redirs bounds a
  # misbehaving SP that loops.
  code="$(curl -s --insecure \
      --config <(_rf_curl_config "$user" "$pass") \
      --location --max-redirs 3 \
      --connect-timeout "$ILO_CONNECT_TIMEOUT" \
      --max-time "$ILO_MAX_TIME" \
      --retry "$ILO_RETRIES" \
      -H 'Accept: application/json' \
      -o "$out" \
      -w '%{http_code}' \
      "https://${sp}${path}" 2>/dev/null)" || code="000"

  RF_HTTP_CODE="${code:-000}"

  case "$RF_HTTP_CODE" in
    200) : ;;
    000) RF_STATUS="unreachable"; log_debug "${sp}${path} -> no answer";       return 1 ;;
    401|403) RF_STATUS="auth_failed"; log_debug "${sp}${path} -> HTTP ${RF_HTTP_CODE}"; return 1 ;;
    *)   RF_STATUS="http_${RF_HTTP_CODE}"; log_debug "${sp}${path} -> HTTP ${RF_HTTP_CODE}"; return 1 ;;
  esac

  if ! jq -e . "$out" >/dev/null 2>&1; then
    RF_STATUS="http_200_nonjson"
    log_debug "${sp}${path} -> 200 with a non-JSON body"
    return 1
  fi

  RF_STATUS="ok"
  return 0
}

# rf_auth_probe <user> <pass> <sp>
# Ask one cheap authenticated question and print the raw HTTP status.
#
# This exists because a failed fetch cannot by itself tell "wrong password"
# from "the box is powered off", and that difference decides whether trying
# another credential is sensible or is just burning a login attempt against a
# machine that is not listening. Service processors lock an account after a
# handful of failures, so across a fleet guessing wrong is expensive.
#
# Deliberately --retry 0: the caller is counting login attempts and curl's
# retry logic would quietly turn one into several.
rf_auth_probe() {
  local user="$1" pass="$2" sp="$3" code
  code="$(curl -s --insecure \
      --config <(_rf_curl_config "$user" "$pass") \
      --connect-timeout "$ILO_CONNECT_TIMEOUT" \
      --max-time "$ILO_MAX_TIME" \
      --retry 0 \
      -H 'Accept: application/json' \
      -o /dev/null \
      -w '%{http_code}' \
      "https://${sp}/redfish/v1/Systems" 2>/dev/null)" || code="000"
  printf '%s' "${code:-000}"
}

# rf_try_credentials <sp> <path> <outfile>
# Walk CRED_USERS/CRED_PASSES in order until one fetches <path> successfully.
# Sets RF_STATUS and RF_CRED_LABEL. Returns 0 on success.
#
# ---------------------------------------------------------------------------
# LOCKOUT SAFETY IS THE POINT OF THIS FUNCTION - DO NOT "OPTIMISE" THE SLEEP
# ---------------------------------------------------------------------------
# After a couple of rejected logins an HPE iLO answers 401 to EVERY login for
# a short window, valid ones included. A credential list walked faster than
# that window locks itself out on the wrong passwords and then reports the
# CORRECT one as rejected - indistinguishable from a genuinely unknown
# credential, and the most expensive class of false negative this tooling can
# produce. ILO_AUTH_RETRY_DELAY defaults to 15s for that reason.
#
# The window is a firmware setting and varies per host. An iLO publishes its
# own value, unauthenticated and free, at /redfish/v1/ ->
# Oem.Hpe.Sessions.LoginFailureDelay; rf_login_failure_delay reads it, and the
# effective pace is max(published, ILO_AUTH_RETRY_DELAY). Treat a published 0
# as a floor to respect, never as proof that no delay applies - a host
# declaring 0 has been observed exhibiting the lockout anyway.
#
# Candidate 1 goes straight to the real fetch (optimistic, no probe, no sleep),
# so the happy path costs zero failed logins. Candidates 2..N are gated behind
# a cheap probe. Advance ONLY on a genuine 401/403: a timeout or a refusal
# means nothing is listening, and trying another password proves nothing.
rf_try_credentials() {
  local sp="$1" path="$2" out="$3"
  local i n label user pass code
  local saw_rejection=0 last_status="unreachable" delay

  n="${#CRED_USERS[@]}"
  (( n )) || { RF_STATUS="no_credentials"; return 1; }

  delay="$(rf_effective_delay "$sp")"

  for (( i = 0; i < n; i++ )); do
    label="${CRED_LABELS[$i]}"; user="${CRED_USERS[$i]}"; pass="${CRED_PASSES[$i]}"

    if (( i > 0 )); then
      log_debug "pacing ${delay}s before credential '${label}' on ${sp}"
      sleep "$delay"
      # Cheap probe first, so a doomed attempt costs one login rather than a
      # full resource walk.
      code="$(rf_auth_probe "$user" "$pass" "$sp")"
      case "$code" in
        000)     RF_STATUS="unreachable"; return 1 ;;
        401|403) saw_rejection=1; last_status="auth_failed"; continue ;;
      esac
    fi

    if rf_get "$user" "$pass" "$sp" "$path" "$out"; then
      RF_CRED_LABEL="$label"
      RF_STATUS="ok"
      return 0
    fi

    last_status="$RF_STATUS"
    case "$RF_HTTP_CODE" in
      401|403) saw_rejection=1 ;;
      # Anything else means the SP is not refusing us - it is down, or broken,
      # or answering something unexpected. Another password cannot help.
      *) RF_STATUS="$last_status"; return 1 ;;
    esac
  done

  # Upgrade-only: if any probe proved the SP is up and rejecting us, say so
  # rather than reporting it as unreachable. Never overwrite a verdict a real
  # fetch was certain of.
  if (( saw_rejection )); then
    RF_STATUS="auth_failed"
  else
    RF_STATUS="$last_status"
  fi
  return 1
}

# rf_detect_vendor <sp>
# Print "HPE", "Lenovo", or "unknown" for a service processor.
#
# UNAUTHENTICATED AND FREE. The Redfish service root needs no credentials, so
# this costs no login attempt and cannot contribute to a lockout. That is what
# makes it the right way for check_hardware.sh to choose between
# check_hpe_iml.sh and check_lenovo_iml.sh: a wrong guess would otherwise mean
# reading the wrong log path with a real credential and getting a 404.
#
# ---------------------------------------------------------------------------
# THE TWO VENDORS ADVERTISE THEMSELVES DIFFERENTLY - CHECK BOTH
# ---------------------------------------------------------------------------
# HPE  : .Oem.Hpe is populated, .Product is "ProLiant ...", no .Vendor field.
# Lenovo: .Oem is an EMPTY OBJECT and .Product is absent; the only marker at
#         the root is a top-level .Vendor = "Lenovo".
#
# A detector that only looks at .Oem.<name> therefore returns "unknown" for
# every Lenovo machine - which is exactly what happened here during testing,
# after an earlier probe that did include the .Vendor fallback had worked.
# Verified across all seven test hosts: 5 HPE by .Oem.Hpe, 2 Lenovo by .Vendor.
rf_detect_vendor() {
  local sp="$1" v
  v="$(curl -s --insecure \
        --connect-timeout "$ILO_CONNECT_TIMEOUT" --max-time 20 --retry 0 \
        -H 'Accept: application/json' \
        "https://${sp}/redfish/v1/" 2>/dev/null \
      | jq -r 'if (.Vendor // "") != "" then .Vendor
               elif (.Oem.Hpe // null) != null then "HPE"
               elif (.Oem.Lenovo // null) != null then "Lenovo"
               elif ((.Product // "") | test("ProLiant"; "i")) then "HPE"
               elif ((.Product // "") | test("ThinkSystem"; "i")) then "Lenovo"
               else "unknown" end' 2>/dev/null)" || v=""
  printf '%s' "${v:-unknown}"
}

# rf_login_failure_delay <sp>
# Print the SP's own published lockout window in seconds, or nothing.
# Unauthenticated and free - the service root needs no credentials - so this
# costs no login attempt and cannot itself contribute to a lockout.
rf_login_failure_delay() {
  local sp="$1" v
  v="$(curl -s --insecure \
        --connect-timeout "$ILO_CONNECT_TIMEOUT" --max-time 15 --retry 0 \
        -H 'Accept: application/json' \
        "https://${sp}/redfish/v1/" 2>/dev/null \
      | jq -r '.Oem.Hpe.Sessions.LoginFailureDelay // empty' 2>/dev/null)" || v=""
  [[ "$v" =~ ^[0-9]+$ ]] && printf '%s' "$v"
}

# rf_effective_delay <sp>
# max(published LoginFailureDelay, ILO_AUTH_RETRY_DELAY).
rf_effective_delay() {
  local sp="$1" pub
  pub="$(rf_login_failure_delay "$sp")"
  if [[ "$pub" =~ ^[0-9]+$ ]] && (( pub > ILO_AUTH_RETRY_DELAY )); then
    printf '%s' "$pub"
  else
    printf '%s' "$ILO_AUTH_RETRY_DELAY"
  fi
}

# rf_resolve_system <user> <pass> <sp> <workdir>
# Print the Redfish ComputerSystem resource id (e.g. "1", or "Node.1" on some
# Lenovo XCC firmware). Tries the conventional /Systems/1 first so the common
# case costs one request, then falls back to enumerating the collection.
#
# Returns immediately on 401/403 rather than enumerating: a credential that
# was refused on /Systems/1 will be refused on /Systems too, and spending a
# second guaranteed-doomed login per host is exactly what drives a lockout.
rf_resolve_system() {
  local user="$1" pass="$2" sp="$3" wd="$4" id

  if rf_get "$user" "$pass" "$sp" "/redfish/v1/Systems/1" "${wd}/sys1.json"; then
    printf '1'; return 0
  fi
  case "$RF_HTTP_CODE" in
    401|403|000) return 1 ;;
  esac

  rf_get "$user" "$pass" "$sp" "/redfish/v1/Systems" "${wd}/systems.json" || return 1
  id="$(jq -r '.Members[0]."@odata.id" // empty' "${wd}/systems.json" 2>/dev/null)"
  id="${id%/}"; id="${id##*/}"
  [[ -n "$id" ]] || return 1
  printf '%s' "$id"
}

# rf_get_collection <user> <pass> <sp> <path> <outfile>
# Fetch a Redfish collection, following Members@odata.nextLink and merging
# every page's Members into one document at <outfile>.
#
# The test host returns all 226 IML entries in a single response, but a server
# with a long fault history can page. Without this, such a host silently
# reports only its first page of findings - a quiet undercount, which is worse
# than an error.
rf_get_collection() {
  local user="$1" pass="$2" sp="$3" path="$4" out="$5"
  local page=0 next="$path" tmp merged
  tmp="${out}.page"
  merged="${out}.acc"
  : > "$merged"

  while [[ -n "$next" ]]; do
    page=$(( page + 1 ))
    if (( page > 50 )); then
      log_warn "${sp}: stopping after 50 pages of ${path}; results may be incomplete"
      break
    fi
    rf_get "$user" "$pass" "$sp" "$next" "$tmp" || { rm -f "$tmp"; return 1; }
    jq -c '.Members[]?' "$tmp" >> "$merged" 2>/dev/null
    next="$(jq -r '.["Members@odata.nextLink"] // empty' "$tmp" 2>/dev/null)"
    # A nextLink may be absolute; reduce it to a path.
    [[ "$next" == http* ]] && next="/${next#*://*/}"
  done

  # Reassemble into a document with the same shape as a single-page response,
  # so every caller downstream can ignore paging entirely.
  jq -s '{Members: ., "Members@odata.count": length}' "$merged" > "$out" 2>/dev/null || {
    rm -f "$tmp" "$merged" 2>/dev/null || true; return 1
  }
  # Quietly: some mounts permit write but not unlink, and the work directory
  # is removed wholesale by the caller's EXIT trap anyway.
  rm -f "$tmp" "$merged" 2>/dev/null || true
  (( page > 1 )) && log_debug "${sp}${path}: merged ${page} pages"
  return 0
}
