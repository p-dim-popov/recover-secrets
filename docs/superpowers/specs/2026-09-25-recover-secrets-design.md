# recover-secrets — Design

Date: 2026-09-25
Status: approved design, pending implementation plan

## 1. Problem and goal

GitHub Actions secrets are write-only. The usual workaround (print the value
through some encoding to dodge log masking) leaves plaintext in run history,
and GitHub now masks common encodings anyway.

`recover-secrets` is a public composite GitHub Action, plus a reusable
workflow that wraps it, which encrypts selected Actions secrets to a public key
the caller controls and emits only ciphertext. The caller decrypts locally with
a bundled `decrypt.sh`. The private key never touches GitHub, so the flow is
safe even on public repositories.

**Who it is for:** a repo admin who lost the original value of a secret and
would rather recover it than rotate it.

**Success:** open a throwaway PR (or run a dispatch), copy one string from the
run summary, run `decrypt.sh`, see plaintext. Nothing readable ever appears in
logs, summaries, outputs, artifacts, or on the runner's disk after the step.
CI proves the roundtrip and the absence of leaks for every backend.

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Action type | Composite (bash) | Every line that touches secrets is auditable on GitHub without a build step. |
| Encryption backends | age, gpg, openssl — all three | Zero-setup path for SSH keys (age) and GPG keys (gpg); openssl for "no extra tools". |
| Backend selection | Auto-detected from key format and blob header | Formats don't overlap; no `method` input. |
| Key delivery | `public-key-url` (https only) or inline `public-key` | Gist/`github.com/<user>.keys` or paste into a dispatch field. |
| Secret selection | `secrets-json: ${{ toJSON(secrets) }}` + `include` globs | Bulk by default, cherry-pick without editing the workflow. |
| `github_token` | Excluded unless named in `include` | Ephemeral, noise. |
| Output channels | Log group + step summary + `blob` output always; artifact optional | Summary is the easiest copy target; artifact for large dumps or `gh run download`. |
| Blob format | `rs1:<backend>:<base64, single line>` | One string to paste; explicit backend and version. |
| Input naming | kebab-case | Matches GitHub's own actions (`fetch-depth`, `retention-days`). |
| Primary usage flow | Throwaway branch/PR with `on: pull_request` | `workflow_dispatch` requires the file on the default branch (GitHub docs). |
| Reusable workflow | Yes, `.github/workflows/recover.yml` | Shorter caller, whole job is our code, `environment` input reaches environment secrets. |
| Repo / license | `p-dim-popov/recover-secrets`, MIT | — |
| Versioning | Semver tags + moving `v1` | Marketplace convention. |

Rejected: JavaScript action (compiled `dist/` is not auditable by eye; age and
gpg would still be shell-outs). Docker action (slow pull, Linux only, another
image to trust). A `method` input (detection is unambiguous).

## 3. Repository layout

```
recover-secrets/
├── action.yml                        # inputs, outputs, composite steps, branding
├── decrypt.sh                        # local helper; self-contained; the one file users download
├── scripts/
│   ├── recover.sh                    # driver: fetch key, validate, filter, encrypt, emit
│   ├── detect.sh                     # detect_key_format / detect_blob_format (sourced)
│   ├── encrypt-age.sh
│   ├── encrypt-gpg.sh
│   └── encrypt-openssl.sh
├── tests/
│   ├── roundtrip.sh                  # encrypt with each backend, decrypt, diff, leak-check
│   └── fixtures/                     # secrets JSON fixtures; keypairs generated at test time
├── .github/workflows/
│   ├── ci.yml                        # shellcheck + roundtrip matrix + calls recover.yml locally
│   ├── recover.yml                   # reusable: on workflow_call, wraps the action
│   └── examples/                     # not run by GitHub (not directly under workflows/)
│       ├── throwaway-branch.yml      # on: pull_request, uses the reusable workflow
│       └── dispatch.yml              # on: workflow_dispatch with include/key inputs
├── docs/superpowers/specs/           # this document
├── README.md
└── LICENSE
```

## 4. Interfaces

### 4.1 `action.yml`

Inputs:

