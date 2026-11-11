import { css, cx } from '../styled-system/css'
import {
  decryptOutput,
  decryptShort,
  faqs,
  licenseUrl,
  marketplaceUrl,
  pipeFull,
  pipeLines,
  pipeLinesNarrow,
  pipeOutput,
  pipeShort,
  readmeUrl,
  repoUrl,
  runLog,
  sampleBlob,
  summaryLine,
  workflowAction,
  workflowRun,
  writeupUrl,
} from './content'
import {
  CopyButton,
  CopyWorkflowButton,
  Marked,
  TabbedWell,
  codeScroll,
  codeScrollRaw,
  codeTextRaw,
  prompt,
  secondaryButton,
  secondaryRaw,
  well,
} from './ui'
import { glyphLock } from './glyphLock'

const container = 'container'

const grid = css({
  display: 'grid',
  gridTemplateColumns: 'minmax(0, 1fr)',
  gap: 'xl',
  md: { gridTemplateColumns: 'repeat(12, minmax(0, 1fr))', columnGap: 'columns', rowGap: '2xl' },
})

const lead = cx('lead', css({ color: 'ink2' }))

const linkRaw = css.raw({
  color: 'ink2',
  textDecorationStyle: 'dotted',
  textUnderlineOffset: '0.2em',
  transitionProperty: 'color',
  transitionDuration: 'micro',
  transitionTimingFunction: 'step',
  _hover: { color: 'accent' },
})

const ruleTop = css.raw({ borderTopWidth: 'hair', borderTopStyle: 'solid', borderTopColor: 'rule' })

function Nav() {
  const navLink = css(linkRaw, {
    display: 'none',
    alignItems: 'center',
    minHeight: 'control',
    px: 'sm',
    fontSize: 'sm',
    textDecoration: 'none',
    sm: { display: 'inline-flex' },
  })
  return (
    <header className={css({ position: 'sticky', top: 'md', zIndex: 'nav', mt: 'md' })}>
      <div className={container}>
        <nav
          aria-label="Main"
          className={css({
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 'md',
            minHeight: 'control',
            pl: 'md',
            pr: '2xs',
            py: '2xs',
            bg: 'paper2',
            borderWidth: 'hair',
            borderStyle: 'solid',
            borderColor: 'rule',
          })}
        >
          <a
            href="#top"
            aria-label="recover-secrets, back to the top"
            className={css({ fontWeight: 'bold', fontSize: 'sm', color: 'ink', textDecoration: 'none', whiteSpace: 'nowrap', _hover: { color: 'accent' } })}
          >
            recover-secrets
          </a>
          <div className={css({ display: 'flex', alignItems: 'center', gap: '2xs' })}>
            <a className={navLink} href="#how">
              How it works
            </a>
            <a className={navLink} href="#faq">
              Questions
            </a>
            <a className={css(secondaryRaw, { fontSize: 'sm', borderColor: 'rule2' })} href={repoUrl}>
              GitHub
            </a>
          </div>
        </nav>
      </div>
    </header>
  )
}

// The lock printed in the blob's characters, as SVG text: 6.5 units a character.
function GlyphLock({ cols, className }: { cols: number; className: string }) {
  const rows = glyphLock(sampleBlob, cols)
  const adv = 6.5
  const rowH = 12
  return (
    <div className={className}>
      <svg
        role="img"
        aria-label="The recover-secrets lock icon, printed in the characters of an encrypted blob"
        viewBox={`0 0 ${cols * adv} ${rows.length * rowH}`}
        className="glyph-art"
      >
        {rows.flatMap((runs, r) => {
          let col = 0
          return runs.map((run, i) => {
            const x = col * adv
            col += run.text.length
            if (!run.level) return null
            return (
              <text
                key={`${r}-${i}`}
                x={x}
                y={(r + 1) * rowH - 2.5}
                textLength={run.text.length * adv}
                lengthAdjust="spacing"
                className={`g${run.level}`}
              >
                {run.text}
              </text>
            )
          })
        })}
      </svg>
    </div>
  )
}

