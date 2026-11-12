#!/usr/bin/env bash
# Usage: encrypt-age.sh validate <pubkey>
#        encrypt-age.sh encrypt  <pubkey> <plaintext> <out>
# Recipients: lines starting age1, ssh-ed25519, ssh-rsa. Installs age if missing.
# Exit 69: age is missing and the install failed. The ::error:: line says why.
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

ensure_age() {
  command -v age >/dev/null 2>&1 && return 0
  local installer rc=0 log="$work/install.log"
  local fix="Install age in an earlier step. See https://github.com/p-dim-popov/recover-secrets#if-the-runner-cannot-install-age"
  if command -v apt-get >/dev/null 2>&1; then
    installer=apt-get
    # shellcheck disable=SC2024  # this user, not root, writes the log in its own temp dir
    sudo apt-get install -y -qq age > "$log" 2>&1 || rc=$?
  elif command -v brew >/dev/null 2>&1; then
    installer=brew
    brew install -q age > "$log" 2>&1 || rc=$?
  else
    echo "::error::age is not installed, and this runner has no apt-get or brew to install it. $fix" >&2
    return 1
  fi
  command -v age >/dev/null 2>&1 && return 0
  echo "::error::age is not installed, and \`$installer install age\` did not install it (exit $rc). $fix" >&2
  if [[ -s "$log" ]]; then
    echo "Last lines of the $installer output:" >&2
    tail -n 10 "$log" >&2
  fi
  return 1
}

SUPPORTED='^(age1|ssh-ed25519 |ssh-rsa )'
IGNORED='^(#|[[:space:]]*$)'

# recipients_from <pub> <out> [warn]: writes supported lines; exit 1 if none.
recipients_from() {
  local src="$1" dst="$2" warn="${3:-}" skipped
  grep -E "$SUPPORTED" "$src" > "$dst" 2>/dev/null || true
  skipped="$(grep -vE "$SUPPORTED" "$src" 2>/dev/null | grep -cvE "$IGNORED" 2>/dev/null || true)"
  if [[ -n "$warn" && "$skipped" -gt 0 ]]; then
    echo "::warning::Skipped $skipped unsupported key line(s); age accepts age1, ssh-ed25519 and ssh-rsa" >&2
  fi
  [[ -s "$dst" ]]
}

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    ensure_age || exit 69
    recipients_from "$pub" "$work/recipients" warn || exit 1
    : > "$work/empty"
    age -R "$work/recipients" -o "$work/probe" "$work/empty" 2>/dev/null || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    ensure_age || exit 69
    recipients_from "$pub" "$work/recipients" || exit 1
    age -R "$work/recipients" -o "$out" "$plaintext" 2>/dev/null
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
