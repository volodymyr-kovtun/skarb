import { NavLink, Outlet } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { LayoutDashboard, LogOut, Receipt, RefreshCw, Settings, Shapes, Wallet } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { api } from './api'
import { IconButton, Mark, ThemeToggle } from './ui'

const nav: { to: string; label: string; icon: LucideIcon }[] = [
  { to: '/', label: 'Overview', icon: LayoutDashboard },
  { to: '/transactions', label: 'Transactions', icon: Receipt },
  { to: '/accounts', label: 'Accounts', icon: Wallet },
  { to: '/categories', label: 'Categories', icon: Shapes },
  { to: '/settings', label: 'Settings', icon: Settings },
]

export default function Layout() {
  const qc = useQueryClient()
  const { data: status } = useQuery({
    queryKey: ['sync-status'],
    queryFn: api.syncStatus,
    refetchInterval: (q) => (q.state.data?.running.length ? 4_000 : 30_000),
  })
  const syncing = (status?.running.length ?? 0) > 0

  const { data: session } = useQuery({ queryKey: ['session'], queryFn: api.session })

  const syncNow = async () => {
    await api.syncAll()
    qc.invalidateQueries({ queryKey: ['sync-status'] })
  }

  const signOut = async () => {
    await api.logout()
    qc.invalidateQueries() // re-reads the session, which drops back to the sign-in screen
  }

  return (
    // The bottom padding clears the phone tab bar — and the home indicator under it.
    <div className="min-h-screen px-4 pt-5 pb-[calc(5.25rem+env(safe-area-inset-bottom))] sm:px-10 sm:pt-7 sm:pb-14">
      <div className="mx-auto max-w-[1288px]">
        <header className="mb-5 flex flex-wrap items-center justify-between gap-3 sm:mb-8 sm:gap-4">
          <div className="flex items-center gap-2.5">
            <Mark size="sm" />
            <span className="font-display text-xl font-semibold tracking-tight">Skarb</span>
          </div>

          {/* From `sm` up the destinations ride in the header as pills — on their own centered
              row until the window is wide enough to seat all three groups side by side. */}
          <nav className="order-3 hidden w-full items-center justify-center gap-1 rounded-[22px] bg-surface2 p-1.5 sm:flex lg:order-none lg:w-auto lg:rounded-full">
            {nav.map(({ to, label }) => (
              <NavLink
                key={to}
                to={to}
                end={to === '/'}
                className={({ isActive }) =>
                  `whitespace-nowrap rounded-full px-4 py-2 text-sm transition-colors ` +
                  (isActive ? 'bg-surface font-semibold text-ink shadow-card' : 'font-medium text-muted hover:text-ink')
                }
              >
                {label}
              </NavLink>
            ))}
          </nav>

          <div className="flex shrink-0 items-center gap-2">
            <button
              onClick={syncNow}
              disabled={syncing}
              title={syncing ? `Syncing ${status!.running.join(', ')}` : 'Sync every connected bank now'}
              className="flex h-9 items-center gap-2 rounded-full bg-surface2 px-3.5 text-[12.5px] font-semibold text-muted transition-colors hover:bg-hover hover:text-ink disabled:opacity-70"
            >
              <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} />
              {/* On a phone the icon carries this; the word would crowd out the mark. */}
              <span className="hidden xs:inline">{syncing ? 'Syncing…' : 'Sync now'}</span>
            </button>
            <ThemeToggle />
            <IconButton label={`Sign out${session?.email ? ` — ${session.email}` : ''}`} onClick={signOut}>
              <LogOut size={16} />
            </IconButton>
          </div>
        </header>

        <main>
          <Outlet />
        </main>
      </div>

      {/*
       * On a phone the same five destinations become a tab bar. As header pills they wrapped
       * onto a second row and took the top third of the screen before any money was on it —
       * and the thumb has to reach the top of the phone to use them.
       */}
      <nav
        className="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-surface/92 pb-[env(safe-area-inset-bottom)] backdrop-blur-lg sm:hidden"
        aria-label="Sections"
      >
        <div className="mx-auto flex max-w-md items-stretch px-1 pt-1.5 pb-1">
          {nav.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              title={label}
              className="flex min-w-0 flex-1 flex-col items-center gap-1 rounded-2xl py-1"
            >
              {({ isActive }) => (
                <>
                  <span
                    className={`flex h-7 w-12 items-center justify-center rounded-full transition-colors ${
                      isActive ? 'bg-accent/15 text-accent' : 'text-muted'}`}
                  >
                    <Icon size={18} />
                  </span>
                  <span
                    className={`w-full truncate text-center text-[10px] leading-none font-semibold ${
                      isActive ? 'text-accent' : 'text-muted'}`}
                  >
                    {label}
                  </span>
                </>
              )}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
