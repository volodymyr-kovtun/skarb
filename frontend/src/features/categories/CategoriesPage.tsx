import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Search, X } from 'lucide-react'
import { api, refreshAll, type CategoryKind, type CategoryWithCount, type Tag } from '../../shared/api'
import { CATEGORY_COLORS, Card, CardHeader, CategoryDot, ColorPicker, Dot, Modal, ModalActions, btnGhost, btnPrimary, cardPadX, errMsg, fieldLabelCls, inputCls, pageTitleCls, quietLinkCls } from '../../shared/ui'
import { useIsDark } from '../../shared/theme'
import { swatch, tint } from '../../shared/color'

const KIND_META: Record<CategoryKind, { title: string; blurb: string }> = {
  expense: { title: 'Spending', blurb: 'Day-to-day money out — counted as spending.' },
  income: { title: 'Income', blurb: 'Money coming in — salary, freelance, cashback.' },
  investment: { title: 'Investments', blurb: 'Contributions to brokers or savings — tracked as "Invested", never as spending.' },
}

export default function CategoriesPage() {
  const qc = useQueryClient()
  const { data: categories } = useQuery({ queryKey: ['categories'], queryFn: api.categories })
  const [editing, setEditing] = useState<CategoryWithCount | null>(null)
  const [adding, setAdding] = useState<CategoryKind | null>(null)
  const refresh = () => refreshAll(qc)

  return (
    <div className="flex flex-col gap-5">
      <div>
        <h1 className={pageTitleCls}>Categories</h1>
        <p className="mt-2 max-w-2xl text-[14.5px] leading-relaxed text-muted">
          How your money gets labeled. New bank transactions are categorized automatically by your rules and card codes.
        </p>
      </div>

      {(['expense', 'investment', 'income'] as CategoryKind[]).map((kind) => {
        const items = (categories ?? []).filter((c) => c.kind === kind)
        return (
          <Card key={kind} className="pb-7">
            <CardHeader
              title={KIND_META[kind].title}
              action={
                <button onClick={() => setAdding(kind)} className={`${btnGhost} h-8 px-3.5 py-0 text-[13px]`}>
                  <Plus size={15} /> Add
                </button>
              }
            />
            <p className={`${cardPadX} pb-4 text-[13px] text-faint`}>{KIND_META[kind].blurb}</p>
            <div className={`grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4 ${cardPadX}`}>
              {items.map((c) => (
                <button
                  key={c.id}
                  onClick={() => setEditing(c)}
                  className="flex items-center gap-3 rounded-row bg-surface2 px-3 py-2.5 text-left transition-colors hover:bg-hover"
                >
                  <CategoryDot category={c} size="sm" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13.5px] font-semibold">{c.name}</span>
                    <span className="mt-px block text-[12px] text-faint">
                      {c.transactionCount === 0 ? 'unused' : `${c.transactionCount} transaction${c.transactionCount === 1 ? '' : 's'}`}
                    </span>
                  </span>
                  <Dot color={c.color} size={8} />
                </button>
              ))}
              {items.length === 0 && (
                <p className="py-4 text-center text-sm text-faint sm:col-span-2 xl:col-span-4">No categories yet.</p>
              )}
            </div>
          </Card>
        )
      })}

      <TagsCard />

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
}

/**
 * Tags live next to categories because they answer the same question one step finer.
 * Attaching one happens in the transaction editor; this is where they get tidied up,
 * and the overview reports what each one costs.
 */
function TagsCard() {
  const dark = useIsDark()
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })
  const [editing, setEditing] = useState<Tag | null>(null)
  const [adding, setAdding] = useState(false)
  const tags = meta?.tags ?? []

  return (
    <Card className="pb-7">
      <CardHeader
        title="Tags"
        action={
          <button onClick={() => setAdding(true)} className={`${btnGhost} h-8 px-3.5 py-0 text-[13px]`}>
            <Plus size={15} /> Add
          </button>
        }
      />
      <p className={`max-w-3xl pb-4 text-[13px] leading-relaxed text-faint ${cardPadX}`}>
        Free-form labels, finer than a category and stackable — #vacation, #renovation. Attach them
        in the transaction editor; the overview reports what each one costs this month.
      </p>
      <div className={`flex flex-wrap gap-2.5 ${cardPadX}`}>
        {tags.map((t) => (
          <button
            key={t.id}
            onClick={() => setEditing(t)}
            className="rounded-full px-4 py-2 text-[13.5px] font-semibold transition-transform hover:scale-105"
            style={{ background: tint(t.color, dark), color: swatch(t.color, dark) }}
          >
            #{t.name}
          </button>
        ))}
        {tags.length === 0 && <p className="w-full py-2 text-sm text-faint">No tags yet.</p>}
      </div>

      {adding && <TagForm onClose={() => setAdding(false)} onSaved={() => setAdding(false)} />}
      {editing && <TagForm tag={editing} onClose={() => setEditing(null)} onSaved={() => setEditing(null)} />}
    </Card>
  )
}

