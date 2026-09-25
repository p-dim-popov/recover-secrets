#!/usr/bin/env bash
# recover-secrets. Built by `make` from source/. Edit the files there, not this one.
# Encrypts GitHub Actions secrets to your public key and prints the blob.
# Inputs are environment variables: RS_SECRETS_JSON, RS_PUBLIC_KEY_URL or
# RS_PUBLIC_KEY, RS_INCLUDE, RS_ARTIFACT_NAME. See README.md.
set -euo pipefail
umask 077
RS_SRC="$(mktemp -d)"
trap 'rm -rf -- "$RS_SRC"' EXIT

cat > "$RS_SRC/detect.sh" <<'RS_SOURCE_EOF'
#!/usr/bin/env bash
# Sourced by source/main.sh. decrypt.sh carries a byte-identical copy of the
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
RS_SOURCE_EOF

cat > "$RS_SRC/filter.sh" <<'RS_SOURCE_EOF'
#!/usr/bin/env bash
# Sourced by source/main.sh.

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
RS_SOURCE_EOF

cat > "$RS_SRC/encrypt-age.sh" <<'RS_SOURCE_EOF'
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
  grep -E "$SUPPORTED" "$src" > "$dst" 2>/dev/null || true
  skipped="$(grep -vE "$SUPPORTED" "$src" 2>/dev/null | grep -cvE "$IGNORED" 2>/dev/null || true)"
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
RS_SOURCE_EOF

cat > "$RS_SRC/encrypt-gpg.sh" <<'RS_SOURCE_EOF'
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

# import_keys <pub>: import into the throwaway keyring, then print one line per
# primary key: "ok <fpr>" if usable for encryption, "skip <fpr>" otherwise.
# Usable means capital E in the capabilities field (12, E for the whole key
# including subkeys) and a validity (field 2) other than e(xpired), r(evoked)
# or i(nvalid).
import_keys() {
  gpg --batch --quiet --import "$1" >/dev/null 2>&1 || return 1
  gpg --batch --list-keys --with-colons 2>/dev/null | awk -F: '
    $1 == "pub" { use = ($12 ~ /E/ && $2 !~ /^[eri]$/); want = 1; next }
    $1 == "fpr" && want { print (use ? "ok " : "skip ") $10; want = 0; next }
    { want = 0 }'
}

case "$cmd" in
  validate)
    [[ -n "$pub" ]] || exit 64
    keys="$(import_keys "$pub")" || exit 1
    grep -q '^ok ' <<<"$keys" 2>/dev/null || exit 1
    skipped="$(grep -c '^skip ' <<<"$keys" 2>/dev/null || true)"
    if [[ "$skipped" -gt 0 ]]; then
      echo "::warning::Skipped $skipped unusable GPG key(s) (no encryption capability, expired or revoked)" >&2
    fi
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    keys="$(import_keys "$pub")" || exit 1
    grep -q '^ok ' <<<"$keys" 2>/dev/null || exit 1
    # One --recipient per usable fingerprint. --recipient-file is not used: it
    # silently drops every key in the file except the first.
    recipients=()
    while IFS= read -r fpr; do
      [[ -n "$fpr" ]] && recipients+=("--recipient" "$fpr")
    done < <(sed -n 's/^ok //p' <<<"$keys" 2>/dev/null)
    gpg --batch --quiet --trust-model always ${recipients[@]+"${recipients[@]}"} \
      --encrypt --output "$out" "$plaintext" 2>/dev/null
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
RS_SOURCE_EOF

cat > "$RS_SRC/encrypt-openssl.sh" <<'RS_SOURCE_EOF'
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
    grep -q -- '-----BEGIN .*PRIVATE KEY-----' "$pub" 2>/dev/null && exit 1
    openssl rsa -pubin -in "$pub" -noout >/dev/null 2>&1 || exit 1
    bits="$(openssl rsa -pubin -in "$pub" -noout -text 2>/dev/null \
            | sed -n 's/^Public-Key: (\([0-9]*\) bit)$/\1/p')"
    [[ -n "$bits" && "$bits" -ge 2048 ]] || exit 1
    ;;
  encrypt)
    plaintext="${3:-}"; out="${4:-}"
    [[ -n "$pub" && -n "$plaintext" && -n "$out" ]] || exit 64
    work="$(mktemp -d)"
    openssl rand -hex 32 > "$work/pass" 2>/dev/null
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt \
      -pass "file:$work/pass" -in "$plaintext" -out "$work/data" 2>/dev/null
    openssl pkeyutl -encrypt -pubin -inkey "$pub" \
      -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
      -in "$work/pass" -out "$work/key" 2>/dev/null
    # printf, not jq --arg: an argument that long fails above roughly 98 KB of
    # plaintext. base64 needs no JSON escaping. printf is a bash builtin, so
    # the data never passes through exec arguments.
    k="$(base64 < "$work/key" 2>/dev/null | tr -d '\n')"
    d="$(base64 < "$work/data" 2>/dev/null | tr -d '\n')"
    printf '{"k":"%s","d":"%s"}\n' "$k" "$d" > "$out"
    ;;
  *)
    echo "usage: $0 validate <pub> | encrypt <pub> <plaintext> <out>" >&2
    exit 64
    ;;
esac
RS_SOURCE_EOF

cat > "$RS_SRC/main.sh" <<'RS_SOURCE_EOF'
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
# shellcheck disable=SC2016  # literal GitHub Actions syntax; must not be bash-expanded
[[ -n "$RS_SECRETS_JSON" ]] || die 'secrets-json is required (pass ${{ toJSON(secrets) }})'
set +e
FILTERED="$(filter_secrets "$RS_SECRETS_JSON" "$RS_INCLUDE")"
rc=$?
set -e
case $rc in
  0) ;;
  2)
    # shellcheck disable=SC2016  # literal GitHub Actions syntax; must not be bash-expanded
    die 'secrets-json must be a JSON object (pass ${{ toJSON(secrets) }})' ;;
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
RS_SOURCE_EOF

bash "$RS_SRC/main.sh"