function Hero() {
  return (
    <section
      aria-labelledby="hero-title"
      className={css({ display: 'flex', alignItems: 'center', minHeight: 'heroMin', py: 'xl' })}
    >
      <div className={cx(container, grid, css({ alignItems: 'center', md: { rowGap: 'xl' } }))}>
        <div className={css({ md: { gridColumn: '1 / 9' } })}>
          <h1 id="hero-title" className={css({ fontSize: 'displayS' })}>
            Recover GitHub Actions secrets.
            <br />
            Log no values.
          </h1>
          <p className={cx(lead, css({ mt: 'lg', maxWidth: 'corridor' }))}>
            Encrypted on the runner to your public key, decrypted on your machine.
          </p>
          <div className={css({ display: 'flex', flexWrap: 'wrap', gap: 'sm', mt: 'xl' })}>
            <CopyWorkflowButton text={workflowAction} href="#workflow" />
            <a className={secondaryButton} href={repoUrl}>
              View on GitHub
            </a>
          </div>
        </div>
        <GlyphLock
          cols={56}
          className={css({ display: 'none', md: { display: 'block', gridColumn: '9 / 13', gridRow: '1 / span 2', alignSelf: 'stretch', alignContent: 'center' } })}
        />
        <figure className={css({ mx: '0', my: '0', md: { gridColumn: '1 / 9' } })}>
          <div className={cx(well, css({ display: 'flex', alignItems: 'flex-start' }))}>
            <pre className={css(codeTextRaw, { flex: '1', minWidth: '0', fontSize: 'sm', md: { fontSize: 'md' } })}>
              <code className={css({ display: 'none', md: { display: 'inline' } })}>
                <span className={prompt}>~ $ </span>
                {pipeLines.join('\n')}
                {'\n'}
                <span className={css({ color: 'accent' })}>{pipeOutput}</span>
              </code>
              <code className={css({ md: { display: 'none' } })}>
                <span className={prompt}>~ $ </span>
                {pipeLinesNarrow.join('\n')}
                {'\n'}
                <span className={css({ color: 'accent' })}>{pipeOutput}</span>
              </code>
            </pre>
            <CopyButton text={pipeShort} label="Copy the command" />
          </div>
          <figcaption className={css({ mt: 'sm', fontSize: 'sm', color: 'muted' })}>
            Nothing prints between the command and the ✓.
          </figcaption>
        </figure>
        <GlyphLock cols={32} className={css({ mx: 'auto', width: 'full', maxWidth: 'corridor', md: { display: 'none' } })} />
      </div>
    </section>
  )
}

function Workflow() {
  const steps = [
    'Push it to a branch named recover-secrets-tmp.',
    'Copy the blob from the run summary.',
    'Decrypt it on your machine.',
    'Delete the branch and the run.',
  ]
  return (
    <section id="workflow" aria-labelledby="workflow-title" className={css({ pt: '2xl', pb: '2xl' })}>
      <div className={cx(container, grid)}>
        <div className={css({ md: { gridColumn: '1 / 6' } })}>
          <h2 id="workflow-title">Push one file, get one blob</h2>
          <ol
            className={css({
              mt: '2xl',
              counterReset: 'step',
              '& > li': {
                ...ruleTop,
                counterIncrement: 'step',
                display: 'grid',
                gridTemplateColumns: 'token(spacing.xl) minmax(0, 1fr)',
                py: 'md',
                color: 'ink2',
                _before: { content: 'counter(step)', color: 'accent' },
              },
            })}
          >
            {steps.map((s) => (
              <li key={s}>{s}</li>
            ))}
          </ol>
        </div>
        <div className={css({ minWidth: '0', md: { gridColumn: '6 / 13' } })}>
          <TabbedWell
            label="Workflow variant"
            tabs={[
              {
                key: 'action',
                label: 'uses: action',
                body: <Marked code={workflowAction} mark="<your-user>" />,
                copy: workflowAction,
                copyLabel: 'Copy the workflow that uses the action',
              },
              {
                key: 'run',
                label: 'run: step',
                body: <Marked code={workflowRun} mark="<your-user>" />,
                copy: workflowRun,
                copyLabel: 'Copy the workflow with the run: step',
              },
            ]}
          />
          <p className={css({ mt: 'sm', fontSize: 'sm', color: 'muted' })}>
            Replace <span className={css({ color: 'accent' })}>&lt;your-user&gt;</span> with your GitHub username and the secret names with your own.
          </p>
        </div>
      </div>
    </section>
  )
}

type Line = { text: string; tone?: 'prompt' | 'muted' | 'strong' | 'blob' }

