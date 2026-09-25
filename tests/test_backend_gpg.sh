#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
ENC="$REPO_ROOT/scripts/encrypt-gpg.sh"

test_validate_ok()        { gen_gpg gh pub.asc; bash "$ENC" validate pub.asc; }
test_rejects_garbage()    { echo nope > k; assert_fails bash "$ENC" validate k; }
test_rejects_pem()        { gen_rsa 2048 k; assert_fails bash "$ENC" validate k.pub; }
test_rejects_key_without_encryption_subkey() {
  mkdir -m 700 gh
  GNUPGHOME=gh gpg --batch --quiet --passphrase '' --quick-gen-key 'x <x@example.com>' ed25519 cert never 2>/dev/null
  GNUPGHOME=gh gpg --batch --export --armor > pub.asc
  assert_fails bash "$ENC" validate pub.asc
}
test_roundtrip() {
  gen_gpg gh pub.asc; fixture_secrets > plain.json
  bash "$ENC" encrypt pub.asc plain.json out
  assert_eq "$(cat plain.json)" "$(GNUPGHOME=gh gpg --batch --quiet --decrypt out 2>/dev/null)"
}
test_output_is_binary_not_armored() {
  gen_gpg gh pub.asc; echo '{}' > plain.json
  bash "$ENC" encrypt pub.asc plain.json out
  assert_fails grep -q 'BEGIN PGP MESSAGE' out
}
test_encrypt_is_silent() {
  gen_gpg gh pub.asc; echo '{}' > plain.json
  assert_eq "" "$(bash "$ENC" encrypt pub.asc plain.json out 2>&1)"
}
test_does_not_touch_user_keyring() {
  gen_gpg gh pub.asc; echo '{}' > plain.json
  mkdir -m 700 userhome
  GNUPGHOME="$PWD/userhome" bash "$ENC" encrypt pub.asc plain.json out
  assert_eq "" "$(ls userhome)"
}
test_multiple_keys_in_file_all_become_recipients() {
  gen_gpg gh1 p1.asc; gen_gpg gh2 p2.asc; cat p1.asc p2.asc > both.asc
  echo '{"a":1}' > plain.json
  bash "$ENC" encrypt both.asc plain.json out
  assert_eq '{"a":1}' "$(GNUPGHOME=gh1 gpg --batch --quiet --decrypt out 2>/dev/null)"
  assert_eq '{"a":1}' "$(GNUPGHOME=gh2 gpg --batch --quiet --decrypt out 2>/dev/null)"
}
test_unusable_key_in_file_is_skipped() {
  gen_gpg gh pub_good.asc
  mkdir -m 700 gh2
  GNUPGHOME=gh2 gpg --batch --quiet --passphrase '' --quick-gen-key 'y <y@example.com>' ed25519 cert never 2>/dev/null
  GNUPGHOME=gh2 gpg --batch --export --armor > pub_cert.asc
  cat pub_good.asc pub_cert.asc > both.asc
  err="$(bash "$ENC" validate both.asc 2>&1)"
  assert_eq '::warning::Skipped 1 unusable GPG key(s) (no encryption capability, expired or revoked)' "$err"
  echo '{"a":1}' > plain.json
  bash "$ENC" encrypt both.asc plain.json out
  assert_eq '{"a":1}' "$(GNUPGHOME=gh gpg --batch --quiet --decrypt out 2>/dev/null)"
}
test_validate_ok_is_silent() {
  gen_gpg gh pub.asc
  assert_eq "" "$(bash "$ENC" validate pub.asc 2>&1)"
}

run_tests
