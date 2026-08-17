import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Landmark } from 'lucide-react'
import { api, fmtMoney, refreshAll, type Account } from '../../shared/api'
import { ACCOUNT_COLORS, Card, ColorPicker, Modal, ModalActions, btnPrimary, errMsg, fieldLabelCls, inputCls } from '../../shared/ui'

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
