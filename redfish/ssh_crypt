#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ssh_crypt.sh - encrypt/decrypt a file against an RSA SSH keypair.
# ---------------------------------------------------------------------------
#
# WHAT THIS IS
# ------------
# A standalone operator tool. It wraps any small file with the public half of
# an RSA SSH key so that what sits on disk is unreadable without the private
# half. Written for creds/ilo_creds -- which is why that is the default target
# -- but the file is just bytes to this script, so it works on any file that
# fits inside one RSA block.
#
#     ssh_crypt.sh check                    # key + file status, changes nothing
#     ssh_crypt.sh encrypt                  # creds/ilo_creds -> creds/ilo_creds.enc
#     ssh_crypt.sh decrypt                  # plaintext to stdout
#     ssh_crypt.sh edit                     # decrypt -> $EDITOR -> re-encrypt
#
#     ssh_crypt.sh encrypt ~/notes.txt                  # any other file
#     ssh_crypt.sh -k ~/.ssh/other_rsa decrypt secrets   # any other keypair
#
# The scheme is deliberately identical to the one already in local use by
# snow_lookup / rtm_job_lookup / ib_get_mac:
#
#     ssh-keygen -e -f ~/.ssh/id_rsa.pub -m PKCS8   ->  an RSA public key PEM
#     openssl pkeyutl -encrypt -pubin -inkey <that> ->  raw ciphertext
#     base64                                        ->  a text file
#
# and in reverse with "openssl pkeyutl -decrypt -inkey ~/.ssh/id_rsa". An
# operator who has seen one of those scripts can recover a file here by hand.
#
# ---------------------------------------------------------------------------
# !! THIS SCRIPT OWNS THE ON-DISK FORMAT !!
# ---------------------------------------------------------------------------
# This script is self-contained ON PURPOSE: copy it anywhere and it runs. It is
# also the ONLY implementation of the format - collect_inventory.sh shells out
# to this file to decrypt at run time rather than carrying its own copy of the
# crypt primitives. There is nothing left to keep in sync.
#
# The collector still recognises an encrypted credentials file by comparing its
# first line inline, so the magic string is duplicated there as CREDS_MAGIC -
# that one constant, and nothing else, has to match:
#
#     * the magic line below,
#     * base64 of a single raw PKCS#1 v1.5 RSA block,
#     * body starts at line 2.
#
# If the format is ever bumped, update CREDS_MAGIC in collect_inventory.sh too,
# or an overnight collection run stops recognising its own credentials.
#
# THE SIZE CEILING -- READ THIS BEFORE ADDING CREDENTIALS
# ------------------------------------------------------
# This is direct RSA, not an AES envelope, so the plaintext must fit inside a
# single RSA block: keysize/8 - 11 bytes with PKCS#1 v1.5 padding. For a
# 2048-bit key that is 245 bytes. The ceiling is a known and accepted tradeoff,
# not an oversight, and it is enforced loudly at ENCRYPT time against the real
# key rather than hardcoded, so a larger key lifts the limit automatically.
#
# WHY THE MAGIC LINE IS A SHELL COMMENT
# ------------------------------------
# "#ILO-CREDS-RSA1" is both the format marker AND a valid no-op shell comment,
# so if some future code path sources an encrypted file by mistake, line 1
# cannot execute anything. The base64 body below it is not valid shell and
# errors out visibly rather than silently defining half a credential.
#
# KEY FORMAT CAVEAT
# -----------------
# "openssl pkeyutl -decrypt" cannot read the modern OpenSSH container
# ("-----BEGIN OPENSSH PRIVATE KEY-----"); it needs classic PEM. That failure
# would only show up on DECRYPT, i.e. long after the plaintext might have been
# deleted -- so preflight refuses to encrypt against such a key, and encrypt
# additionally decrypts its own output and compares it to the source before
# committing anything. ED25519 keys cannot be used at all and are caught up
# front.
# ---------------------------------------------------------------------------

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
BASE_DIR="$(dirname "$SELF")"
PROG="$(basename "$SELF")"

# Format marker. Bump the trailing digit if the payload encoding ever changes
# -- and mirror it into CREDS_MAGIC in run_inventory/collect_inventory.sh.
MAGIC='#ILO-CREDS-RSA1'

# Default target. creds/ lives beside this script at the tree root, which is
# also what inventory.service's --creds argument and the ILO_CREDS_FILE line
# in the site conf point at. Any other file can be named on the command line.
TARGET="${BASE_DIR}/creds/ilo_creds"

