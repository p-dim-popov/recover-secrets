#!/usr/bin/env bash
# The root recover.sh and decrypt.sh are built by `make` from source/.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

expected() { fixture_secrets | jq -c 'del(.github_token)'; }

# build_here: copy Makefile and source/ into $PWD and run make there, so the
# repository's committed files are never touched.
build_here() {
  cp -r "$REPO_ROOT/source" . && cp "$REPO_ROOT/Makefile" .
  make -s
}

test_make_builds_both_root_scripts() {
  build_here
  [[ -x recover.sh ]] || fail "recover.sh missing or not executable"
  [[ -x decrypt.sh ]] || fail "decrypt.sh missing or not executable"
}
test_built_decrypt_includes_detect_block() {
  build_here
  assert_contains "$(cat decrypt.sh)" 'detect_blob_format()'
  assert_not_contains "$(cat decrypt.sh)" '# include detect.sh'
  assert_fails grep -qE '^[[:space:]]*(source|\.) ' decrypt.sh
}
test_built_files_say_they_are_generated() {
  build_here
  assert_contains "$(head -5 recover.sh)" 'make'
  assert_contains "$(head -5 decrypt.sh)" 'make'
}
test_committed_root_scripts_are_fresh() {
  build_here
  diff recover.sh "$REPO_ROOT/recover.sh" || fail "recover.sh is stale; run make"
  diff decrypt.sh "$REPO_ROOT/decrypt.sh" || fail "decrypt.sh is stale; run make"
}
test_make_check_fails_on_stale_bundle() {
  build_here
  make -s check || fail "make check should pass right after make"
  echo '# edited' >> source/main.sh
  assert_fails make -s check
}
test_bundle_roundtrip_through_built_decrypt() {
  build_here
  gen_ssh ed25519 s
  RS_DRIVER="$PWD/recover.sh" run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)"
  blob="$(blob_from_output)"
  [[ "$blob" == rs1:age:* ]] || fail "blob prefix: ${blob:0:20}"
  assert_eq "$(expected)" "$(bash decrypt.sh --blob "$blob" --key s | jq -c .)"
  assert_contains "$(cat "$TMP/log")" 'Encrypted 9 secret(s) with age'
}
test_bundle_every_backend() {
  build_here
  gen_rsa 2048 k; gen_gpg gh pub.asc
  RS_DRIVER="$PWD/recover.sh" run_recover RS_PUBLIC_KEY="$(cat k.pub)" RS_SECRETS_JSON='{"A":"1"}'
  [[ "$(blob_from_output)" == rs1:openssl:* ]] || fail "openssl via bundle"
  RS_DRIVER="$PWD/recover.sh" run_recover RS_PUBLIC_KEY="$(cat pub.asc)" RS_SECRETS_JSON='{"A":"1"}'
  [[ "$(blob_from_output)" == rs1:gpg:* ]] || fail "gpg via bundle"
}
test_bundle_removes_extracted_source() {
  build_here
  gen_ssh ed25519 s
  RS_DRIVER="$PWD/recover.sh" run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='{"A":"1"}'
  assert_eq "" "$(ls -A "$TMP/tmpdir")"
}
test_bundle_propagates_failure_and_still_cleans_up() {
  build_here
  gen_ssh ed25519 s
  export RS_DRIVER="$PWD/recover.sh"
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON='["no"]'
  assert_contains "$(cat "$TMP/err")" '::error::'
  assert_eq "" "$(ls -A "$TMP/tmpdir")"
}

run_tests
