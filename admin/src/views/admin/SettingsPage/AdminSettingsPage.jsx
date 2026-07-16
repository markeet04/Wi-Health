import { useEffect, useState } from 'react'
import './AdminSettingsPage.css'
import { fetchAdminSettings, updateAdminSettings } from '../../../services/adminApi'

const emptySettings = {
  alertThresholds: {
    tachypneaBpm: 22,
    bradypneaBpm: 10,
    apneaTriggerSeconds: 20,
  },
  defaultRoleForNewInvite: 'app_user',
  requireEmailVerification: true,
  passwordResetWindowMinutes: 30,
  refreshIntervalSeconds: 5,
  landingPagePreference: 'Statistics / Analytics',
}

function AdminSettingsPage({ accessToken }) {
  const [settings, setSettings] = useState(emptySettings)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false

    async function loadSettings() {
      if (!accessToken) {
        setLoading(false)
        return
      }

      try {
        const nextSettings = await fetchAdminSettings(accessToken)
        if (!cancelled && nextSettings) {
          setSettings(nextSettings)
        }
      } catch {
        if (!cancelled) {
          setError('Unable to load saved settings.')
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    loadSettings()
    return () => {
      cancelled = true
    }
  }, [accessToken])

  const handleChange = (field, value) => {
    setMessage('')
    setError('')

    if (field.startsWith('alertThresholds.')) {
      const key = field.split('.')[1]
      setSettings((current) => ({
        ...current,
        alertThresholds: {
          ...current.alertThresholds,
          [key]: Number(value),
        },
      }))
      return
    }

    setSettings((current) => ({
      ...current,
      [field]: value,
    }))
  }

  const handleSubmit = async (event) => {
    event.preventDefault()

    if (!accessToken) {
      setError('Admin session is required to save settings.')
      return
    }

    setSaving(true)
    setMessage('')
    setError('')

    try {
      const nextSettings = await updateAdminSettings(accessToken, settings)
      setSettings(nextSettings)
      setMessage('Preferences saved successfully.')
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : 'Unable to save preferences.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="page-grid admin-settings-page page-fade">
      <form className="settings-layout" onSubmit={handleSubmit}>
        <div className="card settings-panel">
          <h2>Alert Defaults</h2>
          <div className="stacked-form">
            <label>
              Tachypnea Threshold (bpm)
              <input
                type="number"
                value={settings.alertThresholds.tachypneaBpm}
                onChange={(event) => handleChange('alertThresholds.tachypneaBpm', event.target.value)}
              />
            </label>
            <label>
              Bradypnea Threshold (bpm)
              <input
                type="number"
                value={settings.alertThresholds.bradypneaBpm}
                onChange={(event) => handleChange('alertThresholds.bradypneaBpm', event.target.value)}
              />
            </label>
            <label>
              Apnea Trigger Duration (sec)
              <input
                type="number"
                value={settings.alertThresholds.apneaTriggerSeconds}
                onChange={(event) => handleChange('alertThresholds.apneaTriggerSeconds', event.target.value)}
              />
            </label>
          </div>
        </div>

        <div className="card settings-panel">
          <h2>Role and Account Settings</h2>
          <div className="stacked-form">
            <label>
              Default Role for New Invite
              <select
                value={settings.defaultRoleForNewInvite}
                onChange={(event) => handleChange('defaultRoleForNewInvite', event.target.value)}
              >
                <option value="app_user">App User</option>
                <option value="admin">Admin</option>
              </select>
            </label>
            <label>
              Require Email Verification
              <select
                value={settings.requireEmailVerification ? 'Yes' : 'No'}
                onChange={(event) => handleChange('requireEmailVerification', event.target.value === 'Yes')}
              >
                <option value="Yes">Yes</option>
                <option value="No">No</option>
              </select>
            </label>
            <label>
              Password Reset Window (min)
              <input
                type="number"
                value={settings.passwordResetWindowMinutes}
                onChange={(event) => handleChange('passwordResetWindowMinutes', Number(event.target.value))}
              />
            </label>
          </div>
        </div>

        <div className="card settings-panel">
          <h2>Panel Preferences</h2>
          <div className="stacked-form settings-form-content">
            <label>
              Refresh Interval
              <select
                value={settings.refreshIntervalSeconds}
                onChange={(event) => handleChange('refreshIntervalSeconds', Number(event.target.value))}
              >
                <option value={5}>5 seconds</option>
                <option value={10}>10 seconds</option>
                <option value={30}>30 seconds</option>
              </select>
            </label>
            <label>
              Landing Page
              <select
                value={settings.landingPagePreference}
                onChange={(event) => handleChange('landingPagePreference', event.target.value)}
              >
                <option value="Statistics / Analytics">Statistics / Analytics</option>
                <option value="User Management">User Management</option>
                <option value="Alerts">Alerts</option>
                <option value="Complaints">Complaints</option>
                <option value="Settings">Settings</option>
              </select>
            </label>

            <div className="settings-actions">
              <button type="submit" disabled={saving || loading}>
                {saving ? 'Saving...' : 'Save Preferences'}
              </button>
              {loading ? <span className="settings-status">Loading saved preferences…</span> : null}
            </div>

            {message ? <p className="settings-message success-message">{message}</p> : null}
            {error ? <p className="settings-message error-message">{error}</p> : null}
          </div>
        </div>
      </form>
    </section>
  )
}

export default AdminSettingsPage