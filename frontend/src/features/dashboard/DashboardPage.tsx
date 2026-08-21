import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  PieChart, Pie, Cell, AreaChart, Area,
} from 'recharts'
import { accountLabel, api, fmtMoney } from '../../shared/api'
import {
  Card, CardHeader, CurrencySwitch, Segmented, TxRow, cardPadX, labelCls, quietLinkCls,
} from '../../shared/ui'
import { useDisplayCurrency } from '../../shared/currency'
import {
  PERIODS, formatRange, periodComparison, periodName, periodPhrase, useReportPeriod,
} from '../../shared/period'
import { useChartColors, useIsDark } from '../../shared/theme'
import { swatch } from '../../shared/color'
import AccountsCard from './AccountsCard'

type Breakdown = 'category' | 'tag' | 'account'

/** One wedge of the spending donut, whichever way the month is broken down. */
type Slice = { key: string; name: string; color: string; amount: number; href?: string; hint?: string }

export default function DashboardPage() {
  const [currency, pickCurrency] = useDisplayCurrency()
  const [period, pickPeriod] = useReportPeriod()
  const [breakdown, setBreakdown] = useState<Breakdown>('category')
  const c = useChartColors()
  const dark = useIsDark()
  const { data, isLoading } = useQuery({
    queryKey: ['dashboard', currency, period],
    queryFn: () => api.dashboard(currency || undefined, period),
    // Keep the previous currency and window on screen while the next one loads — switching
    // shouldn't blank the page.
    placeholderData: (prev) => prev,
  })

  if (isLoading || !data) return <p className="py-24 text-center text-sm text-faint">Loading your money…</p>

  const cur = data.currency
  const flow = data.cashflow.map((m) => ({ ...m, label: format(parseISO(m.month + '-01'), 'MMM') }))
  const net = data.totals.net
  // Every label below reads off the window the server answered for, not the pill that was
  // clicked. While a switch is in flight the old figures are still on screen, and they should
  // keep the name they were counted under.
  const shown = data.period.key
  const range = formatRange(data.period.start, data.period.end)
  const comparedWith = `Measured against ${formatRange(data.period.previousStart, data.period.previousEnd)}`
  const phrase = periodPhrase[shown]

  const categorySlices: Slice[] = data.spendingByCategory.map((s) => ({
    key: s.categoryId ?? 'uncategorized', name: s.name, color: s.color, amount: s.amount,
  }))
  // Which account the month left from. The legend is a narrow column, so the account name
  // carries the line and the bank rides along in the hover. Each one opens its transactions.
  const accountSlices: Slice[] = data.spendingByAccount.map((a) => ({
    key: a.accountId, name: a.name, color: a.color, amount: a.amount,
    hint: accountLabel(a), href: `/transactions?account=${a.accountId}`,
  }))
  // Tagged spending, with the untagged remainder as its own wedge so the ring still
  // covers the month. Each tag opens the transactions behind it.
  const tagSlices: Slice[] = [
    ...data.spendingByTag.map((t) => ({
      key: t.tagId, name: `#${t.name}`, color: t.color, amount: t.amount,
      href: `/transactions?tags=${t.tagId}`,
    })),
    ...(data.untaggedSpending > 0
      ? [{ key: 'untagged', name: 'Untagged', color: c.uncategorized, amount: data.untaggedSpending }]
      : []),
  ].sort((a, b) => b.amount - a.amount)
  const donut = topSlices(
    breakdown === 'category' ? categorySlices : breakdown === 'account' ? accountSlices : tagSlices)
  const nothingTagged = breakdown === 'tag' && data.spendingByTag.length === 0

  return (
    <div className="flex flex-col gap-5">
      {/* Hero: net worth */}
      <Card className="flex flex-col gap-7 px-5 py-7 sm:gap-8 sm:px-8 sm:py-9 lg:flex-row lg:items-center lg:justify-between lg:gap-14">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
            <p className={labelCls}>Net worth</p>
            <CurrencySwitch value={cur} options={data.availableCurrencies} onChange={pickCurrency} />
          </div>
          <h1 className="tnum mt-3.5 font-display text-[44px] font-semibold leading-none tracking-[-0.03em] sm:text-[64px]">
            {fmtMoney(data.netWorth, cur)}
          </h1>
          <p className="mt-4 max-w-md text-[15px] leading-relaxed text-muted">
            {net === 0 ? `Flat ${phrase}.` : (
              <>
                <span className={net > 0 ? 'font-bold text-income' : 'font-bold text-ink'}>
                  {fmtMoney(net, cur, { sign: true })}
                </span>{' '}
                left {phrase}, after everything you spent and invested.
              </>
            )}
          </p>
        </div>
        <NetWorthTrend data={data} cur={cur} accent={c.invested} />
      </Card>

      {/* The window the tiles and the spending breakdown below are counted over, and the
          control that moves it. The dates are spelled out because the pill alone doesn't say
          whether "this month" means the whole of it. */}
      <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3 px-1">
        <div className="min-w-0">
          <p className={labelCls}>{periodName[shown]}</p>
          <p className="tnum mt-1.5 text-[13.5px] text-muted">{range}</p>
        </div>
        <Segmented
          value={period}
          options={PERIODS.map((o) => ({ value: o.value, label: o.label }))}
          onChange={pickPeriod}
          label="Report over"
        />
      </div>

      {/* Window tiles */}
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatTile label="Earned" value={data.totals.income} prev={data.previous.income} cur={cur} tone="text-income"
          compare={periodComparison[shown]} compareTitle={comparedWith} />
        <StatTile label="Spent" value={data.totals.expense} prev={data.previous.expense} cur={cur} tone="text-spend"
          compare={periodComparison[shown]} compareTitle={comparedWith} />
        <StatTile label="Invested" value={data.totals.invested} prev={data.previous.invested} cur={cur} tone="text-accent"
          footer={`${fmtMoney(data.allTimeInvested, cur, { decimals: 0 })} all time`} />
        <StatTile label="Net" value={data.totals.net} cur={cur} signed
          tone={data.totals.net >= 0 ? 'text-income' : 'text-ink'} footer="after spending & investing" />
      </div>

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-5">
        {/* Spending, by category, account or tag */}
        <Card className="pb-7 lg:col-span-2">
          <CardHeader
            title="Where it went"
            subtitle={range}
            action={
              <Segmented
                value={breakdown}
                options={[
                  { value: 'category', label: 'Categories' },
                  { value: 'account', label: 'Accounts' },
                  { value: 'tag', label: 'Tags' },
                ]}
                onChange={(v) => setBreakdown(v as Breakdown)}
                label="Break spending down by"
              />
            }
          />
          {nothingTagged ? (
            <p className={`${cardPadX} py-12 text-center text-sm text-faint`}>
              Nothing tagged {phrase}. Tags are free-form labels — open a{' '}
              <Link to="/transactions" className="font-semibold text-ink underline">transaction</Link> to add one.
            </p>
          ) : donut.length === 0 ? (
            <p className={`${cardPadX} py-12 text-center text-sm text-faint`}>Nothing spent {phrase}.</p>
          ) : (
            <div className={`flex flex-col items-center gap-6 sm:flex-row sm:items-center lg:flex-col xl:flex-row ${cardPadX}`}>
              <div className="relative h-[196px] w-[196px] shrink-0">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie data={donut} dataKey="amount" nameKey="name" innerRadius={62} outerRadius={92}
                      paddingAngle={2} strokeWidth={0} isAnimationActive={false}>
                      {donut.map((s) => <Cell key={s.key} fill={swatch(s.color, dark)} />)}
                    </Pie>
                    <Tooltip content={<DonutTip cur={cur} />} />
                  </PieChart>
                </ResponsiveContainer>
                <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                  <span className="text-[11px] text-faint">{periodName[shown]}</span>
                  <span className="tnum mt-1 font-display text-[21px] font-semibold">
                    {fmtMoney(data.totals.expense, cur, { decimals: 0 })}
                  </span>
                </div>
              </div>
              <ul className="flex w-full min-w-0 flex-col gap-2.5">
                {donut.map((s) => (
                  <li key={s.key}>
                    <SliceRow slice={s} cur={cur} dark={dark} />
                  </li>
                ))}
              </ul>
            </div>
          )}
          {breakdown === 'tag' && data.multiTagCount > 0 && (
            <p className={`${cardPadX} pt-4 text-[11px] text-faint`}>
              {data.multiTagCount} transaction{data.multiTagCount === 1 ? '' : 's'} in this window carr
              {data.multiTagCount === 1 ? 'ies' : 'y'} more than one tag, so these slices overlap.
            </p>
          )}
        </Card>

        {/* Cashflow */}
        <Card className="pb-5 lg:col-span-3">
          <CardHeader
            title="In and out"
            subtitle={`Last ${flow.length} months, always up to today`}
            action={
              <span className="flex items-center gap-4 text-[12.5px] text-muted">
                <span className="flex items-center gap-2"><i className="h-2.5 w-2.5 rounded-full bg-income" /> Earned</span>
                <span className="flex items-center gap-2"><i className="h-2.5 w-2.5 rounded-full bg-spend" /> Spent</span>
              </span>
            }
          />
          <div className="h-[232px] px-4">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={flow} barGap={4} margin={{ top: 12, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid vertical={false} stroke={c.grid} />
                <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fill: c.faint, fontSize: 12.5 }} />
                <YAxis axisLine={false} tickLine={false} tick={{ fill: c.faint, fontSize: 11 }} width={54}
                  tickFormatter={(v: number) => (v >= 1000 ? `${(v / 1000).toFixed(v % 1000 === 0 ? 0 : 1)}k` : `${v}`)} />
                <Tooltip cursor={{ fill: c.ink, opacity: 0.05 }} content={<FlowTip cur={cur} />} />
                <Bar dataKey="income" name="Earned" fill={c.income} radius={[7, 7, 0, 0]} maxBarSize={14} isAnimationActive={false} />
                <Bar dataKey="expense" name="Spent" fill={c.spend} radius={[7, 7, 0, 0]} maxBarSize={14} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <AccountsCard rows={data.accounts} currency={cur} />
        </div>

        {/* Recent activity */}
        <Card className="pb-5 lg:col-span-3">
          <CardHeader
            title="Recent activity"
            subtitle={data.recent.length ? `Latest ${data.recent.length}, whenever they happened` : undefined}
            action={<Link to="/transactions" className={quietLinkCls}>See all</Link>}
          />
          <div className="px-4">
            {data.recent.length === 0 ? (
              <p className="px-3 py-10 text-center text-sm text-faint">
                No transactions yet. Connect a bank in <Link to="/settings" className="font-semibold text-ink underline">Settings</Link> or add one manually.
              </p>
            ) : (
              data.recent.map((tx) => <TxRow key={tx.id} tx={tx} />)
            )}
          </div>
        </Card>
      </div>
    </div>
  )
}