# Wrapping keypair. The CREDS_SSH_* env vars are honoured because the collector
# may set them and passes CREDS_SSH_KEY through as -k when it calls this script;
# -k/-p override them. HOME is not dependable under cron or systemd, so fall
# back to the passwd entry rather than silently resolving "/.ssh/id_rsa".
if [[ -z "${CREDS_SSH_KEY:-}" ]]; then
    _home="${HOME:-}"
    [[ -n "$_home" ]] || _home="$(getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $6}')"
    CREDS_SSH_KEY="${_home}/.ssh/id_rsa"
    unset _home
fi
# The public half defaults to <key>.pub so that -k alone does the right thing.
: "${CREDS_SSH_PUB:=${CREDS_SSH_KEY}.pub}"

OUT=""          # -o; defaults to <TARGET>.enc at use time
PUB_EXPLICIT=0  # did -p name a public key, or are we deriving it from -k?
[[ -n "${CREDS_SSH_PUB+x}" && "$CREDS_SSH_PUB" != "${CREDS_SSH_KEY}.pub" ]] && PUB_EXPLICIT=1

err()  { printf '[ERROR] %s\n' "$*" >&2; }
warn() { printf '[WARN ] %s\n' "$*" >&2; }
info() { printf '[INFO ] %s\n' "$*" >&2; }

usage() {
  cat >&2 <<EOF
usage: ${PROG} [options] {check|encrypt|decrypt|edit} [FILE]

  check     report key type, block limit and the state of both files
  encrypt   encrypt FILE to FILE.enc (the plaintext is left in place)
  decrypt   write the decrypted contents of FILE.enc to stdout
  edit      decrypt FILE.enc into a temp file, open \$EDITOR, re-encrypt

  FILE      file to operate on; a trailing .enc is ignored, so both
            spellings work. May also be given as -f FILE.
            (default: ${TARGET})

  -k, --key FILE   private key (default: ${CREDS_SSH_KEY})
  -p, --pub FILE   public key  (default: <private key>.pub)
  -o, --out FILE   destination for encrypt (default: <FILE>.enc)
  -h, --help       this text

Diagnostics go to stderr, so "decrypt" can be piped or redirected safely.
EOF
}

# --- inspection --------------------------------------------------------------

# is_encrypted <file> -- true when line 1 carries the format marker. Cheap:
# reads one line. Non-zero for a missing, unreadable or empty file too, so it
# doubles as a plain "is this the encrypted one?" test.
is_encrypted() {
    local f="${1:-}" first
    [[ -n "$f" && -r "$f" ]] || return 1
    IFS= read -r first < "$f" || return 1
    [[ "$first" == "$MAGIC" ]]
}

# ssh-keygen -lf prints "<bits> <fingerprint> <comment> (<TYPE>)".
keybits() {
    local line bits
    line="$(ssh-keygen -lf "$CREDS_SSH_PUB" 2>/dev/null)" || return 1
    bits="${line%% *}"
    [[ "$bits" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$bits"
}

keytype() {
    local line
    line="$(ssh-keygen -lf "$CREDS_SSH_PUB" 2>/dev/null)" || return 1
    line="${line##*\(}"
    printf '%s\n' "${line%\)}"
}

# Largest plaintext that fits one block: keysize/8 minus PKCS#1 v1.5 padding.
max_bytes() {
    local bits
    bits="$(keybits)" || return 1
    printf '%s\n' "$(( bits / 8 - 11 ))"
}

# Only the PEM banner is ever bound to a variable; the ENCRYPTED probe runs as
# a pipeline so no line of actual key material is captured anywhere.
key_format() {
    local banner=""
    [[ -r "$CREDS_SSH_KEY" ]] || { printf 'unreadable\n'; return 1; }
    IFS= read -r banner < "$CREDS_SSH_KEY" || true
    case "$banner" in
        *"BEGIN OPENSSH PRIVATE KEY"*)   printf 'openssh\n' ;;
        *"BEGIN ENCRYPTED PRIVATE KEY"*) printf 'encrypted-pkcs8\n' ;;
        *"BEGIN RSA PRIVATE KEY"*)
            # A passphrase-protected classic PEM key announces itself with
            # "Proc-Type: 4,ENCRYPTED" a line or two after the banner.
            if head -n 3 -- "$CREDS_SSH_KEY" 2>/dev/null | grep -q 'ENCRYPTED'; then
                printf 'encrypted-pem-rsa\n'
            else
                printf 'pem-rsa\n'
            fi
            ;;
        *"BEGIN PRIVATE KEY"*)           printf 'pem-pkcs8\n' ;;
        *)                               printf 'unknown\n' ;;
    esac
}

