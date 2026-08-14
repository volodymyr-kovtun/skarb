import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { api, type CategoryKind, type CategoryWithCount } from '../../shared/api'
import { Card, CardHeader, Modal, btnGhost, btnPrimary, inputCls } from '../../shared/ui'

const COLORS = [
  '#22C55E', '#F97316', '#3B82F6', '#EC4899', '#8B5CF6', '#06B6D4',
  '#EF4444', '#EAB308', '#14B8A6', '#6366F1', '#94A3B8', '#64748B',
  '#10B981', '#84CC16', '#F59E0B', '#B45309', '#A16207', '#131B2E',
]

const KIND_META: Record<CategoryKind, { title: string; blurb: string }> = {
  expense: { title: 'Spending', blurb: 'Day-to-day money out — counted as spending.' },
  income: { title: 'Income', blurb: 'Money coming in — salary, freelance, cashback.' },
  investment: { title: 'Investments', blurb: 'Contributions to brokers or savings — tracked as "Invested", never as spending.' },
}

export default function CategoriesPage() {
  const qc = useQueryClient()
  const { data: categories } = useQuery({ queryKey: ['categories'], queryFn: api.categories })
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })
  const [editing, setEditing] = useState<CategoryWithCount | null>(null)
  const [adding, setAdding] = useState<CategoryKind | null>(null)
  const refresh = () => ['categories', 'meta', 'dashboard', 'transactions', 'rules']
    .forEach((k) => qc.invalidateQueries({ queryKey: [k] }))

  return (
    <div className="flex flex-col gap-4">
      <div className="px-1 pt-2">
        <h1 className="font-display text-2xl font-bold tracking-tight">Categories</h1>
        <p className="mt-1 text-sm text-muted">
          How your money gets labeled. New bank transactions are categorized automatically by your rules and card codes.
        </p>
      </div>

      {(['expense', 'investment', 'income'] as CategoryKind[]).map((kind) => {
        const items = (categories ?? []).filter((c) => c.kind === kind)
        return (
          <Card key={kind} className="pb-4">
            <CardHeader
              title={KIND_META[kind].title}
              action={
                <button
                  onClick={() => setAdding(kind)}
                  className="flex items-center gap-1 text-sm font-medium text-muted hover:text-ink"
                >
                  <Plus size={14} /> Add
                </button>
              }
            />
            <p className="px-5 pb-2 text-xs text-faint">{KIND_META[kind].blurb}</p>
            <div className="grid grid-cols-3 gap-2 px-5">
              {items.map((c) => (
                <button
                  key={c.id}
                  onClick={() => setEditing(c)}
                  className="flex items-center gap-2.5 rounded-xl border border-line px-3 py-2.5 text-left transition-colors hover:border-ink"
                >
                  <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm"
                    style={{ background: c.color + '22' }}>{c.emoji}</span>
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-medium">{c.name}</span>
                    <span className="block text-xs text-faint">
                      {c.transactionCount === 0 ? 'unused' : `${c.transactionCount} transaction${c.transactionCount === 1 ? '' : 's'}`}
                    </span>
                  </span>
                  <span className="ml-auto h-2 w-2 shrink-0 rounded-full" style={{ background: c.color }} />
                </button>
              ))}
              {items.length === 0 && (
                <p className="col-span-3 py-4 text-center text-sm text-faint">No categories yet.</p>
              )}
            </div>
          </Card>
        )
      })}

      <RulesCard />

      {adding && (
        <CategoryForm
          kind={adding}
          onClose={() => setAdding(null)}
          onSaved={() => { setAdding(null); refresh() }}
        />
      )}
      {editing && (
        <CategoryForm
          category={editing}
          kind={editing.kind}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); refresh() }}
        />
      )}
    </div>
  )

  function RulesCard() {
    const { data: rules } = useQuery({ queryKey: ['rules'], queryFn: api.rules })
    const [pattern, setPattern] = useState('')
    const [categoryId, setCategoryId] = useState('')

    const add = async () => {
      if (!pattern.trim() || !categoryId) return
      await api.createRule({ pattern: pattern.trim(), categoryId, priority: (rules?.length ?? 0) + 1 })
      setPattern('')
      qc.invalidateQueries({ queryKey: ['rules'] })
    }

    return (
      <Card className="pb-4">
        <CardHeader title="Auto-categorization rules" />
        <div className="px-5 pt-1">
          <p className="mb-3 text-sm text-muted">
            When a new transaction's description contains a keyword, it gets the category automatically —
            e.g. <code className="rounded bg-paper px-1">ibkr</code> → 📈 Brokerage counts as investing.
          </p>
          <div className="flex gap-2">
            <input className={inputCls} placeholder='Keyword, e.g. "zabka"' value={pattern} onChange={(e) => setPattern(e.target.value)} />
            <select className={inputCls + ' w-56'} value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">Pick category…</option>
              {(meta?.categories ?? []).map((c) => <option key={c.id} value={c.id}>{c.emoji} {c.name}</option>)}
            </select>
            <button className={btnPrimary} onClick={add} disabled={!pattern.trim() || !categoryId}>Add</button>
          </div>
          {(rules ?? []).length > 0 && (
            <ul className="mt-3 flex flex-col">
              {rules!.map((r) => (
                <li key={r.id} className="flex items-center gap-2 border-b border-line py-2 text-sm last:border-0">
                  <code className="rounded-md bg-paper px-2 py-0.5 text-xs">{r.pattern}</code>
                  <span className="text-faint">→</span>
                  <span>{r.category.emoji} {r.category.name}</span>
                  <button className="ml-auto text-xs text-faint hover:text-danger"
                    onClick={async () => { await api.deleteRule(r.id); qc.invalidateQueries({ queryKey: ['rules'] }) }}>
                    remove
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </Card>
    )
  }
}

function CategoryForm({ category, kind: initialKind, onClose, onSaved }:
  { category?: CategoryWithCount; kind: CategoryKind; onClose: () => void; onSaved: () => void }) {
  const isEdit = !!category
  const [name, setName] = useState(category?.name ?? '')
  const [emoji, setEmoji] = useState(category?.emoji ?? '🏷️')
  const [color, setColor] = useState(category?.color ?? COLORS[0])
  const [kind, setKind] = useState<CategoryKind>(initialKind)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      if (!name.trim()) { setError('Name is required.'); return }
      if (isEdit) await api.updateCategory(category!.id, { name: name.trim(), emoji, color, kind })
      else await api.createCategory({ name: name.trim(), emoji, color, kind })
      onSaved()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong')
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    const uses = category!.transactionCount
    const warning = uses > 0
      ? `Delete "${category!.name}"? ${uses} transaction${uses === 1 ? '' : 's'} will become uncategorized.`
      : `Delete "${category!.name}"?`
    if (!confirm(warning)) return
    await api.deleteCategory(category!.id)
    onSaved()
  }

  return (
    <Modal title={isEdit ? 'Edit category' : 'New category'} onClose={onClose}>
      <div className="flex flex-col gap-3">
        <div className="grid grid-cols-[64px_1fr] gap-3">
          <label className="text-sm">
            <span className="mb-1 block text-xs font-medium text-muted">Emoji</span>
            <input className={inputCls + ' text-center'} value={emoji} maxLength={4}
              onChange={(e) => setEmoji(e.target.value)} />
          </label>
          <label className="text-sm">
            <span className="mb-1 block text-xs font-medium text-muted">Name</span>
            <input className={inputCls} value={name} onChange={(e) => setName(e.target.value)} placeholder="Coffee" autoFocus />
          </label>
        </div>

        <label className="text-sm">
          <span className="mb-1 block text-xs font-medium text-muted">Type</span>
          <select className={inputCls} value={kind} onChange={(e) => setKind(e.target.value as CategoryKind)}>
            <option value="expense">Spending</option>
            <option value="income">Income</option>
            <option value="investment">Investment — counts as "Invested", not spending</option>
          </select>
        </label>

        <div className="text-sm">
          <span className="mb-1 block text-xs font-medium text-muted">Color</span>
          <div className="flex flex-wrap gap-2">
            {COLORS.map((c) => (
              <button key={c} onClick={() => setColor(c)} aria-label={`Color ${c}`}
                className={`h-7 w-7 rounded-full transition-transform ${color === c ? 'scale-110 ring-2 ring-ink ring-offset-2' : ''}`}
                style={{ background: c }} />
            ))}
          </div>
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <div className="mt-2 flex items-center justify-between">
          {isEdit ? (
            <button className="text-sm font-medium text-danger hover:underline" onClick={remove}>Delete</button>
          ) : <span />}
          <div className="flex gap-2">
            <button className={btnGhost} onClick={onClose}>Cancel</button>
            <button className={btnPrimary} onClick={save} disabled={busy}>{busy ? 'Saving…' : 'Save'}</button>
          </div>
        </div>
      </div>
    </Modal>
  )
}
