#!/usr/bin/env bash
# Minimal test harness. Source this, define test_* functions, end with run_tests.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
_PASS=0
_FAIL=0
_CURRENT=""

fail() { echo "  FAIL [$_CURRENT]: $*" >&2; return 1; }

assert_eq() { # expected actual [msg]
  [[ "$1" == "$2" ]] || fail "${3:-assert_eq}: expected '$1', got '$2'"
}
assert_contains() { # haystack needle
  [[ "$1" == *"$2"* ]] || fail "expected to contain '$2', got: ${1:0:300}"
}
assert_not_contains() { # haystack needle
  [[ "$1" != *"$2"* ]] || fail "expected NOT to contain '$2'"
}
assert_fails() { # cmd...
  if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi
}
assert_file_lacks() { # file needle
  if grep -qF -- "$2" "$1"; then fail "$1 contains '$2'"; fi
}

# ---- fixtures -------------------------------------------------------------

fixture_secrets() {
  local big
  big="$(head -c 51200 /dev/zero | tr '\0' 'x')"
  jq -cn --arg big "$big" --arg quotes "it's \"quoted\"" '{
    PLAIN: "hello",
    MULTILINE: "line1\nline2\n",
    QUOTES: $quotes,
    UNICODE: "üñí 🔐",
    EQUALS: "a=b=c",
    SPACES: "  padded  ",
    AWS_ACCESS_KEY_ID: "AKIAEXAMPLEKEY",
    AWS_SECRET_ACCESS_KEY: "wJalrXUtnFEMIexampleSECRET",
    BIG: $big,
    github_token: "ghs_fakeTOKENvalue"
  }'
}

gen_rsa() { # bits path -> path, path.pub
  openssl genpkey -algorithm RSA -pkeyopt "rsa_keygen_bits:$1" -out "$2" 2>/dev/null
  openssl pkey -in "$2" -pubout -out "$2.pub" 2>/dev/null
}
gen_ec() { # path -> path, path.pub
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1" 2>/dev/null
  openssl pkey -in "$1" -pubout -out "$1.pub" 2>/dev/null
}
gen_ssh() { # type path -> path, path.pub
  ssh-keygen -q -t "$1" -N '' -f "$2" >/dev/null 2>&1
}
gen_age() { # path -> path, path.pub
  age-keygen -o "$1" 2>/dev/null
  age-keygen -y "$1" > "$1.pub"
}
gen_gpg() { # homedir pubout
  mkdir -m 700 "$1"
  GNUPGHOME="$1" gpg --batch --quiet --passphrase '' --quick-gen-key 'rs-test <rs@example.com>' ed25519 cert never 2>/dev/null
  local fpr
  fpr="$(GNUPGHOME="$1" gpg --batch --list-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
  GNUPGHOME="$1" gpg --batch --quiet --passphrase '' --quick-add-key "$fpr" cv25519 encr never 2>/dev/null
  GNUPGHOME="$1" gpg --batch --export --armor > "$2" 2>/dev/null
}

# ---- driver runner --------------------------------------------------------

run_recover() { # ENV=value ... ; runs $RS_DRIVER (default source/main.sh) with fake GitHub files
  : > "$TMP/output"; : > "$TMP/summary"; : > "$TMP/log"; : > "$TMP/err"
  mkdir -p "$TMP/runner_temp" "$TMP/tmpdir"
  env GITHUB_OUTPUT="$TMP/output" GITHUB_STEP_SUMMARY="$TMP/summary" \
      RUNNER_TEMP="$TMP/runner_temp" TMPDIR="$TMP/tmpdir" \
      RS_SECRETS_JSON= RS_PUBLIC_KEY= RS_PUBLIC_KEY_URL= RS_INCLUDE= RS_ARTIFACT_NAME= \
      "$@" bash "${RS_DRIVER:-$REPO_ROOT/source/main.sh}" > "$TMP/log" 2> "$TMP/err"
}
blob_from_output() { sed -n 's/^blob=//p' "$TMP/output"; }

# ---- runner ---------------------------------------------------------------

run_tests() {
  local t rc
  for t in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    _CURRENT="$t"
    TMP="$(mktemp -d)"; export TMP
    set +e
    ( set -euo pipefail; cd "$TMP" && "$t" )
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then _PASS=$((_PASS+1)); echo "  ok   $t"
    else _FAIL=$((_FAIL+1)); echo "  FAIL $t"; fi
    rm -rf "$TMP"
  done
  echo "$(basename "$0"): $_PASS passed, $_FAIL failed"
  [[ $_FAIL -eq 0 ]]
}
