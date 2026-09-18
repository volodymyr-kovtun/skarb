import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import { ArrowLeftRight, Check, ChevronDown, ListChecks, Plus, RotateCcw, Search, Tag as TagIcon, X } from 'lucide-react'
import {
  accountLabel, api, fmtMoney, refreshAll, type BulkPatch, type Category, type Meta, type RuleRevert,
  type RuleSuggestion, type Tag, type Tx,
} from '../../shared/api'
import {
  Card, Modal, ModalActions, Toast, TxRow, btnGhost, btnPrimary, dayLabel, errMsg, fieldLabelCls, inputCls,
  labelCls, pageTitleCls, pillCls, pillOnCls,
} from '../../shared/ui'
import { useIsDark } from '../../shared/theme'
import { swatch } from '../../shared/color'
import { CURRENCIES } from '../../shared/currency'
import { BulkBar } from './BulkBar'
import { RuleOfferSheet } from './RuleOfferSheet'

/** Account and category filters: a native select wearing the same pill as everything else. */
const selectPill =
  'h-11 shrink-0 rounded-full border-r-8 border-transparent bg-surface2 pl-4 text-sm font-semibold text-ink outline-none'

/**
 * Below `sm` the filter bar is two controls to a row. Left to size themselves the pills came
 * out ragged — one filter alone on a line, two on the next — which read as a mistake.
 */
