#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=../scripts/filter.sh
source "$REPO_ROOT/scripts/filter.sh"

keys() { jq -c 'keys' <<<"$1"; }

test_glob_star()    { assert_eq '^AWS_.*$' "$(glob_to_regex 'AWS_*')"; }
test_glob_question(){ assert_eq '^A.B$'    "$(glob_to_regex 'A?B')"; }
test_glob_escapes_punctuation() { assert_eq '^a\.b\+$' "$(glob_to_regex 'a.b+')"; }

test_empty_include_keeps_all_but_token() {
  out="$(filter_secrets "$(fixture_secrets)" '')"
  assert_eq false "$(jq 'has("github_token")' <<<"$out")"
  assert_eq 9 "$(jq 'length' <<<"$out")"
}
test_include_exact_name() {
  assert_eq '["PLAIN"]' "$(keys "$(filter_secrets "$(fixture_secrets)" 'PLAIN')")"
}
test_include_glob() {
  assert_eq '["AWS_ACCESS_KEY_ID","AWS_SECRET_ACCESS_KEY"]' "$(keys "$(filter_secrets "$(fixture_secrets)" 'AWS_*')")"
}
test_include_tolerates_spaces() {
  assert_eq '["AWS_ACCESS_KEY_ID","AWS_SECRET_ACCESS_KEY","PLAIN"]' \
    "$(keys "$(filter_secrets "$(fixture_secrets)" 'AWS_* , PLAIN')")"
}
test_include_star_does_not_pull_in_token() {
  assert_eq false "$(filter_secrets "$(fixture_secrets)" '*' | jq 'has("github_token")')"
}
test_include_token_by_exact_name() {
  assert_eq '["PLAIN","github_token"]' "$(keys "$(filter_secrets "$(fixture_secrets)" 'github_token,PLAIN')")"
}
test_values_preserved() {
  assert_eq "$(fixture_secrets | jq -r .MULTILINE)" "$(filter_secrets "$(fixture_secrets)" 'MULTILINE' | jq -r .MULTILINE)"
}
test_not_object_exits_2() {
  set +e; filter_secrets '["a"]' '' >/dev/null; rc=$?; set -e
  assert_eq 2 "$rc"
}
test_invalid_json_exits_2() {
  set +e; filter_secrets 'not json' '' >/dev/null; rc=$?; set -e
  assert_eq 2 "$rc"
}
test_no_match_exits_3() {
  set +e; filter_secrets "$(fixture_secrets)" 'NOPE_*' >/dev/null; rc=$?; set -e
  assert_eq 3 "$rc"
}
test_empty_object_exits_3() {
  set +e; filter_secrets '{}' '' >/dev/null; rc=$?; set -e
  assert_eq 3 "$rc"
}
test_only_token_exits_3() {
  set +e; filter_secrets '{"github_token":"x"}' '' >/dev/null; rc=$?; set -e
  assert_eq 3 "$rc"
}

run_tests
