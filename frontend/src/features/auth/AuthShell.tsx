import type { ReactNode } from 'react'
import { Mark } from '../../shared/ui'

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
    <div className="flex min-h-screen items-center justify-center bg-paper px-4 py-12 sm:px-6">
      <div className={`w-full ${wide ? 'max-w-md' : 'max-w-sm'}`}>
        <header className="mb-8 flex flex-col items-center gap-4">
          <Mark />
          <div className="text-center">
            <h1 className="font-display text-[28px] font-semibold tracking-[-0.02em]">{title}</h1>
            {subtitle && <p className="mt-2 text-sm leading-relaxed text-muted">{subtitle}</p>}
          </div>
        </header>

        <div className="rounded-card bg-surface p-5 shadow-card sm:p-7">{children}</div>

        {footer && <div className="mt-5 text-center text-xs leading-relaxed text-faint">{footer}</div>}
      </div>
    </div>
  )
}

/** Inline error, sized to sit under a field without shifting the card around. */
export function FormError({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="rounded-row bg-danger/10 px-3.5 py-2.5 text-sm font-medium leading-snug text-danger">
      {children}
    </p>
  )
}

/** A 6-digit authenticator code. Wide tracking makes a mistyped digit obvious at a glance. */
export const codeInputCls =
  'w-full rounded-row bg-surface2 px-3 py-3 text-center text-lg font-semibold tracking-[0.35em] tnum outline-none ' +
  'transition-shadow focus:shadow-[inset_0_0_0_1.5px_var(--sk-accent)] placeholder:font-normal placeholder:tracking-normal placeholder:text-faint'
