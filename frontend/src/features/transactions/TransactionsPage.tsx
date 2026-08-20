import { useEffect, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import { ArrowLeftRight, ChevronDown, Plus, Search, Tag as TagIcon, X } from 'lucide-react'
import { accountLabel, api, refreshAll, type Meta, type Tag, type Tx } from '../../shared/api'
import {
  Card, Modal, ModalActions, TxRow, btnGhost, btnPrimary, dayLabel, errMsg, fieldLabelCls, inputCls, labelCls, pillCls,
} from '../../shared/ui'
import { useIsDark } from '../../shared/theme'
import { swatch } from '../../shared/color'

/** Account and category filters: a native select wearing the same pill as everything else. */
const selectPill =
  'h-11 shrink-0 rounded-full border-r-8 border-transparent bg-surface2 pl-4 text-sm font-semibold text-ink outline-none'

const SPECIAL_FILTERS = {
  uncategorized: '· Uncategorized',
  internal: '🔁 Internal transfers',
  investments: '📈 Investments',
} as const

export default function TransactionsPage() {
  const qc = useQueryClient()
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })

  // Followed in from a link elsewhere: ?account=<id> and ?tags=<id> start the
  // filters where the link pointed.
  const [searchParams] = useSearchParams()
  const [search, setSearch] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [accountId, setAccountId] = useState(() => searchParams.get('account') ?? '')
  const [categoryId, setCategoryId] = useState('')
  const [tagIds, setTagIds] = useState<string[]>(() => searchParams.getAll('tags'))
  const [hideInternal, setHideInternal] = useState(false)
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
    const p: Record<string, string | string[]> = { page: String(page), pageSize: '50' }
    if (debouncedSearch) p.search = debouncedSearch
    if (accountId) p.accountId = accountId
    if (tagIds.length) p.tagIds = tagIds
    if (categoryId === 'uncategorized') p.uncategorized = 'true'
    else if (categoryId === 'internal') p.internalOnly = 'true'
    else if (categoryId === 'investments') p.investmentsOnly = 'true'
    else if (categoryId) p.categoryId = categoryId
    // Asking for internal transfers and hiding them at once would only ever return nothing,
    // so the "internal" filter wins and the toggle sits disabled while it is on.
    if (hideInternal && categoryId !== 'internal') p.hideInternal = 'true'
    return p
  }, [debouncedSearch, accountId, categoryId, tagIds, hideInternal, page])

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
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="font-display text-[30px] font-semibold tracking-[-0.02em]">Transactions</h1>
        <button className={btnPrimary} onClick={() => setAdding(true)}>
          <Plus size={16} />
          Add transaction
        </button>
      </div>

      {/* Filter bar */}
      <Card className="flex flex-wrap items-center gap-2.5 p-3">
        <label className="flex h-11 min-w-[15rem] flex-1 items-center gap-2.5 rounded-full bg-surface2 px-4 transition-shadow focus-within:shadow-[inset_0_0_0_1.5px_var(--sk-accent)]">
          <Search size={17} className="shrink-0 text-faint" />
          <input
            className="h-full w-full min-w-0 bg-transparent text-sm outline-none placeholder:text-faint"
            placeholder="Search description, merchant or note…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {search && (
            <button onClick={() => setSearch('')} aria-label="Clear search" className="shrink-0 text-faint hover:text-ink">
              <X size={15} />
            </button>
          )}
        </label>
        <select
          className={`${selectPill} w-44`}
          value={accountId}
          onChange={(e) => { setAccountId(e.target.value); setPage(1) }}
        >
          <option value="">All accounts</option>
          {meta?.accounts.map((a) => <option key={a.id} value={a.id}>{accountLabel(a)}</option>)}
        </select>
        <select
          className={`${selectPill} w-48`}
          value={categoryId}
          onChange={(e) => { setCategoryId(e.target.value); setPage(1) }}
        >
          <option value="">All categories</option>
          {Object.entries(SPECIAL_FILTERS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          <option disabled>──────────</option>
          {meta?.categories.map((c) => <option key={c.id} value={c.id}>{c.emoji} {c.name}</option>)}
        </select>
        <TagFilter
          tags={meta?.tags ?? []}
          selected={tagIds}
          onChange={(ids) => { setTagIds(ids); setPage(1) }}
        />
        <InternalToggle
          on={hideInternal}
          disabled={categoryId === 'internal'}
          onChange={(v) => { setHideInternal(v); setPage(1) }}
        />
      </Card>

      <Card className="px-4 py-4">
        {groups.length === 0 && (
          <p className="px-3 py-12 text-center text-sm text-faint">Nothing here yet. Adjust filters or add a transaction.</p>
        )}
        {groups.map((g) => (
          <div key={g.day} className="mt-2.5 first:mt-0">
            <p className={`${labelCls} px-3 pb-1.5`}>{dayLabel(g.items[0].occurredAt)}</p>
            {g.items.map((tx) => <TxRow key={tx.id} tx={tx} onClick={() => setEditing(tx)} />)}
          </div>
        ))}
      </Card>

      {data && data.total > data.pageSize && (
        <div className="flex items-center justify-center gap-4 pb-2 text-sm">
          <button className={btnGhost} disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
          <span className="text-[13.5px] text-muted">Page {page} of {totalPages}</span>
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

/** Drops transfers between your own accounts from the list, leaving only real money in and out. */
function InternalToggle({ on, disabled, onChange }:
  { on: boolean; disabled: boolean; onChange: (on: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!on)}
      disabled={disabled}
      aria-pressed={on}
      title={disabled
        ? 'Not available while the internal-transfers filter is on'
        : 'Hide transfers between your own accounts'}
      className={`${pillCls} ${on ? 'bg-accent text-paper hover:text-paper' : ''}`}
    >
      <ArrowLeftRight size={15} />
      Hide internal
    </button>
  )
}

/** Multi-select over the tags in use; picking several shows transactions carrying any of them. */
function TagFilter({ tags, selected, onChange }:
  { tags: Tag[]; selected: string[]; onChange: (ids: string[]) => void }) {
  const [open, setOpen] = useState(false)
  const dark = useIsDark()
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false) }
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('mousedown', onDown)
    window.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('mousedown', onDown)
      window.removeEventListener('keydown', onKey)
    }
  }, [open])

  if (tags.length === 0) return null

  const picked = tags.filter((t) => selected.includes(t.id))
  const label = picked.length === 0 ? 'Tags'
    : picked.length === 1 ? `#${picked[0].name}`
    : `${picked.length} tags`

  return (
    <div className="relative shrink-0" ref={ref}>
      <button
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className={`${pillCls} ${picked.length ? 'bg-accent text-paper hover:text-paper' : ''}`}
      >
        <TagIcon size={15} />
        <span className="max-w-32 truncate">{label}</span>
        <ChevronDown size={15} className={`transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && (
        <div className="absolute right-0 z-30 mt-2 w-64 rounded-card bg-surface p-4 shadow-pop">
          <div className="mb-2.5 flex items-center justify-between">
            <span className="text-xs font-semibold text-muted">Filter by tag</span>
            {picked.length > 0 && (
              <button onClick={() => onChange([])} className="text-xs font-semibold text-muted hover:text-ink">Clear</button>
            )}
          </div>
          <div className="flex max-h-64 flex-wrap gap-1.5 overflow-y-auto">
            {tags.map((t) => {
              const on = selected.includes(t.id)
              return (
                <button
                  key={t.id}
                  onClick={() => onChange(on ? selected.filter((id) => id !== t.id) : [...selected, t.id])}
                  aria-pressed={on}
                  className="rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                  style={on
                    ? { background: swatch(t.color, dark), color: 'var(--sk-paper)' }
                    : { background: 'var(--sk-surface2)', color: 'var(--sk-muted)' }}
                >
                  #{t.name}
                </button>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}

function TxForm({ meta, tx, onClose, onSaved }:
  { meta: Meta; tx?: Tx; onClose: () => void; onSaved: () => void }) {
  const qc = useQueryClient()
  const dark = useIsDark()
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
        <div className="grid grid-cols-2 gap-1 rounded-full bg-surface2 p-1.5">
          {(['expense', 'income'] as const).map((k) => (
            <button
              key={k}
              onClick={() => { setKind(k); setCategoryId('') }}
              className={`rounded-full py-2 text-sm font-semibold transition-colors ${kind === k ? 'bg-surface text-ink shadow-card' : 'text-muted hover:text-ink'}`}
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
          <div className="flex flex-wrap items-center gap-2">
            {meta.tags.map((t) => {
              const on = tagIds.includes(t.id)
              return (
                <button
                  key={t.id}
                  onClick={() => setTagIds((ids) => on ? ids.filter((x) => x !== t.id) : [...ids, t.id])}
                  className="rounded-full px-3 py-1.5 text-xs font-semibold transition-colors"
                  style={on
                    ? { background: swatch(t.color, dark), color: 'var(--sk-paper)' }
                    : { background: 'var(--sk-surface2)', color: 'var(--sk-muted)' }}
                >
                  #{t.name}
                </button>
              )
            })}
            <input
              className="w-28 rounded-full bg-surface2 px-3 py-1.5 text-xs outline-none placeholder:text-faint"
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
              <input type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} className="h-4 w-4 accent-[var(--sk-accent)]" />
              Internal transfer between my own accounts (never counted in stats)
            </label>
            <label className="flex items-center gap-2 text-sm text-muted">
              <input type="checkbox" checked={excluded} onChange={(e) => setExcluded(e.target.checked)} className="h-4 w-4 accent-[var(--sk-accent)]" />
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
