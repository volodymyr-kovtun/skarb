import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Landmark } from 'lucide-react'
import { api, fmtMoney, type Account } from '../../shared/api'
import { Card, Modal, btnGhost, btnPrimary, inputCls } from '../../shared/ui'

const COLORS = ['#4F46E5', '#0B5FFF', '#059669', '#C29B3C', '#DB2777', '#0891B2', '#131B2E', '#EA580C']

const providerLabel: Record<string, string> = {
  manual: 'Manual',
  monobank: 'Auto-synced',
  enablebanking: 'Auto-synced',
}

export default function AccountsPage() {
  const qc = useQueryClient()
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<Account | null>(null)
  const refresh = () => ['meta', 'dashboard', 'transactions'].forEach((k) => qc.invalidateQueries({ queryKey: [k] }))

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

      <div className="grid grid-cols-2 gap-4">
        {active.map((a) => (
          <button key={a.id} onClick={() => setEditing(a)} className="text-left">
            <Card className="px-5 py-4 transition-shadow hover:shadow-pop">
              <div className="flex items-center gap-2">
                <span className="h-2.5 w-2.5 rounded-full" style={{ background: a.color }} />
                <span className="text-sm font-semibold">{a.bank || 'Manual'}</span>
                <span className="ml-auto rounded-md bg-paper px-2 py-0.5 text-[11px] font-medium text-muted">
                  {providerLabel[a.provider] ?? a.provider}
                </span>
              </div>
              <p className="mt-3 font-display text-2xl font-bold tnum">{fmtMoney(a.balance, a.currency)}</p>
              <p className="mt-1 truncate text-xs text-faint">
                {a.name}
                {a.maskedPan ? ` · ${a.maskedPan.slice(-8)}` : a.iban ? ` · …${a.iban.slice(-6)}` : ''}
              </p>
            </Card>
          </button>
        ))}
      </div>

      {archived.length > 0 && (
        <details className="px-1 text-sm text-muted">
          <summary className="cursor-pointer font-medium">Archived ({archived.length})</summary>
          <div className="mt-2 flex flex-col gap-1">
            {archived.map((a) => (
              <button key={a.id} onClick={() => setEditing(a)}
                className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-surface">
                <span className="h-2 w-2 rounded-full" style={{ background: a.color }} />
                {a.bank || a.name} <span className="tnum ml-auto">{fmtMoney(a.balance, a.currency)}</span>
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
  const [color, setColor] = useState(account?.color ?? COLORS[0])
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
      setError(e instanceof Error ? e.message : 'Something went wrong')
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
          <span className="mb-1 block text-xs font-medium text-muted">Name</span>
          <input className={inputCls} value={name} onChange={(e) => setName(e.target.value)} placeholder="Cash wallet" autoFocus />
        </label>

        {!isEdit && (
          <>
            <label className="text-sm">
              <span className="mb-1 block text-xs font-medium text-muted">Bank / institution (optional)</span>
              <input className={inputCls} value={bank} onChange={(e) => setBank(e.target.value)} placeholder="ZEN, cash, …" />
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label className="text-sm">
                <span className="mb-1 block text-xs font-medium text-muted">Currency</span>
                <select className={inputCls} value={currency} onChange={(e) => setCurrency(e.target.value)}>
                  {['PLN', 'UAH', 'EUR', 'USD', 'GBP', 'CZK', 'CHF'].map((c) => <option key={c}>{c}</option>)}
                </select>
              </label>
              <label className="text-sm">
                <span className="mb-1 block text-xs font-medium text-muted">Current balance</span>
                <input className={inputCls + ' tnum'} type="number" step="0.01" value={balance} onChange={(e) => setBalance(e.target.value)} />
              </label>
            </div>
          </>
        )}

        <div className="text-sm">
          <span className="mb-1 block text-xs font-medium text-muted">Color</span>
          <div className="flex gap-2">
            {COLORS.map((c) => (
              <button key={c} onClick={() => setColor(c)} aria-label={`Color ${c}`}
                className={`h-7 w-7 rounded-full transition-transform ${color === c ? 'scale-110 ring-2 ring-ink ring-offset-2' : ''}`}
                style={{ background: c }} />
            ))}
          </div>
        </div>

        {isEdit && (
          <label className="flex items-center gap-2 text-sm text-muted">
            <input type="checkbox" checked={archived} onChange={(e) => setArchived(e.target.checked)} className="h-4 w-4 accent-ink" />
            Archive (hide from overview and stop syncing)
          </label>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}

        <div className="mt-2 flex items-center justify-between">
          {isEdit ? (
            <button className="text-sm font-medium text-danger hover:underline" onClick={remove}>Delete</button>
          ) : <span />}
          <div className="flex gap-2">
            <button className={btnGhost} onClick={onClose}>Cancel</button>
            <button className={btnPrimary} onClick={save} disabled={busy}>{busy ? 'Saving…' : 'Save'}</button>
          </div>
        </div>
      </div>
    </Modal>
  )
}
