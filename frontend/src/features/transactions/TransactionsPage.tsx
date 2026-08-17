import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { format, parseISO } from 'date-fns'
import { Plus, Search, X } from 'lucide-react'
import { accountLabel, api, refreshAll, type Meta, type Tx } from '../../shared/api'
import { Card, Modal, ModalActions, TxRow, btnGhost, btnPrimary, dayLabel, errMsg, fieldLabelCls, inputCls } from '../../shared/ui'

const SPECIAL_FILTERS = {
  uncategorized: '· Uncategorized',
  internal: '🔁 Internal transfers',
  investments: '📈 Investments',
} as const

export default function TransactionsPage() {
  const qc = useQueryClient()
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })

  const [search, setSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [accountId, setAccountId] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [page, setPage] = useState(1)
  const [editing, setEditing] = useState<Tx | null>(null)
  const [adding, setAdding] = useState(false)

  // Debounce typing so we don't fire a search request per keystroke.
  useEffect(() => {
    const t = setTimeout(() => { setDebouncedSearch(search); setPage(1) }, 300)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search])

  const params = useMemo(() => {
    const p: Record<string, string> = { page: String(page), pageSize: '50' }
    if (debouncedSearch) p.search = debouncedSearch
    if (accountId) p.accountId = accountId
    if (categoryId === 'uncategorized') p.uncategorized = 'true'
    else if (categoryId === 'internal') p.internalOnly = 'true'
    else if (categoryId === 'investments') p.investmentsOnly = 'true'
    else if (categoryId) p.categoryId = categoryId
    return p
  }, [debouncedSearch, accountId, categoryId, page])

  const { data } = useQuery({
    queryKey: ['transactions', params],
    queryFn: () => api.transactions(params),
    placeholderData: (prev) => prev,
  })

  const groups = useMemo(() => {
    const out: { day: string; items: Tx[] }[] = []
    for (const tx of data?.items ?? []) {
      const day = format(parseISO(tx.occurredAt), 'yyyy-MM-dd')
      const last = out[out.length - 1]
      if (last?.day === day) last.items.push(tx)
      else out.push({ day, items: [tx] })
    }
    return out
  }, [data])

  const refresh = () => refreshAll(qc)
  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between px-1 pt-2">
        <h1 className="font-display text-2xl font-bold tracking-tight">Transactions</h1>
        <button className={btnPrimary} onClick={() => setAdding(true)}>
          <Plus size={15} className="mr-1 inline -translate-y-px" />
          Add transaction
        </button>
      </div>

      {/* Filter bar */}
      <Card className="flex items-center gap-2 p-2">
        <label className="flex h-10 min-w-0 flex-1 items-center gap-2.5 rounded-xl bg-paper px-3.5 transition-shadow focus-within:shadow-[inset_0_0_0_1.5px_#131B2E]">
          <Search size={15} className="shrink-0 text-faint" />
          <input
            className="h-full w-full min-w-0 bg-transparent text-sm outline-none placeholder:text-faint"
            placeholder="Search description, merchant or note…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {search && (
            <button onClick={() => setSearch('')} aria-label="Clear search" className="shrink-0 text-faint hover:text-ink">
              <X size={14} />
            </button>
          )}
        </label>
        <select
          className="h-10 w-44 shrink-0 rounded-xl border-r-8 border-transparent bg-paper px-3 text-sm font-medium text-ink outline-none"
          value={accountId}
          onChange={(e) => { setAccountId(e.target.value); setPage(1) }}
        >
          <option value="">All accounts</option>
          {meta?.accounts.map((a) => <option key={a.id} value={a.id}>{accountLabel(a)}</option>)}
        </select>
        <select
          className="h-10 w-48 shrink-0 rounded-xl border-r-8 border-transparent bg-paper px-3 text-sm font-medium text-ink outline-none"
          value={categoryId}
          onChange={(e) => { setCategoryId(e.target.value); setPage(1) }}
        >
          <option value="">All categories</option>
          {Object.entries(SPECIAL_FILTERS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          <option disabled>──────────</option>
          {meta?.categories.map((c) => <option key={c.id} value={c.id}>{c.emoji} {c.name}</option>)}
        </select>
      </Card>

      <Card className="px-2 py-2">
        {groups.length === 0 && (
          <p className="px-3 py-10 text-center text-sm text-faint">Nothing here yet. Adjust filters or add a transaction.</p>
        )}
        {groups.map((g) => (
          <div key={g.day}>
            <p className="px-3 pb-1 pt-3 text-xs font-semibold uppercase tracking-[0.08em] text-faint">
              {dayLabel(g.items[0].occurredAt)}
            </p>
            {g.items.map((tx) => <TxRow key={tx.id} tx={tx} onClick={() => setEditing(tx)} />)}
          </div>
        ))}
      </Card>

      {data && data.total > data.pageSize && (
        <div className="flex items-center justify-center gap-3 pb-4 text-sm">
          <button className={btnGhost} disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
          <span className="text-muted">Page {page} of {totalPages}</span>
          <button className={btnGhost} disabled={page >= totalPages} onClick={() => setPage(page + 1)}>Next</button>
        </div>
      )}

      {adding && meta && (
        <TxForm meta={meta} onClose={() => setAdding(false)} onSaved={() => { setAdding(false); refresh() }} />
      )}
      {editing && meta && (
        <TxForm meta={meta} tx={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); refresh() }} />
      )}
    </div>
  )
}