function TagForm({ tag, onClose, onSaved }: { tag?: Tag; onClose: () => void; onSaved: () => void }) {
  const qc = useQueryClient()
  const [name, setName] = useState(tag?.name ?? '')
  const [color, setColor] = useState(tag?.color ?? CATEGORY_COLORS[0])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      if (!name.trim()) { setError('Give the tag a name.'); return }
      if (tag) await api.updateTag(tag.id, { name: name.trim(), color })
      else await api.createTag({ name: name.trim(), color })
      refreshAll(qc)
      onSaved()
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!confirm(`Delete #${tag!.name}? Its transactions keep their history, they just lose the label.`)) return
    await api.deleteTag(tag!.id)
    refreshAll(qc)
    onSaved()
  }

  return (
    <Modal title={tag ? `Edit #${tag.name}` : 'New tag'} onClose={onClose}>
      <div className="flex flex-col gap-3">
        <label className="text-sm">
          <span className={fieldLabelCls}>Name</span>
          <input className={inputCls} value={name} onChange={(e) => setName(e.target.value)}
            placeholder="vacation" autoFocus />
        </label>
        <div className="text-sm">
          <span className={fieldLabelCls}>Color</span>
          <ColorPicker colors={CATEGORY_COLORS} value={color} onChange={setColor} />
        </div>
        {error && <p className="text-sm text-danger">{error}</p>}
        <ModalActions busy={busy} onCancel={onClose} onSave={save} onDelete={tag ? remove : undefined} />
      </div>
    </Modal>
  )
}

/** Rules shown before "Show more" — the seeded set alone runs to a few hundred. */
const RULES_PAGE = 12