const halfWidth = 'w-[calc(50%-0.3125rem)]'

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
  // A category just changed by hand, and what Skarb would make of it. Held here rather than in
  // the editor so the offer outlives the modal that produced it.
  const [offer, setOffer] = useState<{ tx: Tx; category: Category; suggestion: RuleSuggestion } | null>(null)
  // Selection is a set of ids rather than of rows, and deliberately outlives the page and the
  // filters it was made under: search one merchant, tick them, search the next, tick those,
  // then file the lot in one go.
  const [selecting, setSelecting] = useState(false)
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set())
  const [bulkBusy, setBulkBusy] = useState(false)
  const [bulkToast, setBulkToast] = useState<{ ok: boolean; text: string; reverts: RuleRevert[] } | null>(null)
  // Where a shift-click measures its range from.
  const anchor = useRef<string | null>(null)

  // Debounce typing so we don't fire a search request per keystroke.
  useEffect(() => {
    const t = setTimeout(() => { setDebouncedSearch(search); setPage(1) }, 300)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search])

  // The filters on their own, without the page — "select all" asks the same question of the
  // whole ledger that the list asks of fifty rows at a time.
  const filters = useMemo(() => {
    const p: Record<string, string | string[]> = {}
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
  }, [debouncedSearch, accountId, categoryId, tagIds, hideInternal])
  const params = useMemo(() => ({ ...filters, page: String(page), pageSize: '50' }), [filters, page])

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

  const stopSelecting = useCallback(() => {
    setSelecting(false)
    setSelected(new Set())
    setBulkToast(null)
    anchor.current = null
  }, [])

  const toggle = (tx: Tx, e: ReactMouseEvent) => {
    const items = data?.items ?? []
    const from = items.findIndex((t) => t.id === anchor.current)
    const to = items.findIndex((t) => t.id === tx.id)
    setSelected((prev) => {
      const next = new Set(prev)
      // Shift extends from the last row touched, the way every list that has checkboxes does.
      if (e.shiftKey && from >= 0 && to >= 0) {
        for (let i = Math.min(from, to); i <= Math.max(from, to); i++) next.add(items[i].id)
      } else if (!next.delete(tx.id)) {
        next.add(tx.id)
      }
      return next
    })
    anchor.current = tx.id
  }

  const toggleDay = (items: Tx[]) => setSelected((prev) => {
    const next = new Set(prev)
    const all = items.every((t) => next.has(t.id))
    for (const t of items) if (all) next.delete(t.id); else next.add(t.id)
    return next
  })

  const selectAllMatching = async () => {
    setBulkBusy(true)
    try {
      const { ids, total } = await api.transactionIds(filters)
      setSelected(new Set(ids))
      if (total > ids.length)
        setBulkToast({ ok: true, text: `Selected the newest ${ids.length} of ${total} — the rest is one more pass`, reverts: [] })
    } catch (e) {
      setBulkToast({ ok: false, text: errMsg(e), reverts: [] })
    } finally {
      setBulkBusy(false)
    }
  }

  const applyBulk = async (patch: BulkPatch, done: string) => {
    setBulkBusy(true)
    try {
      const { updated, reverts } = await api.bulkUpdateTransactions([...selected], patch)
      refresh()
      setBulkToast({ ok: true, text: `${updated} transaction${updated === 1 ? '' : 's'} ${done}`, reverts })
    } catch (e) {
      setBulkToast({ ok: false, text: errMsg(e), reverts: [] })
    } finally {
      setBulkBusy(false)
    }
  }

  const undoBulk = async (reverts: RuleRevert[]) => {
    setBulkToast(null)
    await api.revertRules(reverts)
    refresh()
  }

  const newTag = async (name: string) => {
    const tag = await api.createTag({ name })
    rememberTag(qc, tag)
    return tag
  }

  /**
   * After a category is set by hand, ask whether it should become a rule. The save has already
   * landed, so this is pure upside: if the suggestion can't be fetched, or there is nothing worth
   * suggesting, the transaction is simply left as corrected.
   */
  const askAboutRule = async (tx: Tx) => {
    if (!tx.category) return
    try {
      const suggestion = await api.ruleSuggestion(tx.id)
      if (suggestion.pattern) setOffer({ tx, category: tx.category, suggestion })
    } catch {
      /* never let the offer get in the way of the edit that already worked */
    }
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3 sm:gap-4">
        <h1 className={pageTitleCls}>Transactions</h1>
        <div className="flex items-center gap-2">
          {/* A mode rather than a checkbox on every row: the rows stay one tap from their editor
              the rest of the time, and a phone has no hover to reveal a checkbox on. */}
          <button
            className={selecting ? btnPrimary : btnGhost}
            onClick={() => (selecting ? stopSelecting() : setSelecting(true))}
            aria-pressed={selecting}
            title="Select several transactions to tag, file, mark internal or exclude at once"
          >
            <ListChecks size={16} />
            Select
          </button>
          <button className={btnPrimary} onClick={() => setAdding(true)}>
            <Plus size={16} />
            {/* The page it sits on already says "transaction"; a phone needs the width more. */}
            Add<span className="hidden sm:inline"> transaction</span>
          </button>
        </div>
      </div>

      {/* Filter bar */}
      <Card className="flex flex-wrap items-center gap-2.5 p-3">
        <label className="flex h-11 w-full items-center gap-2.5 rounded-full bg-surface2 px-4 transition-shadow focus-within:shadow-[inset_0_0_0_1.5px_var(--sk-accent)] sm:w-auto sm:min-w-[15rem] sm:flex-1">
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
          className={`${selectPill} ${halfWidth} sm:w-44`}
          value={accountId}
          onChange={(e) => { setAccountId(e.target.value); setPage(1) }}
        >
          <option value="">All accounts</option>
          {meta?.accounts.map((a) => <option key={a.id} value={a.id}>{accountLabel(a)}</option>)}
        </select>
        <select
          className={`${selectPill} ${halfWidth} sm:w-48`}
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

      {/* `select-none` because a shift-click would otherwise paint the page with a text selection. */}
      <Card className={`px-4 py-4 ${selecting ? 'select-none' : ''}`}>
        {groups.length === 0 && (
          <p className="px-3 py-12 text-center text-sm text-faint">Nothing here yet. Adjust filters or add a transaction.</p>
        )}
        {groups.map((g) => (
          <div key={g.day} className="mt-2.5 first:mt-0">
            <div className="flex items-baseline justify-between gap-3 px-3 pb-1.5">
              <p className={labelCls}>{dayLabel(g.items[0].occurredAt)}</p>
              {selecting && (
                <button onClick={() => toggleDay(g.items)} className="text-xs font-semibold text-muted hover:text-ink">
                  {g.items.every((t) => selected.has(t.id)) ? 'Clear day' : 'Select day'}
                </button>
              )}
            </div>
            {g.items.map((tx) => (
              <TxRow
                key={tx.id}
                tx={tx}
                selected={selecting ? selected.has(tx.id) : undefined}
                onClick={(e) => (selecting ? toggle(tx, e) : setEditing(tx))}
              />
            ))}
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
        <TxForm
          meta={meta}
          tx={editing}
          onClose={() => setEditing(null)}
          onSaved={(recategorized) => { setEditing(null); refresh(); if (recategorized) askAboutRule(recategorized) }}
        />
      )}
      {offer && (
        <RuleOfferSheet
          tx={offer.tx}
          category={offer.category}
          initial={offer.suggestion}
          onClose={() => setOffer(null)}
        />
      )}

      {selecting && meta && (
        <>
          {/* The bar is fixed over the end of the list; this is the room it stands in. */}
          <div className="h-28 sm:h-16" aria-hidden />
          <BulkBar
            count={selected.size}
            matching={data?.total ?? 0}
            meta={meta}
            busy={bulkBusy}
            onApply={applyBulk}
            onSelectAll={selectAllMatching}
            onNewTag={newTag}
            onDone={stopSelecting}
            toast={bulkToast && (
              <Toast inline onClose={() => setBulkToast(null)}>
                {bulkToast.ok
                  ? <Check size={17} className="shrink-0 text-income" />
                  : <X size={17} className="shrink-0 text-danger" />}
                <span>{bulkToast.text}</span>
                {bulkToast.reverts.length > 0 && (
                  <button
                    onClick={() => undoBulk(bulkToast.reverts)}
                    className="ml-1 flex items-center gap-1.5 font-semibold text-accent hover:underline"
                  >
                    <RotateCcw size={14} />
                    Undo
                  </button>
                )}
              </Toast>
            )}
          />
        </>
      )}
    </div>
  )
}

