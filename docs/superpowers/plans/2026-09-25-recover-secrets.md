# recover-secrets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish `p-dim-popov/recover-secrets`, a composite GitHub Action (plus reusable workflow) that encrypts selected Actions secrets to a caller-owned public key via age, gpg, or openssl, and a self-contained `decrypt.sh` that turns the blob back into JSON locally.

**Architecture:** A bash driver (`scripts/recover.sh`) reads inputs from `RS_*` env vars, fetches and validates a public key, filters `toJSON(secrets)` with jq, dispatches to one of three tiny backend scripts sharing a `validate`/`encrypt` contract, and emits a single `rs1:<backend>:<base64>` blob to the step output, log, summary, and optionally an artifact. `decrypt.sh` reverses it and is the only file end users download. Every unit is a sourced bash function or a script with a fixed argv contract, tested by a minimal bash harness under `tests/`.

**Tech Stack:** bash 5, jq 1.7, openssl 3.x, gpg 2.4, age 1.1, curl, shellcheck, actionlint, GitHub Actions composite + `workflow_call`.

**Spec:** `docs/superpowers/specs/2026-09-25-recover-secrets-design.md`

## Global Constraints

- Inputs are **never** interpolated into `run:` blocks; they reach shell only via `env:` and `RS_*` variables (spec §4.1, §5).
- Input names are kebab-case: `secrets-json`, `public-key-url`, `public-key`, `include`, `artifact-name`, `retention-days`. Output: `blob` (spec §4.1).
- Blob format is exactly `rs1:<backend>:<base64 single line, no wrapping>` with backend ∈ `age|gpg|openssl` (spec §4.5).
- Key fetch: `curl --proto '=https'`, 64 KiB cap (`--max-filesize 65536`), 20 s timeout (`--max-time 20`), https-only (spec §5 step 3).
- openssl backend: RSA only, ≥ 2048 bits, AES-256-CBC with PBKDF2 100000 iterations, RSA-OAEP SHA-256 hash and MGF1 (spec §6).
- `github_token` is excluded unless `include` names it exactly (spec §5 step 5).
- The action itself never writes a secret name or value to stderr, stdout, `$GITHUB_OUTPUT`, `$GITHUB_STEP_SUMMARY`, or a file that survives the step (spec §7, §8). The runner's step header shows the `with:`/`env:` inputs, so secret names appear there, with values masked by GitHub.
- Every temp file is shredded (`shred -u`, fallback `rm -rf`) on EXIT, including failure (spec §5 step 1).
- `decrypt.sh` has no `source` lines and depends only on jq plus the backend tool named by the blob (spec §4.6).
- `scripts/detect.sh` and the `# BEGIN detect` … `# END detect` block in `decrypt.sh` must be byte-identical (spec §4.4).
- All shell scripts pass `shellcheck`; all workflow files pass `actionlint`.
- `base64` invocations use `base64 | tr -d '\n'` for encoding (macOS has no `-w0`). No `sed -i`, no `shred` without a `command -v` guard, no GNU-only flags: the whole test suite runs on `macos-latest` too.
- `recover.yml` checks out this repository at `github.job_workflow_sha` and runs `uses: ./recover-secrets-action` rather than `uses: p-dim-popov/recover-secrets@v1` (spec §4.2 refinement): same pinning effect for callers, and CI can exercise the reusable path before `v1` exists.
- Plan refinements of the spec's file layout (allowed, recorded here): backend scripts take a verb (`validate` | `encrypt`) as first arg; filtering lives in `scripts/filter.sh`; tests are `tests/run.sh` + `tests/test_*.sh` + `tests/lib.sh` instead of a single `roundtrip.sh`.

## Review Focus

1. **Key file with CRLF line endings** (gist edited on Windows): detection and age recipient parsing must still work. Test in Task 7 (`test_crlf_key_is_normalized`).
2. **`include` with spaces around commas** (`"AWS_*, DB_URL"`): both entries must match. Test in Task 3 (`test_include_tolerates_spaces`).
3. **`github.com/<user>.keys` mixing ecdsa and ed25519 keys**: ecdsa lines skipped with a warning, ed25519 used, run succeeds. Test in Task 6 (`test_age_skips_unsupported_key_lines`).
4. **Blob pasted with line wraps and trailing newline** into `decrypt.sh` stdin: must decrypt. Test in Task 8 (`test_decrypt_stdin_tolerates_wrapping`).
5. **Secret value containing a newline or a single quote** in `--env` output: `source` must reproduce it exactly. Test in Task 8 (`test_decrypt_env_output_is_sourceable`).

---

## File structure

| File | Responsibility |
|---|---|
| `LICENSE` | MIT |
| `.gitignore`, `.shellcheckrc` | ignore `tests/.tmp/`; shellcheck source resolution |
| `tests/lib.sh` | harness: `run_tests`, `assert_*`, fixture and keygen helpers, `run_recover` |
| `tests/run.sh` | runs every `tests/test_*.sh`, non-zero if any fails |
| `scripts/detect.sh` | `detect_key_format`, `detect_blob_format` |
| `scripts/filter.sh` | `glob_to_regex`, `filter_secrets` |
| `scripts/encrypt-openssl.sh` | `validate`/`encrypt` for PEM RSA |
| `scripts/encrypt-gpg.sh` | `validate`/`encrypt` for PGP keys |
| `scripts/encrypt-age.sh` | `validate`/`encrypt` for age/SSH recipients, installs age if missing |
| `scripts/recover.sh` | driver |
| `decrypt.sh` | local decrypt helper |
| `action.yml` | composite action |
| `.github/workflows/recover.yml` | reusable workflow |
| `.github/workflows/ci.yml` | lint, roundtrip matrix, end-to-end |
| `.github/workflows/examples/throwaway-branch.yml`, `dispatch.yml` | copy-paste examples |
| `README.md` | docs |

---

### Task 1: Scaffold, prerequisites, test harness

**Files:**
- Create: `LICENSE`, `.gitignore`, `.shellcheckrc`, `tests/lib.sh`, `tests/run.sh`, `tests/test_harness.sh`

**Interfaces:**
- Produces: `tests/lib.sh` exporting `REPO_ROOT`, `TMP` (fresh per test), `run_tests`, `fail`, `assert_eq expected actual [msg]`, `assert_contains haystack needle`, `assert_not_contains haystack needle`, `assert_fails cmd...`, `assert_file_lacks file needle`, `fixture_secrets` (prints JSON), `gen_rsa bits path` (writes `path` and `path.pub`), `gen_ec path`, `gen_ssh type path`, `gen_age path` (writes `path` and `path.pub`), `gen_gpg homedir pubout`, `run_recover ENV=val...` (runs driver with fakes; log in `$TMP/log`, stderr in `$TMP/err`, output in `$TMP/output`, summary in `$TMP/summary`, runner temp in `$TMP/runner_temp`), `blob_from_output`.

- [ ] **Step 1: Install local prerequisites**

```bash
sudo apt-get install -y age shellcheck
# actionlint: single static binary
curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash -s -- latest "$HOME/.local/bin"
age --version && shellcheck --version | head -2 && "$HOME/.local/bin/actionlint" -version
```
Expected: three version strings. (`age-keygen` ships with `age`.)

- [ ] **Step 2: Write LICENSE and .gitignore**