# Everything knowable before touching the target file. Called by encrypt and
# check; NOT by decrypt, which stays cheap.
preflight() {
    local cmd missing="" ktype kfmt

    for cmd in openssl ssh-keygen base64; do
        command -v "$cmd" >/dev/null 2>&1 || missing="${missing} ${cmd}"
    done
    [[ -z "$missing" ]] || { err "missing required command(s):${missing}"; return 1; }

    [[ -r "$CREDS_SSH_PUB" ]] || { err "public key not readable: $CREDS_SSH_PUB"; return 1; }
    [[ -r "$CREDS_SSH_KEY" ]] || { err "private key not readable: $CREDS_SSH_KEY"; return 1; }

    ktype="$(keytype)" || { err "cannot fingerprint $CREDS_SSH_PUB"; return 1; }
    if [[ "$ktype" != "RSA" ]]; then
        err "$CREDS_SSH_PUB is an ${ktype} key, and this scheme requires RSA:" \
            "ssh-keygen cannot express ${ktype} as PKCS8 and openssl pkeyutl cannot wrap with it"
        return 1
    fi

    kfmt="$(key_format)"
    case "$kfmt" in
        pem-rsa|pem-pkcs8) ;;
        openssh)
            err "$CREDS_SSH_KEY is in the OpenSSH container format, which" \
                "'openssl pkeyutl -decrypt' cannot read -- encryption would appear to" \
                "succeed and then fail on the next run. Convert a COPY of the key with:" \
                "ssh-keygen -p -m PEM -f <copy-of-key>"
            return 1
            ;;
        encrypted-pem-rsa|encrypted-pkcs8)
            err "$CREDS_SSH_KEY is passphrase-protected; an unattended run could not" \
                "decrypt without prompting. Use an unencrypted key for this purpose."
            return 1
            ;;
        *)
            warn "could not identify the format of $CREDS_SSH_KEY; continuing," \
                 "encrypt-time self-verification will catch it if it is unusable"
            ;;
    esac
    return 0
}

# --- the actual work ---------------------------------------------------------

