import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Landmark } from 'lucide-react'
import { api, fmtMoney, refreshAll, type Account, type TelegramChat } from '../../shared/api'
import { ACCOUNT_COLORS, Card, ColorPicker, Dot, Modal, ModalActions, bankLabel, btnGhost, btnPrimary, errMsg, fieldLabelCls, inputCls, sectionTitleCls } from '../../shared/ui'

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
    <div className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="font-display text-[30px] font-semibold tracking-[-0.02em]">Accounts</h1>
        <button className={btnPrimary} onClick={() => setAdding(true)}>
          <Plus size={16} />
          Add manual account
        </button>
      </div>

      {active.length === 0 && (
        <Card className="px-6 py-16 text-center">
          <Landmark className="mx-auto mb-4 text-faint" size={30} />
          <p className="text-sm text-muted">
            No accounts yet. Connect a bank in Settings, or add a manual account to track cash.
          </p>
        </Card>
      )}

      {active.length > 0 && (
        <Card className="px-4 pb-5 pt-2">
          {groupByBank(active).map((g, i) => {
            const providers = [...new Set(g.accounts.map((a) => a.provider))]
            const sum = singleCurrencyTotal(g.accounts)
            return (
              <div key={g.label} className={i > 0 ? 'mt-4 border-t border-line pt-4' : 'pt-3'}>
                <header className="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-3 pb-2">
                  <h2 className={sectionTitleCls}>{g.label}</h2>
                  <span className="text-[12.5px] text-faint">
                    {g.accounts.length} account{g.accounts.length === 1 ? '' : 's'}
                    {providers.length === 1 && ` · ${providerLabel[providers[0]] ?? providers[0]}`}
                  </span>
                  {sum && (
                    <span className="tnum ml-auto text-[15px] font-semibold">{fmtMoney(sum.total, sum.currency)}</span>
                  )}
                </header>
                <div>
                  {g.accounts.map((a) => (
                    <button
                      key={a.id}
                      onClick={() => setEditing(a)}
                      className="flex w-full items-center gap-3.5 rounded-row px-3 py-3 text-left transition-colors hover:bg-hover"
                    >
                      <Dot color={a.color} />
                      <span className="min-w-0 flex-1">
                        <span className="flex items-center gap-2">
                          <span className="truncate text-[14.5px] font-semibold">{a.name}</span>
                          {a.isExcluded && (
                            <span className="shrink-0 rounded-full bg-surface2 px-2 py-0.5 text-[11px] font-semibold text-faint">
                              not counted
                            </span>
                          )}
                        </span>
                        <span className="mt-0.5 block truncate text-[12.5px] text-faint">
                          {a.currency}
                          {a.maskedPan ? ` · ${a.maskedPan.slice(-8)}` : a.iban ? ` · …${a.iban.slice(-6)}` : ''}
                          {providers.length > 1 && ` · ${providerLabel[a.provider] ?? a.provider}`}
                          {a.lowBalanceThreshold != null && ` · alert < ${fmtMoney(a.lowBalanceThreshold, a.currency, { decimals: 0 })}`}
                        </span>
                      </span>
                      <span className="tnum text-[14.5px] font-semibold">{fmtMoney(a.balance, a.currency)}</span>
                    </button>
                  ))}
                </div>
              </div>
            )
          })}
        </Card>
      )}

      {archived.length > 0 && (
        <details className="px-2 text-sm text-muted">
          <summary className="cursor-pointer font-semibold marker:text-faint">Archived ({archived.length})</summary>
          <div className="mt-3 flex flex-col gap-1">
            {archived.map((a) => (
              <button key={a.id} onClick={() => setEditing(a)}
                className="flex items-center gap-3 rounded-row px-3 py-2.5 text-left transition-colors hover:bg-hover">
                <Dot color={a.color} size={8} />
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
  const [excluded, setExcluded] = useState(account?.isExcluded ?? false)
  const [threshold, setThreshold] = useState(account?.lowBalanceThreshold?.toString() ?? '')
  const [alertChat, setAlertChat] = useState(account?.lowBalanceChatId ?? '')
  const [chats, setChats] = useState<TelegramChat[] | null>(null)
  const [tgNote, setTgNote] = useState<{ ok: boolean; text: string } | null>(null)
  const [tgBusy, setTgBusy] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  // Only to warn when alerts are configured but have nowhere to go.
  const { data: telegram } = useQuery({ queryKey: ['telegram'], queryFn: api.telegramSettings, enabled: isEdit })

  const findChats = async () => {
    setTgBusy(true)
    setTgNote(null)
    try {
      const list = await api.telegramChats()
      setChats(list)
      if (list.length === 0)
        setTgNote({
          ok: false,
          text: 'No chats found. The recipient has to open the bot in Telegram and send it anything ' +
            'first — messages only show up here for about a day.',
        })
    } catch (e) {
      setTgNote({ ok: false, text: errMsg(e) })
    } finally {
      setTgBusy(false)
    }
  }

  const sendTest = async () => {
    setTgBusy(true)
    setTgNote(null)
    try {
      const r = await api.telegramTest(alertChat.trim())
      setTgNote({ ok: true, text: `Test sent to chat ${r.sentTo} — check Telegram.` })
    } catch (e) {
      setTgNote({ ok: false, text: errMsg(e) })
    } finally {
      setTgBusy(false)
    }
  }

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      if (isEdit) {
        const limit = parseFloat(threshold)
        if (!Number.isNaN(limit) && !alertChat.trim()) {
          setError('Pick who to ping — Find chats lists everyone who has messaged the bot.')
          return
        }
        await api.updateAccount(account!.id, {
          name, color, isArchived: archived, isExcluded: excluded,
          lowBalanceSet: true,
          lowBalanceThreshold: Number.isNaN(limit) ? null : limit,
          lowBalanceChatId: alertChat.trim() || null,
        })
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
          <div className="flex flex-col gap-3 border-t border-line pt-3">
            <div>
              <span className={fieldLabelCls}>Low balance alert</span>
              <div className="flex items-center gap-2">
                <input className={inputCls + ' tnum'} type="number" step="0.01" placeholder="off"
                  value={threshold} onChange={(e) => setThreshold(e.target.value)} />
                <span className="shrink-0 text-sm text-muted">{account!.currency}</span>
              </div>
              <p className="mt-1 text-xs leading-relaxed text-faint">
                A Telegram message goes out the moment the balance drops below this, with a daily
                reminder while it stays low. Leave empty for no alert.
              </p>
              {threshold.trim() !== '' && (
                <>
                  <div className="mt-2 flex gap-2">
                    <input className={inputCls} placeholder="Telegram chat ID"
                      value={alertChat} onChange={(e) => setAlertChat(e.target.value)} />
                    <button type="button" className={btnGhost + ' shrink-0'} onClick={findChats}
                      disabled={tgBusy || !telegram?.hasToken}
                      title="List chats that recently messaged the bot">
                      Find chats
                    </button>
                  </div>
                  <p className="mt-1 text-xs leading-relaxed text-faint">
                    Who to ping — e.g. the person who tops this account up. They message the bot
                    once, then Find chats lists them by name.
                  </p>
                  {chats && chats.length > 0 && (
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {chats.map((c) => (
                        <button key={c.id} type="button"
                          className="rounded-full bg-surface2 px-3 py-1.5 text-xs font-medium transition-colors hover:bg-hover"
                          onClick={() => { setAlertChat(c.id); setChats(null); setTgNote(null) }}>
                          {c.name} <span className="text-faint">· {c.id}</span>
                        </button>
                      ))}
                    </div>
                  )}
                  {tgNote && (
                    <p className={`mt-1.5 text-xs font-medium ${tgNote.ok ? 'text-income' : 'text-danger'}`}>
                      {tgNote.text}
                    </p>
                  )}
                  {alertChat.trim() !== '' && telegram?.hasToken && (
                    <button type="button" className="mt-1.5 text-xs font-semibold text-muted underline hover:text-ink"
                      onClick={sendTest} disabled={tgBusy}>
                      Send a test message to this chat
                    </button>
                  )}
                  {telegram && !telegram.hasToken && (
                    <p className="mt-1.5 text-xs font-medium text-danger">
                      No Telegram bot is connected yet — paste its token in Settings → Notifications
                      first, or this alert has nowhere to go.
                    </p>
                  )}
                </>
              )}
            </div>
            <div className="border-t border-line pt-3">
              <label className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" checked={excluded} onChange={(e) => setExcluded(e.target.checked)} className="h-4 w-4 accent-[var(--sk-accent)]" />
                Don't count this account
              </label>
              <p className="mt-1 pl-6 text-xs leading-relaxed text-faint">
                It keeps syncing and keeps showing its balance here, but it stops counting toward
                net worth and everything else on the overview, and its transactions leave the
                transactions list. Pick it in the account filter to see them again.
              </p>
            </div>
            <div>
              <label className="flex items-center gap-2 text-sm font-medium">
                <input type="checkbox" checked={archived} onChange={(e) => setArchived(e.target.checked)} className="h-4 w-4 accent-[var(--sk-accent)]" />
                Archive
              </label>
              <p className="mt-1 pl-6 text-xs leading-relaxed text-faint">
                For an account you've closed: the same, and it stops syncing and moves out of the
                list above.
              </p>
            </div>
          </div>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}

        <ModalActions busy={busy} onCancel={onClose} onSave={save} onDelete={isEdit ? remove : undefined} />
      </div>
    </Modal>
  )
}
