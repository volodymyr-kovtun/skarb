import { useState } from 'react'
import { format, parseISO } from 'date-fns'

/** The windows a report can be read over. The keys are the API's; the labels are ours. */
export const PERIODS = [
  { value: 'month', label: 'This month' },
  { value: 'last', label: 'Last month' },
  { value: '3m', label: '3M' },
  { value: '6m', label: '6M' },
  { value: 'ytd', label: 'YTD' },
] as const

export type PeriodKey = (typeof PERIODS)[number]['value']

/** How a window names itself where its dates will not fit — inside the donut, mostly. */
export const periodName: Record<PeriodKey, string> = {
  month: 'This month',
  last: 'Last month',
  '3m': 'Last 3 months',
  '6m': 'Last 6 months',
  ytd: 'Year to date',
}

/** The same window worked into a sentence: "nothing spent this month". */
export const periodPhrase: Record<PeriodKey, string> = {
  month: 'this month',
  last: 'last month',
  '3m': 'over the last 3 months',
  '6m': 'over the last 6 months',
  ytd: 'this year so far',
}

/**
 * What a window is measured against. The server compares like with like — three weeks of August
 * against the first three weeks of July, never against the whole of it — and this says so, because
 * a percentage that quietly compares 21 days to 31 reads as a collapse in spending every month.
 */
export const periodComparison: Record<PeriodKey, string> = {
  month: 'on the same days last month',
  last: 'on the month before',
  '3m': 'on the previous 3 months',
  '6m': 'on the previous 6 months',
  ytd: 'on the same stretch last year',
}

const PERIOD_KEY = 'skarb.dashboardPeriod'

const isPeriod = (v: string): v is PeriodKey => PERIODS.some((p) => p.value === v)

/** Remembered so the dashboard reopens on the window you last read your money over. */
export function useReportPeriod() {
  const [period, set] = useState<PeriodKey>(() => {
    const saved = localStorage.getItem(PERIOD_KEY)
    return saved && isPeriod(saved) ? saved : 'month'
  })
  const pick = (p: string) => {
    if (!isPeriod(p)) return
    localStorage.setItem(PERIOD_KEY, p)
    set(p)
  }
  return [period, pick] as const
}

/**
 * A window with both ends inclusive, written as short as it goes without turning ambiguous:
 * the day alone repeats inside one month, the month repeats across two, and the year is always
 * spelled out — this whole control exists because the range was being guessed at.
 */
export function formatRange(start: string, end: string) {
  const from = parseISO(start)
  const to = parseISO(end)
  if (start === end) return format(to, 'd MMM yyyy')
  if (from.getFullYear() !== to.getFullYear()) return `${format(from, 'd MMM yyyy')} – ${format(to, 'd MMM yyyy')}`
  if (from.getMonth() !== to.getMonth()) return `${format(from, 'd MMM')} – ${format(to, 'd MMM yyyy')}`
  return `${format(from, 'd')} – ${format(to, 'd MMM yyyy')}`
}
