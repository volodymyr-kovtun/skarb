import { useEffect, type ReactNode } from 'react'
import { X, ArrowLeftRight, Monitor, Moon, Sun } from 'lucide-react'
import { fmtMoney, type Category, type Tx } from './api'
import { setThemeMode, useIsDark, useThemeMode, type ThemeMode } from './theme'
import { swatch, tint } from './color'
import { format, isToday, isYesterday, parseISO } from 'date-fns'

/** The micro-label above a figure — stat tiles, the net-worth hero, day headings. */
export const labelCls = 'text-[11px] font-semibold uppercase tracking-[0.1em] text-faint'
/** The heading on a card. Real titles, not small caps. */
export const sectionTitleCls = 'font-display text-[17px] font-semibold'
/** Label above a form input. */
export const fieldLabelCls = 'mb-1.5 block text-xs font-medium text-muted'

/** Institution an account is grouped under. Manual accounts have no bank of their own. */
export const bankLabel = (a: { bank: string }) => a.bank || 'Manual'

export function errMsg(e: unknown, fallback = 'Something went wrong') {
  return e instanceof Error ? e.message : fallback
}

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <section className={`rounded-card bg-surface shadow-card ${className}`}>{children}</section>
}

export function CardHeader({ title, action }: { title: string; action?: ReactNode }) {
  return (
    <header className="flex items-center justify-between gap-4 px-7 pt-6 pb-3">
      <h2 className={sectionTitleCls}>{title}</h2>
      {action}
    </header>
  )
}

/** The quiet link that sits opposite a card title — "Manage", "See all". */
export const quietLinkCls = 'text-sm font-medium text-muted transition-colors hover:text-accent'

