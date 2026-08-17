import { useEffect, type ReactNode } from 'react'
import { X, ArrowLeftRight } from 'lucide-react'
import { fmtMoney, type Category, type Tx } from './api'
import { UNCATEGORIZED } from './theme'
import { format, isToday, isYesterday, parseISO } from 'date-fns'

/** Small-caps section label used by cards, page sections and stat tiles. */
export const labelCls = 'text-[13px] font-semibold uppercase tracking-[0.08em] text-faint'
/** Label above a form input. */
export const fieldLabelCls = 'mb-1 block text-xs font-medium text-muted'

export function errMsg(e: unknown, fallback = 'Something went wrong') {
  return e instanceof Error ? e.message : fallback
}

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-2xl border border-line bg-surface shadow-card ${className}`}>
      {children}
    </section>
  )
}

export function CardHeader({ title, action }: { title: string; action?: ReactNode }) {
  return (
    <header className="flex items-center justify-between px-5 pt-4 pb-1">
      <h2 className={labelCls}>{title}</h2>
      {action}
    </header>
  )
}

export function Money({ amount, currency, signed = false, muted = false, className = '' }:
  { amount: number; currency: string; signed?: boolean; muted?: boolean; className?: string }) {
  const color = muted ? 'text-faint' : signed && amount > 0 ? 'text-income' : 'text-ink'
  return <span className={`tnum ${color} ${className}`}>{fmtMoney(amount, currency, { sign: signed })}</span>
}

export function CategoryDot({ category, size = 'md' }: { category: Category | null; size?: 'sm' | 'md' }) {
  return (
    <span
      className={`flex shrink-0 items-center justify-center rounded-full ${size === 'sm' ? 'h-8 w-8 text-sm' : 'h-9 w-9 text-base'}`}
      style={{ background: (category?.color ?? UNCATEGORIZED) + '22' }}
      aria-hidden
    >
      {category?.emoji ?? '❔'}
    </span>
  )
}

export function Modal({ title, onClose, children, wide = false }:
  { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-ink/40 p-6 backdrop-blur-[2px]" onMouseDown={onClose}>
      <div
        className={`mt-10 w-full ${wide ? 'max-w-2xl' : 'max-w-md'} rounded-2xl bg-surface p-6 shadow-pop`}
        onMouseDown={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="font-display text-lg font-bold">{title}</h2>
          <button onClick={onClose} aria-label="Close" className="rounded-lg p-1 text-muted hover:bg-paper hover:text-ink">
            <X size={18} />
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

export const inputCls =
  'w-full rounded-xl border border-line bg-surface px-3 py-2 text-sm outline-none transition-colors focus:border-ink placeholder:text-faint'
export const btnPrimary =
  'rounded-xl bg-ink px-4 py-2 text-sm font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50'
export const btnGhost =
  'rounded-xl border border-line px-4 py-2 text-sm font-medium text-muted transition-colors hover:border-ink hover:text-ink disabled:opacity-60'

export const ACCOUNT_COLORS = ['#4F46E5', '#0B5FFF', '#059669', '#C29B3C', '#DB2777', '#0891B2', '#131B2E', '#EA580C']
export const CATEGORY_COLORS = [
  '#22C55E', '#F97316', '#3B82F6', '#EC4899', '#8B5CF6', '#06B6D4',
  '#EF4444', '#EAB308', '#14B8A6', '#6366F1', '#94A3B8', '#64748B',
  '#10B981', '#84CC16', '#F59E0B', '#B45309', '#A16207', '#131B2E',
]

export function ColorPicker({ colors, value, onChange }:
  { colors: string[]; value: string; onChange: (c: string) => void }) {
  return (
    <div className="flex flex-wrap gap-2">
      {colors.map((c) => (
        <button key={c} onClick={() => onChange(c)} aria-label={`Color ${c}`}
          className={`h-7 w-7 rounded-full transition-transform ${value === c ? 'scale-110 ring-2 ring-ink ring-offset-2' : ''}`}
          style={{ background: c }} />
      ))}
    </div>
  )
}

/** Standard modal footer: optional delete link, cancel, primary action. */
export function ModalActions({ busy = false, saveLabel = 'Save', onCancel, onSave, onDelete }:
  { busy?: boolean; saveLabel?: string; onCancel: () => void; onSave: () => void; onDelete?: () => void }) {
  return (
    <div className="mt-2 flex items-center justify-between">
      {onDelete ? (
        <button className="text-sm font-medium text-danger hover:underline" onClick={onDelete}>Delete</button>
      ) : <span />}
      <div className="flex gap-2">
        <button className={btnGhost} onClick={onCancel}>Cancel</button>
        <button className={btnPrimary} onClick={onSave} disabled={busy}>
          {busy ? 'Saving…' : saveLabel}
        </button>
      </div>
    </div>
  )
}

export function dayLabel(iso: string) {
  const d = parseISO(iso)
  if (isToday(d)) return 'Today'
  if (isYesterday(d)) return 'Yesterday'
  return format(d, 'EEEE, d MMMM')
}

export function TxRow({ tx, onClick }: { tx: Tx; onClick?: () => void }) {
  const dimmed = tx.isInternal || tx.isExcluded
  return (
    <button
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-paper"
    >
      {tx.isInternal ? (
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-paper text-muted" aria-hidden>
          <ArrowLeftRight size={15} />
        </span>
      ) : (
        <CategoryDot category={tx.category} />
      )}
      <div className="min-w-0 flex-1">
        <p className={`truncate text-sm font-medium ${dimmed ? 'text-muted' : ''}`}>
          {tx.description}
          {tx.isInternal && <span className="ml-2 rounded-md bg-paper px-1.5 py-0.5 text-[11px] font-medium text-faint">internal</span>}
          {tx.isExcluded && <span className="ml-2 rounded-md bg-paper px-1.5 py-0.5 text-[11px] text-faint">excluded</span>}
        </p>
        <p className="mt-0.5 flex items-center gap-1.5 truncate text-xs text-faint">
          <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: tx.accountColor }} />
          {tx.bank || tx.accountName}
          {!tx.isInternal && tx.category && <span>· {tx.category.name}</span>}
          {tx.tags.map((t) => (
            <span key={t.id} className="rounded-md px-1 py-px text-[11px] font-medium" style={{ background: t.color + '1f', color: t.color }}>
              #{t.name}
            </span>
          ))}
        </p>
      </div>
      <Money amount={tx.amount} currency={tx.currency} signed={!dimmed} muted={dimmed} className="text-sm font-semibold" />
    </button>
  )
}
