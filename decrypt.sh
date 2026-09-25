#!/usr/bin/env bash
# recover-secrets decrypt helper. Self-contained: needs jq plus whichever of
# age, gpg, or openssl the blob names.
#
# Usage: decrypt.sh [--blob <string> | --file <path>] [--key <path>] [--env]
#   no --blob/--file  read the blob from stdin (paste, then Ctrl-D)
#   --key <path>      private key: SSH key or age identity (age), PEM (openssl);
#                     ignored for gpg, which uses your keyring
#   --env             print NAME='value' lines instead of JSON
set -euo pipefail
umask 077

SUPPORTED_VERSION="rs1"

# BEGIN detect
# detect_key_format <file> -> prints openssl | gpg | age ; exit 1 if unknown
detect_key_format() {
  local file="$1"
  if grep -qE '^-----BEGIN (RSA )?PUBLIC KEY-----' "$file"; then
    echo openssl
  elif grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$file"; then
    echo gpg
  elif grep -qE '^(age1|ssh-ed25519 |ssh-rsa )' "$file"; then
    echo age
  else
    return 1
  fi
}

# detect_blob_format <blob-string> -> prints age | gpg | openssl ; exit 1 if not an rs1 blob
detect_blob_format() {
  case "$1" in
    rs1:age:*) echo age ;;
    rs1:gpg:*) echo gpg ;;
    rs1:openssl:*) echo openssl ;;
    *) return 1 ;;
  esac
}
# END detect

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}
die()  { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required. Install it with: $2"; }

BLOB=""; FILE=""; KEY=""; ENV_OUT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --blob) BLOB="${2:-}"; [[ -n "$BLOB" ]] || { echo "--blob needs a value" >&2; exit 64; }; shift 2 ;;
    --file) FILE="${2:-}"; [[ -n "$FILE" ]] || { echo "--file needs a value" >&2; exit 64; }; shift 2 ;;
    --key)  KEY="${2:-}";  [[ -n "$KEY"  ]] || { echo "--key needs a value"  >&2; exit 64; }; shift 2 ;;
    --env)  ENV_OUT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done
if [[ -n "$BLOB" && -n "$FILE" ]]; then
  echo "Use --blob or --file, not both" >&2; exit 64
fi

if [[ -n "$FILE" ]]; then
  BLOB="$(cat "$FILE")"
elif [[ -z "$BLOB" ]]; then
  [[ -t 0 ]] && echo "Paste the blob, then press Ctrl-D:" >&2
  BLOB="$(cat)"
fi
BLOB="$(printf '%s' "$BLOB" | tr -d '[:space:]')"

need jq "brew install jq  |  sudo apt-get install jq"
BACKEND="$(detect_blob_format "$BLOB")" \
  || die "Not a blob this script understands. Expected '${SUPPORTED_VERSION}:<age|gpg|openssl>:...'; a newer decrypt.sh may be needed"

WORK="$(mktemp -d)"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$WORK" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT

printf '%s' "${BLOB#rs1:*:}" | base64 -d > "$WORK/in" 2>/dev/null || die "Blob payload is not valid base64"

case "$BACKEND" in
  age)
    need age "brew install age  |  sudo apt-get install age"
    if [[ -z "$KEY" ]]; then
      for candidate in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.config/age/keys.txt"; do
        [[ -f "$candidate" ]] && { KEY="$candidate"; break; }
      done
      [[ -n "$KEY" ]] || die "No key found. Pass --key <SSH private key or age identity>"
    fi
    age -d -i "$KEY" -o "$WORK/plain" "$WORK/in" 2>/dev/null \
      || die "age decryption failed. Wrong key? (used $KEY)"
    ;;
  gpg)
    need gpg "brew install gnupg  |  sudo apt-get install gnupg"
    gpg --quiet --decrypt --output "$WORK/plain" "$WORK/in" 2>/dev/null \
      || die "gpg decryption failed. Is the matching private key in your keyring?"
    ;;
  openssl)
    need openssl "brew install openssl  |  sudo apt-get install openssl"
    [[ -n "$KEY" ]] || die "Pass --key <RSA private key PEM>"
    jq -r '.k' "$WORK/in" 2>/dev/null | base64 -d > "$WORK/key" 2>/dev/null || die "Malformed openssl envelope"
    jq -r '.d' "$WORK/in" 2>/dev/null | base64 -d > "$WORK/data" 2>/dev/null || die "Malformed openssl envelope"
    openssl pkeyutl -decrypt -inkey "$KEY" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
      -in "$WORK/key" -out "$WORK/pass" 2>/dev/null \
      || die "RSA unwrap failed. Wrong key? (used $KEY)"
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "file:$WORK/pass" \
      -in "$WORK/data" -out "$WORK/plain" 2>/dev/null \
      || die "AES decryption failed. Corrupted blob?"
    ;;
esac

jq -e 'type == "object"' "$WORK/plain" >/dev/null 2>&1 \
  || die "Decrypted data is not a JSON object. Wrong key or corrupted blob"

if $ENV_OUT; then
  # NAME='value' with embedded single quotes closed/escaped/reopened: it's -> 'it'\''s'
  # @sh is jq's built-in shell-quoting format; it produces exactly that idiom.
  jq -r 'to_entries[] | "\(.key)=\(.value | tostring | @sh)"' "$WORK/plain"
else
  jq . "$WORK/plain"
fi
