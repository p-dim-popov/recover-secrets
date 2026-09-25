#!/usr/bin/env bash
# Sourced by source/main.sh. decrypt.sh carries a byte-identical copy of the
# block between BEGIN/END detect; tests/test_decrypt.sh asserts they match.

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
