export type CategoryKind = 'expense' | 'income' | 'investment'
export type Category = { id: string; name: string; emoji: string; color: string; kind: CategoryKind }
export type CategoryWithCount = Category & { transactionCount: number }
export type Tag = { id: string; name: string; color: string }

export type Account = {
  id: string; name: string; bank: string; provider: string; currency: string
  balance: number; iban: string | null; maskedPan: string | null; color: string
  isArchived: boolean; connectionId: string | null
}

export type Tx = {
  id: string; accountId: string; accountName: string; accountColor: string; bank: string
  amount: number; currency: string; description: string; counterParty: string | null
  mcc: number | null; category: Category | null; tags: Tag[]; occurredAt: string
  source: string; note: string | null; isExcluded: boolean; isInternal: boolean
}

export type Meta = { accounts: Account[]; categories: Category[]; tags: Tag[] }
export type Paged<T> = { items: T[]; total: number; page: number; pageSize: number }

export type Dashboard = {
  baseCurrency: string
  netWorth: number
  accounts: { account: Account; balanceBase: number }[]
  month: { income: number; expense: number; invested: number; net: number }
  prevMonth: { income: number; expense: number; invested: number }
  allTimeInvested: number
  spendingByCategory: { categoryId: string | null; name: string; emoji: string; color: string; amount: number }[]
  cashflow: { month: string; income: number; expense: number; invested: number }[]
  recent: Tx[]
}

export type Connection = {
  id: string; provider: string; displayName: string; status: string
  lastSyncedAt: string | null; lastError: string | null
  accountCount: number; consentValidUntil: string | null
}

export type Rule = { id: string; pattern: string; priority: number; category: Category }
export type SyncStatus = {
  running: string[]
  logs: { at: string; provider: string; message: string; success: boolean; newTransactions: number }[]
}

async function http<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
  if (!res.ok) {
    let message = `${res.status} ${res.statusText}`
    try {
      const body = await res.json()
      if (body?.error) message = body.error
    } catch { /* keep default */ }
    throw new Error(message)
  }
  if (res.status === 204) return undefined as T
  return res.json()
}

const get = <T,>(url: string) => http<T>(url)
const post = <T,>(url: string, body?: unknown) => http<T>(url, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) })
const patch = <T,>(url: string, body: unknown) => http<T>(url, { method: 'PATCH', body: JSON.stringify(body) })
const del = (url: string) => http<void>(url, { method: 'DELETE' })

export const api = {
  meta: () => get<Meta>('/api/meta'),
  dashboard: () => get<Dashboard>('/api/dashboard'),

  transactions: (params: Record<string, string>) =>
    get<Paged<Tx>>('/api/transactions?' + new URLSearchParams(params)),
  createTransaction: (body: {
    accountId: string; amount: number; currency?: string; description: string
    categoryId: string | null; tagIds: string[]; occurredAt: string; note: string | null
  }) => post<Tx>('/api/transactions', body),
  updateTransaction: (id: string, body: {
    description?: string; amount?: number; occurredAt?: string; note?: string
    isExcluded?: boolean; isInternal?: boolean
    categorySet?: boolean; categoryId?: string | null; tagIds?: string[]
  }) => patch<Tx>(`/api/transactions/${id}`, body),
  deleteTransaction: (id: string) => del(`/api/transactions/${id}`),

  createAccount: (body: { name: string; bank: string; currency: string; balance: number; color?: string }) =>
    post<Account>('/api/accounts', body),
  updateAccount: (id: string, body: { name?: string; color?: string; isArchived?: boolean }) =>
    patch<Account>(`/api/accounts/${id}`, body),
  deleteAccount: (id: string) => del(`/api/accounts/${id}`),

  categories: () => get<CategoryWithCount[]>('/api/categories'),
  createCategory: (body: { name: string; emoji: string; color: string; kind: CategoryKind }) =>
    post<Category>('/api/categories', body),
  updateCategory: (id: string, body: { name: string; emoji: string; color: string; kind: CategoryKind }) =>
    patch<Category>(`/api/categories/${id}`, body),
  deleteCategory: (id: string) => del(`/api/categories/${id}`),
  createTag: (body: { name: string; color?: string }) => post<Tag>('/api/tags', body),

  rules: () => get<Rule[]>('/api/rules'),
  createRule: (body: { pattern: string; categoryId: string; priority: number }) => post('/api/rules', body),
  deleteRule: (id: string) => del(`/api/rules/${id}`),

  connections: () => get<Connection[]>('/api/connections'),
  deleteConnection: (id: string) => del(`/api/connections/${id}`),
  connectMonobank: (token: string) => post<{ id: string }>('/api/connections/monobank', { token }),
  setMonobankWebhook: (id: string, publicBaseUrl: string) =>
    post<{ webhookUrl: string }>(`/api/connections/${id}/monobank/webhook`, { publicBaseUrl }),
  connectEnableBanking: (body: { displayName: string; applicationId: string; privateKeyPem: string }) =>
    post<{ id: string }>('/api/connections/enablebanking', body),
  ebAspsps: (id: string, country: string) =>
    get<{ name: string; country: string; logo: string | null }[]>(
      `/api/connections/${id}/enablebanking/aspsps?country=${country}`),
  ebAuthorize: (id: string, body: { aspspName: string; aspspCountry: string; redirectUrl: string }) =>
    post<{ url: string }>(`/api/connections/${id}/enablebanking/authorize`, body),
  ebComplete: (id: string, code: string) =>
    post<{ status: string }>(`/api/connections/${id}/enablebanking/complete`, { code }),

  syncAll: () => post<{ started: string[] }>('/api/sync'),
  syncOne: (id: string) => post<{ started: string[] }>(`/api/sync/${id}`),
  syncStatus: () => get<SyncStatus>('/api/sync/status'),

  importCsv: (body: {
    accountId: string; content: string
    dateColumn: number; amountColumn: number; descriptionColumn: number; currencyColumn: number | null
    dateFormat: string; decimalSeparator: string; delimiter: string; hasHeader: boolean; invertAmount: boolean
  }) => post<{ imported: number; skipped: number; errors: string[] }>('/api/import/csv', body),
}

export function fmtMoney(amount: number, currency: string, opts?: { sign?: boolean; decimals?: number }) {
  const f = new Intl.NumberFormat('en-US', {
    style: 'currency', currency, currencyDisplay: 'narrowSymbol',
    minimumFractionDigits: opts?.decimals ?? 2, maximumFractionDigits: opts?.decimals ?? 2,
  }).format(Math.abs(amount))
  const sign = amount < 0 ? '−' : opts?.sign ? '+' : ''
  return sign + f
}