/** Adds a just-created tag to the cached meta — immutably, never by mutating the cache object. */
function rememberTag(qc: ReturnType<typeof useQueryClient>, tag: Tag) {
  qc.setQueryData<Meta>(['meta'], (old) =>
    old && !old.tags.some((t) => t.id === tag.id) ? { ...old, tags: [...old.tags, tag] } : old)
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
      className={`${on ? pillOnCls : pillCls} ${halfWidth} justify-center sm:w-auto`}
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
    <div className={`relative shrink-0 ${halfWidth} sm:w-auto`} ref={ref}>
      <button
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className={`${picked.length ? pillOnCls : pillCls} w-full justify-center sm:w-auto`}
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

/**
 * @param onSaved Receives the saved transaction when this edit changed its category to a new one,
 *   which is what the page needs in order to offer a rule for it.
 */
function TxForm({ meta, tx, onClose, onSaved }:
  { meta: Meta; tx?: Tx; onClose: () => void; onSaved: (recategorized?: Tx) => void }) {
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

  // A withdrawal that was moved to a cash wallet can say what the wallet really got. An empty
  // amount means "what the bank says", which is why a correction is the only thing prefilled.
  const cash = tx?.cash ?? null
  const isWalletSide = tx?.source === 'cash'
  const [cashCurrency, setCashCurrency] = useState(cash?.currency ?? '')
  const [cashAmount, setCashAmount] = useState(cash?.corrected ? String(cash.amount) : '')
  const abroad = !!cash && cashCurrency !== tx!.currency
  const { data: estimate } = useQuery({
    queryKey: ['cash-estimate', tx?.id, cashCurrency],
    queryFn: () => api.cashEstimate(tx!.id, cashCurrency),
    enabled: abroad,
  })

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
      // Only sent when it changed: an untouched block must not freeze today's figure into a
      // correction, or the wallet would stop following the bank's amount when a hold settles.
      const received = cashAmount.trim() === '' ? null : parseFloat(cashAmount)
      const correcting = !!cash && internal &&
        (cashCurrency !== cash.currency || received !== (cash.corrected ? cash.amount : null))
      if (correcting && received !== null && !(received > 0)) {
        setError('The cash you received has to be more than zero.')
        return
      }
      if (isEdit) {
        const saved = await api.updateTransaction(tx!.id, {
          description: description.trim(),
          amount: tx!.source === 'manual' ? signed : undefined,
          occurredAt: date + 'T12:00:00Z',
          note,
          isExcluded: excluded,
          isInternal: internal,
          categorySet: true,
          categoryId: categoryId || null,
          tagIds,
          ...(correcting ? { cashSet: true, cashCurrency, cashAmount: received } : {}),
        })
        // Only a change to a real category is worth generalising — clearing one, or re-saving
        // the category it already had, teaches nothing.
        const changed = !!categoryId && categoryId !== (tx!.category?.id ?? '')
        onSaved(changed && !saved.isInternal ? saved : undefined)
        return
      }

      await api.createTransaction({
        accountId,
        amount: signed,
        description: description.trim(),
        categoryId: categoryId || null,
        tagIds,
        occurredAt: date + 'T12:00:00Z',
        note: note || null,
      })
      onSaved()
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    const question = isWalletSide
      ? 'Delete the wallet side? The withdrawal it belongs to goes back to counting as spending.'
      : cash
        ? 'Delete this withdrawal? The cash it put in your wallet goes with it.'
        : 'Delete this transaction?'
    if (!confirm(question)) return
    await api.deleteTransaction(tx!.id)
    onSaved()
  }

  const addTag = async () => {
    const name = newTag.trim().toLowerCase()
    if (!name) return
    const tag = await api.createTag({ name })
    rememberTag(qc, tag)
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

        {cash && internal && (
          <CashReceived
            tx={tx!}
            wallets={meta.accounts.filter((a) => a.isCash).map((a) => a.currency)}
            currency={cashCurrency}
            amount={cashAmount}
            estimate={abroad ? estimate?.amount : undefined}
            // The figure typed for one currency means nothing in the next, and clearing it is
            // what lets the estimate for the new one show through as the placeholder.
            onCurrency={(c) => { setCashCurrency(c); setCashAmount('') }}
            onAmount={setCashAmount}
          />
        )}

        {isWalletSide && (
          <p className="rounded-row bg-surface2 px-4 py-3 text-[13px] leading-relaxed text-muted">
            The wallet side of a cash withdrawal — Skarb wrote it when the money left the bank.
            To change what you received, open the withdrawal itself. Deleting this row counts the
            withdrawal as spending again.
          </p>
        )}

        {isEdit && !isWalletSide && (
          <>
            <label className="flex items-center gap-2 text-sm text-muted">
              <input type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} className="h-4 w-4 accent-[var(--sk-accent)]" />
              Internal transfer between my own accounts (never counted in stats)
            </label>
            {cash && !internal && (
              <p className="-mt-1.5 pl-6 text-xs leading-relaxed text-faint">
                Saving this takes {fmtMoney(cash.amount, cash.currency)} back out of your cash wallet
                and counts the withdrawal as spending.
              </p>
            )}
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

/**
 * What a cash withdrawal actually put in the wallet. The bank only knows what left the account:
 * a UAH card in an Italian ATM shows hryvnias while the hand holds euros, and the machine's own
 * fee is in the bank's figure without ever reaching the wallet. Neither can be worked out from
 * the statement, so the rate only ever fills the placeholder — the amount is the user's to give.
 *
 * @param estimate Today's-rate guess for another currency: undefined while it loads (or when
 *   the currency is the account's own), null when there is no rate to guess with.
 */
function CashReceived({ tx, wallets, currency, amount, estimate, onCurrency, onAmount }: {
  tx: Tx; wallets: string[]; currency: string; amount: string; estimate: number | null | undefined
  onCurrency: (c: string) => void; onAmount: (a: string) => void
}) {
  const abroad = currency !== tx.currency
  const options = [...new Set([tx.currency, tx.cash!.currency, ...wallets, ...CURRENCIES])]
  const placeholder = !abroad ? Math.abs(tx.amount).toFixed(2)
    : estimate != null ? `≈ ${estimate.toFixed(2)}`
    : 'Amount received'

  return (
    <div className="border-t border-line pt-3">
      <span className={fieldLabelCls}>Cash you received</span>
      <div className="grid grid-cols-[1fr_6.5rem] gap-3">
        <input
          className={inputCls + ' tnum'} type="number" min="0" step="0.01" inputMode="decimal"
          aria-label="Amount received" value={amount} placeholder={placeholder}
          onChange={(e) => onAmount(e.target.value)}
        />
        <select className={inputCls} aria-label="Currency received" value={currency} onChange={(e) => onCurrency(e.target.value)}>
          {options.map((c) => <option key={c}>{c}</option>)}
        </select>
      </div>
      <p className="mt-1.5 text-xs leading-relaxed text-faint">
        {!abroad ? (
          <>
            This withdrawal went to your {currency} cash wallet instead of counting as spending.
            Took it out abroad, or the ATM kept a fee? Say what you were actually handed.
          </>
        ) : (
          <>
            Goes to your {currency} cash wallet{wallets.includes(currency) ? '' : ', which opens with it'}.{' '}
            {estimate === null
              ? 'Skarb has no rate for it, so the amount is yours to fill in.'
              : amount.trim() === '' && estimate !== undefined
                ? `Leave the amount empty to use today's rate — about ${fmtMoney(estimate, currency)} — or type what the ATM really paid out.`
                : 'The rate is only a guess: fees and the bank\u2019s own spread are why the real figure differs.'}
          </>
        )}
      </p>
    </div>
  )
}
