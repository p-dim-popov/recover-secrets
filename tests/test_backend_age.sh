#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
ENC="$REPO_ROOT/scripts/encrypt-age.sh"

test_validate_age_recipient() { gen_age a; bash "$ENC" validate a.pub; }
test_validate_ssh_ed25519()   { gen_ssh ed25519 s; bash "$ENC" validate s.pub; }
test_validate_ssh_rsa()       { gen_ssh rsa s; bash "$ENC" validate s.pub; }
test_rejects_garbage()        { echo nope > k; assert_fails bash "$ENC" validate k; }
test_rejects_pem()            { gen_rsa 2048 k; assert_fails bash "$ENC" validate k.pub; }
test_rejects_ecdsa_only()     { gen_ssh ecdsa s; assert_fails bash "$ENC" validate s.pub; }
test_rejects_corrupt_recipient() { echo 'age1notarealrecipient' > k; assert_fails bash "$ENC" validate k; }

test_age_skips_unsupported_key_lines() {
  gen_ssh ecdsa e; gen_ssh ed25519 s
  { echo '# comment'; cat e.pub; echo; cat s.pub; } > list
  err="$(bash "$ENC" validate list 2>&1)"
  assert_contains "$err" '::warning::Skipped 1 unsupported'
  echo '{"a":1}' > plain.json
  bash "$ENC" encrypt list plain.json out
  assert_eq '{"a":1}' "$(age -d -i s out)"
}
test_roundtrip_age_identity() {
  gen_age a; fixture_secrets > plain.json
  bash "$ENC" encrypt a.pub plain.json out
  assert_eq "$(cat plain.json)" "$(age -d -i a out)"
}
test_roundtrip_ssh_ed25519() {
  gen_ssh ed25519 s; fixture_secrets > plain.json
  bash "$ENC" encrypt s.pub plain.json out
  assert_eq "$(cat plain.json)" "$(age -d -i s out)"
}
test_roundtrip_ssh_rsa() {
  gen_ssh rsa s; fixture_secrets > plain.json
  bash "$ENC" encrypt s.pub plain.json out
  assert_eq "$(cat plain.json)" "$(age -d -i s out)"
}
test_multiple_recipients() {
  gen_ssh ed25519 s1; gen_ssh ed25519 s2; cat s1.pub s2.pub > list
  echo '{"a":1}' > plain.json
  bash "$ENC" encrypt list plain.json out
  assert_eq '{"a":1}' "$(age -d -i s1 out)"
  assert_eq '{"a":1}' "$(age -d -i s2 out)"
}
test_encrypt_is_silent() {
  gen_ssh ecdsa e; gen_ssh ed25519 s; cat e.pub s.pub > list; echo '{}' > plain.json
  assert_eq "" "$(bash "$ENC" encrypt list plain.json out 2>&1)"
}

run_tests
