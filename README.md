# recover-secrets

recover-secrets encrypts GitHub Actions secrets to a public key you control
and prints only the ciphertext. You decrypt on your machine. The private key
never touches GitHub, so it is safe on public repositories.

## Quick start (SSH key, throwaway branch)

1. You need an SSH key on your GitHub account. Your public keys are listed
   at `https://github.com/<user>.keys`.
2. Create a branch, add `.github/workflows/recover-secrets.yml` with the
   content of
   [`examples/throwaway-branch.yml`](.github/workflows/examples/throwaway-branch.yml),
   set `public-key-url` to your own URL, push, and open a pull request.
3. Open the workflow run and copy the blob from the run summary.
4. Fetch the decrypt script and read it before running it:
   ```bash
   curl -O https://raw.githubusercontent.com/p-dim-popov/recover-secrets/v1/decrypt.sh
   ```
   Then decrypt:
   ```bash
   bash decrypt.sh --blob 'rs1:...'
   ```
   Or paste the blob on stdin and press Ctrl-D.
5. Close the pull request, delete the branch, and delete the workflow run.

## Backends

| Key type | Where to get one | `public-key-url` to use | Decrypt with |
|---|---|---|---|
| age / SSH | `ssh-keygen -t ed25519`, or an existing key | `https://github.com/<user>.keys` | `decrypt.sh --key ~/.ssh/id_ed25519` (the default) |
| GPG | An existing signing key | `https://github.com/<user>.gpg` | `decrypt.sh` (uses your keyring) |
| openssl RSA | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem && openssl pkey -in key.pem -pubout -out key.pub` | A gist raw URL | `decrypt.sh --key key.pem` |

`age` is installed on GitHub-hosted runners with `apt-get` when it is
missing. Self-hosted runners must preinstall it.

## Manual dispatch flow

For repositories that keep the workflow file on the default branch
permanently, use
[`examples/dispatch.yml`](.github/workflows/examples/dispatch.yml):

```yaml
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

Run it from the Actions tab and fill in the form. `workflow_dispatch` only
triggers a run when the workflow file exists on the default branch, so this
flow needs the file committed there first.

## Using the action directly

The reusable workflow calls the action with `toJSON(secrets)`. Callers that
need more control can call the action directly instead:

```yaml
jobs:
  recover:
    runs-on: ubuntu-latest
    environment: production   # only if the secrets are environment-level
    steps:
      - id: recover
        uses: p-dim-popov/recover-secrets@v1
        with:
          secrets-json: ${{ toJSON(secrets) }}
          public-key-url: https://github.com/<user>.keys
          include: "AWS_*,DATABASE_URL"
      - run: echo "${{ steps.recover.outputs.blob }}"
```

Set `environment:` on the job when the secrets being recovered are
environment-level secrets.

## `decrypt.sh` reference

```
Usage: decrypt.sh [--blob <string> | --file <path>] [--key <path>] [--env]
  no --blob/--file  read the blob from stdin (paste, then Ctrl-D)
  --key <path>      private key: SSH key or age identity (age), PEM (openssl);
                    ignored for gpg, which uses your keyring
  --env             print NAME='value' lines instead of JSON
```

`-h` / `--help` prints this text.

`--env` mode prints shell-sourceable `NAME='value'` lines instead of JSON.
Secret names must be valid shell identifiers in this mode; the script
refuses to emit anything else and falls back to an error asking for JSON
output instead. Example:

```bash
bash decrypt.sh --file blob.txt --env > .env
```

## Inputs and outputs

### Action (`p-dim-popov/recover-secrets@v1`)

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `secrets-json` | yes | none | JSON object of the secrets to recover. Normally the result of calling `toJSON` on the workflow's `secrets` context. A hand-built object such as `{"FOO": "<value of secrets.FOO>"}` also works. |
| `public-key-url` | no | `""` | HTTPS URL of the public key to encrypt to. Accepts an SSH keys list such as `https://github.com/<user>.keys`, a GPG key such as `https://github.com/<user>.gpg`, an age1 recipient, or a PEM RSA public key. Use this or `public-key`. |
| `public-key` | no | `""` | The public key text itself, as an alternative to `public-key-url`. |
| `include` | no | `""` | Comma-separated secret names or globs (`AWS_*`). Empty means every secret except `github_token`, which is only included when named exactly. |
| `artifact-name` | no | `""` | If set, also upload the encrypted blob as an artifact with this name. |
| `retention-days` | no | `"1"` | Retention for the artifact, in days. |

**Outputs**

| Name | Description |
|---|---|
| `blob` | The encrypted blob, `rs1:<backend>:<base64>`. Feed it to `decrypt.sh`. |

### Reusable workflow (`p-dim-popov/recover-secrets/.github/workflows/recover.yml@v1`)

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `public-key-url` | no | `""` | Same as the action's `public-key-url`. |
| `public-key` | no | `""` | Same as the action's `public-key`. |
| `include` | no | `""` | Same as the action's `include`. |
| `artifact-name` | no | `""` | Same as the action's `artifact-name`. |
| `retention-days` | no | `"1"` | Same as the action's `retention-days`. |
| `environment` | no | `""` | Deployment environment to run in, to reach environment-level secrets. |

**Outputs**

| Name | Description |
|---|---|
| `blob` | The encrypted blob, `rs1:<backend>:<base64>`. |

## Security notes

- Threat model: anyone with read access to the repository can see the
  encrypted blob. It must be computationally useless without the private
  key. That is the only property the action promises.
- Whoever controls the key URL controls who can decrypt. `.keys` and `.gpg`
  URLs on `github.com/<user>` are safer than a gist, because only the
  account holder can change them.
- `toJSON(secrets)` and `secrets: inherit` are flagged by security scanners
  (Datadog and others) as overprovisioning. This is expected. Callers who
  cannot accept it can pass a hand-built object instead, such as
  `{"FOO": "${{ secrets.FOO }}"}`.
- After recovery: close the pull request, delete the branch, delete the
  workflow run, and rotate the secret if compromise is suspected.
- Environment-level secrets require the job to run in that environment. The
  reusable workflow's `environment` input does this. Environments
  restricted to protected branches reject a throwaway branch; temporarily
  allow it, or use the dispatch flow from the default branch instead.
- `workflow_dispatch` only works when the workflow file exists on the
  default branch, per GitHub's documentation. This is why the
  throwaway-branch flow uses `on: pull_request`.
- Same-repository branches get secrets on `pull_request`. Forked pull
  requests do not.
- The openssl backend has no authentication tag: the openssl CLI has no
  AES-GCM mode. Confidentiality is the goal; integrity on decrypt means the
  plaintext parses as a JSON object.
- `github_token` is excluded from the secrets unless `include` names it
  exactly.

## Development

Prerequisites: `age`, `gpg`, `openssl`, `jq`, `shellcheck`, `actionlint`.

Run the test suite:

```bash
bash tests/run.sh
```

## Release checklist

```bash
git tag vX.Y.Z && git tag -f v1 && git push origin vX.Y.Z && git push -f origin v1
```

Then create a GitHub release from the new tag. On the first release, tick
"Publish this Action to the GitHub Marketplace".

## License

MIT. See [LICENSE](LICENSE).
