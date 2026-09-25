#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

err() { cat "$TMP/err"; }

test_happy_path_age_inline_key() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)"
  blob="$(blob_from_output)"
  [[ "$blob" == rs1:age:* ]] || fail "blob prefix: ${blob:0:20}"
  assert_eq 1 "$(wc -l < "$TMP/output" | tr -d ' ')"
  printf '%s' "${blob#rs1:age:}" | base64 -d > out.age
  assert_eq "$(fixture_secrets | jq -c 'del(.github_token)')" "$(age -d -i s out.age | jq -c .)"
  assert_contains "$(cat "$TMP/log")" '::group::'
  assert_contains "$(cat "$TMP/log")" "$blob"
  assert_contains "$(cat "$TMP/log")" 'Encrypted 9 secret(s) with age'
  assert_contains "$(cat "$TMP/summary")" "$blob"
  assert_contains "$(cat "$TMP/summary")" '```'
}
test_happy_path_openssl() {
  gen_rsa 2048 k
  run_recover RS_PUBLIC_KEY="$(cat k.pub)" RS_SECRETS_JSON='{"A":"1"}'
  [[ "$(blob_from_output)" == rs1:openssl:* ]]
}
test_happy_path_gpg() {
  gen_gpg gh pub.asc
  run_recover RS_PUBLIC_KEY="$(cat pub.asc)" RS_SECRETS_JSON='{"A":"1"}'
  [[ "$(blob_from_output)" == rs1:gpg:* ]]
}
test_include_filters() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)" RS_INCLUDE='AWS_*'
  assert_contains "$(cat "$TMP/log")" 'Encrypted 2 secret(s)'
}
test_crlf_key_is_normalized() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(printf '%s\r\n' "$(cat s.pub)")" RS_SECRETS_JSON='{"A":"1"}'
  [[ "$(blob_from_output)" == rs1:age:* ]]
}
test_artifact_file_written_only_when_named() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{"A":"1"}'
  [[ ! -e "$TMP/runner_temp/recover-secrets/blob.txt" ]]
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{"A":"1"}' RS_ARTIFACT_NAME=x
  assert_eq "$(blob_from_output)" "$(cat "$TMP/runner_temp/recover-secrets/blob.txt")"
}
test_temp_dir_is_cleaned() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{"A":"1"}'
  assert_eq "" "$(ls -A "$TMP/tmpdir")"
}
test_temp_dir_is_cleaned_on_failure() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='["not","object"]'
  assert_eq "" "$(ls -A "$TMP/tmpdir")"
}

test_error_both_keys() {
  assert_fails run_recover RS_PUBLIC_KEY=x RS_PUBLIC_KEY_URL=https://x RS_SECRETS_JSON='{}'
  assert_contains "$(err)" '::error::'; assert_contains "$(err)" 'not both'
}
test_error_no_key() {
  assert_fails run_recover RS_SECRETS_JSON='{}'
  assert_contains "$(err)" 'public-key or public-key-url is required'
}
test_error_http_url() {
  assert_fails run_recover RS_PUBLIC_KEY_URL=http://example.com/k RS_SECRETS_JSON='{}'
  assert_contains "$(err)" 'must start with https://'
}
test_error_unreachable_url() {
  assert_fails run_recover RS_PUBLIC_KEY_URL=https://localhost:1/k RS_SECRETS_JSON='{}'
  assert_contains "$(err)" 'Fetching public-key-url failed'
}
test_error_unknown_key_format() {
  assert_fails run_recover RS_PUBLIC_KEY='hello' RS_SECRETS_JSON='{}'
  assert_contains "$(err)" 'Unrecognized public key format'
}
test_error_key_rejected_by_backend() {
  gen_rsa 1024 k
  assert_fails run_recover RS_PUBLIC_KEY="$(cat k.pub)" RS_SECRETS_JSON='{}'
  assert_contains "$(err)" 'rejected by openssl backend'
}
test_error_secrets_missing() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)"
  assert_contains "$(err)" 'secrets-json is required'
}
test_error_secrets_not_object() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='[1]'
  assert_contains "$(err)" 'must be a JSON object'
}
test_error_no_match_reports_count_not_names() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)" RS_INCLUDE='NOPE'
  assert_contains "$(err)" 'matched none of the 9 available'
  assert_not_contains "$(err)" 'AWS_ACCESS_KEY_ID'
}
test_error_empty_object() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{}'
  assert_contains "$(err)" 'matched none of the 0 available'
}
test_errors_never_echo_values() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)" RS_INCLUDE='NOPE'
  assert_file_lacks "$TMP/err" 'AKIAEXAMPLEKEY'
  assert_file_lacks "$TMP/log" 'AKIAEXAMPLEKEY'
}
test_key_validation_precedes_secret_parsing() {
  # Bad key AND bad secrets: the key error must win, proving secrets were not read yet.
  assert_fails run_recover RS_PUBLIC_KEY='hello' RS_SECRETS_JSON='[1]'
  assert_contains "$(err)" 'Unrecognized public key format'
}

run_tests
