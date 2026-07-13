import { useEffect, useMemo, useState } from 'react'
import './App.css'
import './styles/pageTransitions.css'
import { adminPages } from './data/appData'
import AppSidebar from './components/AppSidebar/AppSidebar'
import LoginPage from './views/auth/LoginPage/LoginPage'
import AdminAlertsPage from './views/admin/AlertsPage/AdminAlertsPage'
import AdminComplaintsPage from './views/admin/ComplaintsPage/AdminComplaintsPage'
import AdminSettingsPage from './views/admin/SettingsPage/AdminSettingsPage'
import AdminStatisticsPage from './views/admin/StatisticsPage/AdminStatisticsPage'
import AdminUsersPage from './views/admin/UsersPage/AdminUsersPage'
import {
  fetchAdminData,
  restoreAdminSession,
  signInAdmin,
  signOutAdmin,
} from './services/adminApi'

function App() {
  const [session, setSession] = useState(null)
  const [isBooting, setIsBooting] = useState(true)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [authError, setAuthError] = useState('')
  const [dashboard, setDashboard] = useState(null)
  const [activePage, setActivePage] = useState(adminPages[0])

  useEffect(() => {
    let cancelled = false

    async function boot() {
      const restoredSession = await restoreAdminSession()
      if (cancelled) return

      if (restoredSession) {
        setSession(restoredSession)
        const data = await fetchAdminData(restoredSession.accessToken)
        if (!cancelled) {
          setDashboard(data)
        }
      }

      if (!cancelled) {
        setIsBooting(false)
      }
    }

    boot()

    return () => {
      cancelled = true
    }
  }, [])

  const adminStats = useMemo(() => {
    const fleetDevices = dashboard?.fleetDevices ?? []
    const alerts = dashboard?.alerts ?? []
    const online = fleetDevices.filter((device) => device.status === 'Online').length
    const offline = fleetDevices.length - online
    const urgentAlerts = alerts.filter((alert) => alert.severity === 'Urgent' && alert.status !== 'Resolved').length

    return [
      { label: 'Monitored Patients', value: String(dashboard?.stats?.monitoredPatients ?? 0) },
      { label: 'Devices Online', value: String(online) },
      { label: 'Devices Offline', value: String(offline) },
      { label: 'Active Urgent Alerts', value: String(urgentAlerts) },
    ]
  }, [dashboard])

  const handleSignIn = async ({ email, password }) => {
    setIsSubmitting(true)
    setAuthError('')

    try {
      const nextSession = await signInAdmin({ email, password })
      const data = await fetchAdminData(nextSession.accessToken)

      setSession(nextSession)
      setDashboard(data)
      setActivePage(adminPages[0])
    } catch (error) {
      setAuthError(error instanceof Error ? error.message : 'Unable to sign in.')
    } finally {
      setIsSubmitting(false)
      setIsBooting(false)
    }
  }

  const handleSignOut = async () => {
    await signOutAdmin(session?.accessToken)
    setSession(null)
    setDashboard(null)
    setActivePage(adminPages[0])
    setAuthError('')
  }

  const pageContent = {
    'Statistics / Analytics': <AdminStatisticsPage adminStats={adminStats} fleetDevices={dashboard?.fleetDevices ?? []} alerts={dashboard?.alerts ?? []} />,
    'User Management': <AdminUsersPage users={dashboard?.users ?? []} />,
    Alerts: <AdminAlertsPage alerts={dashboard?.alerts ?? []} />,
    Complaints: <AdminComplaintsPage complaints={dashboard?.complaints ?? []} />,
    Settings: <AdminSettingsPage />,
  }

  if (isBooting) {
    return (
      <div className="login-shell login-page page-fade">
        <section className="login-card login-page__card">
          <div className="login-card__hero login-page__hero">
            <p className="muted">Wi-Netra Health</p>
            <h1>Loading admin session</h1>
            <p>Checking the backend for a valid admin session and the latest fleet data.</p>
          </div>
        </section>
      </div>
    )
  }

  if (!session) {
    return <LoginPage onLogin={handleSignIn} loading={isSubmitting} error={authError} />
  }

  return (
    <div className="admin-shell">
      <AppSidebar
        pages={adminPages}
        activePage={activePage}
        onNavigate={setActivePage}
        onSignOut={handleSignOut}
        session={session}
      />

      <main className="content">
        <header className="content-head">
          <div>
            <p className="muted">Oversight Console</p>
            <h2>{activePage}</h2>
          </div>
          <button type="button" className="ghost-btn">
            Export
          </button>
        </header>
        {pageContent[activePage]}
      </main>
    </div>
  )
}

export default App