/**
 * Where the net worth has been. Skarb does not store historical balances, so the line
 * is walked backwards from today's total through each month's net — it tracks money in
 * and out, not what holdings did on the market.
 */
function NetWorthTrend({ data, cur, accent }: { data: import('../../shared/api').Dashboard; cur: string; accent: string }) {
  const months = data.cashflow
  if (months.length < 2) return null

  const nets = months.map((m) => m.income - m.expense - m.invested)
  const series = months.map((m, i) => ({
    label: format(parseISO(m.month + '-01'), 'MMM'),
    // Everything earned after month i has to come back off today's total.
    value: data.netWorth - nets.slice(i + 1).reduce((sum, n) => sum + n, 0),
  }))
  const values = series.map((p) => p.value)
  const lo = Math.min(...values)
  const hi = Math.max(...values)
  const pad = (hi - lo || Math.abs(hi) || 1) * 0.35

  return (
    <div className="w-full shrink-0 lg:w-[420px]">
      <div className="h-[124px]">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={series} margin={{ top: 6, right: 16, left: 16, bottom: 0 }}>
            <defs>
              <linearGradient id="nwFade" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={accent} stopOpacity={0.22} />
                <stop offset="100%" stopColor={accent} stopOpacity={0} />
              </linearGradient>
            </defs>
            <YAxis hide domain={[lo - pad, hi + pad]} />
            <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fill: 'currentColor', fontSize: 11 }}
              className="text-faint" height={18} />
            <Tooltip content={<TrendTip cur={cur} />} />
            <Area type="monotone" dataKey="value" stroke={accent} strokeWidth={2.5} fill="url(#nwFade)"
              dot={false} activeDot={{ r: 4, fill: accent, strokeWidth: 0 }} isAnimationActive={false} />
          </AreaChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-1 text-center text-[11px] text-faint">
        Traced back through {months.length} months of cashflow
      </p>
    </div>
  )
}

