import { useState, type FormEvent } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { ShieldCheck } from 'lucide-react'
import { api, type SetupChallenge } from '../../shared/api'
import { btnPrimary, errMsg, fieldLabelCls, inputCls } from '../../shared/ui'
import { AuthShell, FormError, codeInputCls } from './AuthShell'
import { RecoveryCodes } from './RecoveryCodes'

const MIN_PASSWORD = 12

/**
 * Claiming a fresh instance, in three steps: credentials, authenticator, recovery codes.
 * The account only becomes usable at the end, so a half-finished setup can simply be redone.
 */
export default function SetupPage({ onDone }: { onDone: () => void }) {
  const [step, setStep] = useState<1 | 2 | 3>(1)
  const [setupToken, setSetupToken] = useState('')
  const [email, setEmail] = useState('')
  const [challenge, setChallenge] = useState<SetupChallenge | null>(null)
  const [codes, setCodes] = useState<string[]>([])

  return (
    <AuthShell
      wide={step > 1}
      title={step === 3 ? 'Save your recovery codes' : 'Set up Skarb'}
      subtitle={
        step === 1 ? 'This instance has no owner yet. Claim it to keep your finances yours.'
          : step === 2 ? 'Add Skarb to your authenticator app, then confirm a code.'
          : 'Each code signs you in once if you ever lose your authenticator.'
      }
      footer={step === 1 && (
        <>The setup token was printed in the server log when Skarb started.</>
      )}
    >
      <Steps current={step} />

      {step === 1 && (
        <CredentialsStep
          setupToken={setupToken}
          onTokenChange={setSetupToken}
          email={email}
          onEmailChange={setEmail}
          onDone={(c) => { setChallenge(c); setStep(2) }}
        />
      )}

      {step === 2 && challenge && (
        <AuthenticatorStep
          challenge={challenge}
          setupToken={setupToken}
          onDone={(c) => { setCodes(c); setStep(3) }}
        />
      )}

      {step === 3 && (
        <div className="flex flex-col gap-4">
          <RecoveryCodes codes={codes} />
          <p className="rounded-xl bg-paper px-3 py-2 text-xs leading-relaxed text-muted">
            Store them somewhere other than the device holding your authenticator — a password
            manager or a printout. They are shown only now.
          </p>
          <button className={`${btnPrimary} w-full`} onClick={onDone}>
            I've saved them — open Skarb
          </button>
        </div>
      )}
    </AuthShell>
  )
}

function Steps({ current }: { current: 1 | 2 | 3 }) {
  return (
    <div className="mb-5 flex gap-1.5" aria-hidden>
      {[1, 2, 3].map((n) => (
        <span
          key={n}
          className={`h-1 flex-1 rounded-full transition-colors ${n <= current ? 'bg-ink' : 'bg-line'}`}
        />
      ))}
    </div>
  )
}

function CredentialsStep({ setupToken, onTokenChange, email, onEmailChange, onDone }: {
  setupToken: string
  onTokenChange: (v: string) => void
  email: string
  onEmailChange: (v: string) => void
  onDone: (challenge: SetupChallenge) => void
}) {
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const mismatch = confirm.length > 0 && confirm !== password
  const valid = email.includes('@') && password.length >= MIN_PASSWORD && confirm === password && setupToken.trim()

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      onDone(await api.setup({ setupToken: setupToken.trim(), email: email.trim(), password }))
    } catch (err) {
      setError(errMsg(err, 'Setup failed'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="flex flex-col gap-4" onSubmit={submit}>
      <label className="block">
        <span className={fieldLabelCls}>Setup token</span>
        <input
          className={`${inputCls} font-mono text-xs`}
          value={setupToken}
          onChange={(e) => onTokenChange(e.target.value)}
          autoComplete="off"
          autoFocus
          required
        />
      </label>

      <label className="block">
        <span className={fieldLabelCls}>Email</span>
        <input
          className={inputCls}
          type="email"
          value={email}
          onChange={(e) => onEmailChange(e.target.value)}
          autoComplete="username"
          required
        />
      </label>

      <label className="block">
        <span className={fieldLabelCls}>Password</span>
        <input
          className={inputCls}
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          autoComplete="new-password"
          required
        />
        <span className="mt-1 block text-xs text-faint">
          At least {MIN_PASSWORD} characters. A passphrase of a few words beats a short scramble.
        </span>
      </label>

      <label className="block">
        <span className={fieldLabelCls}>Confirm password</span>
        <input
          className={inputCls}
          type="password"
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          autoComplete="new-password"
          required
        />
        {mismatch && <span className="mt-1 block text-xs text-danger">Passwords don't match.</span>}
      </label>

      {error && <FormError>{error}</FormError>}

      <button className={`${btnPrimary} w-full`} disabled={busy || !valid}>
        {busy ? 'Creating…' : 'Continue'}
      </button>
    </form>
  )
}

function AuthenticatorStep({ challenge, setupToken, onDone }: {
  challenge: SetupChallenge
  setupToken: string
  onDone: (codes: string[]) => void
}) {
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      const { recoveryCodes } = await api.setupConfirm({ setupToken: setupToken.trim(), code })
      onDone(recoveryCodes)
    } catch (err) {
      setError(errMsg(err, 'That code was not accepted'))
      setCode('')
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="flex flex-col gap-4" onSubmit={submit}>
      <div className="flex justify-center">
        <div className="rounded-2xl border border-line bg-white p-3">
          <QRCodeSVG value={challenge.provisioningUri} size={164} level="M" fgColor="#131b2e" bgColor="#ffffff" />
        </div>
      </div>

      <p className="text-center text-xs leading-relaxed text-muted">
        Scan with 1Password, Aegis, Bitwarden, Google Authenticator — any TOTP app.
      </p>

      <details className="text-xs text-muted">
        <summary className="cursor-pointer font-medium text-faint transition-colors hover:text-muted">
          Can't scan? Enter the key by hand
        </summary>
        <code className="mt-2 block rounded-lg bg-paper px-3 py-2 font-mono text-[11px] leading-relaxed break-all">
          {challenge.secret}
        </code>
      </details>

      <label className="block">
        <span className={fieldLabelCls}>Code from the app</span>
        <input
          className={codeInputCls}
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          placeholder="000000"
          inputMode="numeric"
          autoComplete="one-time-code"
          autoFocus
          required
        />
      </label>

      {error && <FormError>{error}</FormError>}

      <button className={`${btnPrimary} flex w-full items-center justify-center gap-2`} disabled={busy || code.length < 6}>
        <ShieldCheck size={15} />
        {busy ? 'Verifying…' : 'Turn on two-factor'}
      </button>
    </form>
  )
}