| Input | Required | Default | Description |
|---|---|---|---|
| `secrets-json` | yes | — | JSON object of secrets, normally `${{ toJSON(secrets) }}`. |
| `public-key-url` | one of the two | — | HTTPS URL of the public key (PEM, PGP armor, `age1`, or SSH `.keys` list). |
| `public-key` | one of the two | — | The public key text itself. |
| `include` | no | `` (all) | Comma-separated names or globs (`AWS_*`). Empty means every secret except `github_token`. |
| `artifact-name` | no | `` | If set, upload the blob as an artifact with this name. |
| `retention-days` | no | `1` | Artifact retention, passed to `actions/upload-artifact`. |

Outputs: `blob` — the `rs1:...` string.

Steps:

1. `run: bash "$GITHUB_ACTION_PATH/scripts/recover.sh"` with every input mapped
   into `env:` (`RS_SECRETS_JSON`, `RS_PUBLIC_KEY_URL`, `RS_PUBLIC_KEY`,
   `RS_INCLUDE`, `RS_ARTIFACT_NAME`). Inputs are never interpolated into the
   script body.
2. `uses: actions/upload-artifact@v4`, `if: inputs.artifact-name != ''`,
   uploading `$RUNNER_TEMP/recover-secrets/blob.txt` with `retention-days`.
3. `run:` cleanup of `$RUNNER_TEMP/recover-secrets`, `if: always()`.

`branding`: icon `lock`, color `gray-dark`. Every input description is written
for the Marketplace page.

### 4.2 `recover.yml` (reusable workflow)

- `on: workflow_call`. Inputs mirror the action minus `secrets-json`, plus
  `environment` (optional string). Output `blob`.
- One job, `runs-on: ubuntu-latest`, `permissions: {}`,
  `environment: ${{ inputs.environment }}`.
- Calls `uses: p-dim-popov/recover-secrets@v1` (not `./`) with
  `secrets-json: ${{ toJSON(secrets) }}`, so a caller pinned to
  `recover.yml@v1` needs no checkout and gets the matching action. Tag bumps
  move both together.
- Callers pass `secrets: inherit`. This is the only way for the called workflow
  to see all secrets and is where "overprovisioned secrets" scanners will
  complain; the README says so.

### 4.3 Backend script contract

```
scripts/encrypt-<backend>.sh <pubkey-file> <plaintext-file> <out-file>
```

No stdout. Non-zero exit on any failure. Tool stderr is suppressed by the
driver (gpg and openssl echo input fragments).

### 4.4 `detect.sh`

Two functions, sourced by `recover.sh`; `decrypt.sh` carries an identical copy
(it must be self-contained). CI asserts both copies agree on the same fixtures.

- `detect_key_format <file>` → `openssl` | `gpg` | `age` | error.
  - `-----BEGIN PUBLIC KEY-----` or `-----BEGIN RSA PUBLIC KEY-----` → `openssl`
  - `-----BEGIN PGP PUBLIC KEY BLOCK-----` → `gpg`
  - any line starting `age1`, `ssh-ed25519 `, `ssh-rsa ` → `age`
- `detect_blob_format <string>` → parses `rs1:<backend>:` prefix.

### 4.5 Blob format

```
rs1:<backend>:<base64 of backend output, single line, no wrapping>
```

- `age`: raw binary output of `age -R recipients -o out plaintext`.
- `gpg`: binary (unarmored) output of `gpg --encrypt`.
- `openssl`: JSON `{"k":"<base64 RSA-OAEP-wrapped passphrase>","d":"<base64 openssl enc output>"}`.

`rs1` is the envelope version. A future incompatible change bumps it;
`decrypt.sh` refuses unknown versions with a message naming its own version.

### 4.6 `decrypt.sh`

```
decrypt.sh [--blob <string> | --file <path>] [--key <path>] [--env]
```

- No `--blob`/`--file`: read stdin (paste, Ctrl-D). Whitespace and newlines
  inside the pasted blob are stripped. `--file` works on a downloaded artifact.
- `--key`: private key path. Ignored for gpg (keyring). Age default: first
  existing of `~/.ssh/id_ed25519`, `~/.ssh/id_rsa`, `~/.config/age/keys.txt`.
  No default for openssl.
- Output: `jq .` pretty JSON on stdout. `--env`: `NAME='value'` lines with
  inner single quotes escaped, safe to `source`.
