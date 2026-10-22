#!/usr/bin/env bash
# lib/creds.sh - load and parse iLO/XCC credentials.
#
# Credentials come from a single ordered list:
#
#     ILO_CREDS=( "label:username:password" ... )
#
# set either in the environment or in a credentials file (--creds). There is
# no fleet default and no per-datacenter override to rank ahead of it: the
# array IS the whole statement of intent, tried in the order written. This is
# the model the inventory_script project settled on - do not re-introduce the
# retired ILO_USER / ILO_PASS / ILO_CREDS_ALT variables.
#
# The file may be encrypted at rest. ssh_crypt.sh at the tree root owns that
# format; this library only recognises it and shells out to decrypt. The
# plaintext never touches disk.

# CREDS_MAGIC must match MAGIC in ssh_crypt.sh. It is compared inline rather
# than by invoking the crypt tool, so the common case - a plaintext file, or
# none at all - costs no subprocess.
: "${CREDS_MAGIC:=#ILO-CREDS-RSA1}"

declare -ga ILO_CREDS=()
declare -ga CRED_LABELS=() CRED_USERS=() CRED_PASSES=()

# Which file the credentials actually came from, and whether it was encrypted.
# A run log that does not record this cannot answer "was this run reading the
# encrypted file?" after the fact - which is the whole question once the
# plaintext is deleted. Set by _load_creds_from on success.
declare -g CREDS_SOURCE=""
declare -g CREDS_ENCRYPTED=0

# _load_creds_from <file>
# Load one candidate credentials file. Returns non-zero if it could not be
# used, so the caller falls through to the next candidate instead of aborting:
# a key or openssl problem must never kill an unattended run outright.
_load_creds_from() {
  local src="$1" perms plain first='' key_args=()

  perms="$(stat -c '%a' "$src" 2>/dev/null || stat -f '%OLp' "$src" 2>/dev/null)"
  if [[ -n "$perms" && "${perms: -2}" != "00" ]]; then
    log_warn "${src} is readable by group/other (mode ${perms}); chmod 600 it"
  fi

  IFS= read -r first 2>/dev/null < "$src" || first=''

  if [[ "$first" != "$CREDS_MAGIC" ]]; then
    log_debug "reading credentials ${src}"
    # shellcheck disable=SC1090
    source "$src"
    CREDS_SOURCE="$src"; CREDS_ENCRYPTED=0
    return 0
  fi

  log_debug "decrypting credentials ${src}"
  if [[ ! -r "$SSH_CRYPT" ]]; then
    log_warn "${src} is encrypted but ${SSH_CRYPT} is missing; trying the next candidate"
    return 1
  fi
  # ssh_crypt.sh defaults to ~/.ssh/id_rsa and honours CREDS_SSH_KEY from the
  # environment, but a conf file can set it without exporting it and this is a
  # child process - so pass it explicitly when set.
  [[ -n "${CREDS_SSH_KEY:-}" ]] && key_args=(-k "$CREDS_SSH_KEY")
  # Run through bash rather than executing directly: a lost exec bit (archive
  # unpacked under a strict umask, a noexec mount) must not break a scheduled
  # run. The file goes via -f, NOT as a positional argument.
  plain="$(bash "$SSH_CRYPT" "${key_args[@]+"${key_args[@]}"}" -f "$src" decrypt 2>/dev/null)" || {
    log_warn "could not decrypt ${src}; trying the next candidate"
    return 1
  }
  if [[ -z "$plain" ]]; then
    log_warn "${src} decrypted to an empty file; trying the next candidate"
    return 1
  fi
  # RSA PKCS#1 v1.5 unpadding can return rc=0 and binary noise on a corrupt
  # block (OpenSSL 3.x implicit rejection), which bash would happily execute.
  # Require the result to look like a credentials file before sourcing it.
  if ! printf '%s\n' "$plain" | grep -Eq '^[[:space:]]*(export[[:space:]]+)?ILO_[A-Z0-9_]+='; then
    log_warn "${src} decrypted to something that is not a credentials file; trying the next candidate"
    unset plain
    return 1
  fi
  # shellcheck disable=SC1090
  source <(printf '%s\n' "$plain")
  unset plain
  CREDS_SOURCE="$src"; CREDS_ENCRYPTED=1
  return 0
}

