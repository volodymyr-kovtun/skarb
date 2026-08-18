import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell,
} from 'recharts'
import { api, fmtMoney } from '../../shared/api'
import { Card, CardHeader, CurrencySwitch, Segmented, TxRow, labelCls } from '../../shared/ui'
import { useDisplayCurrency } from '../../shared/currency'
import { FAINT, INCOME, INK, INVESTED, SPEND, UNCATEGORIZED } from '../../shared/theme'
import AccountsCard from './AccountsCard'

type Breakdown = 'category' | 'tag'

/** One wedge of the spending donut, whichever way the month is broken down. */
type Slice = { key: string; name: string; color: string; amount: number; href?: string }

export default function DashboardPage() {
  const [currency, pickCurrency] = useDisplayCurrency()
  const [breakdown, setBreakdown] = useState<Breakdown>('category')
  const { data, isLoading } = useQuery({
    queryKey: ['dashboard', currency],
    queryFn: () => api.dashboard(currency || undefined),
    // Keep the previous currency on screen while the next one loads — switching
    // shouldn't blank the page.
    placeholderData: (prev) => prev,
  })

  if (isLoading || !data) return <p className="py-20 text-center text-sm text-faint">Loading your money…</p>

  const cur = data.currency
  const flow = data.cashflow.map((m) => ({ ...m, label: format(parseISO(m.month + '-01'), 'MMM') }))
  const monthDelta = data.month.net

  const categorySlices: Slice[] = data.spendingByCategory.map((c) => ({
    key: c.categoryId ?? 'uncategorized', name: c.name, color: c.color, amount: c.amount,
  }))
  // Tagged spending, with the untagged remainder as its own wedge so the ring still
  // covers the month. Each tag opens the transactions behind it.
  const tagSlices: Slice[] = [
    ...data.spendingByTag.map((t) => ({
      key: t.tagId, name: `#${t.name}`, color: t.color, amount: t.amount,
      href: `/transactions?tags=${t.tagId}`,
    })),
    ...(data.untaggedSpending > 0
      ? [{ key: 'untagged', name: 'Untagged', color: UNCATEGORIZED, amount: data.untaggedSpending }]
      : []),
  ].sort((a, b) => b.amount - a.amount)
  const donut = topSlices(breakdown === 'category' ? categorySlices : tagSlices)
  const nothingTagged = breakdown === 'tag' && data.spendingByTag.length === 0

  return (
    <div className="flex flex-col gap-5">
      {/* Hero: net worth */}
      <div className="px-1 pt-2">
        <div className="flex items-center justify-between gap-4">
          <p className={labelCls}>Net worth</p>
          <CurrencySwitch value={cur} options={data.availableCurrencies} onChange={pickCurrency} />
        </div>
        <div className="mt-1 flex items-end gap-4">
          <h1 className="font-display text-5xl font-bold tracking-tight tnum">
            {fmtMoney(data.netWorth, cur)}
          </h1>
          <span className="mb-1.5 inline-block h-1 w-14 rounded-full bg-gold" aria-hidden />
        </div>
        <p className="mt-2 text-sm text-muted">
          {monthDelta === 0 ? 'Flat this month' : (
            <>
              <span className={monthDelta > 0 ? 'font-semibold text-income' : 'font-semibold text-ink'}>
                {fmtMoney(monthDelta, cur, { sign: true })}
              </span>{' '}
              left after spending and investing this month
            </>
          )}
        </p>

      </div>

      <AccountsCard rows={data.accounts} currency={cur} />

      {/* Month tiles */}
      <div className="grid grid-cols-4 gap-4">
        <StatTile label="Earned" value={data.month.income} prev={data.prevMonth.income} cur={cur} accent={INCOME} />
        <StatTile label="Spent" value={data.month.expense} prev={data.prevMonth.expense} cur={cur} accent={SPEND} />
        <StatTile label="Invested" value={data.month.invested} prev={data.prevMonth.invested} cur={cur} accent={INVESTED}
          footer={`${fmtMoney(data.allTimeInvested, cur, { decimals: 0 })} all time`} />
        <StatTile label="Net" value={data.month.net} cur={cur} signed
          accent={data.month.net >= 0 ? INCOME : INK} footer="after spending & investing" />
      </div>

      <div className="grid grid-cols-5 gap-4">
        {/* Cashflow */}
        <Card className="col-span-3 pb-3">
          <CardHeader
            title="Cashflow"
            action={
              <span className="flex items-center gap-3 text-xs text-muted">
                <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full" style={{ background: INCOME }} /> Earned</span>
                <span className="flex items-center gap-1.5"><i className="h-2 w-2 rounded-full" style={{ background: SPEND }} /> Spent</span>
              </span>
            }
          />
          <div className="h-56 px-2">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={flow} barGap={3} margin={{ top: 12, right: 12, left: 0, bottom: 0 }}>
                <CartesianGrid vertical={false} stroke="#EEF0F4" />
                <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fill: FAINT, fontSize: 12 }} />
                <YAxis axisLine={false} tickLine={false} tick={{ fill: FAINT, fontSize: 11 }} width={54}
                  tickFormatter={(v: number) => (v >= 1000 ? `${Math.round(v / 1000)}k` : `${v}`)} />
                <Tooltip cursor={{ fill: INK, opacity: 0.04 }} content={<FlowTip cur={cur} />} />
                <Bar dataKey="income" name="Earned" fill={INCOME} radius={[4, 4, 0, 0]} maxBarSize={18} isAnimationActive={false} />
                <Bar dataKey="expense" name="Spent" fill={SPEND} radius={[4, 4, 0, 0]} maxBarSize={18} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>

        {/* Spending, by category or by tag */}
        <Card className="col-span-2 pb-4">
          <CardHeader
            title="Spending"
            action={
              <Segmented
                value={breakdown}
                options={[{ value: 'category', label: 'Categories' }, { value: 'tag', label: 'Tags' }]}
                onChange={(v) => setBreakdown(v as Breakdown)}
                label="Break spending down by"
              />
            }
          />
          {nothingTagged ? (
            <p className="px-5 py-10 text-center text-sm text-faint">
              Nothing tagged this month. Tags are free-form labels — open a{' '}
              <Link to="/transactions" className="font-medium text-ink underline">transaction</Link> to add one.
            </p>
          ) : donut.length === 0 ? (
            <p className="px-5 py-10 text-center text-sm text-faint">No spending yet this month.</p>
          ) : (
            <>
              <div className="relative mx-auto h-40 w-40">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={donut} dataKey="amount" nameKey="name" innerRadius={54} outerRadius={72}
                      paddingAngle={2} strokeWidth={0} isAnimationActive={false}>
                      {donut.map((c) => <Cell key={c.key} fill={c.color} />)}
                    </Pie>
                    <Tooltip content={<DonutTip cur={cur} />} />
                  </PieChart>
                </ResponsiveContainer>
                <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                  <span className="text-[10px] uppercase tracking-wide text-faint">This month</span>
                  <span className="tnum font-display text-[15px] font-bold">
                    {fmtMoney(data.month.expense, cur, { decimals: 0 })}
                  </span>
                </div>
              </div>
              <ul className="mt-2 flex flex-col gap-1 px-5">
                {donut.map((c) => (
                  <li key={c.key}>
                    <SliceRow slice={c} cur={cur} />
                  </li>
                ))}
              </ul>
              {breakdown === 'tag' && data.multiTagCount > 0 && (
                <p className="px-5 pt-2 text-[11px] text-faint">
                  {data.multiTagCount} transaction{data.multiTagCount === 1 ? '' : 's'} carr
                  {data.multiTagCount === 1 ? 'ies' : 'y'} more than one tag, so these slices overlap.
                </p>
              )}
            </>
          )}
        </Card>
      </div>

      {/* Recent activity */}
      <Card className="pb-2">
        <CardHeader
          title="Recent activity"
          action={<Link to="/transactions" className="text-sm font-medium text-muted hover:text-ink">See all</Link>}
        />
        <div className="px-2 pb-2">
          {data.recent.length === 0 ? (
            <p className="px-3 py-8 text-center text-sm text-faint">
              No transactions yet. Connect a bank in <Link to="/settings" className="font-medium text-ink underline">Settings</Link> or add one manually.
            </p>
          ) : (
            data.recent.map((tx) => <TxRow key={tx.id} tx={tx} />)
          )}
        </div>
      </Card>
    </div>
  )
}

