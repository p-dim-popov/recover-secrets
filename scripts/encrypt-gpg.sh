#!/usr/bin/env bash
# Usage: encrypt-gpg.sh validate <pubkey>
#        encrypt-gpg.sh encrypt  <pubkey> <plaintext> <out>
# Uses a throwaway GNUPGHOME so the runner's keyring is never read or written.
set -euo pipefail
umask 077

cmd="${1:-}"
pub="${2:-}"

work="$(mktemp -d)"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$work" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    # At least one key, and at least one (sub)key with the E (encrypt) capability.
    keys="$(gpg --batch --quiet --show-keys "$pub" 2>/dev/null)" || exit 1
    grep -q '^pub ' <<<"$keys" || exit 1
    grep -qE '^(pub|sub) .*\[[A-Z]*E[A-Z]*\]' <<<"$keys" || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    # Import keys from file
    gpg --batch --quiet --import "$pub" 2>/dev/null
    # Build recipient list from imported fingerprints and encrypt
    recipients=()
    while IFS= read -r fpr; do
      [[ -n "$fpr" ]] && recipients+=("--recipient" "$fpr")
    done < <(gpg --batch --list-keys --with-colons 2>/dev/null | awk -F: '/^fpr:/{print $10}')
    gpg --batch --quiet --trust-model always "${recipients[@]}" \
      --encrypt --output "$out" "$plaintext" 2>/dev/null
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
