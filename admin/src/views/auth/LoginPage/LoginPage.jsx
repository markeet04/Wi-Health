import './LoginPage.css'
import { useState } from 'react'

function LoginPage({ onLogin, loading = false, error = '' }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')

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
            Requires a Firebase account with the admin role. The demo account only works while the
            backend runs without Firebase configuration.
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
            <input
              type="email"
              value={email}
              placeholder="admin email"
              onChange={(event) => setEmail(event.target.value)}
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              placeholder="password"
              onChange={(event) => setPassword(event.target.value)}
            />
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