/** Compact pill switcher — display currency, report periods. */
export function Segmented({ value, options, onChange, label, title }:
  { value: string; options: { value: string; label: string }[]; onChange: (v: string) => void; label: string; title?: string }) {
  if (options.length < 2) return null
  return (
    <div className="flex items-center gap-0.5 rounded-full bg-surface2 p-1" role="group" aria-label={label} title={title}>
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          aria-pressed={value === o.value}
          className={`rounded-full px-3 py-1.5 text-xs font-semibold transition-colors ${
            value === o.value ? 'bg-surface text-ink shadow-card' : 'text-muted hover:text-ink'}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

/** Reports a whole page in another currency, converted at today's rates. */
export function CurrencySwitch({ value, options, onChange }:
  { value: string; options: string[]; onChange: (c: string) => void }) {
  return (
    <Segmented
      value={value}
      options={options.map((c) => ({ value: c, label: c }))}
      onChange={onChange}
      label="Display currency"
      title="Converted to this currency at today's rates"
    />
  )
}

export function Money({ amount, currency, signed = false, muted = false, className = '' }:
  { amount: number; currency: string; signed?: boolean; muted?: boolean; className?: string }) {
  const color = muted ? 'text-faint' : signed && amount > 0 ? 'text-income' : 'text-ink'
  return <span className={`tnum ${color} ${className}`}>{fmtMoney(amount, currency, { sign: signed })}</span>
}

/** A category's emoji on a wash of its own color. The wash follows the theme. */
export function CategoryDot({ category, size = 'md' }: { category: Category | null; size?: 'sm' | 'md' }) {
  const dark = useIsDark()
  const color = category?.color ?? '#91897C'
  return (
    <span
      className={`flex shrink-0 items-center justify-center rounded-tile ${size === 'sm' ? 'h-9 w-9 text-[15px]' : 'h-10 w-10 text-[17px]'}`}
      style={{ background: tint(color, dark) }}
      aria-hidden
    >
      {category?.emoji ?? '·'}
    </span>
  )
}

/** A colored dot for legends, account rows and tag lists. */
export function Dot({ color, size = 10, className = '' }: { color: string; size?: number; className?: string }) {
  const dark = useIsDark()
  return (
    <span
      className={`inline-block shrink-0 rounded-full ${className}`}
      style={{ background: swatch(color, dark), height: size, width: size }}
      aria-hidden
    />
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
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-ink/30 p-6 backdrop-blur-[3px]" onMouseDown={onClose}>
      <div
        className={`mt-12 w-full ${wide ? 'max-w-2xl' : 'max-w-md'} rounded-card bg-surface p-7 shadow-pop`}
        onMouseDown={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="mb-5 flex items-center justify-between gap-4">
          <h2 className="font-display text-xl font-semibold tracking-tight">{title}</h2>
          <button onClick={onClose} aria-label="Close" className="rounded-full p-1.5 text-muted transition-colors hover:bg-hover hover:text-ink">
            <X size={18} />
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

export const inputCls =
  'w-full rounded-row bg-surface2 px-4 py-2.5 text-sm text-ink outline-none transition-shadow ' +
  'placeholder:text-faint focus:shadow-[inset_0_0_0_1.5px_var(--sk-accent)]'
export const btnPrimary =
  'inline-flex items-center justify-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-paper ' +
  'transition-opacity hover:opacity-90 disabled:opacity-50'
export const btnGhost =
  'inline-flex items-center justify-center gap-2 rounded-full bg-surface2 px-5 py-2.5 text-sm font-semibold text-muted ' +
  'transition-colors hover:text-ink disabled:opacity-60'
/** A filter control: same height and shape as a button, quieter. */
export const pillCls =
  'inline-flex h-11 shrink-0 items-center gap-2 rounded-full bg-surface2 px-4 text-sm font-semibold text-muted ' +
  'transition-colors hover:text-ink disabled:opacity-40'

/** Round icon button used across the header and card actions. */
export function IconButton({ label, onClick, children, className = '' }:
  { label: string; onClick?: () => void; children: ReactNode; className?: string }) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      className={`flex h-9 w-9 items-center justify-center rounded-full bg-surface2 text-muted transition-colors hover:bg-hover hover:text-ink ${className}`}
    >
      {children}
    </button>
  )
}

/** Cycles light → dark → follow the system, which is also the default. */
export function ThemeToggle() {
  const mode = useThemeMode()
  const next: Record<ThemeMode, ThemeMode> = { light: 'dark', dark: 'system', system: 'light' }
  const icon = mode === 'light' ? <Sun size={16} /> : mode === 'dark' ? <Moon size={16} /> : <Monitor size={16} />
  const label =
    mode === 'light' ? 'Light theme — switch to dark'
    : mode === 'dark' ? 'Dark theme — follow the system instead'
    : 'Following the system — switch to light'
  return <IconButton label={label} onClick={() => setThemeMode(next[mode])}>{icon}</IconButton>
}

/** The eight hues the design is built from, so a picked color always belongs. */
export const ACCOUNT_COLORS = ['#775B88', '#426F50', '#9F4B25', '#546783', '#974D6E', '#456D67', '#7B6230', '#91897C']
export const CATEGORY_COLORS = [
  '#426F50', '#9F4B25', '#546783', '#974D6E', '#775B88', '#456D67',
  '#B0322A', '#7B6230', '#2F7168', '#5A5F9E', '#91897C', '#6B6559',
  '#3F7A5C', '#6B7A38', '#A06A24', '#8A4A20', '#7A5A2A', '#211D18',
]

export function ColorPicker({ colors, value, onChange }:
  { colors: string[]; value: string; onChange: (c: string) => void }) {
  return (
    <div className="flex flex-wrap gap-2">
      {colors.map((c) => (
        <button key={c} onClick={() => onChange(c)} aria-label={`Color ${c}`} type="button"
          className={`h-8 w-8 rounded-full transition-transform ${value === c ? 'scale-110 ring-2 ring-ink ring-offset-2 ring-offset-surface' : ''}`}
          style={{ background: c }} />
      ))}
    </div>
  )
}

/** Standard modal footer: optional delete link, cancel, primary action. */
export function ModalActions({ busy = false, saveLabel = 'Save', onCancel, onSave, onDelete }:
  { busy?: boolean; saveLabel?: string; onCancel: () => void; onSave: () => void; onDelete?: () => void }) {
  return (
    <div className="mt-3 flex items-center justify-between gap-3">
      {onDelete ? (
        <button className="text-sm font-semibold text-danger hover:underline" onClick={onDelete}>Delete</button>
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
  const dark = useIsDark()
  const dimmed = tx.isInternal || tx.isExcluded
  return (
    <button
      onClick={onClick}
      className="flex w-full items-center gap-3.5 rounded-row px-3 py-2.5 text-left transition-colors hover:bg-hover"
    >
      {tx.isInternal ? (
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-tile bg-surface2 text-faint" aria-hidden>
          <ArrowLeftRight size={17} />
        </span>
      ) : (
        <CategoryDot category={tx.category} />
      )}
      <div className="min-w-0 flex-1">
        <p className={`flex items-center gap-2 truncate text-[14.5px] font-semibold ${dimmed ? 'text-muted' : ''}`}>
          <span className="truncate">{tx.description}</span>
          {tx.isInternal && <span className="shrink-0 rounded-full bg-surface2 px-2.5 py-0.5 text-[11px] font-semibold text-faint">internal</span>}
          {tx.isExcluded && <span className="shrink-0 rounded-full bg-surface2 px-2.5 py-0.5 text-[11px] font-semibold text-faint">excluded</span>}
          {tx.tags.map((t) => (
            <span key={t.id} className="shrink-0 rounded-full px-2.5 py-0.5 text-[11px] font-semibold"
              style={{ background: tint(t.color, dark), color: swatch(t.color, dark) }}>
              #{t.name}
            </span>
          ))}
        </p>
        <p className="mt-0.5 flex items-center gap-1.5 truncate text-[12.5px] text-faint">
          <Dot color={tx.accountColor} size={6} />
          {tx.bank || tx.accountName}
          {!tx.isInternal && tx.category && <span>· {tx.category.name}</span>}
        </p>
      </div>
      <Money amount={tx.amount} currency={tx.currency} signed={!dimmed} muted={dimmed} className="text-[14.5px] font-semibold" />
    </button>
  )
}
