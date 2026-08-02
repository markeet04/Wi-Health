import { useEffect, useMemo, useState } from 'react'
import './App.css'
import './styles/pageTransitions.css'
import { adminPages } from './data/appData'
import AppSidebar from './components/AppSidebar/AppSidebar'
import LoginPage from './views/auth/LoginPage/LoginPage'
import AdminAlertsPage from './views/admin/AlertsPage/AdminAlertsPage'
import AdminComplaintsPage from './views/admin/ComplaintsPage/AdminComplaintsPage'
import AdminDevicesPage from './views/admin/DevicesPage/AdminDevicesPage'
import AdminSettingsPage from './views/admin/SettingsPage/AdminSettingsPage'
import AdminStatisticsPage from './views/admin/StatisticsPage/AdminStatisticsPage'
import AdminUsersPage from './views/admin/UsersPage/AdminUsersPage'
import {
  fetchAdminData,
  fetchAdminSettings,
  restoreAdminSession,
  signInAdmin,
  signOutAdmin,
} from './services/adminApi'

// Pick the page to open on sign-in from the saved preference, falling back to
// the first page if the preference is missing or no longer a valid page.
function resolveLandingPage(settings) {
  const preferred = settings?.landingPagePreference
  return adminPages.includes(preferred) ? preferred : adminPages[0]
}

function App() {
  const [session, setSession] = useState(null)
  const [isBooting, setIsBooting] = useState(true)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [authError, setAuthError] = useState('')
  const [dashboard, setDashboard] = useState(null)
  const [activePage, setActivePage] = useState(adminPages[0])
  const [refreshIntervalSeconds, setRefreshIntervalSeconds] = useState(5)

  useEffect(() => {
    let cancelled = false

    async function boot() {
      const restoredSession = await restoreAdminSession()
      if (cancelled) return

      if (restoredSession) {
        setSession(restoredSession)
        const [data, settings] = await Promise.all([
          fetchAdminData(restoredSession.accessToken),
          fetchAdminSettings(restoredSession.accessToken),
        ])
        if (!cancelled) {
          setDashboard(data)
          setActivePage(resolveLandingPage(settings))
          if (settings?.refreshIntervalSeconds) setRefreshIntervalSeconds(settings.refreshIntervalSeconds)
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
      const [data, settings] = await Promise.all([
        fetchAdminData(nextSession.accessToken),
        fetchAdminSettings(nextSession.accessToken),
      ])

      setSession(nextSession)
      setDashboard(data)
      setActivePage(resolveLandingPage(settings))
      if (settings?.refreshIntervalSeconds) setRefreshIntervalSeconds(settings.refreshIntervalSeconds)
    } catch (error) {
      setAuthError(error instanceof Error ? error.message : 'Unable to sign in.')
    } finally {
      setIsSubmitting(false)
      setIsBooting(false)
    }
  }

  const refreshDashboard = async () => {
    if (!session?.accessToken) return
    const data = await fetchAdminData(session.accessToken)
    setDashboard(data)
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
    'User Management': <AdminUsersPage
      users={dashboard?.users ?? []}
      accessToken={session?.accessToken}
      currentAdminEmail={session?.user?.email}
      currentAdminUid={session?.user?.uid}
      onUsersChanged={refreshDashboard}
    />,
    'Device Assignment': <AdminDevicesPage accessToken={session?.accessToken} />,
    Alerts: <AdminAlertsPage alerts={dashboard?.alerts ?? []} />,
    Complaints: <AdminComplaintsPage complaints={dashboard?.complaints ?? []} accessToken={session?.accessToken} onComplaintsChanged={refreshDashboard} refreshIntervalSeconds={refreshIntervalSeconds} />,
    Settings: <AdminSettingsPage accessToken={session?.accessToken} />,
  }

  if (isBooting) {
    return (
      <div className="boot-shell page-fade">
        <div className="boot-card">
          <span className="boot-spinner" aria-hidden="true" />
          <p className="boot-eyebrow">Wi-Netra Health</p>
          <h1>Loading admin session</h1>
          <p>Checking the backend for a valid admin session and the latest fleet data.</p>
        </div>
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
        </header>
        {pageContent[activePage]}
      </main>
    </div>
  )
}

export default App
