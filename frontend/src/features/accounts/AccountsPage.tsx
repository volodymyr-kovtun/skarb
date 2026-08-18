import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Landmark } from 'lucide-react'
import { api, fmtMoney, refreshAll, type Account } from '../../shared/api'
import { ACCOUNT_COLORS, Card, ColorPicker, Modal, ModalActions, bankLabel, btnPrimary, errMsg, fieldLabelCls, inputCls, labelCls } from '../../shared/ui'

const providerLabel: Record<string, string> = {
  manual: 'Manual',
  monobank: 'Auto-synced',
  enablebanking: 'Auto-synced',
}

type Group = { label: string; accounts: Account[] }

/** One section per institution, biggest first — the page stays short as accounts pile up. */
function groupByBank(accounts: Account[]): Group[] {
  const byLabel = new Map<string, Group>()
  for (const a of accounts) {
    const label = bankLabel(a)
    const group = byLabel.get(label) ?? { label, accounts: [] }
    group.accounts.push(a)
    byLabel.set(label, group)
  }
  return [...byLabel.values()].sort((x, y) => y.accounts.length - x.accounts.length)
}

/** Only meaningful when a group holds a single currency — no exchange rates on this page. */
function singleCurrencyTotal(accounts: Account[]) {
  const currencies = new Set(accounts.map((a) => a.currency))
  if (currencies.size !== 1) return null
  return { currency: [...currencies][0], total: accounts.reduce((s, a) => s + a.balance, 0) }
}

export default function AccountsPage() {
  const qc = useQueryClient()
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<Account | null>(null)
  const refresh = () => refreshAll(qc)

  const accounts = meta?.accounts ?? []
  const active = accounts.filter((a) => !a.isArchived)
  const archived = accounts.filter((a) => a.isArchived)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between px-1 pt-2">
        <h1 className="font-display text-2xl font-bold tracking-tight">Accounts</h1>
        <button className={btnPrimary} onClick={() => setAdding(true)}>
          <Plus size={15} className="mr-1 inline -translate-y-px" />
          Add manual account
        </button>
      </div>

      {active.length === 0 && (
        <Card className="px-6 py-12 text-center">
          <Landmark className="mx-auto mb-3 text-faint" size={28} />
          <p className="text-sm text-muted">
            No accounts yet. Connect a bank in Settings, or add a manual account to track cash.
          </p>
        </Card>
      )}

      {active.length > 0 && (
        <Card className="pb-3">
          {groupByBank(active).map((g, i) => {
            const providers = [...new Set(g.accounts.map((a) => a.provider))]
            const sum = singleCurrencyTotal(g.accounts)
            return (
              <div key={g.label} className={i > 0 ? 'mt-1 border-t border-line' : ''}>
                <header className="flex items-baseline gap-2.5 px-5 pt-4 pb-1">
                  <h2 className={labelCls}>{g.label}</h2>
                  <span className="text-xs text-faint">
                    {g.accounts.length} account{g.accounts.length === 1 ? '' : 's'}
                    {providers.length === 1 && ` · ${providerLabel[providers[0]] ?? providers[0]}`}
                  </span>
                  {sum && (
                    <span className="tnum ml-auto text-sm font-semibold">{fmtMoney(sum.total, sum.currency)}</span>
                  )}
                </header>
                <div className="px-2">
                  {g.accounts.map((a) => (
                    <button
                      key={a.id}
                      onClick={() => setEditing(a)}
                      className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-paper"
                    >
                      <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: a.color }} />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-medium">{a.name}</span>
                        <span className="block truncate text-xs text-faint">
                          {a.currency}
                          {a.maskedPan ? ` · ${a.maskedPan.slice(-8)}` : a.iban ? ` · …${a.iban.slice(-6)}` : ''}
                          {providers.length > 1 && ` · ${providerLabel[a.provider] ?? a.provider}`}
                        </span>
                      </span>
                      <span className="tnum text-sm font-semibold">{fmtMoney(a.balance, a.currency)}</span>
                    </button>
                  ))}
                </div>
              </div>
            )
          })}
        </Card>
      )}

      {archived.length > 0 && (
        <details className="px-1 text-sm text-muted">
          <summary className="cursor-pointer font-medium">Archived ({archived.length})</summary>
          <div className="mt-2 flex flex-col gap-1">
            {archived.map((a) => (
              <button key={a.id} onClick={() => setEditing(a)}
                className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-surface">
                <span className="h-2 w-2 rounded-full" style={{ background: a.color }} />
                <span className="truncate">{bankLabel(a)} · {a.name}</span>
                <span className="tnum ml-auto">{fmtMoney(a.balance, a.currency)}</span>
              </button>
            ))}
          </div>
        </details>
      )}

      {adding && <AccountForm onClose={() => setAdding(false)} onSaved={() => { setAdding(false); refresh() }} />}
      {editing && <AccountForm account={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); refresh() }} />}
    </div>
  )
}

