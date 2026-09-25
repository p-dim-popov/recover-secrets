# recover-secrets

recover-secrets encrypts GitHub Actions secrets to a public key you control.
It prints only the encrypted blob. You decrypt the blob on your machine. The
private key never touches GitHub. This makes the action safe to use on
public repositories.

## Quick start (SSH key, throwaway branch)

1. If you do not have an SSH key on your GitHub account, add one. Find
   your public keys at `https://github.com/<user>.keys`.
2. Create a branch.
3. Add `.github/workflows/recover-secrets.yml` with the content of
   [`examples/throwaway-branch.yml`](.github/workflows/examples/throwaway-branch.yml).
4. Set `public-key-url` to your own URL.
5. Push the branch and open a pull request.
6. Open the workflow run and copy the blob from the run summary.
7. Fetch the decrypt script and read it before you run it:
   ```bash
   curl -O https://raw.githubusercontent.com/p-dim-popov/recover-secrets/v1/decrypt.sh
   ```
8. Decrypt the blob:
   ```bash
   bash decrypt.sh --blob 'rs1:...'
   ```
   You can also paste the blob on stdin and press Ctrl-D.
9. Close the pull request, delete the branch, and delete the workflow run.

## Backends

| Key type | Where to get one | `public-key-url` to use | Decrypt with |
|---|---|---|---|
| age / SSH | `ssh-keygen -t ed25519`, or an existing key | `https://github.com/<user>.keys` | `decrypt.sh --key ~/.ssh/id_ed25519` (the default) |
| GPG | A GPG key with an encryption subkey | `https://github.com/<user>.gpg` | `decrypt.sh` (uses your keyring) |
| openssl RSA | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out key.pem && openssl pkey -in key.pem -pubout -out key.pub` | A gist raw URL | `decrypt.sh --key key.pem` |

GitHub-hosted runners install `age` with `apt-get` when it is missing.
Self-hosted runners must preinstall it.

## Manual dispatch flow

If your repository keeps the workflow file on the default branch
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

Run it from the Actions tab and fill in the form. `workflow_dispatch`
triggers a run only when the workflow file exists on the default branch.
Commit the workflow file to the default branch before you use this flow.

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
      - env:
          BLOB: ${{ steps.recover.outputs.blob }}
        run: echo "$BLOB"
```

Set `environment:` on the job if you recover environment-level secrets.

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
Secret names must be valid shell identifiers in this mode. The script also
refuses names that change how a shell or the dynamic loader behaves
(`PATH`, `IFS`, `HOME`, `BASH_ENV`, `ENV`, `PROMPT_COMMAND`, `PS1` to `PS4`,
`SHELLOPTS`, `BASHOPTS`, `CDPATH`, `LD_*`, `DYLD_*`). In both cases the
script prints nothing and exits with an error that asks for JSON output
instead. Only decrypt blobs copied from your own workflow run. No backend
authenticates who produced a blob. Example:

```bash
(umask 077; bash decrypt.sh --file blob.txt --env > .env)
```

## Inputs and outputs

### Action (`p-dim-popov/recover-secrets@v1`)

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `secrets-json` | yes | none | JSON object of the secrets to recover. It is usually the output of `toJSON` on the workflow's `secrets` context. A hand-built object such as `{"FOO": ${{ toJSON(secrets.FOO) }}}` also works. |
| `public-key-url` | no | `""` | HTTPS URL of the public key to encrypt to. Accepts an SSH keys list such as `https://github.com/<user>.keys`, a GPG key such as `https://github.com/<user>.gpg`, an age1 recipient, or a PEM RSA public key. Use this or `public-key`. |
| `public-key` | no | `""` | The public key text, as an alternative to `public-key-url`. |
| `include` | no | `""` | Comma-separated secret names or globs (`AWS_*`). Empty means every secret except `github_token`, which is only included when named exactly. |
| `artifact-name` | no | `""` | If set, the action also uploads the encrypted blob as an artifact with this name. |
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

## Limits

- The secrets JSON reaches the script through one environment variable.
  On Linux, a single environment string is capped at 128 KiB. Secrets
  JSON over about 128 KiB fails with the error "Argument list too long".
- GitHub caps step summaries and job outputs at 1 MiB each.

## Security notes

- Under this threat model, anyone with read access to the repository can
  see the encrypted blob. The blob must be computationally useless without
  the private key. This is the only property the action promises.
- Whoever controls the key URL controls who can decrypt the blob. `.keys`
  and `.gpg` URLs on `github.com/<user>` are safer than a gist, because
  only the account holder can change them.
- Security scanners such as Datadog flag `toJSON(secrets)` and
  `secrets: inherit` as overprovisioning. This is expected. Callers who
  cannot accept it can pass a hand-built object instead, such as
  `{"FOO": ${{ toJSON(secrets.FOO) }}}`. `toJSON` quotes and escapes the
  value, so multi-line values and quotes stay valid JSON.
- Secret names are visible in the run log to anyone with read access to
  the repository. The runner prints each step's `with:` and `env:` inputs
  in the step header, so every name in `secrets-json` appears there. The
  values in that header rely on GitHub's secret masking. The action itself
  never writes a secret name or value. A hand-built `secrets-json` limits
  which names appear.
- After recovery, close the pull request, delete the branch, delete the
  workflow run, and rotate the secret if you suspect compromise.
- Environment-level secrets require the job to run in that environment. The
  reusable workflow's `environment` input does this. Environments
  restricted to protected branches reject a throwaway branch. Temporarily
  allow the branch, or use the dispatch flow from the default branch
  instead.
- `workflow_dispatch` runs only when the workflow file exists on the
  default branch, as GitHub's documentation states. This is why the
  throwaway-branch flow uses `on: pull_request`.
- Same-repository branches get secrets on `pull_request`. Forked pull
  requests do not.
- The openssl backend has no authentication tag. The openssl CLI has no
  AES-GCM mode. Confidentiality is the goal. Integrity on decrypt means
  that the plaintext parses as a JSON object.
- The action excludes `github_token` from the secrets unless `include`
  names it exactly.
- Only decrypt blobs copied from your own workflow run. No backend
  authenticates who produced a blob. Anyone who knows the public key can
  encrypt a blob to it.

## Development

This project requires `age`, `gpg`, `openssl`, `jq`, `shellcheck`, and
`actionlint`.

Run the test suite:

```bash
bash tests/run.sh
```

## Release checklist

1. Run:
   ```bash
   git tag vX.Y.Z && git tag -f v1 && git push origin vX.Y.Z && git push -f origin v1
   ```
2. Create a GitHub release from the new tag.
3. On the first release, tick "Publish this Action to the GitHub
   Marketplace".

## License

MIT. See [LICENSE](LICENSE).
