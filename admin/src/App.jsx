import { useMemo, useState } from 'react'
import './App.css'
import './styles/pageTransitions.css'
import { adminPages, alerts, complaints, fleetDevices, users } from './data/appData'
import AppSidebar from './components/AppSidebar/AppSidebar'
import LoginPage from './views/auth/LoginPage/LoginPage'
import AdminAlertsPage from './views/admin/AlertsPage/AdminAlertsPage'
import AdminComplaintsPage from './views/admin/ComplaintsPage/AdminComplaintsPage'
import AdminSettingsPage from './views/admin/SettingsPage/AdminSettingsPage'
import AdminStatisticsPage from './views/admin/StatisticsPage/AdminStatisticsPage'
import AdminUsersPage from './views/admin/UsersPage/AdminUsersPage'

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [activePage, setActivePage] = useState(adminPages[0])

  const adminStats = useMemo(() => {
    const online = fleetDevices.filter((device) => device.status === 'Online').length
    const offline = fleetDevices.length - online
    const urgentAlerts = alerts.filter((alert) => alert.severity === 'Urgent' && alert.status !== 'Resolved').length

    return [
      { label: 'Monitored Patients', value: '4' },
      { label: 'Devices Online', value: String(online) },
      { label: 'Devices Offline', value: String(offline) },
      { label: 'Active Urgent Alerts', value: String(urgentAlerts) },
    ]
  }, [])

  const handleSignIn = () => {
    setIsAuthenticated(true)
    setActivePage(adminPages[0])
  }

  const handleSignOut = () => {
    setIsAuthenticated(false)
  }

  const pageContent = {
    'Statistics / Analytics': <AdminStatisticsPage adminStats={adminStats} fleetDevices={fleetDevices} alerts={alerts} />,
    'User Management': <AdminUsersPage users={users} />,
    Alerts: <AdminAlertsPage alerts={alerts} />,
    Complaints: <AdminComplaintsPage complaints={complaints} />,
    Settings: <AdminSettingsPage />,
  }

  if (!isAuthenticated) {
    return <LoginPage onLogin={handleSignIn} />
  }

  return (
    <div className="admin-shell">
      <AppSidebar
        pages={adminPages}
        activePage={activePage}
        onNavigate={setActivePage}
        onSignOut={handleSignOut}
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