`LICENSE`: the standard MIT text with `Copyright (c) 2026 Petar Popov`.

`.gitignore`:
```
tests/.tmp/
```

`.shellcheckrc` (lets `# shellcheck source=` directives resolve relative to each script):
```
external-sources=true
source-path=SCRIPTDIR
```

- [ ] **Step 3: Write the test harness**

`tests/lib.sh`:
```bash
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

run_recover() { # ENV=value ... ; runs scripts/recover.sh with fake GitHub files
  : > "$TMP/output"; : > "$TMP/summary"; : > "$TMP/log"; : > "$TMP/err"
  mkdir -p "$TMP/runner_temp" "$TMP/tmpdir"
  env GITHUB_OUTPUT="$TMP/output" GITHUB_STEP_SUMMARY="$TMP/summary" \
      RUNNER_TEMP="$TMP/runner_temp" TMPDIR="$TMP/tmpdir" \
      RS_SECRETS_JSON= RS_PUBLIC_KEY= RS_PUBLIC_KEY_URL= RS_INCLUDE= RS_ARTIFACT_NAME= \
      "$@" bash "$REPO_ROOT/scripts/recover.sh" > "$TMP/log" 2> "$TMP/err"
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
```

Why the `set +e` / subshell dance: bash ignores `set -e` inside any command that is the condition of `if`/`||`, so a test run as `if ( "$t" )` would never abort on a failed assertion.

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
status=0
for f in test_*.sh; do
  echo "== $f"
  bash "$f" || status=1
done
exit $status
```

- [ ] **Step 4: Write a harness self-test**

`tests/test_harness.sh`:
```bash
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
```

- [ ] **Step 5: Run it**

Run: `bash tests/run.sh`
Expected: `test_harness.sh: 5 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
chmod +x tests/run.sh
git add LICENSE .gitignore .shellcheckrc tests
git commit -m "chore: scaffold repo with MIT license and bash test harness"
```

---

### Task 2: Key and blob format detection

**Files:**
- Create: `scripts/detect.sh`, `tests/test_detect.sh`

**Interfaces:**
- Produces: `detect_key_format <file>` prints `openssl|gpg|age`, exit 1 if unknown. `detect_blob_format <string>` prints `age|gpg|openssl` for an `rs1:` blob, exit 1 otherwise. Both are sourced, not executed.

- [ ] **Step 1: Write failing tests**

`tests/test_detect.sh`:
```bash
#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=../scripts/detect.sh
source "$REPO_ROOT/scripts/detect.sh"

test_detects_pem_rsa()        { gen_rsa 2048 k; assert_eq openssl "$(detect_key_format k.pub)"; }
test_detects_pem_rsa_legacy() { printf -- '-----BEGIN RSA PUBLIC KEY-----\nAAAA\n-----END RSA PUBLIC KEY-----\n' > k; assert_eq openssl "$(detect_key_format k)"; }
test_detects_pgp()            { gen_gpg gh pub.asc; assert_eq gpg "$(detect_key_format pub.asc)"; }
test_detects_age_recipient()  { gen_age a; assert_eq age "$(detect_key_format a.pub)"; }
test_detects_ssh_ed25519()    { gen_ssh ed25519 s; assert_eq age "$(detect_key_format s.pub)"; }
test_detects_ssh_rsa()        { gen_ssh rsa s; assert_eq age "$(detect_key_format s.pub)"; }
test_detects_keys_list_with_comment() {
  gen_ssh ed25519 s; { echo '# github keys'; cat s.pub; } > list
  assert_eq age "$(detect_key_format list)"
}
test_rejects_unknown_key()    { echo 'hello' > k; assert_fails detect_key_format k; }
test_rejects_private_key()    { gen_rsa 2048 k; assert_fails detect_key_format k; }

test_blob_age()     { assert_eq age     "$(detect_blob_format 'rs1:age:AAAA')"; }
test_blob_gpg()     { assert_eq gpg     "$(detect_blob_format 'rs1:gpg:AAAA')"; }
test_blob_openssl() { assert_eq openssl "$(detect_blob_format 'rs1:openssl:AAAA')"; }
test_blob_unknown_version() { assert_fails detect_blob_format 'rs2:age:AAAA'; }
test_blob_unknown_backend() { assert_fails detect_blob_format 'rs1:rot13:AAAA'; }
test_blob_garbage()         { assert_fails detect_blob_format 'AAAA'; }

run_tests
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_detect.sh`
Expected: `source: No such file` error (exit non-zero).

- [ ] **Step 3: Implement**

`scripts/detect.sh`:
```bash
#!/usr/bin/env bash
# Sourced by scripts/recover.sh. decrypt.sh carries a byte-identical copy of the
# block between BEGIN/END detect; tests/test_decrypt.sh asserts they match.

# BEGIN detect
# detect_key_format <file> -> prints openssl | gpg | age ; exit 1 if unknown
detect_key_format() {
  local file="$1"
  if grep -qE '^-----BEGIN (RSA )?PUBLIC KEY-----' "$file"; then
    echo openssl
  elif grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$file"; then
    echo gpg
  elif grep -qE '^(age1|ssh-ed25519 |ssh-rsa )' "$file"; then
    echo age
  else
    return 1
  fi
}

