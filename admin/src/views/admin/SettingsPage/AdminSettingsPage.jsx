import { useEffect, useState } from 'react'
import './AdminSettingsPage.css'
import { fetchAdminSettings, updateAdminSettings } from '../../../services/adminApi'
import { usePreferences } from '../../../context/PreferencesContext'

const THEME_OPTIONS = [
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
  { value: 'system', label: 'System' },
]

// Only settings the app actually consumes live here. Landing Page sets which
// page opens on sign-in (App.jsx); Refresh Interval drives the live-data poll
// (Complaints page). Anything the system doesn't read was removed so every
// control on this page has a real effect.
const emptySettings = {
  refreshIntervalSeconds: 5,
  landingPagePreference: 'Statistics / Analytics',
}

const LANDING_PAGES = [
  'Statistics / Analytics',
  'User Management',
  'Device Assignment',
  'Alerts',
  'Complaints',
  'Settings',
]

function AdminSettingsPage({ accessToken }) {
  const {
    theme,
    setTheme,
    fontScale,
    increaseFont,
    decreaseFont,
    resetFont,
    fontMin,
    fontMax,
  } = usePreferences()
  const fontPercent = Math.round(fontScale * 100)

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
          setSettings({
            refreshIntervalSeconds: nextSettings.refreshIntervalSeconds ?? emptySettings.refreshIntervalSeconds,
            landingPagePreference: nextSettings.landingPagePreference ?? emptySettings.landingPagePreference,
          })
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
    setSettings((current) => ({ ...current, [field]: value }))
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
      setSettings({
        refreshIntervalSeconds: nextSettings.refreshIntervalSeconds ?? settings.refreshIntervalSeconds,
        landingPagePreference: nextSettings.landingPagePreference ?? settings.landingPagePreference,
      })
      setMessage('Preferences saved successfully.')
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : 'Unable to save preferences.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="admin-settings-page page-fade">
      <div className="settings-grid">
      <div className="card settings-panel">
        <h2>Appearance</h2>
        <div className="stacked-form settings-form-content">
          <div className="appearance-field">
            <span className="appearance-label">Theme</span>
            <div className="theme-toggle" role="group" aria-label="Theme">
              {THEME_OPTIONS.map((option) => (
                <button
                  type="button"
                  key={option.value}
                  className={theme === option.value ? 'theme-toggle__btn is-active' : 'theme-toggle__btn'}
                  onClick={() => setTheme(option.value)}
                >
                  {option.label}
                </button>
              ))}
            </div>
          </div>

          <div className="appearance-field">
            <span className="appearance-label">Text Size</span>
            <div className="font-controls">
              <button
                type="button"
                className="font-btn"
                onClick={decreaseFont}
                disabled={fontScale <= fontMin + 0.001}
                aria-label="Decrease text size"
              >
                A−
              </button>
              <span className="font-value">{fontPercent}%</span>
              <button
                type="button"
                className="font-btn"
                onClick={increaseFont}
                disabled={fontScale >= fontMax - 0.001}
                aria-label="Increase text size"
              >
                A+
              </button>
              <button type="button" className="font-reset" onClick={resetFont}>
                Reset
              </button>
            </div>
          </div>

          <p className="settings-hint">
            Appearance changes apply instantly and are saved on this browser.
          </p>
        </div>
      </div>

      <form className="card settings-panel settings-form-card" onSubmit={handleSubmit}>
          <h2>Panel Preferences</h2>
          <div className="stacked-form settings-form-content">
            <label>
              Landing Page
              <select
                value={settings.landingPagePreference}
                onChange={(event) => handleChange('landingPagePreference', event.target.value)}
              >
                {LANDING_PAGES.map((page) => (
                  <option key={page} value={page}>{page}</option>
                ))}
              </select>
            </label>
            <label>
              Live Refresh Interval
              <select
                value={settings.refreshIntervalSeconds}
                onChange={(event) => handleChange('refreshIntervalSeconds', Number(event.target.value))}
              >
                <option value={5}>5 seconds</option>
                <option value={10}>10 seconds</option>
                <option value={30}>30 seconds</option>
              </select>
            </label>

            <p className="settings-hint">
              Landing Page sets which screen opens when you sign in. Live Refresh Interval
              controls how often live data (e.g. the complaints queue) re-syncs from the backend.
            </p>

            <div className="settings-actions">
              <button type="submit" disabled={saving || loading}>
                {saving ? 'Saving...' : 'Save Preferences'}
              </button>
              {loading ? <span className="settings-status">Loading saved preferences…</span> : null}
            </div>

            {message ? <p className="settings-message success-message">{message}</p> : null}
            {error ? <p className="settings-message error-message">{error}</p> : null}
          </div>
      </form>
      </div>
    </section>
  )
}

export default AdminSettingsPage
