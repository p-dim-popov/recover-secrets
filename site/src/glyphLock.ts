// The action's Marketplace icon (Lucide "lock", 24-unit grid) reduced to a grid
// of brightness levels and printed with the characters of a real rs1 blob, the
// Terminal theme's way of showing a picture. Pure and deterministic, so the
// prerendered HTML and the hydrated page match.

const X0 = 2
const X1 = 22
const Y0 = 0.6
const Y1 = 22.6
const SHACKLE_HALF = 1.35

function inBody(x: number, y: number) {
  if (x < 3 || x > 21 || y < 11 || y > 22) return false
  const r = 2
  const cx = x < 3 + r ? 3 + r : x > 21 - r ? 21 - r : x
  const cy = y < 11 + r ? 11 + r : y > 22 - r ? 22 - r : y
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
}

function inShackle(x: number, y: number) {
  if (y <= 7) {
    const d = Math.hypot(x - 12, y - 7)
    return Math.abs(d - 5) <= SHACKLE_HALF
  }
  if (y > 11.5) return false
  return Math.abs(x - 7) <= SHACKLE_HALF || Math.abs(x - 17) <= SHACKLE_HALF
}

// Small deterministic ripple so the body is not one flat level.
const ripple = (i: number) => ((i * 2654435761) >>> 0) % 3

export type GlyphRun = { level: number; text: string }

export function glyphLock(source: string, COLS = 56): GlyphRun[][] {
  const CELL_W = (X1 - X0) / COLS
  const CELL_H = CELL_W * 1.85
  const ROWS = Math.round((Y1 - Y0) / CELL_H)
  const chars = source.replace(/[^A-Za-z0-9+/=]/g, '')
  let k = 0
  const rows: GlyphRun[][] = []
  for (let r = 0; r < ROWS; r++) {
    const runs: GlyphRun[] = []
    for (let c = 0; c < COLS; c++) {
      let body = 0
      let shackle = 0
      const S = 4
      for (let sy = 0; sy < S; sy++) {
        for (let sx = 0; sx < S; sx++) {
          const x = X0 + (c + (sx + 0.5) / S) * CELL_W
          const y = Y0 + (r + (sy + 0.5) / S) * CELL_H
          if (inBody(x, y)) body++
          else if (inShackle(x, y)) shackle++
        }
      }
      const cover = (body + shackle) / (S * S)
      let level = 0
      if (cover > 0.12) {
        const y = Y0 + (r + 0.5) * CELL_H
        const base = body >= shackle ? 8 - Math.round(((y - 11) / 11) * 3) - ripple(r * COLS + c) : 6 - ripple(r * COLS + c)
        level = Math.max(1, Math.min(8, Math.round(base * Math.min(1, cover * 1.4))))
      }
      const ch = level ? chars[k++ % chars.length] : ' '
      const last = runs[runs.length - 1]
      if (last && last.level === level) last.text += ch
      else runs.push({ level, text: ch })
    }
    rows.push(runs)
  }
  return rows
}