function AccountForm({ account, onClose, onSaved }:
  { account?: Account; onClose: () => void; onSaved: () => void }) {
  const isEdit = !!account
  const [name, setName] = useState(account?.name ?? '')
  const [bank, setBank] = useState(account?.bank ?? '')
  const [currency, setCurrency] = useState(account?.currency ?? 'PLN')
  const [balance, setBalance] = useState('0')
  const [color, setColor] = useState(account?.color ?? ACCOUNT_COLORS[0])
  const [archived, setArchived] = useState(account?.isArchived ?? false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      if (isEdit) {
        await api.updateAccount(account!.id, { name, color, isArchived: archived })
      } else {
        if (!name.trim()) { setError('Give the account a name.'); return }
        await api.createAccount({ name: name.trim(), bank: bank.trim(), currency, balance: parseFloat(balance || '0'), color })
      }
      onSaved()
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setBusy(false)
    }
  }

  const remove = async () => {
    if (!confirm(`Delete "${account!.name}" and all its transactions? This cannot be undone.`)) return
    await api.deleteAccount(account!.id)
    onSaved()
  }

  return (
    <Modal title={isEdit ? 'Edit account' : 'Add manual account'} onClose={onClose}>
      <div className="flex flex-col gap-3">
        <label className="text-sm">
          <span className={fieldLabelCls}>Name</span>
          <input className={inputCls} value={name} onChange={(e) => setName(e.target.value)} placeholder="Cash wallet" autoFocus />
        </label>

        {!isEdit && (
          <>
            <label className="text-sm">
              <span className={fieldLabelCls}>Bank / institution (optional)</span>
              <input className={inputCls} value={bank} onChange={(e) => setBank(e.target.value)} placeholder="ZEN, cash, …" />
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label className="text-sm">
                <span className={fieldLabelCls}>Currency</span>
                <select className={inputCls} value={currency} onChange={(e) => setCurrency(e.target.value)}>
                  {['PLN', 'UAH', 'EUR', 'USD', 'GBP', 'CZK', 'CHF'].map((c) => <option key={c}>{c}</option>)}
                </select>
              </label>
              <label className="text-sm">
                <span className={fieldLabelCls}>Current balance</span>
                <input className={inputCls + ' tnum'} type="number" step="0.01" value={balance} onChange={(e) => setBalance(e.target.value)} />
              </label>
            </div>
          </>
        )}

        <div className="text-sm">
          <span className={fieldLabelCls}>Color</span>
          <ColorPicker colors={ACCOUNT_COLORS} value={color} onChange={setColor} />
        </div>

        {isEdit && (
          <label className="flex items-center gap-2 text-sm text-muted">
            <input type="checkbox" checked={archived} onChange={(e) => setArchived(e.target.checked)} className="h-4 w-4 accent-ink" />
            Archive (hide from overview and stop syncing)
          </label>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}

        <ModalActions busy={busy} onCancel={onClose} onSave={save} onDelete={isEdit ? remove : undefined} />
      </div>
    </Modal>
  )
}
