import type { ReactNode } from 'react'

/**
 * The chrome every signed-out screen shares: the Skarb mark, a title, one card.
 * Signed-out pages have no sidebar and no data, so the page itself is the layout.
 */
export function AuthShell({ title, subtitle, children, footer, wide = false }: {
  title: string
  subtitle?: ReactNode
  children: ReactNode
  footer?: ReactNode
  wide?: boolean
}) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-paper px-6 py-12">
      <div className={`w-full ${wide ? 'max-w-md' : 'max-w-sm'}`}>
        <header className="mb-7 flex flex-col items-center gap-3">
          <Mark />
          <div className="text-center">
            <h1 className="font-display text-2xl font-bold tracking-tight">{title}</h1>
            {subtitle && <p className="mt-1.5 text-sm leading-relaxed text-muted">{subtitle}</p>}
          </div>
        </header>

        <div className="rounded-2xl border border-line bg-surface p-6 shadow-card">{children}</div>

        {footer && <div className="mt-4 text-center text-xs leading-relaxed text-faint">{footer}</div>}
      </div>
    </div>
  )
}

export function Mark({ size = 'lg' }: { size?: 'sm' | 'lg' }) {
  const box = size === 'lg' ? 'h-11 w-11' : 'h-7 w-7'
  const text = size === 'lg' ? 'text-lg' : 'text-sm'
  return (
    <span
      className={`flex ${box} items-center justify-center rounded-full bg-gold shadow-[inset_0_0_0_2px_rgba(19,27,46,0.9)]`}
      aria-hidden
    >
      <span className={`font-display ${text} font-bold text-ink`}>S</span>
    </span>
  )
}

/** Inline error, sized to sit under a field without shifting the card around. */
export function FormError({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="rounded-xl bg-danger/5 px-3 py-2 text-sm leading-snug text-danger">
      {children}
    </p>
  )
}

/** A 6-digit authenticator code. Wide tracking makes a mistyped digit obvious at a glance. */
export const codeInputCls =
  'w-full rounded-xl border border-line bg-surface px-3 py-2.5 text-center text-lg font-semibold tracking-[0.35em] ' +
  'tnum outline-none transition-colors focus:border-ink placeholder:font-normal placeholder:tracking-normal placeholder:text-faint'
