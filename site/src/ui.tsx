import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import { css, cx } from '../styled-system/css'

// Lucide icons (ISC), 24 grid drawn at 16px.
function Icon({ children }: { children: ReactNode }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={css({ flexShrink: 0 })}
    >
      {children}
    </svg>
  )
}
const CopyIcon = () => (
  <Icon>
    <rect width="14" height="14" x="8" y="8" rx="2" ry="2" />
    <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" />
  </Icon>
)
const CheckIcon = () => (
  <Icon>
    <path d="M20 6 9 17l-5-5" />
  </Icon>
)

async function writeClipboard(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}

// The copied state lasts 1.4s, as the theme's install line does.
function useCopied(): [boolean, (text: string) => Promise<boolean>] {
  const [copied, setCopied] = useState(false)
  const timer = useRef<number | undefined>(undefined)
  useEffect(() => () => window.clearTimeout(timer.current), [])
  const copy = async (text: string) => {
    const ok = await writeClipboard(text)
    if (ok) {
      setCopied(true)
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(() => setCopied(false), 1400)
    }
    return ok
  }
  return [copied, copy]
}

const iconButton = css({
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  width: 'control',
  height: 'control',
  flexShrink: 0,
  border: 'none',
  bg: 'transparent',
  color: 'muted',
  cursor: 'pointer',
  transitionProperty: 'color, background-color',
  transitionDuration: 'micro',
  transitionTimingFunction: 'step',
  _hover: { color: 'ink', bg: 'paper3' },
  _active: { bg: 'rule' },
  '&[data-copied]': { color: 'accent' },
})

export function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, copy] = useCopied()
  return (
    <button
      type="button"
      data-needs-js=""
      data-copied={copied ? '' : undefined}
      className={iconButton}
      aria-label={label}
      onClick={() => void copy(text)}
    >
      {copied ? <CheckIcon /> : <CopyIcon />}
      <span role="status" className="visually-hidden">
        {copied ? 'Copied' : ''}
      </span>
    </button>
  )
}

// The page's one filled control. Without script it is a link to the workflow.
export const primaryRaw = css.raw({
  display: 'inline-flex',
  alignItems: 'center',
  gap: 'xs',
  minHeight: 'control',
  px: 'lg',
  bg: 'accent',
  color: 'accentInk',
  borderWidth: 'hair',
  borderStyle: 'solid',
  borderColor: 'accent',
  fontSize: 'md',
  fontWeight: 'bold',
  lineHeight: 'none',
  whiteSpace: 'nowrap',
  textDecoration: 'none',
  cursor: 'pointer',
  transitionProperty: 'background-color, transform',
  transitionDuration: 'micro',
  transitionTimingFunction: 'step',
  _hover: { bg: 'ink', borderColor: 'ink' },
  _active: { transform: 'translateY(1px)' },
})

export const secondaryRaw = css.raw({
  display: 'inline-flex',
  alignItems: 'center',
  minHeight: 'control',
  px: 'lg',
  bg: 'transparent',
  color: 'ink',
  borderWidth: 'hair',
  borderStyle: 'solid',
  borderColor: 'ink2',
  fontSize: 'md',
  lineHeight: 'none',
  whiteSpace: 'nowrap',
  textDecoration: 'none',
  cursor: 'pointer',
  transitionProperty: 'background-color, transform',
  transitionDuration: 'micro',
  transitionTimingFunction: 'step',
  _hover: { bg: 'paper3' },
  _active: { transform: 'translateY(1px)' },
})

export function CopyWorkflowButton({ text, href }: { text: string; href: string }) {
  const [copied, copy] = useCopied()
  return (
    <a
      href={href}
      className={primaryButton}
      onClick={async (e) => {
        e.preventDefault()
        const ok = await copy(text)
        if (!ok) window.location.hash = href
      }}
    >
      {copied ? 'Workflow copied' : 'Copy the workflow'}
      <span role="status" className="visually-hidden">
        {copied ? 'The workflow file is on your clipboard' : ''}
      </span>
    </a>
  )
}

export const wellRaw = css.raw({
  position: 'relative',
  bg: 'paper2',
  borderWidth: 'hair',
  borderStyle: 'solid',
  borderColor: 'rule',
  minWidth: '0',
})