- Passphrase prompts for SSH keys or encrypted PEMs come from age/openssl
  themselves; the script does not handle passphrases.
- Dependencies: jq plus whichever of age/gpg/openssl the blob names. Missing
  tool → message with the platform install hint.
- Distribution: `curl -O` the tagged raw URL, read it, run it. README says not
  to pipe curl into bash.

## 5. Data flow (`scripts/recover.sh`)

1. `set -euo pipefail`; `umask 077`; `WORK=$(mktemp -d)`; `trap cleanup EXIT`.
   `cleanup` shreds every file under `$WORK` (`shred -u`, falling back to
   `rm -rf`) then removes the dir. Runs on success, failure, and cancel.
2. Read all inputs from `RS_*` environment variables.
3. Obtain key: `RS_PUBLIC_KEY` wins; else
   `curl --proto '=https' --fail --silent --show-error --location --max-filesize 65536 --max-time 20 "$RS_PUBLIC_KEY_URL"`.
   Exactly one of the two must be set.
4. `detect_key_format`, then backend-specific validation (section 6). Any
   failure aborts before `RS_SECRETS_JSON` is read.
5. Parse `RS_SECRETS_JSON` with jq: must be a JSON object. Remove
   `github_token` unless `include` names it exactly. Translate each
   comma-separated `include` entry into an anchored regex (`*` → `.*`, `?` →
   `.`, everything else escaped) and keep keys matching any. Zero remaining
   keys is an error.
6. Write the filtered object to `$WORK/plaintext.json`; run the backend; wrap
   as `rs1:<backend>:$(base64 -w0 out)`.
7. Emit: `blob=<...>` to `$GITHUB_OUTPUT`; a collapsed `::group::` in the log;
   a fenced code block in `$GITHUB_STEP_SUMMARY`; and if `RS_ARTIFACT_NAME` is
   set, `$RUNNER_TEMP/recover-secrets/blob.txt` for the upload step.

The driver prints nothing it did not generate itself.

## 6. Backends

### age

- Runner: if `age` is not on PATH, `sudo apt-get install -y age` (Linux) or
  `brew install age` (macOS). Self-hosted runners must preinstall it (README).
- Recipients: keep lines starting `age1`, `ssh-ed25519`, `ssh-rsa`. Warn and
  skip anything else (e.g. `ecdsa-sha2-*`, unsupported by age). Fail if none
  remain. `github.com/<user>.keys` works directly.
- Encrypt: `age -R "$recipients" -o "$out" "$plaintext"`. Validation is age
  itself rejecting bad recipients, run once on an empty file before secrets
  are read.

### gpg

- `GNUPGHOME="$WORK/gnupg"` so the runner keyring is never touched.
- Validate: `gpg --batch --show-keys "$pub"` succeeds and lists at least one key.
- Encrypt: `gpg --batch --trust-model always --recipient-file "$pub" --encrypt --output "$out" "$plaintext"`.
  Binary output. All keys in the file become recipients, which is what
  `github.com/<user>.gpg` needs.

### openssl

- Validate: `openssl pkey -pubin -in "$pub" -noout` succeeds, key type is RSA,
  modulus ≥ 2048 bits. EC keys are rejected (cannot encrypt).
- Passphrase: `openssl rand -hex 32 > "$WORK/pass"`.
- Data: `openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass file:"$WORK/pass" -in "$plaintext" -out "$WORK/data"`.
- Wrap: `openssl pkeyutl -encrypt -pubin -inkey "$pub" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 -in "$WORK/pass" -out "$WORK/key"`.
- Envelope: `jq -n --arg k "$(base64 -w0 key)" --arg d "$(base64 -w0 data)" '{k:$k,d:$d}'`.
- No authentication tag: the openssl CLI cannot do AES-GCM. Confidentiality is
  the goal; integrity on decrypt is "the plaintext parses as a JSON object".
  The README states this.

## 7. Error handling

- Every failure: non-zero exit, one `::error::` line on stderr naming the input
  at fault and what was expected. Never the value.
- Both key inputs set or neither: error before any network call.
- Key fetch failure: HTTP status only, never the body.
- Invalid/unsupported key: detected format and tool exit code; tool stderr
  suppressed.