// A session well. Lines keep their shape and scroll inside the well; a blob
// line breaks anywhere, because it has no spaces.
function Session({ lines, label }: { lines: Line[]; label: string }) {
  return (
    <div className={well}>
      <pre className={codeScroll} tabIndex={0} aria-label={label}>
        <code>
          {lines.map((l, i) => (
            <span
              key={i}
              className={css({
                display: 'block',
                color: l.tone === 'muted' ? 'muted' : 'ink',
                fontWeight: l.tone === 'strong' ? 'bold' : 'body',
                whiteSpace: l.tone === 'blob' ? 'pre-wrap' : 'pre',
                wordBreak: l.tone === 'blob' ? 'break-all' : 'normal',
              })}
            >
              {l.tone === 'prompt' && <span className={prompt}>~ $ </span>}
              {l.text}
            </span>
          ))}
        </code>
      </pre>
    </div>
  )
}

function HowItWorks() {
  const steps = [
    {
      title: 'The runner encrypts',
      text: 'recover.sh fetches your public key and encrypts the secrets to it. The log holds the blob, folded, and a count.',
      visual: <Session label="The step's log" lines={[{ text: `> ${runLog[0]}`, tone: 'muted' }, { text: runLog[2] }]} />,
    },
    {
      title: 'The run shows a blob',
      text: 'Anyone with read access sees this job summary. Without your private key, the blob is useless.',
      visual: (
        <Session
          label="The job summary recover.sh writes"
          lines={[{ text: 'recover-secrets', tone: 'strong' }, { text: summaryLine, tone: 'muted' }, { text: ' ' }, { text: sampleBlob, tone: 'blob' }]}
        />
      ),
    },
    {
      title: 'You decrypt locally',
      text: 'decrypt.sh uses your private key. The plaintext exists only on your machine.',
      visual: (
        <Session
          label="decrypt.sh on your machine"
          lines={[{ text: decryptShort, tone: 'prompt' }, ...decryptOutput.split('\n').map((text) => ({ text }))]}
        />
      ),
    },
  ]
  return (
    <section id="how" aria-labelledby="how-title" className={css(ruleTop, { pt: '2xl', pb: '3xl' })}>
      <div className={container}>
        <h2 id="how-title">What each side sees</h2>
        <ol className={css({ mt: '2xl' })}>
          {steps.map((s) => (
            <li key={s.title} className={cx(grid, css(ruleTop, { py: '2xl', md: { alignItems: 'center' } }))}>
              <div className={css({ md: { gridColumn: '1 / 5' } })}>
                <h3>{s.title}</h3>
                <p className={css({ mt: 'md', color: 'ink2' })}>{s.text}</p>
              </div>
              <div className={css({ minWidth: '0', md: { gridColumn: '6 / 13' } })}>{s.visual}</div>
            </li>
          ))}
        </ol>
      </div>
    </section>
  )
}

function Move() {
  const diagram = ['rs1 blob', '   |', 'decrypt.sh <-- key', '   |', 'jq -j .NPM_TOKEN', '   |', 'gh secret set', '   |', 'new-org/app'].join('\n')
  return (
    <section id="move" aria-labelledby="move-title" className={css({ pt: '2xl', pb: '2xl' })}>
      <div className={cx(container, grid)}>
        <div className={css({ md: { gridColumn: '1 / 8', alignSelf: 'center' } })}>
          <h2 id="move-title">Move a secret without seeing it</h2>
          <p className={cx(lead, css({ mt: 'lg' }))}>
            A coding agent can run this pipe too. The value stays out of its transcript while it stays in the pipe.
          </p>
        </div>
        <pre
          role="img"
          aria-label="Diagram: the rs1 blob goes into decrypt.sh with your private key, jq -j picks one value, and gh secret set stores it in new-org/app."
          className={css({
            fontSize: 'title',
            lineHeight: 'snug',
            color: 'ink2',
            whiteSpace: 'pre',
            overflowX: 'auto',
            md: { gridColumn: '9 / 13' },
          })}
        >
          {diagram}
        </pre>
        <div className={cx(well, css({ display: 'flex', alignItems: 'flex-start', md: { gridColumn: '1 / 13' } }))}>
          <pre
            tabIndex={0}
            aria-label="The pipe, with decrypt.sh fetched by curl"
            className={css(codeTextRaw, codeScrollRaw, { flex: '1', minWidth: '0', fontSize: 'sm', md: { fontSize: 'md' } })}
          >
            <code>
              <span className={prompt}>~ $ </span>
              {pipeFull}
            </code>
          </pre>
          <CopyButton text={pipeFull} label="Copy the pipe" />
        </div>
      </div>
    </section>
  )
}