/** Six wedges plus an "Other" catch-all — more than that and the ring stops being readable. */
function topSlices(slices: Slice[], limit = 6): Slice[] {
  if (slices.length <= limit) return slices
  const rest = slices.slice(limit).reduce((sum, s) => sum + s.amount, 0)
  return [...slices.slice(0, limit), { key: 'other', name: 'Other', color: '#91897C', amount: +rest.toFixed(2) }]
}

/** A legend line. Accounts and tags link to the transactions behind them; categories have nowhere to go yet. */
function SliceRow({ slice, cur, dark }: { slice: Slice; cur: string; dark: boolean }) {
  const body = (
    <>
      <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: swatch(slice.color, dark) }} />
      <span className="truncate text-muted group-hover:text-ink">{slice.name}</span>
      <span className="tnum ml-auto shrink-0 font-semibold">{fmtMoney(slice.amount, cur)}</span>
    </>
  )
  const cls = 'flex w-full items-center gap-2.5 text-[13.5px]'
  // Long names truncate in this column — the full one is always a hover away.
  const title = slice.hint ?? slice.name
  return slice.href
    ? <Link to={slice.href} title={title} className={`group ${cls}`}>{body}</Link>
    : <span className={cls} title={title}>{body}</span>
}

function StatTile({ label, value, prev, cur, tone, footer, compare, compareTitle, signed = false }: {
  label: string; value: number; prev?: number; cur: string; tone: string; footer?: string
  /** How the comparison window relates to this one — "on the same days last month". */
  compare?: string
  /** The comparison window's own dates, for anyone who wants them exactly. */
  compareTitle?: string
  signed?: boolean
}) {
  const diff = prev !== undefined && prev > 0 ? ((value - prev) / prev) * 100 : null
  return (
    <Card className="px-6 py-6">
      <p className={labelCls}>{label}</p>
      <p className={`tnum mt-3 font-display text-[27px] font-semibold leading-none ${tone}`}>
        {fmtMoney(value, cur, { sign: signed })}
      </p>
      {/* The window behind this percentage runs exactly as long as the one above it, so a month
          three weeks in is not read against a whole one and reported as a collapse. */}
      <p className="mt-2.5 text-[13px] text-faint" title={footer ? undefined : compareTitle}>
        {footer ?? (diff === null
          ? 'nothing to compare with'
          : `${diff >= 0 ? '+' : '−'}${Math.abs(diff).toFixed(0)}% ${compare}`)}
      </p>
    </Card>
  )
}

