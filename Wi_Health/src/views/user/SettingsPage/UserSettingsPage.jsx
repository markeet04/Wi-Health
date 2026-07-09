import './UserSettingsPage.css'

function UserSettingsPage() {
  return (
    <section className="page-grid user-settings-page page-fade">
      <div className="card">
        <h2>Account Access</h2>
        <div className="metric-stack">
          <div className="metric-row"><span>Registration</span><strong>Enabled</strong></div>
          <div className="metric-row"><span>Login</span><strong>Active session</strong></div>
          <div className="metric-row"><span>Email verification</span><strong>Verified</strong></div>
          <div className="metric-row"><span>Password reset</span><strong>Available</strong></div>
        </div>
        <div className="inline-actions">
          <button type="button">Register</button>
          <button type="button">Login</button>
          <button type="button">Logout</button>
        </div>
      </div>

      <div className="card">
        <h2>Notification Preferences</h2>
        <form className="stacked-form">
          <label>
            Alert level
            <select defaultValue="Urgent and informational"><option>Urgent only</option><option>Urgent and informational</option></select>
          </label>
          <label>
            Push delivery
            <select defaultValue="Enabled"><option>Enabled</option><option>Disabled</option></select>
          </label>
          <label>
            Reminder window
            <input type="text" defaultValue="15 minutes before nightly review" />
          </label>
        </form>
      </div>

      <div className="card">
        <h2>Privacy and Device Access</h2>
        <form className="stacked-form">
          <label>
            Shared devices
            <select defaultValue="Only linked devices"><option>Only linked devices</option><option>All patient devices</option></select>
          </label>
          <label>
            Password reset window (min)
            <input type="number" defaultValue="30" />
          </label>
          <label>
            Sync mode
            <select defaultValue="Realtime"><option>Realtime</option><option>Manual refresh</option></select>
          </label>
          <button type="button">Save Preferences</button>
        </form>
      </div>
    </section>
  )
}

export default UserSettingsPage