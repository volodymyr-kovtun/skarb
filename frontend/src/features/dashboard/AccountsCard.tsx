import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { fmtMoney, type Account } from '../../shared/api'
import { Card, CardHeader, bankLabel } from '../../shared/ui'

export type AccountRow = { account: Account; balanceConverted: number }
type Group = { label: string; color: string; total: number; rows: AccountRow[] }

/**
 * Where the net worth sits, grouped by institution: a handful of readable lines
 * whether you hold three accounts or thirty. Individual accounts stay one click away.
 */
export default function AccountsCard({ rows, currency }: { rows: AccountRow[]; currency: string }) {
  const [open, setOpen] = useState<string | null>(null)
  if (rows.length === 0) return null

  const groups = groupByBank(rows)
  // Only what you own gets a share of the bar — an account in the red takes no width.
  const positive = groups.reduce((sum, g) => sum + Math.max(g.total, 0), 0)
  const share = (total: number) => (positive > 0 ? Math.max(total, 0) / positive : 0)

  return (
    <Card className="pb-2">
      <CardHeader
        title="Accounts"
        action={<Link to="/accounts" className="text-sm font-medium text-muted hover:text-ink">Manage</Link>}
      />

      {positive > 0 && (
        <div className="flex gap-[3px] px-5 pt-1 pb-3" aria-hidden>
          {groups.filter((g) => g.total > 0).map((g) => (
            <span
              key={g.label}
              className="h-1.5 rounded-full"
              style={{ background: g.color, flexGrow: share(g.total), flexBasis: 6, minWidth: 6 }}
            />
          ))}
        </div>
      )}

      <div className="px-2 pb-1">
        {groups.map((g) => {
          const expanded = open === g.label
          const single = g.rows.length === 1
          return (
            <div key={g.label}>
              <button
                onClick={() => setOpen(expanded ? null : g.label)}
                aria-expanded={expanded}
                className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-paper"
              >
                <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: g.color }} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium">{g.label}</span>
                  <span className="block text-xs text-faint">
                    {single
                      ? `${g.rows[0].account.name} · ${g.rows[0].account.currency}`
                      : `${g.rows.length} accounts · ${[...new Set(g.rows.map((r) => r.account.currency))].join(' · ')}`}
                  </span>
                </span>
                <span className="tnum text-sm font-semibold">{fmtMoney(g.total, currency)}</span>
                <span className="tnum w-9 shrink-0 text-right text-xs text-faint">
                  {positive > 0 ? sharePct(share(g.total)) : ''}
                </span>
                <ChevronRight
                  size={15}
                  className={`shrink-0 text-faint transition-transform ${expanded ? 'rotate-90' : ''}`}
                />
              </button>

              {expanded && (
                <ul className="mb-1 ml-[26px] flex flex-col gap-px border-l border-line pl-3">
                  {g.rows.map(({ account, balanceConverted }) => (
                    <li key={account.id} className="flex items-center gap-3 py-1.5 pr-3 text-sm">
                      <span className="min-w-0 flex-1 truncate text-muted">
                        {account.name}
                        {account.maskedPan
                          ? ` · ${account.maskedPan.slice(-4)}`
                          : account.iban ? ` · …${account.iban.slice(-4)}` : ''}
                      </span>
                      <span className="tnum shrink-0 font-medium">{fmtMoney(account.balance, account.currency)}</span>
                      <span className="tnum w-28 shrink-0 whitespace-nowrap text-right text-xs text-faint">
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