# detect_blob_format <blob-string> -> prints age | gpg | openssl ; exit 1 if not an rs1 blob
detect_blob_format() {
  case "$1" in
    rs1:age:*) echo age ;;
    rs1:gpg:*) echo gpg ;;
    rs1:openssl:*) echo openssl ;;
    *) return 1 ;;
  esac
}
# END detect
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_detect.sh`
Expected: `test_detect.sh: 15 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck scripts/detect.sh tests/lib.sh tests/*.sh
git add scripts/detect.sh tests/test_detect.sh
git commit -m "feat: detect public key and blob formats"
```

---

### Task 3: Secret filtering

**Files:**
- Create: `scripts/filter.sh`, `tests/test_filter.sh`

**Interfaces:**
- Produces: `glob_to_regex <glob>` prints an anchored regex for jq `test()`. `filter_secrets <json-string> <include-csv>` prints the filtered JSON object on stdout; exit 2 if input is not a JSON object, exit 3 if the result is empty. Prints nothing on error. Sourced.

- [ ] **Step 1: Write failing tests**

`tests/test_filter.sh`:
```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_filter.sh`
Expected: `source: No such file` (non-zero).

- [ ] **Step 3: Implement**

`scripts/filter.sh`:
```bash
#!/usr/bin/env bash
# Sourced by scripts/recover.sh.

# glob_to_regex <glob> -> anchored regex for jq's test(). Only * and ? are special.
glob_to_regex() {
  local glob="$1" out="" c i
  for ((i = 0; i < ${#glob}; i++)); do
    c="${glob:i:1}"
    case "$c" in
      '*') out+='.*' ;;
      '?') out+='.' ;;
      [A-Za-z0-9_]) out+="$c" ;;
      *) out+="\\$c" ;;
    esac
  done
  printf '^%s$' "$out"
}

# filter_secrets <json-string> <include-csv>
# stdout: filtered JSON object. exit 2: not an object. exit 3: nothing matched.
# Never prints names or values on error.
filter_secrets() {
  local json="$1" include="$2" regexes='[]' explicit_token=false entry
  jq -e 'type == "object"' <<<"$json" >/dev/null 2>&1 || return 2

  local -a entries=()
  IFS=',' read -ra entries <<<"$include"
  for entry in ${entries[@]+"${entries[@]}"}; do   # safe under set -u on bash 3.2
    entry="${entry//[[:space:]]/}"
    [[ -z "$entry" ]] && continue
    [[ "$entry" == "github_token" ]] && explicit_token=true
    regexes="$(jq -c --arg r "$(glob_to_regex "$entry")" '. + [$r]' <<<"$regexes")"
  done

  local result
  result="$(jq -c --argjson rx "$regexes" --argjson tok "$explicit_token" '
    with_entries(select(
      (.key != "github_token" or $tok)
      and (($rx | length) == 0 or (.key as $k | any($rx[]; . as $r | $k | test($r))))
    ))' <<<"$json")"
  [[ "$(jq 'length' <<<"$result")" -gt 0 ]] || return 3
  printf '%s\n' "$result"
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_filter.sh`
Expected: `test_filter.sh: 16 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck scripts/filter.sh tests/test_filter.sh
git add scripts/filter.sh tests/test_filter.sh
git commit -m "feat: filter secrets by include globs, drop github_token by default"
```

---

### Task 4: openssl backend

**Files:**
- Create: `scripts/encrypt-openssl.sh`, `tests/test_backend_openssl.sh`

**Interfaces:**
- Produces (contract shared by all backends): `encrypt-<backend>.sh validate <pubkey-file>` exits 0 if usable, 1 otherwise. `encrypt-<backend>.sh encrypt <pubkey-file> <plaintext-file> <out-file>` writes ciphertext, no stdout, non-zero on failure. Tool stderr is suppressed inside the script; the script's own stderr is for `::warning::` lines only. Scripts honor `TMPDIR` for their scratch dir.
- openssl `out-file` content: JSON `{"k":"<base64>","d":"<base64>"}` (spec §4.5).

- [ ] **Step 1: Write failing tests**

`tests/test_backend_openssl.sh`:
```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_backend_openssl.sh`
Expected: every test FAILs (script missing); summary shows `0 passed`.

- [ ] **Step 3: Implement**

`scripts/encrypt-openssl.sh`:
```bash
#!/usr/bin/env bash
# Usage: encrypt-openssl.sh validate <pubkey>
#        encrypt-openssl.sh encrypt  <pubkey> <plaintext> <out>
# RSA-OAEP(SHA-256) wraps a random passphrase; AES-256-CBC (PBKDF2, 100k) encrypts the data.
set -euo pipefail
umask 077

cmd="${1:-}"
pub="${2:-}"

cleanup() {
  [[ -n "${work:-}" && -d "$work" ]] || return 0
  if command -v shred >/dev/null 2>&1; then
    find "$work" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    openssl rsa -pubin -in "$pub" -noout >/dev/null 2>&1 || exit 1
    bits="$(openssl rsa -pubin -in "$pub" -noout -text 2>/dev/null \
            | sed -n 's/^Public-Key: (\([0-9]*\) bit)$/\1/p')"
    [[ -n "$bits" && "$bits" -ge 2048 ]] || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    work="$(mktemp -d)"
    openssl rand -hex 32 > "$work/pass"
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
      -pass "file:$work/pass" -in "$plaintext" -out "$work/data" 2>/dev/null
    openssl pkeyutl -encrypt -pubin -inkey "$pub" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
      -in "$work/pass" -out "$work/key" 2>/dev/null
    jq -nc --arg k "$(base64 < "$work/key" | tr -d '\n')" \
           --arg d "$(base64 < "$work/data" | tr -d '\n')" \
           '{k: $k, d: $d}' > "$out"
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_backend_openssl.sh`
Expected: `test_backend_openssl.sh: 12 passed, 0 failed`. (4096-bit keygen takes a few seconds.)

- [ ] **Step 5: Lint and commit**

```bash
shellcheck scripts/encrypt-openssl.sh tests/test_backend_openssl.sh
git add scripts/encrypt-openssl.sh tests/test_backend_openssl.sh
git commit -m "feat: openssl backend (RSA-OAEP + AES-256-CBC)"
```

---

### Task 5: gpg backend

**Files:**
- Create: `scripts/encrypt-gpg.sh`, `tests/test_backend_gpg.sh`

**Interfaces:**
- Consumes: the backend contract from Task 4.
- Produces: `encrypt-gpg.sh validate|encrypt`. `out-file` is binary (unarmored) OpenPGP. Uses a throwaway `GNUPGHOME` under `TMPDIR`.

- [ ] **Step 1: Write failing tests**

`tests/test_backend_gpg.sh`:
```bash
#!/usr/bin/env bash
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
ENC="$REPO_ROOT/scripts/encrypt-gpg.sh"

test_validate_ok()        { gen_gpg gh pub.asc; bash "$ENC" validate pub.asc; }
test_rejects_garbage()    { echo nope > k; assert_fails bash "$ENC" validate k; }
test_rejects_pem()        { gen_rsa 2048 k; assert_fails bash "$ENC" validate k.pub; }
test_rejects_key_without_encryption_subkey() {
  mkdir -m 700 gh
  GNUPGHOME=gh gpg --batch --quiet --passphrase '' --quick-gen-key 'x <x@example.com>' ed25519 cert never 2>/dev/null
  GNUPGHOME=gh gpg --batch --export --armor > pub.asc
  assert_fails bash "$ENC" validate pub.asc
}
test_roundtrip() {
  gen_gpg gh pub.asc; fixture_secrets > plain.json
  bash "$ENC" encrypt pub.asc plain.json out
  assert_eq "$(cat plain.json)" "$(GNUPGHOME=gh gpg --batch --quiet --decrypt out 2>/dev/null)"
}
test_output_is_binary_not_armored() {
  gen_gpg gh pub.asc; echo '{}' > plain.json
  bash "$ENC" encrypt pub.asc plain.json out
  assert_fails grep -q 'BEGIN PGP MESSAGE' out
}
test_encrypt_is_silent() {
  gen_gpg gh pub.asc; echo '{}' > plain.json
  assert_eq "" "$(bash "$ENC" encrypt pub.asc plain.json out 2>&1)"
}
test_does_not_touch_user_keyring() {
  gen_gpg gh pub.asc; echo '{}' > plain.json
  mkdir -m 700 userhome
  GNUPGHOME="$PWD/userhome" bash "$ENC" encrypt pub.asc plain.json out
  assert_eq "" "$(ls userhome)"
}
test_multiple_keys_in_file_all_become_recipients() {
  gen_gpg gh1 p1.asc; gen_gpg gh2 p2.asc; cat p1.asc p2.asc > both.asc
  echo '{"a":1}' > plain.json
  bash "$ENC" encrypt both.asc plain.json out
  assert_eq '{"a":1}' "$(GNUPGHOME=gh1 gpg --batch --quiet --decrypt out 2>/dev/null)"
  assert_eq '{"a":1}' "$(GNUPGHOME=gh2 gpg --batch --quiet --decrypt out 2>/dev/null)"
}

run_tests
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_backend_gpg.sh`
Expected: all FAIL, `0 passed`.

- [ ] **Step 3: Implement**

`scripts/encrypt-gpg.sh`:
```bash
#!/usr/bin/env bash
# Usage: encrypt-gpg.sh validate <pubkey>
#        encrypt-gpg.sh encrypt  <pubkey> <plaintext> <out>
# Uses a throwaway GNUPGHOME so the runner's keyring is never read or written.
set -euo pipefail
umask 077

cmd="${1:-}"
pub="${2:-}"

work="$(mktemp -d)"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$work" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    # At least one key, and at least one (sub)key with the E (encrypt) capability.
    keys="$(gpg --batch --quiet --show-keys "$pub" 2>/dev/null)" || exit 1
    grep -q '^pub ' <<<"$keys" || exit 1
    grep -qE '^(pub|sub) .*\[[A-Z]*E[A-Z]*\]' <<<"$keys" || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    gpg --batch --quiet --trust-model always --recipient-file "$pub" \
      --encrypt --output "$out" "$plaintext" 2>/dev/null
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_backend_gpg.sh`
Expected: `test_backend_gpg.sh: 9 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck scripts/encrypt-gpg.sh tests/test_backend_gpg.sh
git add scripts/encrypt-gpg.sh tests/test_backend_gpg.sh
git commit -m "feat: gpg backend with throwaway keyring"
```

---

### Task 6: age backend

**Files:**
- Create: `scripts/encrypt-age.sh`, `tests/test_backend_age.sh`

**Interfaces:**
- Consumes: the backend contract from Task 4.
- Produces: `encrypt-age.sh validate|encrypt`. Recipients are the lines of the key file starting `age1`, `ssh-ed25519 `, or `ssh-rsa `. Unsupported non-blank, non-comment lines produce one `::warning::` line on stderr during `validate` only. Installs `age` via apt-get/brew if missing.

- [ ] **Step 1: Write failing tests**

`tests/test_backend_age.sh`:
```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_backend_age.sh`
Expected: all FAIL, `0 passed`.

- [ ] **Step 3: Implement**

`scripts/encrypt-age.sh`:
```bash
#!/usr/bin/env bash
# Usage: encrypt-age.sh validate <pubkey>
#        encrypt-age.sh encrypt  <pubkey> <plaintext> <out>
# Recipients: lines starting age1, ssh-ed25519, ssh-rsa. Installs age if missing.
set -euo pipefail
umask 077

cmd="${1:-}"
pub="${2:-}"

work="$(mktemp -d)"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$work" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

ensure_age() {
  command -v age >/dev/null 2>&1 && return 0
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y -qq age >/dev/null 2>&1 || true
  elif command -v brew >/dev/null 2>&1; then
    brew install -q age >/dev/null 2>&1 || true
  fi
  command -v age >/dev/null 2>&1
}

SUPPORTED='^(age1|ssh-ed25519 |ssh-rsa )'
IGNORED='^(#|[[:space:]]*$)'

# recipients_from <pub> <out> [warn]: writes supported lines; exit 1 if none.
recipients_from() {
  local src="$1" dst="$2" warn="${3:-}" skipped
  grep -E "$SUPPORTED" "$src" > "$dst" || true
  skipped="$(grep -vE "$SUPPORTED" "$src" | grep -cvE "$IGNORED" || true)"
  if [[ -n "$warn" && "$skipped" -gt 0 ]]; then
    echo "::warning::Skipped $skipped unsupported key line(s); age accepts age1, ssh-ed25519 and ssh-rsa" >&2
  fi
  [[ -s "$dst" ]]
}

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    ensure_age || exit 1
    recipients_from "$pub" "$work/recipients" warn || exit 1
    : > "$work/empty"
    age -R "$work/recipients" -o "$work/probe" "$work/empty" 2>/dev/null || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    ensure_age || exit 1
    recipients_from "$pub" "$work/recipients" || exit 1
    age -R "$work/recipients" -o "$out" "$plaintext" 2>/dev/null
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_backend_age.sh`
Expected: `test_backend_age.sh: 13 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck scripts/encrypt-age.sh tests/test_backend_age.sh
git add scripts/encrypt-age.sh tests/test_backend_age.sh
git commit -m "feat: age backend accepting age1 and SSH recipients"
```

---

### Task 7: Driver `scripts/recover.sh`

**Files:**
- Create: `scripts/recover.sh`, `tests/test_recover.sh`

**Interfaces:**
- Consumes: `detect_key_format` (Task 2), `filter_secrets` (Task 3), `encrypt-<backend>.sh validate|encrypt` (Tasks 4–6).
- Consumes env: `RS_SECRETS_JSON`, `RS_PUBLIC_KEY_URL`, `RS_PUBLIC_KEY`, `RS_INCLUDE`, `RS_ARTIFACT_NAME`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `RUNNER_TEMP`.
- Produces: `blob=rs1:<backend>:<b64>` line in `$GITHUB_OUTPUT`; log group and summary code block containing the blob; `$RUNNER_TEMP/recover-secrets/blob.txt` when `RS_ARTIFACT_NAME` is set; one `::error::` line on stderr and exit 1 on any failure; final stdout line `Encrypted N secret(s) with <backend>`.

- [ ] **Step 1: Write failing tests**

`tests/test_recover.sh`:
```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_recover.sh`
Expected: all FAIL, `0 passed`.

- [ ] **Step 3: Implement**

`scripts/recover.sh`:
```bash
#!/usr/bin/env bash
# recover-secrets driver. Inputs arrive only as RS_* environment variables.
# Emits one rs1:<backend>:<base64> blob to $GITHUB_OUTPUT, the log, the step
# summary, and (optionally) $RUNNER_TEMP/recover-secrets/blob.txt.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=detect.sh
source "$SCRIPT_DIR/detect.sh"
# shellcheck source=filter.sh
source "$SCRIPT_DIR/filter.sh"

RS_SECRETS_JSON="${RS_SECRETS_JSON:-}"
RS_PUBLIC_KEY_URL="${RS_PUBLIC_KEY_URL:-}"
RS_PUBLIC_KEY="${RS_PUBLIC_KEY:-}"
RS_INCLUDE="${RS_INCLUDE:-}"
RS_ARTIFACT_NAME="${RS_ARTIFACT_NAME:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

WORK="$(mktemp -d)"
export TMPDIR="$WORK"   # backend scratch dirs land inside WORK and die with it
RUNNER_TEMP="${RUNNER_TEMP:-$WORK}"

cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$WORK" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT

die() { echo "::error::$*" >&2; exit 1; }

fetch_key() { # url out
  local url="$1" out="$2" status
  case "$url" in
    https://*) ;;
    *) die "public-key-url must start with https://" ;;
  esac
  status="$(curl --proto '=https' --silent --show-error --location \
              --max-filesize 65536 --max-time 20 \
              --output "$out" --write-out '%{http_code}' "$url" 2>/dev/null)" \
    || die "Fetching public-key-url failed (curl exit $?)"
  [[ "$status" == "200" ]] || die "Fetching public-key-url returned HTTP $status"
}

# 1. Public key ---------------------------------------------------------------
if [[ -n "$RS_PUBLIC_KEY" && -n "$RS_PUBLIC_KEY_URL" ]]; then
  die "Set either public-key or public-key-url, not both"
fi
if [[ -z "$RS_PUBLIC_KEY" && -z "$RS_PUBLIC_KEY_URL" ]]; then
  die "One of public-key or public-key-url is required"
fi
PUB="$WORK/pub.key"
if [[ -n "$RS_PUBLIC_KEY" ]]; then
  printf '%s\n' "$RS_PUBLIC_KEY" > "$PUB"
else
  fetch_key "$RS_PUBLIC_KEY_URL" "$PUB"
fi
tr -d '\r' < "$PUB" > "$PUB.lf" && mv "$PUB.lf" "$PUB"   # CRLF from Windows-edited gists; portable (no sed -i)

BACKEND="$(detect_key_format "$PUB")" \
  || die "Unrecognized public key format: expected PEM RSA, PGP armor, age1, ssh-ed25519 or ssh-rsa"
ENC="$SCRIPT_DIR/encrypt-$BACKEND.sh"
bash "$ENC" validate "$PUB" || die "Public key rejected by $BACKEND backend (exit $?)"

# 2. Secrets -------------------------------------------------------------------
[[ -n "$RS_SECRETS_JSON" ]] || die 'secrets-json is required (pass ${{ toJSON(secrets) }})'
set +e
FILTERED="$(filter_secrets "$RS_SECRETS_JSON" "$RS_INCLUDE")"
rc=$?
set -e
case $rc in
  0) ;;
  2) die 'secrets-json must be a JSON object (pass ${{ toJSON(secrets) }})' ;;
  3) die "include matched none of the $(jq 'del(.github_token) | length' <<<"$RS_SECRETS_JSON") available secrets" ;;
  *) die "Filtering secrets failed (exit $rc)" ;;
esac
printf '%s' "$FILTERED" > "$WORK/plaintext.json"
unset FILTERED RS_SECRETS_JSON
COUNT="$(jq 'length' "$WORK/plaintext.json")"

# 3. Encrypt -------------------------------------------------------------------
bash "$ENC" encrypt "$PUB" "$WORK/plaintext.json" "$WORK/out.bin" \
  || die "$BACKEND encryption failed (exit $?)"
BLOB="rs1:$BACKEND:$(base64 < "$WORK/out.bin" | tr -d '\n')"

# 4. Emit ----------------------------------------------------------------------
echo "blob=$BLOB" >> "$GITHUB_OUTPUT"
echo "::group::Encrypted blob ($BACKEND)"
echo "$BLOB"
echo "::endgroup::"
{
  echo "### recover-secrets"
  echo
  echo "Backend: \`$BACKEND\`. Copy the blob below into \`decrypt.sh\`."
  echo
  echo '```'
  echo "$BLOB"
  echo '```'
} >> "$GITHUB_STEP_SUMMARY"
if [[ -n "$RS_ARTIFACT_NAME" ]]; then
  mkdir -p "$RUNNER_TEMP/recover-secrets"
  printf '%s\n' "$BLOB" > "$RUNNER_TEMP/recover-secrets/blob.txt"
fi
echo "Encrypted $COUNT secret(s) with $BACKEND"
```

Note on `$?` inside `die` after `||`: the argument is expanded after the left side failed, so it carries that command's exit status.

- [ ] **Step 4: Run tests**

Run: `bash tests/test_recover.sh`
Expected: `test_recover.sh: 20 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
shellcheck -x scripts/recover.sh tests/test_recover.sh
git add scripts/recover.sh tests/test_recover.sh
git commit -m "feat: recover.sh driver with validation, filtering and emit"
```

---

### Task 8: `decrypt.sh`

**Files:**
- Create: `decrypt.sh`, `tests/test_decrypt.sh`

**Interfaces:**
- Consumes: blobs produced by `recover.sh` (Task 7); the detect block text from `scripts/detect.sh` (Task 2), copied verbatim.
- Produces: `decrypt.sh [--blob <string> | --file <path>] [--key <path>] [--env]`. Exit 0 with JSON (or `NAME='value'` lines) on stdout; exit 1 with `error: ...` on stderr; exit 64 on usage errors.

- [ ] **Step 1: Write failing tests**

`tests/test_decrypt.sh`:
```bash
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
test_temp_cleaned() {
  gen_ssh ed25519 s; blob="$(make_blob "$(cat s.pub)")"
  mkdir t; TMPDIR="$PWD/t" bash "$DEC" --blob "$blob" --key s >/dev/null
  assert_eq "" "$(ls -A t)"
}

run_tests
```

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/test_decrypt.sh`
Expected: all FAIL, `0 passed`.

- [ ] **Step 3: Implement**

`decrypt.sh` (the `# BEGIN detect` … `# END detect` block is pasted verbatim from `scripts/detect.sh`):
```bash
#!/usr/bin/env bash
# recover-secrets decrypt helper. Self-contained: needs jq plus whichever of
# age, gpg, or openssl the blob names.
#
# Usage: decrypt.sh [--blob <string> | --file <path>] [--key <path>] [--env]
#   no --blob/--file  read the blob from stdin (paste, then Ctrl-D)
#   --key <path>      private key: SSH key or age identity (age), PEM (openssl);
#                     ignored for gpg, which uses your keyring
#   --env             print NAME='value' lines instead of JSON
set -euo pipefail
umask 077

SUPPORTED_VERSION="rs1"

# BEGIN detect
# detect_key_format <file> -> prints openssl | gpg | age ; exit 1 if unknown
detect_key_format() {
  local file="$1"
  if grep -qE '^-----BEGIN (RSA )?PUBLIC KEY-----' "$file"; then
    echo openssl
  elif grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$file"; then
    echo gpg
  elif grep -qE '^(age1|ssh-ed25519 |ssh-rsa )' "$file"; then
    echo age
  else
    return 1
  fi
}

# detect_blob_format <blob-string> -> prints age | gpg | openssl ; exit 1 if not an rs1 blob
detect_blob_format() {
  case "$1" in
    rs1:age:*) echo age ;;
    rs1:gpg:*) echo gpg ;;
    rs1:openssl:*) echo openssl ;;
    *) return 1 ;;
  esac
}
# END detect

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}
die()  { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required. Install it with: $2"; }

BLOB=""; FILE=""; KEY=""; ENV_OUT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --blob) BLOB="${2:-}"; [[ -n "$BLOB" ]] || { echo "--blob needs a value" >&2; exit 64; }; shift 2 ;;
    --file) FILE="${2:-}"; [[ -n "$FILE" ]] || { echo "--file needs a value" >&2; exit 64; }; shift 2 ;;
    --key)  KEY="${2:-}";  [[ -n "$KEY"  ]] || { echo "--key needs a value"  >&2; exit 64; }; shift 2 ;;
    --env)  ENV_OUT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done
if [[ -n "$BLOB" && -n "$FILE" ]]; then
  echo "Use --blob or --file, not both" >&2; exit 64
fi

if [[ -n "$FILE" ]]; then
  BLOB="$(cat "$FILE")"
elif [[ -z "$BLOB" ]]; then
  [[ -t 0 ]] && echo "Paste the blob, then press Ctrl-D:" >&2
  BLOB="$(cat)"
fi
BLOB="$(printf '%s' "$BLOB" | tr -d '[:space:]')"

need jq "brew install jq  |  sudo apt-get install jq"
BACKEND="$(detect_blob_format "$BLOB")" \
  || die "Not a blob this script understands. Expected '${SUPPORTED_VERSION}:<age|gpg|openssl>:...'; a newer decrypt.sh may be needed"

WORK="$(mktemp -d)"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$WORK" -type f -exec shred -u -- {} + 2>/dev/null || true
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT

printf '%s' "${BLOB#rs1:*:}" | base64 -d > "$WORK/in" 2>/dev/null || die "Blob payload is not valid base64"

case "$BACKEND" in
  age)
    need age "brew install age  |  sudo apt-get install age"
    if [[ -z "$KEY" ]]; then
      for candidate in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.config/age/keys.txt"; do
        [[ -f "$candidate" ]] && { KEY="$candidate"; break; }
      done
      [[ -n "$KEY" ]] || die "No key found. Pass --key <SSH private key or age identity>"
    fi
    age -d -i "$KEY" -o "$WORK/plain" "$WORK/in" 2>/dev/null \
      || die "age decryption failed. Wrong key? (used $KEY)"
    ;;
  gpg)
    need gpg "brew install gnupg  |  sudo apt-get install gnupg"
    gpg --quiet --decrypt --output "$WORK/plain" "$WORK/in" 2>/dev/null \
      || die "gpg decryption failed. Is the matching private key in your keyring?"
    ;;
  openssl)
    need openssl "brew install openssl  |  sudo apt-get install openssl"
    [[ -n "$KEY" ]] || die "Pass --key <RSA private key PEM>"
    jq -r '.k' "$WORK/in" 2>/dev/null | base64 -d > "$WORK/key" 2>/dev/null || die "Malformed openssl envelope"
    jq -r '.d' "$WORK/in" 2>/dev/null | base64 -d > "$WORK/data" 2>/dev/null || die "Malformed openssl envelope"
    openssl pkeyutl -decrypt -inkey "$KEY" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
      -in "$WORK/key" -out "$WORK/pass" 2>/dev/null \
      || die "RSA unwrap failed. Wrong key? (used $KEY)"
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "file:$WORK/pass" \
      -in "$WORK/data" -out "$WORK/plain" 2>/dev/null \
      || die "AES decryption failed. Corrupted blob?"
    ;;
esac

jq -e 'type == "object"' "$WORK/plain" >/dev/null 2>&1 \
  || die "Decrypted data is not a JSON object. Wrong key or corrupted blob"

if $ENV_OUT; then
  # NAME='value' with embedded single quotes closed/escaped/reopened: it's -> 'it'\''s'
  jq -r 'to_entries[] | "\(.key)='\(.value | tostring | gsub("'"; "'\\''"))'"' "$WORK/plain"
else
  jq . "$WORK/plain"
fi
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_decrypt.sh`
Expected: `test_decrypt.sh: 22 passed, 0 failed`.

If `test_decrypt_env_output_is_sourceable` fails on `QUOTES`, print `vars.env` and check the line reads exactly `QUOTES='it'\''s "quoted"'`; adjust the jq replacement string so the output has one backslash.

- [ ] **Step 5: Lint and commit**

```bash
chmod +x decrypt.sh
shellcheck decrypt.sh tests/test_decrypt.sh
git add decrypt.sh tests/test_decrypt.sh
git commit -m "feat: self-contained decrypt.sh for age, gpg and openssl blobs"
```

---

### Task 9: Leak check

**Files:**
- Create: `tests/test_leaks.sh`

**Interfaces:**
- Consumes: `run_recover`, `fixture_secrets` (Task 1), `decrypt.sh` (Task 8).

- [ ] **Step 1: Write the test**

`tests/test_leaks.sh`:
```bash
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
```

- [ ] **Step 2: Run**

Run: `bash tests/test_leaks.sh`
Expected: `test_leaks.sh: 6 passed, 0 failed`.

- [ ] **Step 3: Run the whole suite and commit**

Run: `bash tests/run.sh`
Expected: every file reports `0 failed`; exit 0.

```bash
git add tests/test_leaks.sh
git commit -m "test: leak check across backends, failures and decrypt"
```

---

### Task 10: `action.yml` and the reusable workflow

**Files:**
- Create: `action.yml`, `.github/workflows/recover.yml`

**Interfaces:**
- Consumes: `scripts/recover.sh` env contract (Task 7).
- Produces: action inputs `secrets-json`, `public-key-url`, `public-key`, `include`, `artifact-name`, `retention-days`; output `blob`. Reusable workflow `recover.yml` with the same inputs minus `secrets-json`, plus `environment`; output `blob`; requires `secrets: inherit` from the caller.

- [ ] **Step 1: Pin `actions/checkout` and `actions/upload-artifact` to commit SHAs**

```bash
gh api repos/actions/upload-artifact/git/ref/tags/v4 --jq .object.sha
gh api repos/actions/checkout/git/ref/tags/v4 --jq .object.sha
```
If a ref is an annotated tag the SHA points to a tag object; resolve it with `gh api repos/actions/upload-artifact/git/tags/<sha> --jq .object.sha`. Record both SHAs; they go into the `uses:` lines below as `@<sha> # v4`.

- [ ] **Step 2: Write `action.yml`**

```yaml
name: recover-secrets
description: >-
  Encrypt GitHub Actions secrets to your own public key (SSH, age, GPG or RSA)
  so you can recover them locally. Nothing readable is ever written to logs,
  summaries or artifacts.
author: p-dim-popov
branding:
  icon: lock
  color: gray-dark

inputs:
  secrets-json:
    description: >-
      JSON object of the secrets to recover. Normally `${{ toJSON(secrets) }}`.
      A hand-built object such as `{"FOO": "${{ secrets.FOO }}"}` also works.
    required: true
  public-key-url:
    description: >-
      HTTPS URL of the public key to encrypt to. Accepts an SSH keys list such as
      https://github.com/<user>.keys, a GPG key such as https://github.com/<user>.gpg,
      an age1 recipient, or a PEM RSA public key. Use this or `public-key`.
    required: false
    default: ""
  public-key:
    description: The public key text itself, as an alternative to `public-key-url`.
    required: false
    default: ""
  include:
    description: >-
      Comma-separated secret names or globs (`AWS_*`). Empty means every secret
      except `github_token`, which is only included when named exactly.
    required: false
    default: ""
  artifact-name:
    description: If set, also upload the encrypted blob as an artifact with this name.
    required: false
    default: ""
  retention-days:
    description: Retention for the artifact, in days.
    required: false
    default: "1"

outputs:
  blob:
    description: The encrypted blob, `rs1:<backend>:<base64>`. Feed it to decrypt.sh.
    value: ${{ steps.recover.outputs.blob }}

runs:
  using: composite
  steps:
    - id: recover
      shell: bash
      env:
        RS_SECRETS_JSON: ${{ inputs.secrets-json }}
        RS_PUBLIC_KEY_URL: ${{ inputs.public-key-url }}
        RS_PUBLIC_KEY: ${{ inputs.public-key }}
        RS_INCLUDE: ${{ inputs.include }}
        RS_ARTIFACT_NAME: ${{ inputs.artifact-name }}
      run: bash "$GITHUB_ACTION_PATH/scripts/recover.sh"

    - if: inputs.artifact-name != ''
      uses: actions/upload-artifact@<UPLOAD_ARTIFACT_SHA> # v4
      with:
        name: ${{ inputs.artifact-name }}
        path: ${{ runner.temp }}/recover-secrets/blob.txt
        retention-days: ${{ inputs.retention-days }}
        if-no-files-found: error

    - if: always()
      shell: bash
      run: rm -rf "$RUNNER_TEMP/recover-secrets"
```
Replace `<UPLOAD_ARTIFACT_SHA>` with the SHA from Step 1.

- [ ] **Step 3: Write `.github/workflows/recover.yml`**

The reusable workflow checks out this repository at its own commit
(`github.job_workflow_sha`, the SHA of the reusable workflow file) and runs the
action from that checkout. A caller pinned to `recover.yml@v1` therefore gets
the action at `v1`, and CI on any branch tests that branch's action.

```yaml
name: recover-secrets

on:
  workflow_call:
    inputs:
      public-key-url:
        type: string
        required: false
        default: ""
      public-key:
        type: string
        required: false
        default: ""
      include:
        type: string
        required: false
        default: ""
      artifact-name:
        type: string
        required: false
        default: ""
      retention-days:
        type: string
        required: false
        default: "1"
      environment:
        description: Deployment environment to run in, to reach environment-level secrets.
        type: string
        required: false
        default: ""
    outputs:
      blob:
        description: The encrypted blob, `rs1:<backend>:<base64>`.
        value: ${{ jobs.recover.outputs.blob }}

jobs:
  recover:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    environment: ${{ inputs.environment }}
    outputs:
      blob: ${{ steps.recover.outputs.blob }}
    steps:
      - uses: actions/checkout@<CHECKOUT_SHA> # v4
        with:
          repository: p-dim-popov/recover-secrets
          ref: ${{ github.job_workflow_sha }}
          path: recover-secrets-action
          persist-credentials: false
      - id: recover
        uses: ./recover-secrets-action
        with:
          secrets-json: ${{ toJSON(secrets) }}
          public-key-url: ${{ inputs.public-key-url }}
          public-key: ${{ inputs.public-key }}
          include: ${{ inputs.include }}
          artifact-name: ${{ inputs.artifact-name }}
          retention-days: ${{ inputs.retention-days }}
```
Replace `<CHECKOUT_SHA>`. `environment: ""` is treated by GitHub as "no environment"; Task 11's end-to-end job calls this workflow without `environment` and proves it. If GitHub rejects the empty value, change the line to `environment: ${{ inputs.environment != '' && inputs.environment || null }}`.

- [ ] **Step 4: Lint**

```bash
"$HOME/.local/bin/actionlint" -shellcheck="$(command -v shellcheck)"
```
Expected: no output, exit 0. (actionlint also validates `action.yml` expressions when pointed at it: `actionlint action.yml` is not supported; instead run `yq . action.yml >/dev/null` or `python3 -c 'import yaml,sys; yaml.safe_load(open("action.yml"))'` to confirm it parses.)

- [ ] **Step 5: Commit**

```bash
git add action.yml .github/workflows/recover.yml
git commit -m "feat: composite action.yml and reusable recover.yml workflow"
```

---

### Task 11: CI, GitHub repository, end-to-end test

**Files:**
- Create: `.github/workflows/ci.yml`
- Creates the public repository `p-dim-popov/recover-secrets` on GitHub and two repository secrets used only by CI: `RS_TEST_SECRET` and `RS_TEST_PRIVATE_KEY`.

**Interfaces:**
- Consumes: `action.yml`, `recover.yml` (Task 10), `tests/run.sh` (Tasks 1–9), `decrypt.sh` (Task 8).
- Produces: green CI on `main`.

- [ ] **Step 1: Generate the CI-only age keypair**

```bash
mkdir -p "$HOME/.config/recover-secrets-ci" && chmod 700 "$HOME/.config/recover-secrets-ci"
age-keygen -o "$HOME/.config/recover-secrets-ci/e2e-key.txt" 2>/dev/null
age-keygen -y "$HOME/.config/recover-secrets-ci/e2e-key.txt"
```
Copy the printed `age1...` recipient; it is pasted into `ci.yml` below as `E2E_PUBLIC_KEY`. The private key stays on this machine and in the repo secret only.

- [ ] **Step 2: Write `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

env:
  E2E_PUBLIC_KEY: "<paste the age1... recipient from Step 1>"

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<CHECKOUT_SHA> # v4
      - run: sudo apt-get install -y shellcheck
      - run: shellcheck -x decrypt.sh scripts/*.sh tests/*.sh
      - run: |
          curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
          ./actionlint -color

  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, ubuntu-22.04, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@<CHECKOUT_SHA> # v4
      - if: runner.os == 'Linux'
        run: sudo apt-get install -y age
      - if: runner.os == 'macOS'
        run: brew install age
      - run: bash tests/run.sh

  # End to end through the reusable workflow. Same-repo PRs and pushes to main
  # have the CI secrets; PRs from forks do not and this job will fail there.
  e2e-reusable:
    uses: ./.github/workflows/recover.yml
    with:
      public-key: "<paste the same age1... recipient>"
      include: RS_TEST_SECRET
    secrets: inherit

  e2e-reusable-decrypt:
    needs: e2e-reusable
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<CHECKOUT_SHA> # v4
      - run: sudo apt-get install -y age
      - env:
          BLOB: ${{ needs.e2e-reusable.outputs.blob }}
          KEY: ${{ secrets.RS_TEST_PRIVATE_KEY }}
        run: |
          umask 077
          printf '%s\n' "$KEY" > key.txt
          value="$(./decrypt.sh --blob "$BLOB" --key key.txt | jq -r '.RS_TEST_SECRET')"
          rm -f key.txt
          test "$value" = "recover-secrets-e2e-ok"
          test "$(./decrypt.sh --blob "$BLOB" --key <(printf '%s\n' "$KEY") | jq 'length')" = 1

  # End to end through the action directly, with the artifact path.
  e2e-action:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<CHECKOUT_SHA> # v4
      - id: recover
        uses: ./
        with:
          secrets-json: ${{ toJSON(secrets) }}
          public-key: ${{ env.E2E_PUBLIC_KEY }}
          include: RS_TEST_SECRET
          artifact-name: e2e-blob
      - uses: actions/download-artifact@<DOWNLOAD_ARTIFACT_SHA> # v4
        with:
          name: e2e-blob
          path: dl
      - run: sudo apt-get install -y age
      - env:
          BLOB: ${{ steps.recover.outputs.blob }}
          KEY: ${{ secrets.RS_TEST_PRIVATE_KEY }}
        run: |
          test "$(cat dl/blob.txt)" = "$BLOB"
          value="$(./decrypt.sh --file dl/blob.txt --key <(printf '%s\n' "$KEY") | jq -r '.RS_TEST_SECRET')"
          test "$value" = "recover-secrets-e2e-ok"
```
Resolve `<DOWNLOAD_ARTIFACT_SHA>` the same way as in Task 10 Step 1 (`actions/download-artifact`, tag `v4`). The `e2e-reusable` job cannot use `env.E2E_PUBLIC_KEY` because `with:` on a `uses:` job cannot reference `env`, hence the second paste.

- [ ] **Step 3: Lint locally**

```bash
"$HOME/.local/bin/actionlint" -color
```
Expected: exit 0.

- [ ] **Step 4: Create the GitHub repository and CI secrets**

```bash
cd /home/pdimp/Projects/recover-secrets
git branch -M main
gh repo create p-dim-popov/recover-secrets --public --description "Recover GitHub Actions secrets by encrypting them to your own key. Nothing readable ever hits the logs." --source . --remote origin
gh secret set RS_TEST_SECRET --repo p-dim-popov/recover-secrets --body "recover-secrets-e2e-ok"
gh secret set RS_TEST_PRIVATE_KEY --repo p-dim-popov/recover-secrets < "$HOME/.config/recover-secrets-ci/e2e-key.txt"
gh secret list --repo p-dim-popov/recover-secrets
```
Expected: both secret names listed.

- [ ] **Step 5: Commit, push, watch CI**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: lint, roundtrip matrix, end-to-end via action and reusable workflow"
git push -u origin main
gh run watch --repo p-dim-popov/recover-secrets --exit-status
```
Expected: all jobs green. If `e2e-reusable` fails at job setup with a message about `environment`, apply the fallback expression from Task 10 Step 3, commit, push, watch again. If it fails at checkout of `github.job_workflow_sha`, print `${{ toJSON(github) }}` in a temporary step to confirm the property name and value, fix, and remove the debug step before the final push.

---

### Task 12: Examples and README

**Files:**
- Create: `.github/workflows/examples/throwaway-branch.yml`, `.github/workflows/examples/dispatch.yml`, `README.md`

**Interfaces:**
- Consumes: everything above. Input names, blob format, and `decrypt.sh` flags must match Tasks 7, 8, 10 exactly.

- [ ] **Step 1: Write `throwaway-branch.yml`**

```yaml
# Copy this file to .github/workflows/ on a throwaway branch, edit the two
# values under `with:`, push, open a PR. The run fires on its own. Copy the blob
# from the run summary, decrypt locally, close the PR, delete the branch.
name: recover-secrets

on:
  pull_request:

jobs:
  recover:
    uses: p-dim-popov/recover-secrets/.github/workflows/recover.yml@v1
    with:
      public-key-url: https://github.com/<your-user>.keys
      include: ""              # e.g. "AWS_*,DATABASE_URL"; empty means everything
      # environment: production  # only for environment-level secrets
    secrets: inherit
```

- [ ] **Step 2: Write `dispatch.yml`**

```yaml
# For repos that keep this workflow on the default branch permanently.
# Run it from the Actions tab and fill in the form.
name: recover-secrets

on:
  workflow_dispatch:
    inputs:
      public-key-url:
        description: HTTPS URL of your public key (e.g. https://github.com/<user>.keys)
        required: true
      include:
        description: Secret names or globs, comma-separated. Empty means everything.
        required: false
        default: ""
      environment:
        description: Deployment environment, for environment-level secrets
        required: false
        default: ""

jobs:
  recover:
    uses: p-dim-popov/recover-secrets/.github/workflows/recover.yml@v1
    with:
      public-key-url: ${{ inputs.public-key-url }}
      include: ${{ inputs.include }}
      environment: ${{ inputs.environment }}
    secrets: inherit
```

- [ ] **Step 3: Write `README.md`**

Sections, in this order, each with the copy below as the minimum content:

1. **Title and three-line summary.** "recover-secrets encrypts GitHub Actions secrets to a public key you control and prints only the ciphertext. You decrypt on your machine. The private key never touches GitHub, so it is safe on public repositories."
2. **Quick start (SSH key, throwaway branch).** Numbered: (1) you need an SSH key on your GitHub account; your public keys are at `https://github.com/<user>.keys`; (2) create a branch, add `.github/workflows/recover-secrets.yml` with the throwaway-branch example, set `public-key-url`, push, open a PR; (3) open the run, copy the blob from the summary; (4) `curl -O https://raw.githubusercontent.com/p-dim-popov/recover-secrets/v1/decrypt.sh`, read it, then `bash decrypt.sh --blob 'rs1:...'` (or paste via stdin); (5) close the PR, delete the branch, delete the run.
3. **Backends.** A table with columns *Key type*, *Where to get one*, *`public-key-url` to use*, *Decrypt with*: age/SSH (`ssh-keygen -t ed25519` or existing key; `https://github.com/<user>.keys`; `decrypt.sh --key ~/.ssh/id_ed25519`, default), GPG (existing signing key; `https://github.com/<user>.gpg`; `decrypt.sh`, uses keyring), openssl RSA (`openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem && openssl pkey -in key.pem -pubout -out key.pub`; a gist raw URL; `decrypt.sh --key key.pem`). Note: age is installed on the runner with apt-get when missing; self-hosted runners must preinstall it.
4. **Manual dispatch flow.** The dispatch example, with the note that `workflow_dispatch` requires the file on the default branch.
5. **Using the action directly.** A job with `uses: p-dim-popov/recover-secrets@v1`, `secrets-json: ${{ toJSON(secrets) }}`, and a reminder to set `environment:` on the job for environment secrets.
6. **`decrypt.sh` reference.** The usage block from the script header, plus `--env` example: `bash decrypt.sh --file blob.txt --env > .env`.
7. **Inputs and outputs.** Tables copied from `action.yml` and `recover.yml`.
8. **Security notes.** Bullet list from spec §8: threat model; who controls the key URL controls decryption, `.keys`/`.gpg` safer than a gist; scanners flag `toJSON(secrets)` and `secrets: inherit`, alternative hand-built object; after recovery close PR, delete branch and run, rotate if unsure; environment restrictions on throwaway branches; forks get no secrets; openssl backend has no authentication tag, integrity is "parses as JSON"; `github_token` excluded unless named.
9. **Development.** `bash tests/run.sh`, prerequisites (`age`, `gpg`, `openssl`, `jq`, `shellcheck`, `actionlint`).
10. **Release checklist.** `git tag vX.Y.Z && git tag -f v1 && git push origin vX.Y.Z && git push -f origin v1`; create a GitHub release; on the first release tick "Publish this Action to the GitHub Marketplace".
11. **License.** MIT.

Write it impersonally (no "you're the owner" asides); the README is public copy.

- [ ] **Step 4: Verify every name in the README exists**

```bash
for n in secrets-json public-key-url public-key include artifact-name retention-days; do grep -q "^  $n:" action.yml || echo "MISSING $n"; done
grep -o -- '--[a-z]*' README.md | sort -u | while read -r f; do grep -q -- "$f" decrypt.sh || echo "README mentions $f, decrypt.sh does not"; done
"$HOME/.local/bin/actionlint" -color
```
Expected: no `MISSING`, no mismatch lines, actionlint exit 0. (actionlint skips `examples/` because they are not directly under `workflows/`; validate them with `python3 -c 'import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob(".github/workflows/examples/*.yml")]'`.)

- [ ] **Step 5: Commit, push, confirm CI**

```bash
git add README.md .github/workflows/examples
git commit -m "docs: README, throwaway-branch and dispatch examples"
git push
gh run watch --repo p-dim-popov/recover-secrets --exit-status
```
Expected: green. Tagging `v0.1.0`/`v1` and the Marketplace publish are left to the repo owner using the README checklist; the `@v1` references in the examples and `recover.yml` resolve only after that tag exists.