# load_creds
# Prefer the encrypted sidecar when it exists, but keep accepting a plaintext
# file so a scheduled run is never killed by a key problem.
load_creds() {
  local cand
  [[ -n "${CREDS_FILE:-}" ]] || return 0
  for cand in "${CREDS_FILE}.enc" "$CREDS_FILE"; do
    [[ -r "$cand" ]] || continue
    _load_creds_from "$cand" && return 0
  done
  return 0
}

# creds_import_env
# Workers do not re-read the credentials file, so anything it defined has to
# arrive through the environment - and bash cannot export an array. The parent
# flattens ILO_CREDS into a newline-delimited _ILO_CREDS_ENV; this rebuilds it.
# Short-circuits when the list is already populated, so a conf file wins.
creds_import_env() {
  (( ${#ILO_CREDS[@]} )) && return 0
  [[ -n "${_ILO_CREDS_ENV:-}" ]] || return 0
  local e
  while IFS= read -r e; do
    [[ -n "$e" ]] && ILO_CREDS+=("$e")
  done <<< "$_ILO_CREDS_ENV"
}

# creds_export_env
# The inverse, for handing the list to a child process.
creds_export_env() {
  local e
  _ILO_CREDS_ENV=""
  for e in "${ILO_CREDS[@]+"${ILO_CREDS[@]}"}"; do
    if [[ "$e" == *$'\n'* ]]; then
      log_warn "an ILO_CREDS entry contains a newline; ignoring it"
      continue
    fi
    _ILO_CREDS_ENV+="${e}"$'\n'
  done
  export _ILO_CREDS_ENV
}

# creds_parse
# Populate CRED_LABELS / CRED_USERS / CRED_PASSES from ILO_CREDS.
creds_parse() {
  local entry label rest user pass idx=0

  CRED_LABELS=(); CRED_USERS=(); CRED_PASSES=()
  # Counted before expanding: bash 4.2 under `set -u` treats "${arr[@]}" on an
  # empty declared array as an unbound variable, and RHEL 7 is a target.
  (( ${#ILO_CREDS[@]} )) || return 0

  for entry in "${ILO_CREDS[@]}"; do
    idx=$(( idx + 1 ))
    [[ -z "$entry" ]] && continue
    # Split on the first two colons only, so a password containing a colon
    # survives intact. Labels and usernames may not contain one.
    if [[ "$entry" != *:*:* ]]; then
      # Reported by position, never by content: a malformed entry is most
      # often a bare password pasted in the wrong shape.
      log_warn "ILO_CREDS entry ${idx} is not label:username:password; ignoring"
      continue
    fi
    label="${entry%%:*}"; rest="${entry#*:}"
    user="${rest%%:*}";   pass="${rest#*:}"
    if [[ -z "$label" || -z "$user" || -z "$pass" ]]; then
      log_warn "ILO_CREDS entry ${idx} has an empty field; ignoring"
      continue
    fi
    CRED_LABELS+=("$label"); CRED_USERS+=("$user"); CRED_PASSES+=("$pass")
  done
}

# creds_count - how many usable credentials were parsed.
creds_count() { printf '%s' "${#CRED_USERS[@]}"; }

# ---------------------------------------------------------------------------
# Learned credential map
# ---------------------------------------------------------------------------
#
# Remembers WHICH credential worked for a given service processor, so a later
# run goes straight to it instead of walking the list again.
#
# The expensive part of a fallback scheme is not the wasted seconds, it is the
# failed logins accumulating against an account that can be locked out. The
# Gen11 hosts measured here take credential '3' while the older ones take '0',
# so an unaided sweep spends three failed logins and 45 seconds on every Gen11
# machine, every run. With the map, only the first run pays that.
#
# ---------------------------------------------------------------------------
# ONLY THE LABEL IS EVER STORED - NEVER PASSWORD MATERIAL
# ---------------------------------------------------------------------------
# A map file contains one line: the label from the ILO_CREDS entry that won.
# The password stays in the credentials file or the environment. This is a
# guarantee, not an implementation detail: do not "improve" this by caching
# the credential itself, or the directory becomes a secret store that needs
# protecting, auditing and encrypting like creds/ does.
#
# Default location mirrors inventory_script's production setting
# (INVENTORY_BASE/tmp/credmap): the project's own tmp/ directory.
: "${CREDMAP_DIR:=${BASE_DIR:-.}/tmp/credmap}"
: "${USE_CREDMAP:=1}"

# creds_prefer_learned <sp>
# Rotate the remembered credential to the front of the list, leaving the rest
# in configured order so the fallback sequence stays predictable.
#
# Degrades gracefully on a label that is no longer configured: it logs and
# leaves the order alone, so a stale or hand-edited map costs the normal
# fallback rather than a failure.
creds_prefer_learned() {
  local sp="$1" want i n
  (( USE_CREDMAP )) || return 0
  [[ -n "${CREDMAP_DIR:-}" && -n "$sp" ]] || return 0

  local map_file="${CREDMAP_DIR}/${sp}"
  [[ -r "$map_file" ]] || return 0
  IFS= read -r want < "$map_file" || true
  [[ -n "$want" ]] || return 0

  n="${#CRED_LABELS[@]}"
  for (( i = 0; i < n; i++ )); do
    [[ "${CRED_LABELS[$i]}" == "$want" ]] || continue
    (( i == 0 )) && { log_debug "${sp}: remembered credential '${want}' is already first"; return 0; }
    local l="${CRED_LABELS[$i]}" u="${CRED_USERS[$i]}" p="${CRED_PASSES[$i]}"
    # Delete at i, then prepend. Written with explicit index juggling rather
    # than array slicing because bash 4.2 under `set -u` errors on a slice of
    # an array that ends up empty.
    local -a nl=() nu=() np=()
    nl+=("$l"); nu+=("$u"); np+=("$p")
    local j
    for (( j = 0; j < n; j++ )); do
      (( j == i )) && continue
      nl+=("${CRED_LABELS[$j]}"); nu+=("${CRED_USERS[$j]}"); np+=("${CRED_PASSES[$j]}")
    done
    CRED_LABELS=("${nl[@]}"); CRED_USERS=("${nu[@]}"); CRED_PASSES=("${np[@]}")
    log_debug "${sp}: trying remembered credential '${want}' first"
    return 0
  done

  log_warn "${sp}: remembered credential '${want}' is no longer configured; using the configured order"
  return 0
}

# creds_remember <sp> <label>
# Record which credential worked. No-op when the value is unchanged, so a
# repeat run does no writes at all.
creds_remember() {
  local sp="$1" label="$2" tmp current
  (( USE_CREDMAP )) || return 0
  [[ -n "${CREDMAP_DIR:-}" && -n "$sp" && -n "$label" ]] || return 0

  if [[ -r "${CREDMAP_DIR}/${sp}" ]]; then
    IFS= read -r current < "${CREDMAP_DIR}/${sp}" || true
    [[ "$current" == "$label" ]] && return 0
  fi

  mkdir -p "$CREDMAP_DIR" 2>/dev/null || return 0
  tmp="$(mktemp "${CREDMAP_DIR}/.${sp}.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$label" > "$tmp"
  # Rename rather than write in place: the fleet driver runs these
  # concurrently, and a reader must never see a half-written file.
  mv -f "$tmp" "${CREDMAP_DIR}/${sp}" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  log_debug "${sp}: remembered credential '${label}'"
  return 0
}
