import './LoginPage.css'
import { useState } from 'react'

function LoginPage({ onLogin, loading = false, error = '' }) {
  const [email, setEmail] = useState('admin@wi-netra.health')
  const [password, setPassword] = useState('demo-password')

  return (
    <div className="login-shell login-page page-fade">
      <section className="login-card login-page__card">
        <div className="login-card__hero login-page__hero">
          <p className="muted">Wi-Netra Health</p>
          <h1>Admin sign in</h1>
          <p>
            Sign in with an admin account to load the live dashboard, user assignments, alerts, and
            complaints from the backend.
          </p>
          <p className="login-page__hint">
            If the backend is not configured yet, the demo admin account still opens the local fallback
            data so the UI remains usable during development.
          </p>
        </div>

        <form
          className="login-form login-page__form"
          onSubmit={async (event) => {
            event.preventDefault()
            await onLogin({ email, password })
          }}
        >
          <label>
            Email
            <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
          </label>
          <label>
            Password
            <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} />
          </label>
          <div className="login-page__actions">
            {error ? <p className="login-error">{error}</p> : <span />}
            <button type="submit" disabled={loading}>
              {loading ? 'Signing in...' : 'Continue as Admin'}
            </button>
          </div>
        </form>
      </section>
    </div>
  )
}

export default LoginPage
