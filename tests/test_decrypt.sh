#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
DEC="$REPO_ROOT/decrypt.sh"

expected() { fixture_secrets | jq -c 'del(.github_token)'; }
make_blob() { # backend-key-setup then run_recover; prints blob
  run_recover RS_PUBLIC_KEY="$1" RS_SECRETS_JSON="$(fixture_secrets)"
  blob_from_output
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
  # A safe blob: the --env output sources cleanly in a subshell.
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{"OK":"1","MY_PATH":"/x"}'
  blob="$(blob_from_output)"
  bash "$DEC" --blob "$blob" --key s --env > safe.env
  # shellcheck disable=SC1091
  ( source ./safe.env; [[ "$OK" == 1 && "$MY_PATH" == /x ]] ) \
    || fail "sourcing the --env output of a safe blob failed"

  # Unsafe blobs: each one fails before any output.
  local json expect i=0
  for json in '{"A; touch PWNED; B":"v","OK":"1"}' '{"whoami\n":"v","OK":"1"}' \
              '{"PATH":"/nonexistent","OK":"1"}'; do
    i=$((i+1))
    case "$json" in
      *PATH*) expect='would override a shell or loader variable' ;;
      *)      expect='not a valid shell variable name' ;;
    esac
    run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$json"
    blob="$(blob_from_output)"
    [[ -n "$blob" ]] || fail "case $i: recover produced no blob"
    rc=0
    bash "$DEC" --blob "$blob" --key s --env > "out$i.env" 2>errfile || rc=$?
    [[ $rc -ne 0 ]] || fail "case $i: expected --env to fail on an unsafe key name"
    assert_contains "$(cat errfile)" "$expect"
    [[ ! -s "out$i.env" ]] || fail "case $i: --env printed output before failing"
    [[ ! -e PWNED ]] || fail "case $i: PWNED was created"
    bash "$DEC" --blob "$blob" --key s | jq -e 'has("OK")' >/dev/null \
      || fail "case $i: plain JSON output should still succeed for the same blob"
  done
}
test_temp_cleaned() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  mkdir t; TMPDIR="$PWD/t" bash "$DEC" --blob "$blob" --key s >/dev/null
  assert_eq "" "$(ls -A t)"
}

run_tests
