export type CategoryKind = 'expense' | 'income' | 'investment'
export type Category = { id: string; name: string; emoji: string; color: string; kind: CategoryKind }
export type CategoryWithCount = Category & { transactionCount: number }
export type Tag = { id: string; name: string; color: string }

export type Account = {
  id: string; name: string; bank: string; provider: string; currency: string
  balance: number; iban: string | null; maskedPan: string | null; color: string
  isArchived: boolean; isExcluded: boolean; connectionId: string | null
  /** Alert when the balance drops below this (account currency); null = alerts off. */
  lowBalanceThreshold: number | null
  /** Telegram chat this account alerts; null = the default chat from Settings. */
  lowBalanceChatId: string | null
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
  /** Currency every converted number on the dashboard is reported in. */
  currency: string
  baseCurrency: string
  availableCurrencies: string[]
  netWorth: number
  accounts: { account: Account; balanceConverted: number }[]
  month: { income: number; expense: number; invested: number; net: number }
  prevMonth: { income: number; expense: number; invested: number }
  allTimeInvested: number
  spendingByCategory: { categoryId: string | null; name: string; emoji: string; color: string; amount: number }[]
  /** This month's spending cut by the account it left from. */
  spendingByAccount: { accountId: string; name: string; bank: string; color: string; amount: number }[]
  spendingByTag: { tagId: string; name: string; color: string; amount: number }[]
  /** This month's spending carrying no tag at all. */
  untaggedSpending: number
  /** Transactions this month wearing more than one tag — the reason tag slices can overlap. */
  multiTagCount: number
  cashflow: { month: string; income: number; expense: number; invested: number }[]
  recent: Tx[]
}

export type Connection = {
  id: string; provider: string; displayName: string; status: string
  lastSyncedAt: string | null; lastError: string | null
  accountCount: number; consentValidUntil: string | null
}

export type Rule = { id: string; pattern: string; priority: number; category: Category }

/** How far back a rule reaches over transactions that already exist. */
export type RuleScope = 'none' | 'automatic' | 'all'
/**
 * Matching transactions the rule would change, split by how much of a decision their current
 * category was. `untouched` is the ones you filed by hand — plus any filed before Skarb started
 * recording that — and they are only rewritten when you ask for them by name.
 */
export type RuleMatchCounts = { uncategorized: number; automatic: number; untouched: number }
export type RuleSuggestion = {
  /** Null means there is nothing worth offering here — don't show the sheet. */
  pattern: string | null
  alternatives: string[]
  /** Set when a rule already claims this exact keyword: repoint it rather than adding a second. */
  existingRule: { id: string; pattern: string; category: Category } | null
  matches: RuleMatchCounts
  sample: Tx[]
}
/** One rewritten transaction and what it was filed as before — everything undo needs. */
export type RuleRevert = { transactionId: string; previousCategoryId: string | null; previousSource: string | null }
export type RuleApplied = { id: string; applied: number; reverts: RuleRevert[] }
export type SyncStatus = {
  running: string[]
  logs: { at: string; provider: string; message: string; success: boolean; newTransactions: number }[]
}

export type TelegramSettings = { hasToken: boolean; botUsername: string | null; chatId: string }
export type TelegramChat = { id: string; name: string }

export type Session = { authenticated: boolean; email: string | null; setupRequired: boolean }
export type SetupChallenge = { secret: string; provisioningUri: string }

/** No session (or it expired). Thrown separately so the app can fall back to the sign-in screen. */
export class UnauthorizedError extends Error {
  constructor(message = 'Your session has ended. Please sign in again.') {
    super(message)
    this.name = 'UnauthorizedError'
  }
}

