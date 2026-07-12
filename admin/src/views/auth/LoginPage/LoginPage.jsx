import './LoginPage.css'

function LoginPage({ role, onSelectRole, onLogin }) {
  return (
    <div className="login-shell login-page page-fade">
      <section className="login-card login-page__card">
        <div className="login-card__hero login-page__hero">
          <p className="muted">Wi-Netra Health</p>
          <h1>Sign in to continue</h1>
          <p>
            Choose the view you want to enter. App User gives you the patient monitor, alerts, and support tools.
            Admin opens the oversight dashboard.
          </p>
        </div>

        <div className="login-card__roles login-page__roles" role="radiogroup" aria-label="Select role">
          <button
            type="button"
            className={role === 'user' ? 'login-role active' : 'login-role'}
            onClick={() => onSelectRole('user')}
          >
            <span>App User</span>
            <small>Monitor linked patients, review alerts, and submit support requests.</small>
          </button>
          <button
            type="button"
            className={role === 'admin' ? 'login-role active' : 'login-role'}
            onClick={() => onSelectRole('admin')}
          >
            <span>Admin</span>
            <small>Track fleet health, manage assignments, and review complaints.</small>
          </button>
        </div>

        <form
          className="login-form login-page__form"
          onSubmit={(event) => {
            event.preventDefault()
            onLogin()
          }}
        >
          <label>
            Email
            <input type="email" defaultValue="demo@wi-netra.health" />
          </label>
          <label>
            Password
            <input type="password" defaultValue="demo-password" />
          </label>
          <button type="submit">Continue as {role === 'admin' ? 'Admin' : 'App User'}</button>
        </form>
      </section>
    </div>
  )
}

export default LoginPage