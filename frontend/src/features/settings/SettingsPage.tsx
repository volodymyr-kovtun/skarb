import { useEffect, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { formatDistanceToNow, parseISO } from 'date-fns'
import { Landmark, Plug, Upload, Trash2, RefreshCw, Webhook, CheckCircle2, AlertCircle } from 'lucide-react'
import { accountLabel, api, refreshAll, type Connection, type Meta } from '../../shared/api'
import { Card, CardHeader, Modal, btnGhost, btnPrimary, errMsg, fieldLabelCls, inputCls } from '../../shared/ui'

export default function SettingsPage() {
  const qc = useQueryClient()
  const [params, setParams] = useSearchParams()
  const { data: connections } = useQuery({ queryKey: ['connections'], queryFn: api.connections })
  const { data: meta } = useQuery({ queryKey: ['meta'], queryFn: api.meta })
  const { data: status } = useQuery({ queryKey: ['sync-status'], queryFn: api.syncStatus, refetchInterval: 10_000 })

  const [monoOpen, setMonoOpen] = useState(false)
  const [ebOpen, setEbOpen] = useState(false)
  const [csvOpen, setCsvOpen] = useState(false)
  const [banner, setBanner] = useState<{ ok: boolean; text: string } | null>(null)
  const completing = useRef(false)

  const refresh = () => refreshAll(qc)

  // Enable Banking sends the user back here with ?code=...&state=<connectionId>
  useEffect(() => {
    const code = params.get('code')
    const state = params.get('state')
    if (!code || !state || completing.current) return
    completing.current = true
    api.ebComplete(state, code)
      .then(() => setBanner({ ok: true, text: 'Bank linked. First sync has started — transactions will appear shortly.' }))
      .catch((e) => setBanner({ ok: false, text: `Bank linking failed: ${e.message}` }))
      .finally(() => { setParams({}, { replace: true }); refresh() })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params])

  return (
    <div className="flex flex-col gap-5">
      <div className="px-1 pt-2">
        <h1 className="font-display text-2xl font-bold tracking-tight">Settings</h1>
        <p className="mt-1 text-sm text-muted">Bank connections, imports and automation.</p>
      </div>

      {banner && (
        <div className={`flex items-center gap-2 rounded-xl border px-4 py-3 text-sm ${banner.ok ? 'border-income/30 bg-income/5 text-income' : 'border-danger/30 bg-danger/5 text-danger'}`}>
          {banner.ok ? <CheckCircle2 size={16} /> : <AlertCircle size={16} />}
          {banner.text}
          <button className="ml-auto text-xs underline" onClick={() => setBanner(null)}>dismiss</button>
        </div>
      )}

      {/* Connections */}
      <Card className="pb-4">
        <CardHeader title="Bank connections" />
        <div className="flex flex-col gap-3 px-5 pt-2">
          {(connections ?? []).length === 0 && (
            <p className="text-sm text-muted">
              Nothing connected yet. Link Monobank with a personal token, or any of 2,500+ European banks
              (PKO BP included) through Enable Banking.
            </p>
          )}
          {(connections ?? []).map((c) => (
            <ConnectionRow key={c.id} c={c} onChanged={refresh} />
          ))}
          <div className="mt-1 flex gap-2">
            <button className={btnPrimary} onClick={() => setMonoOpen(true)}>
              <Plug size={14} className="mr-1.5 inline -translate-y-px" />Connect Monobank
            </button>
            <button className={btnPrimary} onClick={() => setEbOpen(true)}>
              <Landmark size={14} className="mr-1.5 inline -translate-y-px" />Connect a bank
            </button>
            <button className={btnGhost} onClick={() => setCsvOpen(true)}>
              <Upload size={14} className="mr-1.5 inline -translate-y-px" />Import CSV (ZEN, …)
            </button>
          </div>
        </div>
      </Card>

      {/* Sync activity */}
      <Card className="pb-3">
        <CardHeader title="Sync activity" />
        <div className="px-5 pt-1">
          {(status?.logs ?? []).length === 0 ? (
            <p className="pb-3 text-sm text-faint">No syncs yet.</p>
          ) : (
            <ul className="flex flex-col">
              {status!.logs.map((l, i) => (
                <li key={i} className="flex items-start gap-2 border-b border-line py-2 text-sm last:border-0">
                  {l.success
                    ? <CheckCircle2 size={15} className="mt-0.5 shrink-0 text-income" />
                    : <AlertCircle size={15} className="mt-0.5 shrink-0 text-danger" />}
                  <span className="text-muted">{l.message}</span>
                  <span className="ml-auto shrink-0 text-xs text-faint">
                    {formatDistanceToNow(parseISO(l.at), { addSuffix: true })}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </Card>

      {monoOpen && <MonobankModal onClose={() => setMonoOpen(false)} onDone={() => { setMonoOpen(false); refresh() }} />}
      {ebOpen && <EnableBankingModal onClose={() => setEbOpen(false)} />}
      {csvOpen && meta && <CsvModal meta={meta} onClose={() => setCsvOpen(false)} onDone={(msg) => { setCsvOpen(false); setBanner({ ok: true, text: msg }); refresh() }} />}
    </div>
  )
}

function ConnectionRow({ c, onChanged }: { c: Connection; onChanged: () => void }) {
  const [webhookOpen, setWebhookOpen] = useState(false)
  const statusChip =
    c.status === 'linked' ? 'bg-income/10 text-income' :
    c.status === 'error' ? 'bg-danger/10 text-danger' : 'bg-paper text-muted'

  return (
    <div className="rounded-xl border border-line px-4 py-3">
      <div className="flex items-center gap-3">
        <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-ink font-display text-sm font-bold text-white">
          {c.displayName.slice(0, 1)}
        </span>
        <div className="min-w-0">
          <p className="text-sm font-semibold">
            {c.displayName}
            <span className={`ml-2 rounded-md px-1.5 py-0.5 text-[11px] font-medium ${statusChip}`}>{c.status}</span>
          </p>
          <p className="text-xs text-faint">
            {c.accountCount} account{c.accountCount === 1 ? '' : 's'}
            {c.lastSyncedAt && ` · synced ${formatDistanceToNow(parseISO(c.lastSyncedAt), { addSuffix: true })}`}
            {c.consentValidUntil && ` · consent until ${parseISO(c.consentValidUntil).toLocaleDateString()}`}
          </p>
        </div>
        <div className="ml-auto flex items-center gap-1">
          {c.provider === 'monobank' && (
            <button title="Instant sync (webhook)" className="rounded-lg p-2 text-muted hover:bg-paper hover:text-ink" onClick={() => setWebhookOpen(true)}>
              <Webhook size={16} />
            </button>
          )}
          <button title="Sync now" className="rounded-lg p-2 text-muted hover:bg-paper hover:text-ink"
            onClick={async () => { await api.syncOne(c.id); onChanged() }}>
            <RefreshCw size={16} />
          </button>
          <button title="Remove connection" className="rounded-lg p-2 text-muted hover:bg-paper hover:text-danger"
            onClick={async () => {
              if (confirm(`Remove ${c.displayName}? Accounts and transactions are kept.`)) {
                await api.deleteConnection(c.id)
                onChanged()
              }
            }}>
            <Trash2 size={16} />
          </button>
        </div>
      </div>
      {c.lastError && <p className="mt-2 rounded-lg bg-danger/5 px-3 py-2 text-xs text-danger">{c.lastError}</p>}
      {webhookOpen && <WebhookModal connectionId={c.id} onClose={() => setWebhookOpen(false)} />}
    </div>
  )
}

function MonobankModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [token, setToken] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const connect = async () => {
    setBusy(true)
    setError('')
    try {
      await api.connectMonobank(token)
      onDone()
    } catch (e) {
      setError(errMsg(e, 'Failed'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title="Connect Monobank" onClose={onClose}>
      <ol className="mb-4 list-decimal space-y-1 pl-5 text-sm text-muted">
        <li>Open <a className="font-medium text-ink underline" href="https://api.monobank.ua/" target="_blank" rel="noreferrer">api.monobank.ua</a></li>
        <li>Scan the QR code with your Monobank app and confirm</li>
        <li>Copy the personal token and paste it below</li>
      </ol>
      <input className={inputCls} placeholder="Personal API token" value={token} onChange={(e) => setToken(e.target.value)} autoFocus />
      <p className="mt-2 text-xs text-faint">
        The token grants read access to your statements. It is stored only in your local Skarb database.
        First sync fetches the last 31 days and can take a few minutes (Monobank allows one request per minute).
      </p>
      {error && <p className="mt-2 text-sm text-danger">{error}</p>}
      <div className="mt-4 flex justify-end gap-2">
        <button className={btnGhost} onClick={onClose}>Cancel</button>
        <button className={btnPrimary} onClick={connect} disabled={busy || !token.trim()}>
          {busy ? 'Connecting…' : 'Connect & sync'}
        </button>
      </div>
    </Modal>
  )
}

function WebhookModal({ connectionId, onClose }: { connectionId: string; onClose: () => void }) {
  const [baseUrl, setBaseUrl] = useState('')
  const [result, setResult] = useState('')
  const [error, setError] = useState('')

  const enable = async () => {
    setError('')
    try {
      const r = await api.setMonobankWebhook(connectionId, baseUrl)
      setResult(r.webhookUrl)
    } catch (e) {
      setError(errMsg(e, 'Failed'))
    }
  }

  return (
    <Modal title="Instant sync (webhook)" onClose={onClose}>
      <p className="text-sm text-muted">
        Monobank can push every payment to Skarb the moment it happens. That needs a public HTTPS
        address for this app — for personal use a <span className="font-medium text-ink">Cloudflare Tunnel</span> or{' '}
        <span className="font-medium text-ink">Tailscale Funnel</span> works well (see docs/BANKS.md).
      </p>
      <input className={inputCls + ' mt-3'} placeholder="https://skarb.example.com" value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} />
      {result && <p className="mt-2 break-all rounded-lg bg-income/5 px-3 py-2 text-xs text-income">Webhook registered: {result}</p>}
      {error && <p className="mt-2 text-sm text-danger">{error}</p>}
      <div className="mt-4 flex justify-end gap-2">
        <button className={btnGhost} onClick={onClose}>Close</button>
        <button className={btnPrimary} onClick={enable} disabled={!baseUrl.startsWith('https://')}>Enable</button>
      </div>
    </Modal>
  )
}

function EnableBankingModal({ onClose }: { onClose: () => void }) {
  const [step, setStep] = useState<1 | 2>(1)
  const [displayName, setDisplayName] = useState('PKO Bank Polski')
  const [appId, setAppId] = useState('')
  const [pem, setPem] = useState('')
  const [connectionId, setConnectionId] = useState('')
  const [banks, setBanks] = useState<{ name: string; country: string }[]>([])
  const [bankFilter, setBankFilter] = useState('')
  const [country, setCountry] = useState('PL')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const createConnection = async () => {
    setBusy(true)
    setError('')
    try {
      const { id } = await api.connectEnableBanking({ displayName, applicationId: appId, privateKeyPem: pem })
      setConnectionId(id)
      const list = await api.ebAspsps(id, country)
      setBanks(list)
      setStep(2)
    } catch (e) {
      setError(errMsg(e, 'Failed'))
    } finally {
      setBusy(false)
    }
  }

  const loadBanks = async (cc: string) => {
    setCountry(cc)
    setBusy(true)
    try {
      setBanks(await api.ebAspsps(connectionId, cc))
    } finally {
      setBusy(false)
    }
  }

  const authorize = async (bankName: string, bankCountry: string) => {
    setBusy(true)
    setError('')
    try {
      const { url } = await api.ebAuthorize(connectionId, {
        aspspName: bankName,
        aspspCountry: bankCountry,
        redirectUrl: window.location.origin + '/settings',
      })
      window.location.href = url // bank authorization, returns to /settings?code=…&state=…
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed')
      setBusy(false)
    }
  }

  const shown = banks.filter((b) => b.name.toLowerCase().includes(bankFilter.toLowerCase()))

  return (
    <Modal title="Connect a bank via Enable Banking" onClose={onClose} wide>
      {step === 1 ? (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-muted">
            Enable Banking is a licensed open-banking provider covering 2,500+ European banks, free for
            accessing your own accounts. Create an application at{' '}
            <a href="https://enablebanking.com/cp/applications" target="_blank" rel="noreferrer" className="font-medium text-ink underline">enablebanking.com</a>{' '}
            (environment: <span className="font-medium text-ink">Production</span>, link your own bank account in their portal),
            then paste its credentials here. Full walkthrough: <span className="font-medium">docs/BANKS.md</span>.
          </p>
          <label className="text-sm">
            <span className={fieldLabelCls}>Connection name</span>
            <input className={inputCls} value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="PKO Bank Polski" />
          </label>
          <label className="text-sm">
            <span className={fieldLabelCls}>Application ID</span>
            <input className={inputCls} value={appId} onChange={(e) => setAppId(e.target.value)} placeholder="xxxxxxxx-xxxx-…" />
          </label>
          <label className="text-sm">
            <span className={fieldLabelCls}>RSA private key (PEM)</span>
            <textarea className={inputCls + ' h-28 font-mono text-xs'} value={pem} onChange={(e) => setPem(e.target.value)}
              placeholder={'-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----'} />
          </label>
          {error && <p className="text-sm text-danger">{error}</p>}
          <div className="flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>Cancel</button>
            <button className={btnPrimary} onClick={createConnection} disabled={busy || !appId.trim() || !pem.includes('PRIVATE KEY')}>
              {busy ? 'Checking…' : 'Continue'}
            </button>
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <div className="flex gap-2">
            <select className={inputCls + ' w-40'} value={country} onChange={(e) => loadBanks(e.target.value)}>
              <option value="ALL">🌍 All countries</option>
              {['PL', 'LT', 'DE', 'FR', 'ES', 'IT', 'NL', 'BE', 'AT', 'PT', 'CZ', 'SK', 'HU', 'RO', 'BG', 'HR', 'SI', 'GR', 'IE', 'FI', 'SE', 'DK', 'NO', 'EE', 'LV', 'GB'].map((c) => <option key={c}>{c}</option>)}
            </select>
            <input className={inputCls} placeholder="Filter banks…" value={bankFilter} onChange={(e) => setBankFilter(e.target.value)} />
          </div>
          <div className="max-h-72 overflow-y-auto rounded-xl border border-line">
            {shown.slice(0, 200).map((b) => (
              <button key={`${b.country}:${b.name}`} disabled={busy}
                className="flex w-full items-center gap-2 border-b border-line px-4 py-2.5 text-left text-sm last:border-0 hover:bg-paper"
                onClick={() => authorize(b.name, b.country)}>
                <Landmark size={15} className="shrink-0 text-faint" />
                <span className="truncate">{b.name}</span>
                <span className="ml-auto flex shrink-0 items-center gap-2 text-xs text-faint">
                  <span className="rounded bg-paper px-1.5 py-0.5 font-medium">{b.country}</span>
                  authorize →
                </span>
              </button>
            ))}
            {shown.length > 200 && (
              <p className="px-4 py-2 text-center text-xs text-faint">Showing first 200 — refine the filter.</p>
            )}
            {shown.length === 0 && <p className="px-4 py-6 text-center text-sm text-faint">{busy ? 'Loading…' : 'No banks found.'}</p>}
          </div>
          <p className="text-xs text-faint">
            You will be redirected to the bank to approve read-only access (valid ~90 days), then brought back to{' '}
            <code className="rounded bg-paper px-1">{window.location.origin}/settings</code> — this exact URL must be in
            your Enable Banking app's allowed redirect URLs.
          </p>
          {error && <p className="text-sm text-danger">{error}</p>}
        </div>
      )}
    </Modal>
  )
}

const CSV_PRESETS: Record<string, { label: string; hint: string; dateColumn: number; amountColumn: number; descriptionColumn: number; currencyColumn: number | null; dateFormat: string; decimalSeparator: string; delimiter: string; invertAmount: boolean }> = {
  zen: {
    label: 'ZEN.com statement',
    hint: 'ZEN app → Wallet → currency → ⋯ → Statements → Generate (CSV). One file per currency.',
    dateColumn: 0, amountColumn: 1, descriptionColumn: 3, currencyColumn: 2,
    dateFormat: '', decimalSeparator: '.', delimiter: ',', invertAmount: false,
  },
  pko: {
    label: 'PKO iPKO export',
    hint: 'iPKO → account history → Eksport danych → CSV.',
    dateColumn: 0, amountColumn: 3, descriptionColumn: 6, currencyColumn: 4,
    dateFormat: 'yyyy-MM-dd', decimalSeparator: '.', delimiter: ',', invertAmount: false,
  },
  generic: {
    label: 'Generic CSV',
    hint: 'Any file with date, amount and description columns — set the column numbers below (first column = 0).',
    dateColumn: 0, amountColumn: 1, descriptionColumn: 2, currencyColumn: null,
    dateFormat: '', decimalSeparator: '.', delimiter: ',', invertAmount: false,
  },
}

function CsvModal({ meta, onClose, onDone }: { meta: Meta; onClose: () => void; onDone: (msg: string) => void }) {
  const [accountId, setAccountId] = useState(meta.accounts[0]?.id ?? '')
  const [preset, setPreset] = useState<keyof typeof CSV_PRESETS>('zen')
  const [cfg, setCfg] = useState(CSV_PRESETS.zen)
  const [content, setContent] = useState('')
  const [fileName, setFileName] = useState('')
  const [hasHeader, setHasHeader] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const pickPreset = (key: keyof typeof CSV_PRESETS) => {
    setPreset(key)
    setCfg(CSV_PRESETS[key])
  }

  const onFile = (f: File | undefined) => {
    if (!f) return
    setFileName(f.name)
    f.text().then(setContent)
  }

  const doImport = async () => {
    setBusy(true)
    setError('')
    try {
      const r = await api.importCsv({
        accountId, content,
        dateColumn: cfg.dateColumn, amountColumn: cfg.amountColumn,
        descriptionColumn: cfg.descriptionColumn, currencyColumn: cfg.currencyColumn,
        dateFormat: cfg.dateFormat, decimalSeparator: cfg.decimalSeparator,
        delimiter: cfg.delimiter, hasHeader, invertAmount: cfg.invertAmount,
      })
      const err = r.errors.length ? ` (${r.errors.length} row(s) skipped with errors)` : ''
      onDone(`Imported ${r.imported} transaction(s), ${r.skipped} duplicate(s) skipped${err}.`)
    } catch (e) {
      setError(errMsg(e, 'Import failed'))
    } finally {
      setBusy(false)
    }
  }

  const num = (v: string, fallback: number) => (Number.isNaN(parseInt(v)) ? fallback : parseInt(v))

  return (
    <Modal title="Import a bank statement (CSV)" onClose={onClose} wide>
      <div className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-3">
          <label className="text-sm">
            <span className={fieldLabelCls}>Into account</span>
            <select className={inputCls} value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              {meta.accounts.map((a) => <option key={a.id} value={a.id}>{accountLabel(a)} ({a.currency})</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className={fieldLabelCls}>Format preset</span>
            <select className={inputCls} value={preset} onChange={(e) => pickPreset(e.target.value as keyof typeof CSV_PRESETS)}>
              {Object.entries(CSV_PRESETS).map(([k, p]) => <option key={k} value={k}>{p.label}</option>)}
            </select>
          </label>
        </div>
        <p className="rounded-lg bg-paper px-3 py-2 text-xs text-muted">{cfg.hint}</p>

        <label className="flex cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed border-line px-4 py-6 text-sm text-muted transition-colors hover:border-ink hover:text-ink">
          <Upload size={16} />
          {fileName || 'Choose a .csv file'}
          <input type="file" accept=".csv,text/csv" className="hidden" onChange={(e) => onFile(e.target.files?.[0])} />
        </label>

        <details className="text-sm text-muted">
          <summary className="cursor-pointer text-xs font-medium">Column mapping (first column = 0)</summary>
          <div className="mt-2 grid grid-cols-4 gap-2">
            <label className="text-xs">Date col
              <input className={inputCls + ' mt-1'} type="number" value={cfg.dateColumn} onChange={(e) => setCfg({ ...cfg, dateColumn: num(e.target.value, 0) })} /></label>
            <label className="text-xs">Amount col
              <input className={inputCls + ' mt-1'} type="number" value={cfg.amountColumn} onChange={(e) => setCfg({ ...cfg, amountColumn: num(e.target.value, 1) })} /></label>
            <label className="text-xs">Description col
              <input className={inputCls + ' mt-1'} type="number" value={cfg.descriptionColumn} onChange={(e) => setCfg({ ...cfg, descriptionColumn: num(e.target.value, 2) })} /></label>
            <label className="text-xs">Currency col
              <input className={inputCls + ' mt-1'} type="number" value={cfg.currencyColumn ?? ''} placeholder="—"
                onChange={(e) => setCfg({ ...cfg, currencyColumn: e.target.value === '' ? null : num(e.target.value, 0) })} /></label>
            <label className="text-xs">Date format
              <input className={inputCls + ' mt-1'} value={cfg.dateFormat} placeholder="auto" onChange={(e) => setCfg({ ...cfg, dateFormat: e.target.value })} /></label>
            <label className="text-xs">Decimal sep.
              <select className={inputCls + ' mt-1'} value={cfg.decimalSeparator} onChange={(e) => setCfg({ ...cfg, decimalSeparator: e.target.value })}>
                <option value=".">.</option><option value=",">,</option>
              </select></label>
            <label className="text-xs">Delimiter
              <select className={inputCls + ' mt-1'} value={cfg.delimiter} onChange={(e) => setCfg({ ...cfg, delimiter: e.target.value })}>
                <option value=",">,</option><option value=";">;</option><option value="	">tab</option>
              </select></label>
            <label className="mt-5 flex items-center gap-1.5 text-xs">
              <input type="checkbox" checked={hasHeader} onChange={(e) => setHasHeader(e.target.checked)} className="accent-ink" />
              Header row
            </label>
          </div>
        </details>

        {error && <p className="text-sm text-danger">{error}</p>}
        <div className="flex justify-end gap-2">
          <button className={btnGhost} onClick={onClose}>Cancel</button>
          <button className={btnPrimary} onClick={doImport} disabled={busy || !content || !accountId}>
            {busy ? 'Importing…' : 'Import'}
          </button>
        </div>
      </div>
    </Modal>
  )
}
