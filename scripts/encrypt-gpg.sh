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

# import_keys <pub>: import into the throwaway keyring, then print one line per
# primary key: "ok <fpr>" if usable for encryption, "skip <fpr>" otherwise.
# Usable means capital E in the capabilities field (12, E for the whole key
# including subkeys) and a validity (field 2) other than e(xpired), r(evoked)
# or i(nvalid).
import_keys() {
  gpg --batch --quiet --import "$1" >/dev/null 2>&1 || return 1
  gpg --batch --list-keys --with-colons 2>/dev/null | awk -F: '
    $1 == "pub" { use = ($12 ~ /E/ && $2 !~ /^[eri]$/); want = 1; next }
    $1 == "fpr" && want { print (use ? "ok " : "skip ") $10; want = 0; next }
    { want = 0 }'
}

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    keys="$(import_keys "$pub")" || exit 1
    grep -q '^ok ' <<<"$keys" 2>/dev/null || exit 1
    skipped="$(grep -c '^skip ' <<<"$keys" 2>/dev/null || true)"
    if [[ "$skipped" -gt 0 ]]; then
      echo "::warning::Skipped $skipped unusable GPG key(s) (no encryption capability, expired or revoked)" >&2
    fi
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    keys="$(import_keys "$pub")" || exit 1
    grep -q '^ok ' <<<"$keys" 2>/dev/null || exit 1
    # One --recipient per usable fingerprint. --recipient-file is not used: it
    # silently drops every key in the file except the first.
    recipients=()
    while IFS= read -r fpr; do
      [[ -n "$fpr" ]] && recipients+=("--recipient" "$fpr")
    done < <(sed -n 's/^ok //p' <<<"$keys" 2>/dev/null)
    gpg --batch --quiet --trust-model always ${recipients[@]+"${recipients[@]}"} \
      --encrypt --output "$out" "$plaintext" 2>/dev/null
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
