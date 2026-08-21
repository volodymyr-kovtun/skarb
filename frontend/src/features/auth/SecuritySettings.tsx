import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { KeyRound, ShieldCheck } from 'lucide-react'
import { api } from '../../shared/api'
import { Card, CardHeader, Modal, btnGhost, btnPrimary, cardPadX, errMsg, fieldLabelCls, inputCls } from '../../shared/ui'
import { RecoveryCodes } from './RecoveryCodes'

const MIN_PASSWORD = 12

/** Account security, as its own slice of Settings — nothing here touches bank connections. */
export function SecuritySettings() {
  const { data: session } = useQuery({ queryKey: ['session'], queryFn: api.session })
  const { data: recovery } = useQuery({ queryKey: ['recovery-left'], queryFn: api.recoveryCodesLeft })
  const [passwordOpen, setPasswordOpen] = useState(false)
  const [codesOpen, setCodesOpen] = useState(false)

  const remaining = recovery?.remaining ?? 0

  return (
    <Card className="pb-7">
      <CardHeader title="Security" />
      <div className={`flex flex-col pt-1 ${cardPadX}`}>
        <Row label="Signed in as" value={session?.email ?? '—'} />

        <Row
          label="Two-factor"
          value={
            <span className="inline-flex items-center gap-1.5 rounded-md bg-income/10 px-1.5 py-0.5 text-[11px] font-medium text-income">
              <ShieldCheck size={12} />
              Authenticator app
            </span>
          }
        />

        <Row
          label="Recovery codes"
          value={
            <span className={remaining <= 2 ? 'text-danger' : undefined}>
              {remaining} unused
            </span>
          }
          action={
            <button className="text-xs font-semibold text-muted transition-colors hover:text-ink" onClick={() => setCodesOpen(true)}>
              Regenerate
            </button>
          }
        />

        <div className="mt-5">
          <button className={btnGhost} onClick={() => setPasswordOpen(true)}>
            <KeyRound size={15} />
            Change password
          </button>
        </div>
      </div>

      {passwordOpen && <ChangePasswordModal onClose={() => setPasswordOpen(false)} />}
      {codesOpen && <RegenerateCodesModal onClose={() => setCodesOpen(false)} />}
    </Card>
  )
}

function Row({ label, value, action }: { label: string; value: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-4 border-b border-line py-3.5 text-[13.5px] last:border-0">
      <span className="text-muted">{label}</span>
      <span className="ml-auto truncate">{value}</span>
      {action}
    </div>
  )
}

function ChangePasswordModal({ onClose }: { onClose: () => void }) {
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  const save = async () => {
    setBusy(true)
    setError('')
    try {
      await api.changePassword({ currentPassword: current, newPassword: next })
      setDone(true)
    } catch (e) {
      setError(errMsg(e, 'Could not change the password'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title="Change password" onClose={onClose}>
      {done ? (
        <div className="flex flex-col gap-4">
          <p className="text-sm text-muted">
            Password updated. Every other signed-in browser has been signed out.
          </p>
          <button className={btnPrimary} onClick={onClose}>Done</button>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <label className="block">
            <span className={fieldLabelCls}>Current password</span>
            <input className={inputCls} type="password" value={current} autoComplete="current-password"
              onChange={(e) => setCurrent(e.target.value)} autoFocus />
          </label>
          <label className="block">
            <span className={fieldLabelCls}>New password</span>
            <input className={inputCls} type="password" value={next} autoComplete="new-password"
              onChange={(e) => setNext(e.target.value)} />
            <span className="mt-1 block text-xs text-faint">At least {MIN_PASSWORD} characters.</span>
          </label>
          <label className="block">
            <span className={fieldLabelCls}>Confirm new password</span>
            <input className={inputCls} type="password" value={confirm} autoComplete="new-password"
              onChange={(e) => setConfirm(e.target.value)} />
          </label>
          {error && <p className="text-sm text-danger">{error}</p>}
          <div className="mt-1 flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>Cancel</button>
            <button
              className={btnPrimary}
              onClick={save}
              disabled={busy || !current || next.length < MIN_PASSWORD || next !== confirm}
            >
              {busy ? 'Saving…' : 'Change password'}
            </button>
          </div>
        </div>
      )}
    </Modal>
  )
}

function RegenerateCodesModal({ onClose }: { onClose: () => void }) {
  const qc = useQueryClient()
  const [password, setPassword] = useState('')
  const [codes, setCodes] = useState<string[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const regenerate = async () => {
    setBusy(true)
    setError('')
    try {
      const { recoveryCodes } = await api.newRecoveryCodes({ currentPassword: password })
      setCodes(recoveryCodes)
      qc.invalidateQueries({ queryKey: ['recovery-left'] })
    } catch (e) {
      setError(errMsg(e, 'Could not regenerate codes'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title="Recovery codes" onClose={onClose}>
      {codes ? (
        <div className="flex flex-col gap-4">
          <RecoveryCodes codes={codes} />
          <p className="text-xs text-muted">
            The previous set no longer works. Replace whatever copy you kept.
          </p>
          <button className={btnPrimary} onClick={onClose}>Done</button>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-muted">
            This issues a fresh set and invalidates the old one. Confirm with your password.
          </p>
          <label className="block">
            <span className={fieldLabelCls}>Password</span>
            <input className={inputCls} type="password" value={password} autoComplete="current-password"
              onChange={(e) => setPassword(e.target.value)} autoFocus />
          </label>
          {error && <p className="text-sm text-danger">{error}</p>}
          <div className="mt-1 flex justify-end gap-2">
            <button className={btnGhost} onClick={onClose}>Cancel</button>
            <button className={btnPrimary} onClick={regenerate} disabled={busy || !password}>
              {busy ? 'Generating…' : 'Generate new codes'}
            </button>
          </div>
        </div>
      )}
    </Modal>
  )
}