/** Six wedges plus an "Other" catch-all — more than that and the ring stops being readable. */
function topSlices(slices: Slice[], limit = 6): Slice[] {
  if (slices.length <= limit) return slices
  const rest = slices.slice(limit).reduce((sum, s) => sum + s.amount, 0)
  return [...slices.slice(0, limit), { key: 'other', name: 'Other', color: UNCATEGORIZED, amount: +rest.toFixed(2) }]
}

/** A legend line. Tags link to the transactions behind them; categories have nowhere to go yet. */
function SliceRow({ slice, cur }: { slice: Slice; cur: string }) {
  const body = (
    <>
      <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: slice.color }} />
      <span className="truncate text-muted group-hover:text-ink">{slice.name}</span>
      <span className="tnum ml-auto font-medium">{fmtMoney(slice.amount, cur)}</span>
    </>
  )
  const cls = 'flex w-full items-center gap-2 text-sm'
  return slice.href
    ? <Link to={slice.href} className={`group ${cls}`}>{body}</Link>
    : <span className={cls}>{body}</span>
}

function StatTile({ label, value, prev, cur, accent, footer, signed = false }:
  { label: string; value: number; prev?: number; cur: string; accent: string; footer?: string; signed?: boolean }) {
  const diff = prev !== undefined && prev > 0 ? ((value - prev) / prev) * 100 : null
  return (
    <Card className="px-5 py-4">
      <p className={labelCls}>{label}</p>
      <p className="mt-1.5 font-display text-2xl font-bold tnum" style={{ color: accent }}>
        {fmtMoney(value, cur, { sign: signed })}
      </p>
      <p className="mt-1 text-xs text-faint">
        {footer ?? (diff === null ? 'no data last month' : `${diff >= 0 ? '+' : ''}${diff.toFixed(0)}% vs last month`)}
      </p>
    </Card>
  )
}

type TipProps = { active?: boolean; payload?: { name: string; value: number; payload: { label?: string; name?: string } }[] }

function FlowTip({ active, payload, cur }: TipProps & { cur: string }) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-xl border border-line bg-surface px-3 py-2 text-xs shadow-pop">
      <p className="mb-1 font-semibold">{payload[0].payload.label}</p>
      {payload.map((p) => (
        <p key={p.name} className="tnum text-muted">{p.name}: <span className="font-medium text-ink">{fmtMoney(p.value, cur)}</span></p>
      ))}
    </div>
  )
}

function DonutTip({ active, payload, cur }: TipProps & { cur: string }) {
  if (!active || !payload?.length) return null
  const p = payload[0]
  return (
    <div className="rounded-xl border border-line bg-surface px-3 py-2 text-xs shadow-pop">
      <span className="font-semibold">{p.payload.name}</span>{' '}
      <span className="tnum text-muted">{fmtMoney(p.value, cur)}</span>
    </div>
  )
}