const tipCls = 'rounded-row bg-surface px-3.5 py-2.5 text-xs shadow-pop'

type TipProps = { active?: boolean; payload?: { name: string; value: number; payload: { label?: string; name?: string } }[] }

function FlowTip({ active, payload, cur }: TipProps & { cur: string }) {
  if (!active || !payload?.length) return null
  return (
    <div className={tipCls}>
      <p className="mb-1 font-semibold">{payload[0].payload.label}</p>
      {payload.map((p) => (
        <p key={p.name} className="tnum text-muted">{p.name}: <span className="font-semibold text-ink">{fmtMoney(p.value, cur)}</span></p>
      ))}
    </div>
  )
}

function DonutTip({ active, payload, cur }: TipProps & { cur: string }) {
  if (!active || !payload?.length) return null
  const p = payload[0]
  return (
    <div className={tipCls}>
      <span className="font-semibold">{p.payload.name}</span>{' '}
      <span className="tnum text-muted">{fmtMoney(p.value, cur)}</span>
    </div>
  )
}

function TrendTip({ active, payload, cur }: TipProps & { cur: string }) {
  if (!active || !payload?.length) return null
  return (
    <div className={tipCls}>
      <p className="mb-0.5 font-semibold">{payload[0].payload.label}</p>
      <p className="tnum text-muted">≈ {fmtMoney(payload[0].value, cur)}</p>
    </div>
  )
}