- `secrets-json` not an object, or `include` matches nothing: error with the
  *count* of available names, never the names.
- Backend failure after plaintext exists: trap shreds; output is tool name and
  exit code only.
- `decrypt.sh`: unknown `rs` version or backend names the script's own
  version; missing tool prints an install hint; plaintext that is not a JSON
  object is reported as a failed decrypt (wrong key or corrupted blob).

## 8. Security notes (for the README, binding on the implementation)

- Threat model: anyone with read access to the repo can see the blob. It must
  be computationally useless without the private key. That is the only
  property the action promises.
- Whoever controls the key URL controls who can decrypt. `github.com/<user>.keys`
  and `.gpg` are safer than a gist because only the account holder can change
  them.
- `toJSON(secrets)` and `secrets: inherit` are flagged by scanners (Datadog
  and others) as overprovisioning. Expected. Callers who cannot accept it can
  pass a hand-built object like `{"FOO": "${{ secrets.FOO }}"}`.
- After recovery: close the PR, delete the branch, delete the workflow run,
  rotate any secret if compromise is suspected.
- Environment-level secrets: the job must run in that environment. The
  reusable workflow's `environment` input does this. Environments restricted to
  protected branches will reject a throwaway branch; temporarily allow it or
  use the dispatch flow from the default branch.
- `workflow_dispatch` only works when the workflow file exists on the default
  branch (GitHub docs), hence the throwaway-branch flow uses `on: pull_request`
  (or `on: push`). Same-repo branches get secrets on `pull_request`; forks do
  not.
- The action needs no token: `permissions: {}` in the reusable workflow.

## 9. Testing

### `tests/roundtrip.sh` (runs locally and in CI, no GitHub context needed)

- Generates throwaway keypairs at test time: `age-keygen`, `ssh-keygen -t
  ed25519`, `ssh-keygen -t rsa`, `gpg --quick-gen-key` in a temp home,
  `openssl genpkey` RSA 2048 and 4096.
- Fixture secrets JSON with awkward values: newlines, single and double quotes,
  unicode, `=`, leading/trailing whitespace, a 50 KB value, and `github_token`.
- For each key: fake `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `RUNNER_TEMP`;
  run `recover.sh`; feed the blob to `decrypt.sh` via `--blob`, `--file`, and
  stdin; diff against the fixture. Assert `--env` output round-trips through
  `source`.
- Negative cases: both key inputs, neither, non-https URL, key over 64 KB, EC
  key for openssl, RSA 1024, ecdsa-only SSH list, `include` with no match,
  malformed `secrets-json`, blob with unknown `rs` version.
- `github_token` absent by default, present when named in `include`.
- Leak check: after each run, grep the fake log, summary, output file, artifact
  dir, and `$WORK` path for every fixture value and its base64. Any hit fails.
- Detection parity: same key and blob fixtures through `detect.sh` and
  `decrypt.sh`'s embedded copy; results must match.

### `ci.yml`

- `shellcheck` on every `.sh` file and on `run:` blocks via `actionlint`.
- Roundtrip matrix: `ubuntu-latest`, `ubuntu-22.04` (different age/openssl
  versions), `macos-latest` for the decrypt side.
- End-to-end: a job calling `./.github/workflows/recover.yml` with a test
  public key and a dummy repo secret, followed by a job that decrypts the
  output using a private test key stored as a second repo secret and asserts
  the dummy value. These test keys are for this repo's CI only.

## 10. Documentation and release

README order: what it does (three lines) → quick start with the
throwaway-branch flow and an SSH key → backend table (age / gpg / openssl:
where to get a key, what URL to use, how to decrypt) → manual-dispatch flow →
`decrypt.sh` reference → inputs and outputs → security notes (section 8) →
release checklist.

Release: tag `vX.Y.Z`, force-move `v1`, GitHub release with notes. Marketplace
listing is a checkbox on the first release, done manually by the repo owner.

## 11. Out of scope

- Windows runners.
- Authenticated encryption for the openssl backend.
- Writing secrets to files or re-uploading them anywhere.
- Passphrase handling inside `decrypt.sh`.
- Any key format beyond PEM RSA, PGP armor, `age1`, `ssh-ed25519`, `ssh-rsa`.