// Sessions wrap; YAML and long commands keep their lines and scroll inside the well.
export const codeTextRaw = css.raw({
  display: 'block',
  px: 'lg',
  py: 'lg',
  fontSize: 'sm',
  lineHeight: 'body',
  color: 'ink',
  whiteSpace: 'pre-wrap',
  overflowWrap: 'break-word',
  md: { px: 'xl' },
})

export const codeScrollRaw = css.raw({ whiteSpace: 'pre', overflowWrap: 'normal', overflowX: 'auto' })

export const primaryButton = css(primaryRaw)
export const secondaryButton = css(secondaryRaw)
export const well = css(wellRaw)
export const codeText = css(codeTextRaw)
export const codeScroll = css(codeTextRaw, codeScrollRaw)

export const prompt = css({ color: 'muted', userSelect: 'none' })
export const placeholder = css({ color: 'accent' })

// Marks the parts a reader replaces, such as <your-user>.
export function Marked({ code, mark }: { code: string; mark: string }) {
  const parts = code.split(mark)
  return (
    <>
      {parts.map((p, i) => (
        <span key={i}>
          {p}
          {i < parts.length - 1 && <span className={placeholder}>{mark}</span>}
        </span>
      ))}
    </>
  )
}

export type Tab = { key: string; label: string; body: ReactNode; copy: string; copyLabel: string }

const tabButton = css({
  display: 'inline-flex',
  alignItems: 'center',
  minHeight: 'control',
  px: 'lg',
  border: 'none',
  borderBottomWidth: 'thick',
  borderBottomStyle: 'solid',
  borderBottomColor: 'transparent',
  bg: 'transparent',
  color: 'muted',
  fontSize: 'sm',
  whiteSpace: 'nowrap',
  cursor: 'pointer',
  transitionProperty: 'color, background-color',
  transitionDuration: 'micro',
  transitionTimingFunction: 'step',
  _hover: { color: 'ink', bg: 'paper3' },
  _active: { bg: 'rule' },
  '&[aria-selected=true]': { color: 'ink', borderBottomColor: 'accent', bg: 'accentWash' },
})

// A code well with tabs. Without script, every panel shows in order under
// its own label and the tab row stays hidden.
export function TabbedWell({ tabs, label, className }: { tabs: Tab[]; label: string; className?: string }) {
  const [active, setActive] = useState(0)
  const base = useId()
  const refs = useRef<(HTMLButtonElement | null)[]>([])
  const onKey = (e: KeyboardEvent) => {
    const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
    if (!d) return
    e.preventDefault()
    const next = (active + d + tabs.length) % tabs.length
    setActive(next)
    refs.current[next]?.focus()
  }
  return (
    <div className={cx(well, className)}>
      <div
        role="tablist"
        aria-label={label}
        data-needs-js=""
        onKeyDown={onKey}
        className={css({ display: 'flex', borderBottomWidth: 'hair', borderBottomStyle: 'solid', borderBottomColor: 'rule', overflowX: 'auto' })}
      >
        {tabs.map((t, i) => (
          <button
            key={t.key}
            ref={(el) => {
              refs.current[i] = el
            }}
            type="button"
            role="tab"
            id={`${base}-tab-${t.key}`}
            aria-controls={`${base}-panel-${t.key}`}
            aria-selected={i === active}
            tabIndex={i === active ? 0 : -1}
            className={tabButton}
            onClick={() => setActive(i)}
          >
            {t.label}
          </button>
        ))}
      </div>
      {tabs.map((t, i) => (
        <div
          key={t.key}
          role="tabpanel"
          id={`${base}-panel-${t.key}`}
          aria-labelledby={`${base}-tab-${t.key}`}
          data-tab-panel=""
          data-active={i === active ? '' : undefined}
          className={css({ position: 'relative', display: 'flex', alignItems: 'flex-start' })}
        >
          <div className={css({ flex: '1', minWidth: '0' })}>
            <p
              data-nojs-label=""
              className={css({ px: 'lg', pt: 'lg', fontSize: 'sm', color: 'muted', md: { px: 'xl' } })}
            >
              {t.label}
            </p>
            <pre className={codeScroll} tabIndex={0} aria-label={`${t.label} workflow`}>
              <code>{t.body}</code>
            </pre>
          </div>
          <CopyButton text={t.copy} label={t.copyLabel} />
        </div>
      ))}
    </div>
  )
}
