import { useSyncExternalStore } from 'react'

/**
 * The theme, in one place. Kept outside React so every component reads the same
 * value without a provider, and so the pre-paint script in index.html and this
 * module agree on the storage key.
 */
export type ThemeMode = 'light' | 'dark' | 'system'

const KEY = 'skarb.theme'
const media = window.matchMedia('(prefers-color-scheme: dark)')
const listeners = new Set<() => void>()

function stored(): ThemeMode {
  const v = localStorage.getItem(KEY)
  return v === 'light' || v === 'dark' ? v : 'system'
}

let mode: ThemeMode = stored()

const resolve = (m: ThemeMode): 'light' | 'dark' => (m === 'system' ? (media.matches ? 'dark' : 'light') : m)

function apply() {
  document.documentElement.dataset.theme = resolve(mode)
}

function emit() {
  for (const l of listeners) l()
}

apply()
// Following the system means following it while the app is open, not just at boot.
media.addEventListener('change', () => {
  if (mode === 'system') {
    apply()
    emit()
  }
})

export function setThemeMode(next: ThemeMode) {
  mode = next
  if (next === 'system') localStorage.removeItem(KEY)
  else localStorage.setItem(KEY, next)
  apply()
  emit()
}

const subscribe = (l: () => void) => {
  listeners.add(l)
  return () => void listeners.delete(l)
}

export const useThemeMode = () => useSyncExternalStore(subscribe, () => mode)
export const useIsDark = () => useSyncExternalStore(subscribe, () => resolve(mode) === 'dark')

/**
 * Recharts writes its colors into SVG attributes, which never resolve `var()` —
 * so charts need concrete values, and these have to mirror index.css by hand.
 */
export type ChartColors = {
  income: string; spend: string; invested: string
  ink: string; faint: string; grid: string; surface: string; uncategorized: string
}

const LIGHT: ChartColors = {
  income: '#437051', spend: '#8A6A9E', invested: '#AF5229',
  ink: '#211D18', faint: '#746C5E', grid: '#E8E2D6', surface: '#FFFFFF', uncategorized: '#91897C',
}

const DARK: ChartColors = {
  income: '#7CB794', spend: '#BA9BD2', invested: '#E08A5B',
  ink: '#F4EEE4', faint: '#948B7C', grid: '#322C23', surface: '#221E18', uncategorized: '#716C64',
}

export const useChartColors = (): ChartColors => (useIsDark() ? DARK : LIGHT)
