#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
ENC="$REPO_ROOT/scripts/encrypt-openssl.sh"

# Reference decrypt, independent of decrypt.sh, so the format itself is pinned.
ref_decrypt() { # priv envelope -> stdout plaintext
  jq -r .k "$2" | base64 -d > key.bin
  jq -r .d "$2" | base64 -d > data.bin
  openssl pkeyutl -decrypt -inkey "$1" -pkeyopt rsa_padding_mode:oaep \
    -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 -in key.bin -out pass 2>/dev/null
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass file:pass -in data.bin 2>/dev/null
}

test_validate_rsa_2048() { gen_rsa 2048 k; bash "$ENC" validate k.pub; }
test_validate_rsa_4096() { gen_rsa 4096 k; bash "$ENC" validate k.pub; }
test_rejects_rsa_1024()  { gen_rsa 1024 k; assert_fails bash "$ENC" validate k.pub; }
test_rejects_ec_key()    { gen_ec k;       assert_fails bash "$ENC" validate k.pub; }
test_rejects_garbage()   { echo nope > k;  assert_fails bash "$ENC" validate k; }
test_rejects_private_key(){ gen_rsa 2048 k; assert_fails bash "$ENC" validate k; }

test_roundtrip_2048() {
  gen_rsa 2048 k; fixture_secrets > plain.json
  bash "$ENC" encrypt k.pub plain.json out
  assert_eq "$(cat plain.json)" "$(ref_decrypt k out)"
}
test_roundtrip_4096() {
  gen_rsa 4096 k; fixture_secrets > plain.json
  bash "$ENC" encrypt k.pub plain.json out
  assert_eq "$(cat plain.json)" "$(ref_decrypt k out)"
}
test_envelope_shape() {
  gen_rsa 2048 k; echo '{}' > plain.json
  bash "$ENC" encrypt k.pub plain.json out
  assert_eq '["d","k"]' "$(jq -c 'keys' out)"
  assert_eq 1 "$(wc -l < out | tr -d ' ')"
}
test_encrypt_is_silent() {
  gen_rsa 2048 k; echo '{}' > plain.json
  out="$(bash "$ENC" encrypt k.pub plain.json out 2>&1)"
  assert_eq "" "$out"
}
test_wrong_key_fails_to_decrypt() {
  gen_rsa 2048 k; gen_rsa 2048 other; echo '{"a":1}' > plain.json
  bash "$ENC" encrypt k.pub plain.json out
  assert_fails ref_decrypt other out
}
test_usage_error_without_verb() { assert_fails bash "$ENC"; }

run_tests