# decrypt_to_stdout <encrypted-file>
# Nothing is written to disk at any point, so there is no window in which a
# cleartext copy exists for someone else to read.
#
# -passin pass: supplies an empty passphrase rather than leaving openssl free
# to open /dev/tty and prompt. Not a secret -- it is what turns "hangs a cron
# run forever" into "fails immediately with a readable error".
# key_matches <encrypted-file>
#   0 = the private key really is the one this was encrypted to
#   1 = it is NOT -- whatever openssl hands back is garbage, discard it
#   2 = could not determine (old openssl, no od); caller should fall back
#
# This exists because of a genuinely nasty openssl behaviour change. OpenSSL
# 3.2 (and 3.0.2 as shipped by Ubuntu) implements "implicit rejection", the
# mitigation for the Marvin timing attack on RSA PKCS#1 v1.5: when unpadding
# fails, instead of reporting an error it returns a *deterministic
# pseudorandom string derived from the key and the ciphertext*, with exit
# status 0. So the obvious check -- "did openssl exit non-zero?" -- silently
# passes for a completely wrong key, and the caller gets plausible-looking
# binary noise. Measured on OpenSSL 3.0.2: wrong key -> rc=0, 193 bytes of
# garbage, empty stderr, same bytes on every run.
#
# The fix is to stop asking openssl whether the padding was valid and look at
# the padding ourselves. rsa_padding_mode:none returns the raw modular
# exponentiation result, untouched by any unpadding logic and therefore
# untouched by implicit rejection. A block produced by the matching key is
# PKCS#1 v1.5 formatted:  00 02 <>=8 nonzero padding bytes> 00 <message>.
# With the wrong key the result is uniform noise, which fails that shape
# essentially always -- a false accept needs byte 2 to be 0x02 and then eight
# straight nonzero bytes, about 1 in 2^16.
#
# RHEL 7's OpenSSL 1.0.2 predates implicit rejection and errors out properly,
# so there this is a harmless second opinion. It is the 3.x hosts that need it.
key_matches() {
    local src="${1:-}" hex start i ps=0

    command -v od >/dev/null 2>&1 || return 2

    hex="$(tail -n +2 -- "$src" 2>/dev/null \
            | base64 -d 2>/dev/null \
            | openssl pkeyutl -decrypt -inkey "$CREDS_SSH_KEY" -passin pass: \
                      -pkeyopt rsa_padding_mode:none 2>/dev/null \
            | od -An -tx1 -v 2>/dev/null | tr -d ' \n')"

    # No raw block at all means this openssl would not do rsa_padding_mode:none.
    # That is "cannot tell", not "wrong key" -- do not fail the operator on it.
    [[ -n "$hex" && ${#hex} -ge 128 ]] || return 2

    # Some builds emit the leading zero byte of the block, some drop it.
    start=0
    [[ "${hex:0:2}" == "00" ]] && start=2
    [[ "${hex:start:2}" == "02" ]] || return 1
    (( start += 2 ))

    # Walk the padding string: it must be at least 8 nonzero bytes and is
    # terminated by a 00 separator.
    for (( i = start; i + 1 < ${#hex}; i += 2 )); do
        if [[ "${hex:i:2}" == "00" ]]; then
            (( ps >= 8 )) && return 0
            return 1
        fi
        (( ps++ ))
    done
    return 1
}

decrypt_to_stdout() {
    local src="${1:-}"
    local st0 st1 st2
    local -a st

    [[ -n "$src" && -r "$src" ]] || { err "cannot read ${src:-<no file given>}"; return 1; }
    if ! is_encrypted "$src"; then
        err "$src is not in our format (line 1 is not ${MAGIC})"
        return 1
    fi
    [[ -r "$CREDS_SSH_KEY" ]] || { err "private key not readable: $CREDS_SSH_KEY"; return 1; }

    # Establish the key is right BEFORE emitting a single byte, so a wrong key
    # can never put garbage on stdout -- which for "decrypt > file" or "edit"
    # would mean overwriting good credentials with noise.
    key_matches "$src"
    case $? in
        1) err "$CREDS_SSH_KEY is not the private half of the key $src was" \
               "encrypted to. (Nothing was written. Note that openssl 3.x" \
               "reports success in this case and hands back random bytes," \
               "so this check is deliberately not trusting its exit status.)"
           return 1 ;;
        2) warn "cannot pre-verify the key against $src on this openssl;" \
                "falling back to trusting its exit status" ;;
    esac

    tail -n +2 -- "$src" \
        | base64 -d 2>/dev/null \
        | openssl pkeyutl -decrypt -inkey "$CREDS_SSH_KEY" -passin pass: 2>/dev/null
    st=( "${PIPESTATUS[@]}" )
    st0="${st[0]}"; st1="${st[1]}"; st2="${st[2]}"

    if (( st0 != 0 || st1 != 0 || st2 != 0 )); then
        err "could not decrypt $src (tail=${st0} base64=${st1} openssl=${st2});" \
            "is $CREDS_SSH_KEY the private half of the key it was encrypted to," \
            "and is it in classic PEM format?"
        return 1
    fi
    return 0
}

# encrypt_file <plaintext-file> <destination>
# Writes <destination> only if the result provably decrypts back to the source.
# The source is left alone -- deleting the cleartext is an operator decision,
# never this script's.
encrypt_file() {
    local src="${1:-}" dst="${2:-}"
    local size max pub_pem dstdir tmp

    if [[ -z "$src" || -z "$dst" ]]; then
        err "usage: encrypt_file <plaintext-file> <destination>"
        return 2
    fi
    [[ -r "$src" ]] || { err "cannot read $src"; return 1; }
    preflight || return 1

    if is_encrypted "$src"; then
        err "$src is already encrypted; refusing to double-wrap it"
        return 1
    fi

    # Size gate. This is the whole reason the failure mode of direct RSA is
    # acceptable: it is impossible to silently overflow, because openssl would
    # refuse anyway and we would rather say why.
    size="$(wc -c < "$src" 2>/dev/null | tr -d '[:space:]')"
    max="$(max_bytes)" || { err "cannot determine key size from $CREDS_SSH_PUB"; return 1; }
    if [[ -z "$size" || ! "$size" =~ ^[0-9]+$ ]]; then
        err "cannot determine the size of $src"
        return 1
    fi
    if (( size > max )); then
        err "$src is ${size} bytes but a $(keybits)-bit RSA key can only wrap ${max} bytes" \
            "in one block. Shorten the file, use a larger key, or move to envelope" \
            "encryption (AES data key wrapped with RSA) -- see the header of this script."
        return 1
    fi

    pub_pem="$(ssh-keygen -e -f "$CREDS_SSH_PUB" -m PKCS8 2>/dev/null)" \
        || { err "ssh-keygen could not convert $CREDS_SSH_PUB to a PKCS8 public key"; return 1; }

    dstdir="$(dirname -- "$dst")"
    [[ -d "$dstdir" ]] || { err "destination directory does not exist: $dstdir"; return 1; }

    # mktemp in the DESTINATION directory, not /tmp: it creates at mode 600 with
    # no create-then-chmod race, it inherits whatever protection that directory
    # already has, and being on the same filesystem makes the final mv atomic --
    # so no reader ever sees a half-written file.
    tmp="$(mktemp "${dst}.XXXXXX")" || { err "could not create a temporary file beside $dst"; return 1; }

    if ! { printf '%s\n' "$MAGIC"
           openssl pkeyutl -encrypt -pubin -inkey <(printf '%s\n' "$pub_pem") < "$src" | base64
         } > "$tmp" 2>/dev/null; then
        rm -f -- "$tmp"
        err "encryption of $src failed"
        return 1
    fi

    # Prove it round-trips BEFORE it becomes the file anyone depends on. This is
    # what stops an unreadable-key problem from surfacing days later, on the
    # first run after the cleartext has been deleted.
    if ! cmp -s <(decrypt_to_stdout "$tmp" 2>/dev/null) "$src"; then
        rm -f -- "$tmp"
        err "self-verification failed: the encrypted form of $src does not decrypt back" \
            "to the original. $dst has NOT been modified; do not delete $src."
        return 1
    fi

    chmod 600 -- "$tmp" 2>/dev/null || true
    if ! mv -f -- "$tmp" "$dst"; then
        rm -f -- "$tmp"
        err "could not move the encrypted file into place at $dst"
        return 1
    fi
    return 0
}

# --- commands ----------------------------------------------------------------

cmd_check() {
  local enc="${OUT:-${TARGET}.enc}" type bits max size rc=0

  type="$(keytype)"   || type='?'
  bits="$(keybits)"   || bits='?'
  max="$(max_bytes)"  || max='?'

  printf 'private key : %s\n' "$CREDS_SSH_KEY"
  printf 'public key  : %s\n' "$CREDS_SSH_PUB"
  printf 'key         : %s %s-bit, format %s\n' "$type" "$bits" "$(key_format)"
  printf 'block limit : %s bytes of plaintext\n' "$max"

  if [[ -r "$TARGET" ]]; then
    size="$(wc -c < "$TARGET" 2>/dev/null | tr -d '[:space:]')"
    printf 'plaintext   : %s (%s bytes' "$TARGET" "$size"
    if [[ "$max" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ ]]; then
      printf ', %s bytes of headroom' "$(( max - size ))"
    fi
    printf ')\n'
  else
    printf 'plaintext   : %s (absent)\n' "$TARGET"
  fi

  if [[ -r "$enc" ]]; then
    if is_encrypted "$enc"; then
      if decrypt_to_stdout "$enc" >/dev/null 2>&1; then
        printf 'encrypted   : %s (decrypts cleanly)\n' "$enc"
      else
        printf 'encrypted   : %s (PRESENT BUT WILL NOT DECRYPT)\n' "$enc"
        rc=1
      fi
    else
      printf 'encrypted   : %s (missing magic header - not our format)\n' "$enc"
      rc=1
    fi
  else
    printf 'encrypted   : %s (absent)\n' "$enc"
  fi

  preflight || rc=1
  return "$rc"
}

cmd_encrypt() {
  local dst="${OUT:-${TARGET}.enc}"
  [[ -r "$TARGET" ]] || { err "cannot read ${TARGET}"; return 1; }
  encrypt_file "$TARGET" "$dst" || return 1
  info "wrote ${dst}"
  info "the plaintext ${TARGET} is untouched; delete it once you have"
  info "confirmed a live run reads the encrypted file."
}

cmd_decrypt() {
  local enc="${OUT:-${TARGET}.enc}"
  [[ -r "$enc" ]] || { err "cannot read ${enc}"; return 1; }
  is_encrypted "$enc" || { err "${enc} is not in our format"; return 1; }
  decrypt_to_stdout "$enc"
}

cmd_edit() {
  local enc="${OUT:-${TARGET}.enc}" dir tmp editor rc

  dir="$(dirname -- "$TARGET")"
  [[ -d "$dir" && -w "$dir" ]] || { err "cannot write to ${dir}"; return 1; }

  editor="${VISUAL:-${EDITOR:-vi}}"
  command -v "${editor%% *}" >/dev/null 2>&1 || { err "editor not found: ${editor}"; return 1; }

  tmp="$(mktemp "${dir}/.$(basename -- "$TARGET").edit.XXXXXX")" \
      || { err "mktemp failed in ${dir}"; return 1; }
  chmod 600 -- "$tmp" 2>/dev/null || true
  # shellcheck disable=SC2064
  trap "shred -u -- '$tmp' 2>/dev/null || rm -f -- '$tmp'" EXIT INT TERM

  if [[ -r "$enc" ]] && is_encrypted "$enc"; then
    decrypt_to_stdout "$enc" > "$tmp" || { err "decrypt failed; nothing changed"; return 1; }
  elif [[ -r "$TARGET" ]]; then
    info "no ${enc} yet; starting from the plaintext ${TARGET}"
    cat -- "$TARGET" > "$tmp" || { err "could not read ${TARGET}"; return 1; }
  else
    info "no existing file found; starting from an empty one"
  fi

  "$editor" "$tmp"
  rc=$?
  if (( rc != 0 )); then
    err "editor exited ${rc}; nothing changed"
    return 1
  fi

  if [[ ! -s "$tmp" ]]; then
    err "the edited file is empty; refusing to encrypt it. Nothing changed."
    return 1
  fi

  encrypt_file "$tmp" "$enc" || { err "encrypt failed; ${enc} is unchanged"; return 1; }
  info "updated ${enc}"
}

# ---------------------------------------------------------------------------

main() {
  local action="" file="" arg

  # Options may appear before or after the command. The first bare word is the
  # command, the second is the file -- so both of these read naturally:
  #   ssh_crypt.sh encrypt ~/notes.txt
  #   ssh_crypt.sh -k ~/.ssh/other encrypt ~/notes.txt
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -k|--key)
        # Guard arity explicitly: a bare trailing -k would make "shift 2" fail
        # silently and spin this loop forever.
        [[ $# -ge 2 && -n "$2" ]] || { err "${arg} needs a path"; return 2; }
        CREDS_SSH_KEY="$2"
        (( PUB_EXPLICIT )) || CREDS_SSH_PUB="${2}.pub"
        shift 2 ;;
      -p|--pub)
        [[ $# -ge 2 && -n "$2" ]] || { err "${arg} needs a path"; return 2; }
        CREDS_SSH_PUB="$2"; PUB_EXPLICIT=1; shift 2 ;;
      -f|--file)
        [[ $# -ge 2 && -n "$2" ]] || { err "${arg} needs a path"; return 2; }
        file="$2"; shift 2 ;;
      -o|--out)
        [[ $# -ge 2 && -n "$2" ]] || { err "${arg} needs a path"; return 2; }
        OUT="$2"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      --) shift
          [[ -n "$action" ]] || { action="${1:-}"; shift || true; }
          [[ $# -eq 0 || -n "$file" ]] || file="$1"
          break ;;
      -*) err "unknown option: ${arg}"; usage; return 2 ;;
      *)
        if [[ -z "$action" ]]; then action="$arg"
        elif [[ -z "$file" ]];  then file="$arg"
        else err "unexpected extra argument: ${arg}"; usage; return 2
        fi
        shift ;;
    esac
  done

  [[ -n "$action" ]] || { usage; return 2; }
  [[ -z "$file" ]] || TARGET="$file"
  [[ -n "$TARGET" ]] || { err "no file to operate on"; return 2; }

  # Strip a .enc the operator may have typed, so both spellings work. Only the
  # target is normalised -- an explicit -o is taken exactly as given.
  TARGET="${TARGET%.enc}"

  case "$action" in
    check)   cmd_check ;;
    encrypt) cmd_encrypt ;;
    decrypt) cmd_decrypt ;;
    edit)    cmd_edit ;;
    *) err "unknown command: ${action}"; usage; return 2 ;;
  esac
}

main "$@"
