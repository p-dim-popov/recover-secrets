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
