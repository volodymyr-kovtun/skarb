import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { fmtMoney, type Account } from '../../shared/api'
import { Card, CardHeader, bankLabel, quietLinkCls } from '../../shared/ui'
import { useIsDark } from '../../shared/theme'
import { swatch, tint } from '../../shared/color'

export type AccountRow = { account: Account; balanceConverted: number }
type Group = { label: string; color: string; total: number; rows: AccountRow[] }

/**
 * Where the net worth sits, grouped by institution: a handful of readable lines
 * whether you hold three accounts or thirty. Individual accounts stay one click away.
 */
export default function AccountsCard({ rows, currency }: { rows: AccountRow[]; currency: string }) {
  const [open, setOpen] = useState<string | null>(null)
  const dark = useIsDark()
  if (rows.length === 0) return null

  const groups = groupByBank(rows)
  // Only what you own gets a share of the total — an account in the red takes no width.
  const positive = groups.reduce((sum, g) => sum + Math.max(g.total, 0), 0)
  const share = (total: number) => (positive > 0 ? Math.max(total, 0) / positive : 0)

  return (
    <Card className="h-full pb-5">
      <CardHeader
        title="Accounts"
        action={<Link to="/accounts" className={quietLinkCls}>Manage</Link>}
      />

      <div className="px-4">
        {groups.map((g) => {
          const expanded = open === g.label
          const single = g.rows.length === 1
          return (
            <div key={g.label}>
              <button
                onClick={() => setOpen(expanded ? null : g.label)}
                aria-expanded={expanded}
                className="flex w-full items-center gap-3.5 rounded-row px-3 py-3 text-left transition-colors hover:bg-hover"
              >
                <span
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-tile text-[13px] font-bold"
                  style={{ background: tint(g.color, dark), color: swatch(g.color, dark) }}
                  aria-hidden
                >
                  {initials(g.label)}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[14.5px] font-semibold">{g.label}</span>
                  <span className="mt-0.5 block truncate text-[12.5px] text-faint">
                    {single
                      ? `${g.rows[0].account.name} · ${g.rows[0].account.currency}`
                      : `${g.rows.length} accounts · ${[...new Set(g.rows.map((r) => r.account.currency))].join(' · ')}`}
                  </span>
                </span>
                <span className="shrink-0 text-right">
                  <span className="tnum block text-[14.5px] font-semibold">{fmtMoney(g.total, currency)}</span>
                  <span className="tnum mt-0.5 block text-[12px] text-faint">
                    {positive > 0 ? `${sharePct(share(g.total))} of net worth` : ''}
                  </span>
                </span>
                <ChevronRight
                  size={16}
                  className={`shrink-0 text-faint transition-transform ${expanded ? 'rotate-90' : ''}`}
                />
              </button>

              {expanded && (
                <ul className="mb-2 ml-[30px] flex flex-col gap-px border-l border-line pl-4">
                  {g.rows.map(({ account, balanceConverted }) => (
                    <li key={account.id} className="flex items-center gap-3 py-2 pr-3 text-[13.5px]">
                      <span className="min-w-0 flex-1 truncate text-muted">
                        {account.name}
                        {account.maskedPan
                          ? ` · ${account.maskedPan.slice(-4)}`
                          : account.iban ? ` · …${account.iban.slice(-4)}` : ''}
                      </span>
                      <span className="tnum shrink-0 font-semibold">{fmtMoney(account.balance, account.currency)}</span>
                      <span className="tnum w-28 shrink-0 whitespace-nowrap text-right text-[12px] text-faint">
                        {account.currency === currency ? '' : `≈ ${fmtMoney(balanceConverted, currency)}`}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )
        })}
      </div>
    </Card>
  )
}

/** Two letters is enough to tell PKO BP from Monobank at a glance. */
function initials(label: string) {
  const words = label.trim().split(/\s+/)
  return (words.length > 1 ? words[0][0] + words[1][0] : label.slice(0, 2)).toUpperCase()
}

/** A holding that exists shouldn't read as 0% — small shares round up to "<1%". */
function sharePct(share: number) {
  const pct = share * 100
  return pct > 0 && pct < 1 ? '<1%' : `${Math.round(pct)}%`
}

/** Biggest holdings first; inside a group the account order from the API is kept. */
function groupByBank(rows: AccountRow[]): Group[] {
  const byLabel = new Map<string, Group>()
  for (const row of rows) {
    const label = bankLabel(row.account)
    const group = byLabel.get(label) ?? { label, color: row.account.color, total: 0, rows: [] }
    group.total += row.balanceConverted
    group.rows.push(row)
    byLabel.set(label, group)
  }
  return [...byLabel.values()].sort((a, b) => b.total - a.total)
}
