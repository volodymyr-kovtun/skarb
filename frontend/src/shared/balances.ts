import { useSyncExternalStore } from 'react'
import { fmtMoney } from './api'

/**
 * Whether balances are spelled out or dotted over. Kept outside React, like the theme, so
 * the hero, the accounts card and the accounts page all read one value without a provider
 * threading it down.
 *
 * Hidden is the default on purpose: opening Skarb should show you how the window is going,
 * not put your whole net worth in 64px type before you have asked for it. Only *balances*
 * go through here — what you hold right now. Earned, spent, invested and every transaction
 * stay legible either way, because that is what the page is for.
 */
const KEY = 'skarb.showBalances'
const listeners = new Set<() => void>()

let shown = localStorage.getItem(KEY) === 'true'

export function setBalancesShown(next: boolean) {
  shown = next
  if (next) localStorage.setItem(KEY, 'true')
  else localStorage.removeItem(KEY)
  for (const l of listeners) l()
}

const subscribe = (l: () => void) => {
  listeners.add(l)
  return () => void listeners.delete(l)
}

export const useBalancesShown = () => useSyncExternalStore(subscribe, () => shown)

/** Wide enough to read as a redaction, narrow enough that revealing a row barely moves it. */
const DOTS = '••••••'

/** `fmtMoney` that answers to the toggle. Every balance on screen should print through it. */
export function fmtBalance(
  shown: boolean, amount: number, currency: string, opts?: { sign?: boolean; decimals?: number },
) {
  return shown ? fmtMoney(amount, currency, opts) : DOTS
}