// Top-level component: defining it inside the page would remount it (and drop
// its input state) on every parent render.
function RulesCard() {
  const qc = useQueryClient()
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })
  const { data: rules } = useQuery({ queryKey: ['rules'], queryFn: api.rules })
  const [pattern, setPattern] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [applyMsg, setApplyMsg] = useState('')
  const [search, setSearch] = useState('')
  const [visible, setVisible] = useState(RULES_PAGE)

  const all = rules ?? []
  const query = search.trim().toLowerCase()
  const matches = query
    ? all.filter((r) => r.pattern.toLowerCase().includes(query) || r.category.name.toLowerCase().includes(query))
    : all
  const shown = matches.slice(0, visible)

  // A fresh search starts back at the top of the list.
  const searchFor = (value: string) => {
    setSearch(value)
    setVisible(RULES_PAGE)
  }

  const applyNow = async () => {
    const r = await api.applyRules()
    setApplyMsg(`Categorized ${r.categorized} of ${r.scanned} uncategorized transaction${r.scanned === 1 ? '' : 's'}.`)
    refreshAll(qc)
  }

  const add = async () => {
    if (!pattern.trim() || !categoryId) return
    const added = pattern.trim()
    // No priority: the server sorts a hand-written rule ahead of the seeded ones, which is the
    // only way it can beat a broad default like "supermarket" or "fee".
    await api.createRule({ pattern: added, categoryId })
    setPattern('')
    // A new rule sorts to the bottom of a long list — search for it so it is visible.
    searchFor(added)
    qc.invalidateQueries({ queryKey: ['rules'] })
  }

  return (
    <Card className="pb-7">
      <CardHeader
        title="Auto-categorization rules"
        action={
          <button onClick={applyNow} className={quietLinkCls}>
            Apply to uncategorized
          </button>
        }
      />
      <div className={`${cardPadX} pt-1`}>
        <p className="mb-4 max-w-3xl text-[14px] leading-relaxed text-muted">
          When a new transaction's description contains a keyword, it gets the category automatically —
          e.g. <code className="rounded-md bg-surface2 px-2 py-0.5 text-[12.5px]">ibkr</code> → 📈 Brokerage counts as investing.
          Rules apply to new transactions as they arrive; use <em>Apply to uncategorized</em> to run them
          over existing ones (it only fills blanks). Most rules are easier to make by changing a
          category on a transaction and accepting the offer that follows.
        </p>
        {applyMsg && <p className="mb-4 rounded-row bg-income/10 px-4 py-2.5 text-sm font-medium text-income">{applyMsg}</p>}
        <div className="flex flex-wrap gap-2.5">
          <input className={`${inputCls} min-w-[12rem] flex-1`} placeholder='Keyword, e.g. "zabka"' value={pattern} onChange={(e) => setPattern(e.target.value)} />
          <select className={inputCls + ' w-56 shrink-0'} value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">Pick category…</option>
            {(meta?.categories ?? []).map((c) => <option key={c.id} value={c.id}>{c.emoji} {c.name}</option>)}
          </select>
          <button className={btnPrimary} onClick={add} disabled={!pattern.trim() || !categoryId}>Add</button>
        </div>
        {all.length > 0 && (
          <>
            <label className="mt-5 flex h-11 items-center gap-2.5 rounded-full bg-surface2 px-4 transition-shadow focus-within:shadow-[inset_0_0_0_1.5px_var(--sk-accent)]">
              <Search size={17} className="shrink-0 text-faint" />
              <input
                className="h-full w-full min-w-0 bg-transparent text-sm outline-none placeholder:text-faint"
                placeholder={`Search ${all.length} rules by keyword or category…`}
                value={search}
                onChange={(e) => searchFor(e.target.value)}
              />
              {search && (
                <button onClick={() => searchFor('')} aria-label="Clear search" className="shrink-0 text-faint hover:text-ink">
                  <X size={15} />
                </button>
              )}
            </label>

            {matches.length === 0 ? (
              <p className="py-6 text-center text-sm text-faint">No rule matches “{search.trim()}”.</p>
            ) : (
              <ul className="mt-2 flex flex-col">
                {shown.map((r) => (
                  <li key={r.id} className="flex items-center gap-3 border-b border-line py-2.5 text-[13.5px] last:border-0">
                    <code className="rounded-md bg-surface2 px-2.5 py-1 text-[12.5px]">{r.pattern}</code>
                    <span className="text-faint">→</span>
                    <span>{r.category.emoji} {r.category.name}</span>
                    <button className="ml-auto text-[12.5px] font-semibold text-faint transition-colors hover:text-danger"
                      onClick={async () => { await api.deleteRule(r.id); qc.invalidateQueries({ queryKey: ['rules'] }) }}>
                      remove
                    </button>
                  </li>
                ))}
              </ul>
            )}

            {matches.length > 0 && (
              <div className="mt-4 flex items-center gap-3">
                {shown.length < matches.length && (
                  <button className={`${btnGhost} h-9 px-4 py-0 text-[13px]`} onClick={() => setVisible((v) => v + RULES_PAGE)}>
                    Show more
                  </button>
                )}
                <p className="text-[12.5px] text-faint">
                  Showing {shown.length} of {matches.length}
                  {query && ` matching rule${matches.length === 1 ? '' : 's'}`}
                  {!query && ` rule${matches.length === 1 ? '' : 's'}`}
                </p>
              </div>
            )}
          </>
        )}
      </div>
    </Card>
  )
}

function CategoryForm({ category, kind: initialKind, onClose, onSaved }:
  { category?: CategoryWithCount; kind: CategoryKind; onClose: () => void; onSaved: () => void }) {
  const isEdit = !!category
  const [name, setName] = useState(category?.name ?? '')
  const [emoji, setEmoji] = useState(category?.emoji ?? '🏷️')
  const [color, setColor] = useState(category?.color ?? CATEGORY_COLORS[0])
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
      setError(errMsg(e))
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
            <span className={fieldLabelCls}>Emoji</span>
            <input className={inputCls + ' text-center'} value={emoji} maxLength={4}
              onChange={(e) => setEmoji(e.target.value)} />
          </label>
          <label className="text-sm">
            <span className={fieldLabelCls}>Name</span>
            <input className={inputCls} value={name} onChange={(e) => setName(e.target.value)} placeholder="Coffee" autoFocus />
          </label>
        </div>

        <label className="text-sm">
          <span className={fieldLabelCls}>Type</span>
          <select className={inputCls} value={kind} onChange={(e) => setKind(e.target.value as CategoryKind)}>
            <option value="expense">Spending</option>
            <option value="income">Income</option>
            <option value="investment">Investment — counts as "Invested", not spending</option>
          </select>
        </label>

        <div className="text-sm">
          <span className={fieldLabelCls}>Color</span>
          <ColorPicker colors={CATEGORY_COLORS} value={color} onChange={setColor} />
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <ModalActions busy={busy} onCancel={onClose} onSave={save} onDelete={isEdit ? remove : undefined} />
      </div>
    </Modal>
  )
}
