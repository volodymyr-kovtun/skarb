import { useState } from 'react'

/** Remembered so every report opens in the currency you last read your money in. */
const CURRENCY_KEY = 'skarb.displayCurrency'

/**
 * The currency reports are read in. Empty means "whatever the server calls base",
 * which is what a fresh install should show before anyone has picked anything.
 */
export function useDisplayCurrency() {
  const [currency, set] = useState(() => localStorage.getItem(CURRENCY_KEY) ?? '')
  const pick = (c: string) => {
    localStorage.setItem(CURRENCY_KEY, c)
    set(c)
  }
  return [currency, pick] as const
}
