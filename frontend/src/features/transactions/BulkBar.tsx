import { useEffect, useRef, useState, type ReactNode } from 'react'
import { ArrowLeftRight, EyeOff, Shapes, Tag as TagIcon, X } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { type BulkPatch, type Category, type Meta, type Tag } from '../../shared/api'
import { labelCls } from '../../shared/ui'
import { useIsDark } from '../../shared/theme'
import { swatch } from '../../shared/color'

type Panel = 'category' | 'tag' | 'internal' | 'exclude'

const actions: { key: Panel; label: string; icon: LucideIcon }[] = [
  { key: 'category', label: 'Category', icon: Shapes },
  { key: 'tag', label: 'Tag', icon: TagIcon },
  { key: 'internal', label: 'Internal', icon: ArrowLeftRight },
  { key: 'exclude', label: 'Exclude', icon: EyeOff },
]

const kindHeadings: { kind: Category['kind']; label: string }[] = [
  { kind: 'expense', label: 'Spending' },
  { kind: 'income', label: 'Income' },
  { kind: 'investment', label: 'Investments' },
]

/** One choice inside a panel: a full-width row that applies the moment it is picked. */
const choiceCls =
  'flex w-full items-center gap-2.5 rounded-row px-3 py-2.5 text-left text-sm font-semibold ' +
  'transition-colors hover:bg-hover disabled:opacity-50'

/**
 * What a selection can have done to it. It rides at the bottom of the screen — above the phone's
 * tab bar — because that is where a thumb already is after ticking rows, and because the rows
 * being edited stay in view above it instead of under a dialog.
 *
 * Every choice applies on the click that picks it. The selection survives the edit, so filing
 * forty rows and then tagging the same forty is two clicks rather than two selections; an edit
 * that cannot be reversed by its opposite — a category — comes back with an undo instead.
 *
 * @param matching How many transactions the list's current filters match, across every page.
 * @param onApply Receives the edit and the words that finish "12 transactions …" in the toast.
 * @param toast Rendered stacked on top of the bar, which owns this corner while it is up.
 */
export function BulkBar({ count, matching, meta, busy, toast, onApply, onSelectAll, onNewTag, onDone }: {
  count: number; matching: number; meta: Meta; busy: boolean; toast: ReactNode
  onApply: (patch: BulkPatch, done: string) => void
  onSelectAll: () => void
  onNewTag: (name: string) => Promise<Tag>
  onDone: () => void
}) {
  const [panel, setPanel] = useState<Panel | null>(null)
  const ref = useRef<HTMLDivElement>(null)

  // Escape backs out one level at a time: the open panel first, then selection mode itself.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      if (panel) setPanel(null)
      else onDone()
    }
    const onDown = (e: MouseEvent) => {
      if (panel && !ref.current?.contains(e.target as Node)) setPanel(null)
    }
    window.addEventListener('keydown', onKey)
    window.addEventListener('mousedown', onDown)
    return () => {
      window.removeEventListener('keydown', onKey)
      window.removeEventListener('mousedown', onDown)
    }
  }, [panel, onDone])

  const apply = (patch: BulkPatch, done: string) => {
    setPanel(null)
    onApply(patch, done)
  }
  const idle = count === 0 || busy

  return (
    <div
      ref={ref}
      className="pointer-events-none fixed inset-x-0 bottom-[calc(4.75rem+env(safe-area-inset-bottom))] z-40 flex flex-col items-center gap-2 px-3 sm:bottom-6"
    >
      {toast && <div className="pointer-events-auto">{toast}</div>}

      {panel && (
        <div className="pointer-events-auto w-full max-w-sm rounded-card bg-surface p-3 shadow-pop" role="dialog" aria-label={`${panel} for the selection`}>
          {panel === 'category' && <CategoryPanel categories={meta.categories} onPick={apply} />}
          {panel === 'tag' && <TagPanel tags={meta.tags} onPick={apply} onNewTag={onNewTag} />}
          {panel === 'internal' && (
            <TwoWayPanel
              hint="Transfers between your own accounts never count toward any figure. Un-marking one side of a detected pair releases the other too."
              on={{ label: 'Internal transfer', patch: { isInternal: true }, done: 'marked internal' }}
              off={{ label: 'Not a transfer', patch: { isInternal: false }, done: 'no longer internal' }}
              onPick={apply}
            />
          )}
          {panel === 'exclude' && (
            <TwoWayPanel
              hint="For a reimbursement or a correction: the transaction stays in the list and leaves every total."
              on={{ label: 'Exclude from stats', patch: { isExcluded: true }, done: 'excluded from stats' }}
              off={{ label: 'Count again', patch: { isExcluded: false }, done: 'counted again' }}
              onPick={apply}
            />
          )}
        </div>
      )}

      <div className="pointer-events-auto flex w-full max-w-2xl flex-wrap items-center gap-x-3 gap-y-2.5 rounded-card bg-surface px-4 py-3 shadow-pop sm:w-auto sm:flex-nowrap sm:rounded-full sm:py-2.5 sm:pr-2.5 sm:pl-5">
        <div className="flex min-w-0 flex-1 items-center gap-3 sm:flex-none">
          <span className="tnum whitespace-nowrap text-sm font-semibold" aria-live="polite">
            {count} selected
          </span>
          {matching > count && (
            <button
              onClick={onSelectAll}
              disabled={busy}
              className="truncate text-sm font-semibold text-accent hover:underline disabled:opacity-50"
            >
              Select all {matching}
            </button>
          )}
        </div>

        {/* Below `sm` the four actions take a row of their own, at equal widths — the same
            two-rows-rather-than-ragged reasoning as the filter bar above the list. The icon sits
            over its word there, as in the tab bar: side by side, a quarter of a phone's width
            leaves room for "Cat…" and "Excl…", which is no label at all. */}
        <div className="order-3 grid w-full grid-cols-4 gap-1.5 sm:order-none sm:flex sm:w-auto sm:gap-1.5">
          {actions.map(({ key, label, icon: Icon }) => (
            <button
              key={key}
              onClick={() => setPanel(panel === key ? null : key)}
              disabled={idle}
              aria-expanded={panel === key}
              className={`inline-flex h-[3.25rem] flex-col items-center justify-center gap-1 rounded-row text-[11.5px] font-semibold transition-colors disabled:opacity-40 sm:h-10 sm:flex-row sm:gap-1.5 sm:rounded-full sm:px-4 sm:text-sm ${
                panel === key ? 'bg-accent text-paper' : 'bg-surface2 text-muted hover:text-ink'}`}
            >
              <Icon size={15} className="shrink-0" />
              {label}
            </button>
          ))}
        </div>

        <button
          onClick={onDone}
          title="Leave selection mode"
          className="inline-flex h-10 shrink-0 items-center gap-1.5 rounded-full px-3 text-sm font-semibold text-muted transition-colors hover:text-ink"
        >
          <X size={16} />
          Done
        </button>
      </div>
    </div>
  )
}

