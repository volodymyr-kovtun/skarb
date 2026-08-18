import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryCache, QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './index.css'
import { UnauthorizedError } from './shared/api'
import Layout from './shared/Layout'
import AuthGate from './features/auth/AuthGate'
import DashboardPage from './features/dashboard/DashboardPage'
import TransactionsPage from './features/transactions/TransactionsPage'
import AccountsPage from './features/accounts/AccountsPage'
import CategoriesPage from './features/categories/CategoriesPage'
import SettingsPage from './features/settings/SettingsPage'

// A session can lapse mid-visit. Whichever query notices first re-checks the session,
// which drops the app back to the sign-in screen instead of showing broken pages.
const queryCache = new QueryCache({
  onError: (error) => {
    if (error instanceof UnauthorizedError) queryClient.invalidateQueries({ queryKey: ['session'] })
  },
})

const queryClient = new QueryClient({
  queryCache,
  defaultOptions: {
    queries: {
      staleTime: 15_000,
      retry: (failureCount, error) => !(error instanceof UnauthorizedError) && failureCount < 1,
    },
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AuthGate>
          <Routes>
            <Route element={<Layout />}>
              <Route path="/" element={<DashboardPage />} />
              <Route path="/transactions" element={<TransactionsPage />} />
              <Route path="/accounts" element={<AccountsPage />} />
              <Route path="/categories" element={<CategoriesPage />} />
              <Route path="/settings" element={<SettingsPage />} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Route>
          </Routes>
        </AuthGate>
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
)
