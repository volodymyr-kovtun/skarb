import { useState, type FormEvent } from 'react'
import { api } from '../../shared/api'
import { btnPrimary, errMsg, fieldLabelCls, inputCls } from '../../shared/ui'
import { AuthShell, FormError, codeInputCls } from './AuthShell'

export default function LoginPage({ onSignedIn }: { onSignedIn: () => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [code, setCode] = useState('')
  const [recoveryCode, setRecoveryCode] = useState('')
  const [useRecovery, setUseRecovery] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      await api.login({
        email,
        password,
        ...(useRecovery ? { recoveryCode } : { code }),
      })
      onSignedIn()
    } catch (err) {
      setError(errMsg(err, 'Sign-in failed'))
      setCode('')
      setRecoveryCode('')
    } finally {
      setBusy(false)
    }
  }

  const secondFactorFilled = useRecovery ? recoveryCode.trim().length > 0 : code.trim().length >= 6

  return (
    <AuthShell title="Skarb" subtitle="Sign in to your ledger.">
      <form className="flex flex-col gap-4" onSubmit={submit}>
        <label className="block">
          <span className={fieldLabelCls}>Email</span>
          <input
            className={inputCls}
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username"
            autoFocus
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
            autoComplete="current-password"
            required
          />
        </label>

        {useRecovery ? (
          <label className="block">
            <span className={fieldLabelCls}>Recovery code</span>
            <input
              className={`${inputCls} text-center font-mono`}
              value={recoveryCode}
              onChange={(e) => setRecoveryCode(e.target.value)}
              placeholder="xxxxx-xxxxx"
              autoComplete="off"
              required
            />
          </label>
        ) : (
          <label className="block">
            <span className={fieldLabelCls}>Authenticator code</span>
            <input
              className={codeInputCls}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="000000"
              inputMode="numeric"
              autoComplete="one-time-code"
              required
            />
            <span className="mt-1.5 block text-xs leading-relaxed text-faint">
              Each code works once. If you just signed in, wait for the next one.
            </span>
          </label>
        )}

        {error && <FormError>{error}</FormError>}

        <button className={`${btnPrimary} w-full`} disabled={busy || !email || !password || !secondFactorFilled}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>

        <button
          type="button"
          className="text-center text-xs font-medium text-muted transition-colors hover:text-ink"
          onClick={() => {
            setUseRecovery((v) => !v)
            setError('')
          }}
        >
          {useRecovery ? 'Use my authenticator app' : 'Lost your phone? Use a recovery code'}
        </button>
      </form>
    </AuthShell>
  )
}