function Faq() {
  return (
    <section id="faq" aria-labelledby="faq-title" className={css(ruleTop, { pt: '3xl', pb: '3xl' })}>
      <div className={cx(container, grid)}>
        <h2 id="faq-title" className={css({ md: { gridColumn: '1 / 5' } })}>
          What shows, what stays secret
        </h2>
        <div className={css({ md: { gridColumn: '5 / 13' } })}>
          {faqs.map((f) => (
            <details
              key={f.q}
              className={css({
                borderBottomWidth: 'hair',
                borderBottomStyle: 'solid',
                borderBottomColor: 'rule',
                _first: ruleTop,
                '&[open] > summary': { color: 'ink' },
                '&[open] > summary > span:last-child': { transform: 'rotate(45deg)' },
              })}
            >
              <summary
                className={css({
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 'lg',
                  minHeight: 'control',
                  py: 'md',
                  fontSize: 'lg',
                  color: 'ink2',
                  listStyle: 'none',
                  transitionProperty: 'color, background-color',
                  transitionDuration: 'micro',
                  transitionTimingFunction: 'step',
                  _hover: { color: 'ink', bg: 'paper2' },
                })}
              >
                <h3 className={css({ fontSize: 'lg', fontWeight: 'body', fontStretch: 'var(--stretch-body)', letterSpacing: 'none', maxWidth: 'none' })}>{f.q}</h3>
                <span aria-hidden="true" className={css({ color: 'accent', flexShrink: 0 })}>
                  +
                </span>
              </summary>
              <div className={css({ pb: 'lg', color: 'ink2', maxWidth: 'measure', '& > p + p': { mt: 'md' } })}>
                {f.a.map((p) => (
                  <p key={p}>{p}</p>
                ))}
              </div>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}

// One close: the statement, the page's action again, then the links.
function Footer() {
  const links = [
    { href: repoUrl, label: 'Source on GitHub' },
    { href: marketplaceUrl, label: 'Marketplace' },
    { href: readmeUrl, label: 'README' },
    { href: writeupUrl, label: 'The write-up' },
    { href: licenseUrl, label: 'MIT licence' },
  ]
  return (
    <footer className={css(ruleTop, { pt: 'sectionS', pb: '2xl', bg: 'paper2' })}>
      <div className={container}>
        <p
          className={css({
            fontSize: 'displayS',
            fontStretch: 'var(--stretch-display)',
            fontWeight: 'display',
            letterSpacing: 'display',
            lineHeight: 'tight',
            maxWidth: 'heroCol',
            textWrap: 'balance',
          })}
        >
          The action prints secret values only as ciphertext.
        </p>
        <div className={css({ display: 'flex', flexWrap: 'wrap', gap: 'sm', mt: 'xl' })}>
          <CopyWorkflowButton text={workflowAction} href="#workflow" />
        </div>
        <ul className={css(ruleTop, { display: 'flex', flexWrap: 'wrap', columnGap: 'xl', rowGap: 'xs', mt: '3xl', pt: 'lg' })}>
          {links.map((l) => (
            <li key={l.href}>
              <a className={css(linkRaw, { display: 'inline-flex', alignItems: 'center', minHeight: 'control' })} href={l.href}>
                {l.label}
              </a>
            </li>
          ))}
        </ul>
      </div>
    </footer>
  )
}

export function App() {
  return (
    <>
      <a
        href="#main"
        className={css({
          position: 'absolute',
          left: 'md',
          top: '-3xl',
          zIndex: 'toast',
          px: 'md',
          py: 'xs',
          bg: 'ink',
          color: 'paper',
          _focusVisible: { top: 'md' },
        })}
      >
        Skip to content
      </a>
      <div id="top" />
      <Nav />
      <main id="main">
        <Hero />
        <Workflow />
        <HowItWorks />
        <Move />
        <Faq />
      </main>
      <Footer />
    </>
  )
}