async function http<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    // The session lives in an HttpOnly cookie — it has to ride along with every call.
    credentials: 'include',
    ...init,
  })
  if (!res.ok) {
    let message = `${res.status} ${res.statusText}`
    try {
      const body = await res.json()
      if (body?.error) message = body.error
    } catch { /* keep default */ }
    if (res.status === 401) throw new UnauthorizedError(message)
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
  session: () => get<Session>('/api/auth/session'),
  setup: (body: { setupToken: string; email: string; password: string }) =>
    post<SetupChallenge>('/api/auth/setup', body),
  setupConfirm: (body: { setupToken: string; code: string }) =>
    post<{ recoveryCodes: string[] }>('/api/auth/setup/confirm', body),
  login: (body: { email: string; password: string; code?: string; recoveryCode?: string }) =>
    post<void>('/api/auth/login', body),
  logout: () => post<void>('/api/auth/logout'),
  changePassword: (body: { currentPassword: string; newPassword: string }) =>
    post<void>('/api/auth/password', body),
  newRecoveryCodes: (body: { currentPassword: string }) =>
    post<{ recoveryCodes: string[] }>('/api/auth/recovery-codes', body),
  recoveryCodesLeft: () => get<{ remaining: number }>('/api/auth/recovery-codes/remaining'),

  meta: () => get<Meta>('/api/meta'),
  dashboard: (currency?: string) =>
    get<Dashboard>('/api/dashboard' + (currency ? `?currency=${currency}` : '')),

  /** Array values are repeated (`tagIds=a&tagIds=b`), which is how the API reads a set. */
  transactions: (params: Record<string, string | string[]>) => {
    const q = new URLSearchParams()
    for (const [key, value] of Object.entries(params)) {
      if (Array.isArray(value)) value.forEach((v) => q.append(key, v))
      else q.set(key, value)
    }
    return get<Paged<Tx>>('/api/transactions?' + q)
  },
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
  updateAccount: (id: string, body: {
    name?: string; color?: string; isArchived?: boolean; isExcluded?: boolean
    /** Set true to apply the two lowBalance fields; null threshold turns the alert off. */
    lowBalanceSet?: boolean; lowBalanceThreshold?: number | null; lowBalanceChatId?: string | null
  }) => patch<Account>(`/api/accounts/${id}`, body),
  deleteAccount: (id: string) => del(`/api/accounts/${id}`),

  categories: () => get<CategoryWithCount[]>('/api/categories'),
  createCategory: (body: { name: string; emoji: string; color: string; kind: CategoryKind }) =>
    post<Category>('/api/categories', body),
  updateCategory: (id: string, body: { name: string; emoji: string; color: string; kind: CategoryKind }) =>
    patch<Category>(`/api/categories/${id}`, body),
  deleteCategory: (id: string) => del(`/api/categories/${id}`),
  createTag: (body: { name: string; color?: string }) => post<Tag>('/api/tags', body),
  updateTag: (id: string, body: { name?: string; color?: string }) => patch<Tag>(`/api/tags/${id}`, body),
  deleteTag: (id: string) => del(`/api/tags/${id}`),

  rules: () => get<Rule[]>('/api/rules'),
  /** Omitting `priority` lets the server sort the rule ahead of the seeded ones, which is the point. */
  createRule: (body: { pattern: string; categoryId: string; priority?: number; applyTo?: RuleScope }) =>
    post<RuleApplied>('/api/rules', body),
  updateRule: (id: string, body: { categoryId: string; pattern?: string; applyTo?: RuleScope }) =>
    patch<RuleApplied>(`/api/rules/${id}`, body),
  deleteRule: (id: string) => del(`/api/rules/${id}`),
  applyRules: () => post<{ scanned: number; categorized: number }>('/api/rules/apply'),
  revertRules: (entries: RuleRevert[]) => post<{ reverted: number }>('/api/rules/revert', { entries }),
  /** What a manual category change on this transaction could become. Omit `pattern` for the guess. */
  ruleSuggestion: (txId: string, pattern?: string) =>
    get<RuleSuggestion>(`/api/transactions/${txId}/rule-suggestion` +
      (pattern ? `?pattern=${encodeURIComponent(pattern)}` : '')),

  connections: () => get<Connection[]>('/api/connections'),
  renameConnection: (id: string, displayName: string) =>
    patch<Connection>(`/api/connections/${id}`, { displayName }),
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

  telegramSettings: () => get<TelegramSettings>('/api/notifications/telegram'),
  saveTelegramSettings: (body: { botToken?: string | null; chatId?: string | null }) =>
    patch<TelegramSettings>('/api/notifications/telegram', body),
  telegramTest: (chatId?: string) =>
    post<{ sentTo: string }>('/api/notifications/telegram/test', { chatId: chatId ?? null }),
  telegramChats: () => get<TelegramChat[]>('/api/notifications/telegram/chats'),

  syncAll: () => post<{ started: string[] }>('/api/sync'),
  syncOne: (id: string, full = false) => post<{ started: string[] }>(`/api/sync/${id}${full ? '?full=true' : ''}`),
  syncStatus: () => get<SyncStatus>('/api/sync/status'),

  importCsv: (body: {
    accountId: string; content: string
    dateColumn: number; amountColumn: number; descriptionColumn: number; currencyColumn: number | null
    dateFormat: string; decimalSeparator: string; delimiter: string; hasHeader: boolean; invertAmount: boolean
  }) => post<{ imported: number; skipped: number; errors: string[] }>('/api/import/csv', body),
}

// Intl.NumberFormat construction is expensive and fmtMoney runs per row and per
// chart-tooltip render — cache formatters per currency/precision.
const formatters = new Map<string, Intl.NumberFormat>()

export function fmtMoney(amount: number, currency: string, opts?: { sign?: boolean; decimals?: number }) {
  const decimals = opts?.decimals ?? 2
  const key = `${currency}|${decimals}`
  let f = formatters.get(key)
  if (!f) {
    f = new Intl.NumberFormat('en-US', {
      style: 'currency', currency, currencyDisplay: 'narrowSymbol',
      minimumFractionDigits: decimals, maximumFractionDigits: decimals,
    })
    formatters.set(key, f)
  }
  const sign = amount < 0 ? '−' : opts?.sign ? '+' : ''
  return sign + f.format(Math.abs(amount))
}

export const accountLabel = (a: { bank: string; name: string }) => (a.bank ? `${a.bank} · ` : '') + a.name

/** Every mutation invalidates everything — the app is small and the query graph isn't worth hand-maintaining. */
export const refreshAll = (qc: import('@tanstack/react-query').QueryClient) => qc.invalidateQueries()
