import { useState } from 'react'
import './LoginPage.css'

const TAGS = ['Live fleet oversight', 'Instant anomaly alerts', 'Role-scoped access']

const WAVE_PATH =
  'M0,60 L40,60 C55,60 60,20 75,20 C90,20 92,100 108,100 C124,100 128,10 145,10 ' +
  'C162,10 165,105 182,105 C199,105 202,25 218,25 C234,25 238,95 254,95 ' +
  'C270,95 274,35 290,35 C306,35 309,80 325,60 L400,60'

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m4 7 8 6 8-6" />
    </svg>
  )
}

function LockIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="11" width="16" height="10" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    </svg>
  )
}

function EyeIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M1.5 12S5 5 12 5s10.5 7 10.5 7-3.5 7-10.5 7S1.5 12 1.5 12Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  )
}

function EyeOffIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 3l18 18" />
      <path d="M10.6 5.1A10.9 10.9 0 0 1 12 5c7 0 10.5 7 10.5 7a13.5 13.5 0 0 1-3.1 4.1M6.6 6.6C3.5 8.5 1.5 12 1.5 12s3.5 7 10.5 7a10.7 10.7 0 0 0 4.3-.9" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
    </svg>
  )
}

function ArrowIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  )
}

function LoginPage({ onLogin, loading = false, error = '' }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)

  const handleSubmit = async (event) => {
    event.preventDefault()
    await onLogin({ email, password })
  }

  return (
    <div className="auth-shell page-fade">
      <section className="auth-scope">
        <div className="auth-scope__grid" aria-hidden="true" />

        <div className="auth-scope__trace" aria-hidden="true">
          <svg viewBox="0 0 400 120" preserveAspectRatio="none">
            <path className="auth-scope__trace-ghost" d={WAVE_PATH} />
            <path className="auth-scope__trace-line" d={WAVE_PATH} />
          </svg>
          <span className="auth-scope__scanner" />
        </div>

        <div className="auth-scope__readout auth-scope__readout--a">
          <strong>16.2</strong>
          <span>rpm avg</span>
        </div>
        <div className="auth-scope__readout auth-scope__readout--b">
          <strong>Live</strong>
          <span>signal lock</span>
        </div>

        <div className="auth-scope__body">
          <p className="auth-scope__kicker">Wi-Netra Health</p>
          <h1>
            Wi-Health
            <span className="auth-scope__cursor" aria-hidden="true" />
          </h1>
          <p className="auth-scope__tagline">
            Contactless WiFi-CSI breathing monitoring — fleet oversight, live alerts, and
            patient assignment, read straight off the signal.
          </p>

          <ul className="auth-scope__tags">
            {TAGS.map((tag) => (
              <li key={tag}>{tag}</li>
            ))}
          </ul>
        </div>
      </section>

      <section className="auth-access">
        <div className="auth-access__inner">
          <header className="auth-access__head">
            <p className="auth-access__kicker">Admin console</p>
            <h2>Sign in</h2>
            <p className="auth-access__lede">
              Load the live dashboard, user assignments, alerts, and complaints from the
              backend.
            </p>
          </header>

          <form className="auth-form" onSubmit={handleSubmit} noValidate>
            <label className="auth-line">
              <span className="auth-line__label">Email</span>
              <div className="auth-line__control">
                <MailIcon />
                <input
                  type="email"
                  value={email}
                  placeholder="admin@wi-health.io"
                  autoComplete="email"
                  onChange={(event) => setEmail(event.target.value)}
                />
              </div>
            </label>

            <label className="auth-line">
              <span className="auth-line__label">Password</span>
              <div className="auth-line__control">
                <LockIcon />
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  onChange={(event) => setPassword(event.target.value)}
                />
                <button
                  type="button"
                  className="auth-line__toggle"
                  onClick={() => setShowPassword((value) => !value)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOffIcon /> : <EyeIcon />}
                </button>
              </div>
            </label>

            {error ? (
              <p className="auth-error" role="alert">
                {error}
              </p>
            ) : null}

            <button type="submit" className="auth-go" disabled={loading}>
              <span>{loading ? 'Signing in' : 'Continue as admin'}</span>
              {loading ? <span className="auth-spinner" aria-hidden="true" /> : <ArrowIcon />}
            </button>
          </form>

          <p className="auth-hint">
            Requires a Firebase account with the admin role. The demo account only works while
            the backend runs without Firebase configured.
          </p>
        </div>
      </section>
    </div>
  )
}

export default LoginPage
