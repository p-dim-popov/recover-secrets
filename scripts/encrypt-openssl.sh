#!/usr/bin/env bash
# Usage: encrypt-openssl.sh validate <pubkey>
#        encrypt-openssl.sh encrypt  <pubkey> <plaintext> <out>
# RSA-OAEP(SHA-256) wraps a random passphrase; AES-256-CBC (PBKDF2, 100k) encrypts the data.
set -euo pipefail
umask 077

cmd="${1:-}"
pub="${2:-}"

cleanup() {
  [[ -n "${work:-}" && -d "$work" ]] || return 0
  if command -v shred >/dev/null 2>&1; then
    find "$work" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    openssl rsa -pubin -in "$pub" -noout >/dev/null 2>&1 || exit 1
    bits="$(openssl rsa -pubin -in "$pub" -noout -text 2>/dev/null \
            | sed -n 's/^Public-Key: (\([0-9]*\) bit)$/\1/p')"
    [[ -n "$bits" && "$bits" -ge 2048 ]] || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    work="$(mktemp -d)"
    openssl rand -hex 32 > "$work/pass" 2>/dev/null
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
      -pass "file:$work/pass" -in "$plaintext" -out "$work/data" 2>/dev/null
    openssl pkeyutl -encrypt -pubin -inkey "$pub" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
      -in "$work/pass" -out "$work/key" 2>/dev/null
    jq -nc --arg k "$(base64 < "$work/key" | tr -d '\n')" \
           --arg d "$(base64 < "$work/data" | tr -d '\n')" \
           '{k: $k, d: $d}' > "$out"
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
