/**
 * Categories, tags and accounts carry a color the user picked, stored as a hex string.
 * A hue that reads well on paper disappears on a dark surface, so nothing renders a
 * stored color directly — it goes through here first and comes back inside the
 * lightness band that stays legible in the current theme.
 */

type Hsl = { h: number; s: number; l: number }

function toHsl(hex: string): Hsl | null {
  const m = /^#?([\da-f]{3}|[\da-f]{6})$/i.exec(hex.trim())
  if (!m) return null
  const full = m[1].length === 3 ? m[1].replace(/./g, (c) => c + c) : m[1]
  const r = parseInt(full.slice(0, 2), 16) / 255
  const g = parseInt(full.slice(2, 4), 16) / 255
  const b = parseInt(full.slice(4, 6), 16) / 255

  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const l = (max + min) / 2
  const d = max - min
  if (d === 0) return { h: 0, s: 0, l }

  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  const h =
    max === r ? ((g - b) / d + (g < b ? 6 : 0)) :
    max === g ? (b - r) / d + 2 :
                (r - g) / d + 4
  return { h: h * 60, s, l }
}

function toRgb({ h, s, l }: Hsl): [number, number, number] {
  if (s === 0) {
    const v = Math.round(l * 255)
    return [v, v, v]
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  const channel = (t: number) => {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  const hk = h / 360
  return [channel(hk + 1 / 3), channel(hk), channel(hk - 1 / 3)].map((v) => Math.round(v * 255)) as [number, number, number]
}

/**
 * The band a stored color is allowed to occupy. Light mode needs it dark enough to
 * read against white; dark mode needs it light enough to read against near-black.
 */
const BAND = {
  light: { min: 0.26, max: 0.44 },
  dark: { min: 0.62, max: 0.78 },
}

function normalize(hex: string, dark: boolean): [number, number, number] | null {
  const hsl = toHsl(hex)
  if (!hsl) return null
  const band = dark ? BAND.dark : BAND.light
  // A grey stays grey — pushing saturation onto it would invent a hue.
  const s = hsl.s === 0 ? 0 : Math.min(Math.max(hsl.s, 0.22), 0.62)
  return toRgb({ h: hsl.h, s, l: Math.min(Math.max(hsl.l, band.min), band.max) })
}

/** A stored color, made legible: dots, chart fills, bars, and colored text. */
export function swatch(hex: string, dark: boolean): string {
  const rgb = normalize(hex, dark)
  return rgb ? `rgb(${rgb[0]} ${rgb[1]} ${rgb[2]})` : hex
}

/** The same color as a background wash, for chips and icon tiles. */
export function tint(hex: string, dark: boolean): string {
  const rgb = normalize(hex, dark)
  if (!rgb) return 'transparent'
  return `rgb(${rgb[0]} ${rgb[1]} ${rgb[2]} / ${dark ? 0.24 : 0.14})`
}
