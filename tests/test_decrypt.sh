#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
DEC="$REPO_ROOT/decrypt.sh"

expected() { fixture_secrets | jq -c 'del(.github_token)'; }
make_blob() { # backend-key-setup then run_recover; prints blob
  run_recover RS_PUBLIC_KEY="$1" RS_SECRETS_JSON="$(fixture_secrets)"
  blob_from_output
}

test_detect_block_identical_to_scripts_detect() {
  sed -n '/^# BEGIN detect$/,/^# END detect$/p' "$REPO_ROOT/scripts/detect.sh" > a
  sed -n '/^# BEGIN detect$/,/^# END detect$/p' "$DEC" > b
  [[ -s a && -s b ]] || fail "marker block missing"
  diff a b
}
test_no_source_lines() { assert_fails grep -qE '^[[:space:]]*(source|\.) ' "$DEC"; }

test_age_ssh_key_blob_flag() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  assert_eq "$(expected)" "$(bash "$DEC" --blob "$blob" --key s | jq -c .)"
}
test_age_rsa_ssh_key() {
  gen_ssh rsa s; blob="$(make_blob "$(cat s.pub)")"
  assert_eq "$(expected)" "$(bash "$DEC" --blob "$blob" --key s | jq -c .)"
}
test_age_identity_file() {
  gen_age a; blob="$(make_blob "$(cat a.pub)")"
  assert_eq "$(expected)" "$(bash "$DEC" --blob "$blob" --key a | jq -c .)"
}
test_age_default_key_lookup() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  mkdir -p home/.ssh; cp s home/.ssh/id_ed25519
  assert_eq "$(expected)" "$(HOME="$PWD/home" bash "$DEC" --blob "$blob" | jq -c .)"
}
test_openssl_blob() {
  gen_rsa 2048 k; blob="$(make_blob "$(cat k.pub)")"
  assert_eq "$(expected)" "$(bash "$DEC" --blob "$blob" --key k | jq -c .)"
}
test_gpg_blob_uses_keyring() {
  gen_gpg gh pub.asc; blob="$(make_blob "$(cat pub.asc)")"
  assert_eq "$(expected)" "$(GNUPGHOME="$PWD/gh" bash "$DEC" --blob "$blob" | jq -c .)"
}
test_file_mode() {
  gen_ssh ed25519 s; make_blob "$(cat s.pub)" > blob.txt
  assert_eq "$(expected)" "$(bash "$DEC" --file blob.txt --key s | jq -c .)"
}
test_decrypt_stdin_tolerates_wrapping() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  wrapped="$(printf '%s' "$blob" | fold -w 76; echo; echo)"
  assert_eq "$(expected)" "$(printf '%s\n' "$wrapped" | bash "$DEC" --key s | jq -c .)"
}
test_decrypt_env_output_is_sourceable() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  bash "$DEC" --blob "$blob" --key s --env > vars.env
  # shellcheck disable=SC1091
  ( source vars.env
    [[ "$MULTILINE" == $'line1\nline2\n' ]] || exit 1
    [[ "$QUOTES" == "it's \"quoted\"" ]] || exit 1
    [[ "$SPACES" == "  padded  " ]] || exit 1
    [[ "$EQUALS" == "a=b=c" ]] || exit 1
    [[ "$UNICODE" == "üñí 🔐" ]] || exit 1
    [[ "${#BIG}" -eq 51200 ]] || exit 1 )
}
test_env_output_has_no_token_and_one_var_per_secret() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  out="$(bash "$DEC" --blob "$blob" --key s --env)"
  assert_not_contains "$out" 'github_token'
  assert_eq 9 "$(grep -cE "^[A-Z_]+='" <<<"$out")"
}

test_error_wrong_age_key() {
  gen_ssh ed25519 s; gen_ssh ed25519 other; blob="$(make_blob "$(cat s.pub)")"
  assert_fails bash "$DEC" --blob "$blob" --key other
}
test_error_wrong_rsa_key() {
  gen_rsa 2048 k; gen_rsa 2048 other; blob="$(make_blob "$(cat k.pub)")"
  assert_fails bash "$DEC" --blob "$blob" --key other
}
test_error_unknown_version() {
  err="$(bash "$DEC" --blob 'rs9:age:AAAA' 2>&1 || true)"
  assert_contains "$err" 'rs1'
}
test_error_not_base64() {
  err="$(bash "$DEC" --blob 'rs1:age:***' 2>&1 || true)"
  assert_contains "$err" 'not valid base64'
}
test_error_openssl_needs_key() {
  gen_rsa 2048 k; blob="$(make_blob "$(cat k.pub)")"
  err="$(bash "$DEC" --blob "$blob" 2>&1 || true)"
  assert_contains "$err" '--key'
}
test_error_both_blob_and_file() { assert_fails bash "$DEC" --blob x --file y; }
test_error_unknown_flag()       { assert_fails bash "$DEC" --wat; }
test_help() { assert_contains "$(bash "$DEC" --help)" '--env'; }
test_env_rejects_unsafe_key_names() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{"A; touch PWNED; B":"v","OK":"1"}'
  blob="$(blob_from_output)"
  rc=0
  out="$(bash "$DEC" --blob "$blob" --key s --env 2>errfile)" || rc=$?
  err="$(cat errfile)"
  [[ $rc -ne 0 ]] || fail "expected --env to fail on an unsafe key name"
  assert_contains "$err" 'not a valid shell variable name'
  assert_eq "" "$out"
  [[ ! -e PWNED ]] || fail "PWNED was created; --env output was unsafe to source"
  bash "$DEC" --blob "$blob" --key s | jq -e 'has("OK")' >/dev/null \
    || fail "plain JSON output should still succeed for the same blob"
}
test_temp_cleaned() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  mkdir t; TMPDIR="$PWD/t" bash "$DEC" --blob "$blob" --key s >/dev/null
  assert_eq "" "$(ls -A t)"
}

run_tests