function CategoryPanel({ categories, onPick }:
  { categories: Category[]; onPick: (patch: BulkPatch, done: string) => void }) {
  return (
    // Every kind is offered whatever was selected: the selection can run across pages the list
    // no longer holds, so there is no telling from here whether it is money in, out, or both.
    <div className="max-h-[min(22rem,50vh)] overflow-y-auto">
      {kindHeadings.map(({ kind, label }) => {
        const inKind = categories.filter((c) => c.kind === kind)
        if (inKind.length === 0) return null
        return (
          <div key={kind} className="mb-1.5">
            <p className={`${labelCls} px-3 pt-2 pb-1`}>{label}</p>
            {inKind.map((c) => (
              <button
                key={c.id}
                className={choiceCls}
                onClick={() => onPick({ categorySet: true, categoryId: c.id }, `filed under ${c.emoji} ${c.name}`)}
              >
                <span aria-hidden>{c.emoji}</span>
                <span className="truncate">{c.name}</span>
              </button>
            ))}
          </div>
        )
      })}
      <button
        className={`${choiceCls} border-t border-line text-muted`}
        onClick={() => onPick({ categorySet: true, categoryId: null }, 'left uncategorized')}
      >
        <span aria-hidden>·</span>
        Uncategorized
      </button>
    </div>
  )
}

function TagPanel({ tags, onPick, onNewTag }: {
  tags: Tag[]
  onPick: (patch: BulkPatch, done: string) => void
  onNewTag: (name: string) => Promise<Tag>
}) {
  const dark = useIsDark()
  // Removing is the undo for a tag that went on by mistake, so it lives one click from adding.
  const [removing, setRemoving] = useState(false)
  const [newTag, setNewTag] = useState('')

  const pick = (t: Tag) => onPick(
    removing ? { removeTagIds: [t.id] } : { addTagIds: [t.id] },
    removing ? `no longer tagged #${t.name}` : `tagged #${t.name}`)

  const create = async () => {
    const name = newTag.trim().toLowerCase()
    if (!name) return
    pick(await onNewTag(name))
  }

  return (
    <div className="p-1">
      <div className="mb-3 grid grid-cols-2 gap-1 rounded-full bg-surface2 p-1">
        {[false, true].map((mode) => (
          <button
            key={String(mode)}
            onClick={() => setRemoving(mode)}
            aria-pressed={removing === mode}
            className={`rounded-full py-1.5 text-xs font-semibold transition-colors ${
              removing === mode ? 'bg-surface text-ink shadow-card' : 'text-muted hover:text-ink'}`}
          >
            {mode ? 'Remove a tag' : 'Add a tag'}
          </button>
        ))}
      </div>
      <div className="flex max-h-56 flex-wrap items-center gap-1.5 overflow-y-auto">
        {tags.map((t) => (
          <button
            key={t.id}
            onClick={() => pick(t)}
            className="rounded-full px-3 py-1.5 text-xs font-semibold transition-opacity hover:opacity-80"
            style={{ background: swatch(t.color, dark), color: 'var(--sk-paper)' }}
          >
            {removing ? '− ' : '+ '}#{t.name}
          </button>
        ))}
        {tags.length === 0 && removing && <p className="px-2 text-xs text-faint">No tags yet.</p>}
        {!removing && (
          <input
            className="w-28 rounded-full bg-surface2 px-3 py-1.5 text-xs outline-none placeholder:text-faint"
            placeholder="+ new tag"
            value={newTag}
            onChange={(e) => setNewTag(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && create()}
          />
        )}
      </div>
    </div>
  )
}

type Way = { label: string; patch: BulkPatch; done: string }

/** A flag and its opposite, offered together — the opposite is the undo. */
function TwoWayPanel({ hint, on, off, onPick }:
  { hint: string; on: Way; off: Way; onPick: (patch: BulkPatch, done: string) => void }) {
  return (
    <div>
      <p className="px-3 pt-2 pb-2 text-xs leading-relaxed text-faint">{hint}</p>
      {[on, off].map((w) => (
        <button key={w.label} className={choiceCls} onClick={() => onPick(w.patch, w.done)}>
          {w.label}
        </button>
      ))}
    </div>
  )
}