function TxForm({ meta, tx, onClose, onSaved }:
  { meta: Meta; tx?: Tx; onClose: () => void; onSaved: () => void }) {
  const qc = useQueryClient()
  const isEdit = !!tx
  const [kind, setKind] = useState<'expense' | 'income'>(tx ? (tx.amount > 0 ? 'income' : 'expense') : 'expense')
  const [accountId, setAccountId] = useState(tx?.accountId ?? meta.accounts[0]?.id ?? '')
  const [amount, setAmount] = useState(tx ? String(Math.abs(tx.amount)) : '')
  const [description, setDescription] = useState(tx?.description ?? '')
  const [categoryId, setCategoryId] = useState(tx?.category?.id ?? '')
  const [tagIds, setTagIds] = useState<string[]>(tx?.tags.map((t) => t.id) ?? [])
  const [date, setDate] = useState(tx ? format(parseISO(tx.occurredAt), 'yyyy-MM-dd') : format(new Date(), 'yyyy-MM-dd'))
  const [note, setNote] = useState(tx?.note ?? '')
  const [excluded, setExcluded] = useState(tx?.isExcluded ?? false)
  const [internal, setInternal] = useState(tx?.isInternal ?? false)
  const [newTag, setNewTag] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const account = meta.accounts.find((a) => a.id === accountId)
  // Money out can be an expense or an investment contribution; money in = income categories.
  const cats = meta.categories.filter((c) =>
    kind === 'expense' ? c.kind === 'expense' || c.kind === 'investment' : c.kind === 'income')

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      const signed = (kind === 'expense' ? -1 : 1) * Math.abs(parseFloat(amount || '0'))
      if (!signed || !description.trim() || !accountId) {
        setError('Amount, description and account are required.')
        return
      }
      if (isEdit) {
        await api.updateTransaction(tx!.id, {
          description: description.trim(),
          amount: tx!.source === 'manual' ? signed : undefined,
          occurredAt: date + 'T12:00:00Z',
          note,
          isExcluded: excluded,
          isInternal: internal,
          categorySet: true,
          categoryId: categoryId || null,
          tagIds,
        })
      } else {
        await api.createTransaction({
          accountId,
          amount: signed,
          description: description.trim(),
          categoryId: categoryId || null,
          tagIds,
          occurredAt: date + 'T12:00:00Z',
          note: note || null,
        })
      }
      onSaved()
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!confirm('Delete this transaction?')) return
    await api.deleteTransaction(tx!.id)
    onSaved()
  }

  const addTag = async () => {
    const name = newTag.trim().toLowerCase()
    if (!name) return
    const tag = await api.createTag({ name })
    // Update the cached meta immutably instead of mutating the cache object.
    qc.setQueryData<Meta>(['meta'], (old) =>
      old && !old.tags.some((t) => t.id === tag.id) ? { ...old, tags: [...old.tags, tag] } : old)
    setTagIds((ids) => (ids.includes(tag.id) ? ids : [...ids, tag.id]))
    setNewTag('')
  }

  return (
    <Modal title={isEdit ? 'Edit transaction' : 'Add transaction'} onClose={onClose}>
      <div className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-1 rounded-xl bg-paper p-1">
          {(['expense', 'income'] as const).map((k) => (
            <button
              key={k}
              onClick={() => { setKind(k); setCategoryId('') }}
              className={`rounded-lg py-1.5 text-sm font-medium capitalize transition-colors ${kind === k ? 'bg-surface shadow-card' : 'text-muted'}`}
            >
              {k === 'expense' ? 'Money out' : 'Money in'}
            </button>
          ))}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <label className="text-sm">
            <span className={fieldLabelCls}>Amount {account ? `(${account.currency})` : ''}</span>
            <input className={inputCls + ' tnum'} type="number" min="0" step="0.01" value={amount}
              onChange={(e) => setAmount(e.target.value)} placeholder="0.00" autoFocus
              disabled={isEdit && tx!.source !== 'manual'} />
          </label>
          <label className="text-sm">
            <span className={fieldLabelCls}>Date</span>
            <input className={inputCls} type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
        </div>

        <label className="text-sm">
          <span className={fieldLabelCls}>Description</span>
          <input className={inputCls} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Where did the money go?" />
        </label>

        <div className="grid grid-cols-2 gap-3">
          <label className="text-sm">
            <span className={fieldLabelCls}>Account</span>
            <select className={inputCls} value={accountId} onChange={(e) => setAccountId(e.target.value)} disabled={isEdit}>
              {meta.accounts.map((a) => <option key={a.id} value={a.id}>{a.bank ? `${a.bank} · ` : ''}{a.name}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className={fieldLabelCls}>Category</span>
            <select className={inputCls} value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">Uncategorized</option>
              {cats.map((c) => <option key={c.id} value={c.id}>{c.emoji} {c.name}{c.kind === 'investment' ? ' (investment)' : ''}</option>)}
            </select>
          </label>
        </div>

        <div className="text-sm">
          <span className={fieldLabelCls}>Tags</span>
          <div className="flex flex-wrap items-center gap-1.5">
            {meta.tags.map((t) => {
              const on = tagIds.includes(t.id)
              return (
                <button
                  key={t.id}
                  onClick={() => setTagIds((ids) => on ? ids.filter((x) => x !== t.id) : [...ids, t.id])}
                  className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${on ? 'text-white' : 'text-muted hover:text-ink'}`}
                  style={on ? { background: t.color } : { background: '#F4F5F7' }}
                >
                  #{t.name}
                </button>
              )
            })}
            <input
              className="w-24 rounded-full bg-paper px-2.5 py-1 text-xs outline-none placeholder:text-faint"
              placeholder="+ new tag"
              value={newTag}
              onChange={(e) => setNewTag(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && addTag()}
            />
          </div>
        </div>

        <label className="text-sm">
          <span className={fieldLabelCls}>Note</span>
          <input className={inputCls} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optional" />
        </label>

        {isEdit && (
          <>
            <label className="flex items-center gap-2 text-sm text-muted">
              <input type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} className="h-4 w-4 accent-ink" />
              Internal transfer between my own accounts (never counted in stats)
            </label>
            <label className="flex items-center gap-2 text-sm text-muted">
              <input type="checkbox" checked={excluded} onChange={(e) => setExcluded(e.target.checked)} className="h-4 w-4 accent-ink" />
              Exclude from stats for another reason (reimbursement, correction)
            </label>
          </>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}

        <ModalActions busy={busy} saveLabel={isEdit ? 'Save changes' : 'Add transaction'}
          onCancel={onClose} onSave={save} onDelete={isEdit ? remove : undefined} />
      </div>
    </Modal>
  )
}
