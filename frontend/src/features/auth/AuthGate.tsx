import type { ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from '../../shared/api'
import { btnPrimary, errMsg, Mark } from '../../shared/ui'
import { AuthShell } from './AuthShell'
import LoginPage from './LoginPage'
import SetupPage from './SetupPage'

/**
 * Decides what the app is right now: unclaimed, signed out, or ready. The whole router
 * sits behind it, so there is a single place where "is anyone home?" gets answered —
 * and no route can be reached by typing its URL.
 */
export default function AuthGate({ children }: { children: ReactNode }) {
  const qc = useQueryClient()
  const { data: session, isPending, isError, error, refetch } = useQuery({
    queryKey: ['session'],
    queryFn: api.session,
    retry: false,
    staleTime: 60_000,
  })

  // Re-reading the session flips this gate; clearing the rest drops any data
  // cached for a previous session.
  const refresh = () => qc.invalidateQueries()

  if (isPending) return <Splash />
  if (isError) return <Unreachable message={errMsg(error, 'Could not reach the server')} onRetry={() => void refetch()} />
  if (session.setupRequired) return <SetupPage onDone={refresh} />
  if (!session.authenticated) return <LoginPage onSignedIn={refresh} />

  return <>{children}</>
}

function Splash() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-paper">
      <div className="animate-pulse">
        <Mark />
      </div>
      <span className="sr-only">Loading</span>
    </div>
  )
}

function Unreachable({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <AuthShell title="Skarb" subtitle="Couldn't reach the server.">
      <div className="flex flex-col gap-4">
        <p className="rounded-row bg-danger/10 px-3.5 py-2.5 text-sm font-medium leading-snug text-danger">{message}</p>
        <button className={`${btnPrimary} w-full`} onClick={onRetry}>Try again</button>
      </div>
    </AuthShell>
  )
}
