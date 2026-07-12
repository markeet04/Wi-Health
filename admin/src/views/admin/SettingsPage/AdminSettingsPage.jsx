import './AdminSettingsPage.css'

function AdminSettingsPage() {
  return (
    <section className="page-grid admin-settings-page page-fade">
      <div className="card">
        <h2>Alert Defaults</h2>
        <form className="stacked-form">
          <label>
            Tachypnea Threshold (bpm)
            <input type="number" defaultValue="22" />
          </label>
          <label>
            Bradypnea Threshold (bpm)
            <input type="number" defaultValue="10" />
          </label>
          <label>
            Apnea Trigger Duration (sec)
            <input type="number" defaultValue="20" />
          </label>
        </form>
      </div>

      <div className="card">
        <h2>Role and Account Settings</h2>
        <form className="stacked-form">
          <label>
            Default Role for New Invite
            <select defaultValue="App User"><option>App User</option><option>Admin</option></select>
          </label>
          <label>
            Require Email Verification
            <select defaultValue="Yes"><option>Yes</option><option>No</option></select>
          </label>
          <label>
            Password Reset Window (min)
            <input type="number" defaultValue="30" />
          </label>
        </form>
      </div>

      <div className="card">
        <h2>Panel Preferences</h2>
        <form className="stacked-form">
          <label>
            Refresh Interval
            <select defaultValue="5 seconds"><option>5 seconds</option><option>10 seconds</option><option>30 seconds</option></select>
          </label>
          <label>
            Landing Page
            <select defaultValue="Statistics / Analytics"><option>Statistics / Analytics</option><option>User Management</option><option>Alerts</option><option>Complaints</option><option>Settings</option></select>
          </label>
          <button type="button">Save Preferences</button>
        </form>
      </div>
    </section>
  )
}

export default AdminSettingsPage