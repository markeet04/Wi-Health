import './LoginPage.css'

function LoginPage({ onLogin }) {
  return (
    <div className="login-shell login-page page-fade">
      <section className="login-card login-page__card">
        <div className="login-card__hero login-page__hero">
          <p className="muted">Wi-Netra Health</p>
          <h1>Admin sign in</h1>
          <p>
            The web panel is the oversight console for administrators only — track fleet health, manage
            device and patient assignments, and review alerts and complaints. Patients and caregivers use
            the Wi-Health mobile app.
          </p>
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
            <input type="email" defaultValue="admin@wi-netra.health" />
          </label>
          <label>
            Password
            <input type="password" defaultValue="demo-password" />
          </label>
          <button type="submit">Continue as Admin</button>
        </form>
      </section>
    </div>
  )
}

export default LoginPage
