import { NavLink, Outlet } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { LayoutGrid, ArrowLeftRight, Wallet, Shapes, Tags, Settings, RefreshCw, LogOut } from 'lucide-react'
import { api } from './api'
import { btnGhost } from './ui'

const nav = [
  { to: '/', label: 'Overview', icon: LayoutGrid },
  { to: '/transactions', label: 'Transactions', icon: ArrowLeftRight },
  { to: '/accounts', label: 'Accounts', icon: Wallet },
  { to: '/categories', label: 'Categories', icon: Shapes },
  { to: '/tags', label: 'Tags', icon: Tags },
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
    <div className="flex min-h-screen">
      <aside className="fixed inset-y-0 left-0 z-20 flex w-56 flex-col border-r border-line bg-surface px-4 py-6">
        <div className="mb-8 flex items-center gap-2.5 px-2">
          <span className="relative flex h-7 w-7 items-center justify-center rounded-full bg-gold shadow-[inset_0_0_0_2px_rgba(19,27,46,0.9)]">
            <span className="font-display text-sm font-bold text-ink">S</span>
          </span>
          <span className="font-display text-xl font-bold tracking-tight">Skarb</span>
        </div>

        <nav className="flex flex-col gap-1">
          {nav.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) =>
                `flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition-colors ` +
                (isActive
                  ? 'bg-ink text-white'
                  : 'text-muted hover:bg-paper hover:text-ink')
              }
            >
              <Icon size={17} strokeWidth={2} />
              {label}
            </NavLink>
          ))}
        </nav>

        <div className="mt-auto flex flex-col gap-2 px-1">
          <button
            onClick={syncNow}
            disabled={syncing}
            className={`${btnGhost} flex items-center justify-center gap-2`}
          >
            <RefreshCw size={15} className={syncing ? 'animate-spin' : ''} />
            {syncing ? 'Syncing…' : 'Sync now'}
          </button>
          {syncing && (
            <p className="px-1 text-center text-xs text-faint">
              {status!.running.join(', ')}
            </p>
          )}

          <div className="mt-2 flex items-center gap-1 border-t border-line pt-3">
            <span className="min-w-0 flex-1 truncate px-1 text-xs text-faint" title={session?.email ?? ''}>
              {session?.email}
            </span>
            <button
              onClick={signOut}
              title="Sign out"
              aria-label="Sign out"
              className="rounded-lg p-1.5 text-muted transition-colors hover:bg-paper hover:text-ink"
            >
              <LogOut size={15} />
            </button>
          </div>
        </div>
      </aside>

      <main className="ml-56 flex-1 px-10 py-8">
        <div className="mx-auto max-w-5xl">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
