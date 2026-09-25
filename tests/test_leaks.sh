#!/usr/bin/env bash
# The test that justifies the project: after a run, no secret value (raw or
# base64) exists anywhere the action wrote, and nothing is left on disk.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Every place recover.sh could have written.
artifacts() { echo "$TMP/log" "$TMP/err" "$TMP/output" "$TMP/summary"; find "$TMP/runner_temp" "$TMP/tmpdir" -type f; }

check_no_leaks() {
  local f v enc
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue   # MULTILINE splits into lines; an empty needle would match everything
    enc="$(printf '%s' "$v" | base64 | tr -d '\n')"
    for f in $(artifacts); do
      assert_file_lacks "$f" "$v"
      assert_file_lacks "$f" "$enc"
    done
  done < <(fixture_secrets | jq -r '.[] | select(length < 1000)')  # BIG is checked by its prefix below
  for f in $(artifacts); do assert_file_lacks "$f" 'xxxxxxxxxxxxxxxxxxxx'; done
  assert_file_lacks "$TMP/log" 'AWS_ACCESS_KEY_ID'   # names stay out of the log too
  assert_eq "" "$(ls -A "$TMP/tmpdir")"
}

test_no_leaks_age() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)" RS_ARTIFACT_NAME=x
  check_no_leaks
}
test_no_leaks_gpg() {
  gen_gpg gh pub.asc
  run_recover RS_PUBLIC_KEY="$(cat pub.asc)" RS_SECRETS_JSON="$(fixture_secrets)" RS_ARTIFACT_NAME=x
  check_no_leaks
}
test_no_leaks_openssl() {
  gen_rsa 2048 k
  run_recover RS_PUBLIC_KEY="$(cat k.pub)" RS_SECRETS_JSON="$(fixture_secrets)" RS_ARTIFACT_NAME=x
  check_no_leaks
}
test_no_leaks_on_backend_failure() {
  # Force a failure after plaintext exists: an `age` shim that passes the empty
  # validate probe but exits 1 when handed a non-empty file to encrypt.
  gen_ssh ed25519 s
  mkdir shim
  # shellcheck disable=SC2016  # literal shim-script syntax; must not be bash-expanded here
  printf '#!/usr/bin/env bash\nlast="${*: -1}"\n[[ -s "$last" ]] && exit 1\nexec %q "$@"\n' "$(command -v age)" > shim/age
  chmod +x shim/age
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)" PATH="$PWD/shim:$PATH"
  assert_contains "$(cat "$TMP/err")" 'age encryption failed'
  check_no_leaks
}
test_no_leaks_on_include_mismatch() {
  gen_ssh ed25519 s
  assert_fails run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)" RS_INCLUDE=NOPE
  check_no_leaks
}
test_decrypt_leaves_nothing_behind() {
  gen_ssh ed25519 s
  run_recover RS_PUBLIC_KEY="$(cat s.pub)" RS_SECRETS_JSON="$(fixture_secrets)"
  mkdir t; TMPDIR="$PWD/t" bash "$REPO_ROOT/decrypt.sh" --blob "$(blob_from_output)" --key s > /dev/null
  assert_eq "" "$(ls -A t)"
}

run_tests
