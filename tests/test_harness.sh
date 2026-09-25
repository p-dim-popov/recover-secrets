#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

test_assert_eq_passes() { assert_eq a a; }
test_assert_fails_detects_failure() { assert_fails false; }
test_fixture_is_object_with_github_token() {
  assert_eq true "$(fixture_secrets | jq 'type == "object" and has("github_token")')"
}
test_fixture_big_value_is_50k() {
  assert_eq 51200 "$(fixture_secrets | jq -r '.BIG | length')"
}
test_keygens_work() {
  gen_rsa 2048 rsa; [[ -s rsa.pub ]]
  gen_ec ec;        [[ -s ec.pub ]]
  gen_ssh ed25519 ssh; [[ -s ssh.pub ]]
  gen_age agek;     grep -q '^age1' agek.pub
  gen_gpg gh pub.asc; grep -q 'BEGIN PGP PUBLIC KEY' pub.asc
}

run_tests
