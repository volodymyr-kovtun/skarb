import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { endOfMonth, format, startOfMonth, startOfYear, subMonths } from 'date-fns'
import { Pencil } from 'lucide-react'
import { api, fmtMoney, refreshAll, type Tag, type TagSummaryRow } from '../../shared/api'
import {
  CATEGORY_COLORS, Card, ColorPicker, CurrencySwitch, Modal, ModalActions, Segmented,
  errMsg, fieldLabelCls, inputCls,
} from '../../shared/ui'
import { useDisplayCurrency } from '../../shared/currency'

type Period = 'month' | 'last' | 'year' | 'all'

const PERIODS: { value: Period; label: string }[] = [
  { value: 'month', label: 'This month' },
  { value: 'last', label: 'Last month' },
  { value: 'year', label: 'This year' },
  { value: 'all', label: 'All time' },
]

const day = (d: Date) => format(d, 'yyyy-MM-dd')

/** Both ends are inclusive days, matching what the API does with from/to. */
function range(period: Period): { from?: string; to?: string } {
  const now = new Date()
  switch (period) {
    case 'month': return { from: day(startOfMonth(now)) }
    case 'last': {
      const prev = subMonths(now, 1)
      return { from: day(startOfMonth(prev)), to: day(endOfMonth(prev)) }
    }
    case 'year': return { from: day(startOfYear(now)) }
    case 'all': return {}
  }
}

export default function TagsPage() {
  const [currency, pickCurrency] = useDisplayCurrency()
  const [period, setPeriod] = useState<Period>('month')
  const [editing, setEditing] = useState<Tag | null>(null)
  const params = useMemo(() => ({ ...range(period), currency: currency || undefined }), [period, currency])

  const { data } = useQuery({
    queryKey: ['tag-summary', params],
    queryFn: () => api.tagSummary(params),
    placeholderData: (prev) => prev,
  })

  const rows = data?.tags ?? []
  const spentTotal = rows.reduce((sum, r) => sum + r.spent, 0)
  // Bars are read against the biggest tag, not the total — with a handful of tags
  // shares of the total are all short stubs and compare badly.
  const widest = Math.max(...rows.map((r) => r.spent), 0)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-start justify-between gap-4 px-1 pt-2">
        <div>
          <h1 className="font-display text-2xl font-bold tracking-tight">Tags</h1>
          <p className="mt-1 text-sm text-muted">
            What each label costs you. Pick one to see the transactions behind it.
          </p>
        </div>
        {data && <CurrencySwitch value={data.currency} options={data.availableCurrencies} onChange={pickCurrency} />}
      </div>

      <div className="flex items-center justify-between gap-4 px-1">
        <Segmented
          value={period}
          options={PERIODS}
          onChange={(v) => setPeriod(v as Period)}
          label="Period"
        />
        {data && spentTotal > 0 && (
          <p className="text-sm text-muted">
            <span className="tnum font-semibold text-ink">{fmtMoney(spentTotal, data.currency)}</span> tagged
          </p>
        )}
      </div>

      <Card className="px-2 py-2">
        {rows.length === 0 ? (
          <p className="px-3 py-10 text-center text-sm text-faint">
            No tags yet. Open a{' '}
            <Link to="/transactions" className="font-medium text-ink underline">transaction</Link>{' '}
            and add one — they are free-form labels like <span className="font-medium">#vacation</span> or{' '}
            <span className="font-medium">#renovation</span>.
          </p>
        ) : (
          rows.map((row) => (
            <TagRow
              key={row.tag.id}
              row={row}
              currency={data!.currency}
              share={widest > 0 ? row.spent / widest : 0}
              onEdit={() => setEditing(row.tag)}
            />
          ))
        )}
      </Card>

      {data && data.untagged.transactionCount > 0 && (
        <p className="px-1 pb-4 text-xs text-faint">
          <span className="tnum font-medium text-muted">{fmtMoney(data.untagged.spent, data.currency)}</span>{' '}
          of spending across {data.untagged.transactionCount} transaction
          {data.untagged.transactionCount === 1 ? '' : 's'} carries no tag.
          {' '}Tag totals overlap: a transaction wearing two tags counts under both.
        </p>
      )}

      {editing && (
        <TagForm tag={editing} onClose={() => setEditing(null)} onSaved={() => setEditing(null)} />
      )}
    </div>
  )
}

function TagRow({ row, currency, share, onEdit }:
  { row: TagSummaryRow; currency: string; share: number; onEdit: () => void }) {
  const { tag, spent, earned, invested, transactionCount } = row
  const extras = [
    earned > 0 ? `+${fmtMoney(earned, currency)} in` : '',
    invested !== 0 ? `${fmtMoney(invested, currency)} invested` : '',
  ].filter(Boolean)

  return (
    <div className="group relative flex items-center gap-3 rounded-xl px-3 py-2.5 transition-colors hover:bg-paper">
      {share > 0 && (
        // Bars stop short of the amount column, so the number is never read through a tint.
        <span
          className="pointer-events-none absolute inset-y-1 left-1 rounded-lg"
          style={{ width: `${(share * 68).toFixed(1)}%`, background: tag.color + '1f' }}
          aria-hidden
        />
      )}
      <Link
        to={`/transactions?tags=${tag.id}`}
        className="relative flex min-w-0 flex-1 items-center gap-3"
      >
        <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: tag.color }} />
        <span className="min-w-0">
          <span className="block truncate text-sm font-medium">#{tag.name}</span>
          <span className="block truncate text-xs text-faint">
            {transactionCount === 0
              ? 'unused in this period'
              : `${transactionCount} transaction${transactionCount === 1 ? '' : 's'}`}
            {extras.length > 0 && ` · ${extras.join(' · ')}`}
          </span>
        </span>
      </Link>
      <span className={`tnum relative text-sm font-semibold ${spent > 0 ? '' : 'text-faint'}`}>
        {fmtMoney(spent, currency)}
      </span>
      <button
        onClick={onEdit}
        aria-label={`Edit #${tag.name}`}
        className="relative rounded-lg p-1 text-faint opacity-0 transition-opacity hover:text-ink focus-visible:opacity-100 group-hover:opacity-100"
      >
        <Pencil size={14} />
      </button>
    </div>
  )
}

function TagForm({ tag, onClose, onSaved }: { tag: Tag; onClose: () => void; onSaved: () => void }) {
  const qc = useQueryClient()
  const [name, setName] = useState(tag.name)
  const [color, setColor] = useState(tag.color)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      await api.updateTag(tag.id, { name: name.trim(), color })
      refreshAll(qc)
      onSaved()
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!confirm(`Delete #${tag.name}? Transactions keep their history, they just lose the label.`)) return
    await api.deleteTag(tag.id)
    refreshAll(qc)
    onSaved()
  }

  return (
    <Modal title={`Edit #${tag.name}`} onClose={onClose}>
      <div className="flex flex-col gap-3">
        <label className="text-sm">
          <span className={fieldLabelCls}>Name</span>
          <input className={inputCls} value={name} onChange={(e) => setName(e.target.value)} autoFocus />
        </label>
        <div className="text-sm">
          <span className={fieldLabelCls}>Color</span>
          <ColorPicker colors={CATEGORY_COLORS} value={color} onChange={setColor} />
        </div>
        {error && <p className="text-sm text-danger">{error}</p>}
        <ModalActions busy={busy} onCancel={onClose} onSave={save} onDelete={remove} />
      </div>
    </Modal>
  )
}
