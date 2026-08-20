import { NavLink, Outlet } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { LogOut, RefreshCw } from 'lucide-react'
import { api } from './api'
import { IconButton, Mark, ThemeToggle } from './ui'

const nav = [
  { to: '/', label: 'Overview' },
  { to: '/transactions', label: 'Transactions' },
  { to: '/accounts', label: 'Accounts' },
  { to: '/categories', label: 'Categories' },
  { to: '/settings', label: 'Settings' },
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
    <div className="min-h-screen px-6 pb-14 pt-7 sm:px-10">
      <div className="mx-auto max-w-[1288px]">
        <header className="mb-8 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-2.5">
            <Mark size="sm" />
            <span className="font-display text-xl font-semibold tracking-tight">Skarb</span>
          </div>

          <nav className="order-3 flex w-full flex-wrap items-center justify-center gap-1 rounded-[22px] bg-surface2 p-1.5 sm:order-none sm:w-auto sm:flex-nowrap sm:rounded-full">
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

          <div className="flex items-center gap-2">
            <button
              onClick={syncNow}
              disabled={syncing}
              title={syncing ? `Syncing ${status!.running.join(', ')}` : 'Sync every connected bank now'}
              className="flex h-9 items-center gap-2 rounded-full bg-surface2 px-3.5 text-[12.5px] font-semibold text-muted transition-colors hover:bg-hover hover:text-ink disabled:opacity-70"
            >
              <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} />
              {syncing ? 'Syncing…' : 'Sync now'}
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
    </div>
  )
}
