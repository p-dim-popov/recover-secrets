// Every command and snippet on the page. Keep these in step with README.md.

export const repoUrl = 'https://github.com/p-dim-popov/recover-secrets'
export const marketplaceUrl = 'https://github.com/marketplace/actions/recover-secrets'
export const readmeUrl = `${repoUrl}#readme`
export const writeupUrl =
  'https://dev.to/pdimpopov/getting-a-github-actions-secret-back-without-leaving-it-in-the-log-2ap9'
export const licenseUrl = `${repoUrl}/blob/main/LICENSE`

const expr = (s: string) => '${{ ' + s + ' }}'

export const workflowAction = `name: recover-secrets

on:
  pull_request:

jobs:
  recover:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: p-dim-popov/recover-secrets@v1
        with:
          secrets-json: ${expr('toJSON(secrets)')}
          public-key-url: https://github.com/<your-user>.keys
`

export const workflowRun = `# For organizations that block third-party actions.
name: recover-secrets

on:
  pull_request:

jobs:
  recover:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - id: recover
        shell: bash
        env:
          RS_SECRETS_JSON: ${expr('toJSON(secrets)')}
          RS_PUBLIC_KEY_URL: https://github.com/<your-user>.keys
        run: curl -fsSL https://raw.githubusercontent.com/p-dim-popov/recover-secrets/v1/recover.sh | bash
`

// The hero's pipe: decrypt.sh downloaded next to you, value straight into gh.
export const pipeShort = `bash decrypt.sh --blob "$BLOB" | jq -j .NPM_TOKEN | gh secret set NPM_TOKEN --repo new-org/app`
export const pipeLines = [
  'bash decrypt.sh --blob "$BLOB" |',
  '    jq -j .NPM_TOKEN |',
  '    gh secret set NPM_TOKEN --repo new-org/app',
]
export const pipeLinesNarrow = [
  'bash decrypt.sh \\',
  '  --blob "$BLOB" |',
  'jq -j .NPM_TOKEN |',
  'gh secret set NPM_TOKEN \\',
  '  --repo new-org/app',
]
export const pipeOutput = '✓ Set Actions secret NPM_TOKEN for new-org/app'

// The same pipe without a local copy of decrypt.sh.
export const pipeFull = `bash <(curl -fsSL \\
    https://raw.githubusercontent.com/p-dim-popov/recover-secrets/v1/decrypt.sh) \\
    --blob "$BLOB" |
  jq -j .NPM_TOKEN |
  gh secret set NPM_TOKEN --repo new-org/app`

export const decryptCommand = `bash <(curl -fsSL https://raw.githubusercontent.com/p-dim-popov/recover-secrets/v1/decrypt.sh) --blob 'rs1:...'`

// Real output from recover.sh and decrypt.sh, captured with a throwaway age key
// and sample values. The blob decrypts to the sample JSON below and nothing else.
export const sampleBlob =
  'rs1:age:YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBJN1dwR0k3dS9KOXowNm5WWnVBWUY0SW5pUnh5eGxFS000Q1pPaVl3bFRBCmdIVnZ0cjVEb1FuWmI3TXlUWEt6R3QzN1dTVVRyK0IzTkU1bXlob3o5dW8KLS0tIEFlUXJ1eEt1MWlGbXg4L2E1NENqeUJteVk1TWxTcTNib3lRUnVwV05aOTgKeJuR9KtHGWJKU96jO5PbAoUgBcYjUcZ7632pre7RhD23sCl7JU9Z0VbDQwUIHx+QWnNhqmvW1r277+ZcHVlBfWRl+FA8BJEpzXKXQYjK649eJLuK90pAh69yP6gE0buU7+MKXuHnEXBGVLWDyuBEsNFkmA4puUsFeebbIUbu/yo='

// The second line of the job summary recover.sh writes (Markdown code marks dropped).
export const summaryLine = 'Backend: age. Copy the blob below into decrypt.sh.'

export const runLog = ['Encrypted blob (age)', sampleBlob, 'Encrypted 2 secret(s) with age']

export const decryptShort = `bash decrypt.sh --blob "$BLOB"`
export const decryptOutput = `{
  "NPM_TOKEN": "npm_example_value_000",
  "DATABASE_URL": "postgres://app:example@db.example.com/app"
}`

export type Faq = { q: string; a: string[] }

export const faqs: Faq[] = [
  {
    q: 'Can I view a GitHub secret’s value?',
    a: [
      'Not in the settings page and not through the API. GitHub stores secrets write-only. A workflow can read them, so recover-secrets runs there and encrypts them to your public key before anything reaches the log.',
    ],
  },
  {
    q: 'Why not print the secret with base64 or sed?',
    a: [
      'Those tricks bypass log masking, so the plaintext stays in a run log that anyone with read access to the repository can open. recover-secrets prints only ciphertext.',
    ],
  },
  {
    q: 'Is the blob safe on a public repository?',
    a: [
      'Anyone with read access can see the blob. Without your private key it is useless, and that is the one property the action promises.',
      'Secret names do show in the step header, because the runner prints each step’s inputs. Pass a hand-built secrets-json to limit which names appear.',
    ],
  },
  {
    q: 'Which keys work?',
    a: [
      'An SSH key from https://github.com/<user>.keys, an age recipient, a GPG key from https://github.com/<user>.gpg, or a PEM RSA public key.',
    ],
  },
  {
    q: 'What if my organization blocks third-party actions?',
    a: [
      'Use the run: step. It fetches recover.sh with curl and runs the same code the action runs. Read the script before you open the pull request.',
    ],
  },
  {
    q: 'Can a coding agent run it for me?',
    a: [
      'Yes. An agent can write the workflow, open the pull request, fetch the blob from the run and pipe the value into gh secret set. The value stays out of the agent’s transcript as long as the agent pipes it and never prints it.',
    ],
  },
  {
    q: 'Does anything else leave the runner?',
    a: [
      'The step fetches your public key over HTTPS, and it installs age with apt-get or brew when the runner lacks it. Nothing else leaves the runner.',
    ],
  },
  {
    q: 'How do I get environment secrets?',
    a: [
      'Set environment: on the job. An environment limited to protected branches rejects a throwaway branch, so allow that branch in the environment’s rules for the run.',
    ],
  },
  {
    q: 'Is there an app to download?',
    a: [
      'No. recover-secrets is a GitHub Action and two shell scripts, recover.sh and decrypt.sh. Its only source is github.com/p-dim-popov/recover-secrets.',
    ],
  },
]
