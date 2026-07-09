import { useMemo, useState } from 'react'
import './App.css'
import './styles/pageTransitions.css'
import { adminPages, alerts, complaints, fleetDevices, supportTickets, userAlerts, userPages, userPatients, userSessions, users } from './data/appData'
import AppSidebar from './components/AppSidebar/AppSidebar'
import LoginPage from './views/auth/LoginPage/LoginPage'
import AdminAlertsPage from './views/admin/AlertsPage/AdminAlertsPage'
import AdminComplaintsPage from './views/admin/ComplaintsPage/AdminComplaintsPage'
import AdminSettingsPage from './views/admin/SettingsPage/AdminSettingsPage'
import AdminStatisticsPage from './views/admin/StatisticsPage/AdminStatisticsPage'
import AdminUsersPage from './views/admin/UsersPage/AdminUsersPage'
import UserAlertsPage from './views/user/AlertsPage/UserAlertsPage'
import UserAnalyticsPage from './views/user/AnalyticsPage/UserAnalyticsPage'
import UserOverviewPage from './views/user/OverviewPage/UserOverviewPage'
import UserPatientsPage from './views/user/PatientsPage/UserPatientsPage'
import UserSettingsPage from './views/user/SettingsPage/UserSettingsPage'
import UserSupportPage from './views/user/SupportPage/UserSupportPage'

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [role, setRole] = useState('user')
  const [activePage, setActivePage] = useState(userPages[0])
  const [activePatient, setActivePatient] = useState(userPatients[0].name)

  const selectedPatient = userPatients.find((patient) => patient.name === activePatient) ?? userPatients[0]
  const currentPages = role === 'admin' ? adminPages : userPages

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

  const userStats = useMemo(() => {
    const healthyPatients = userPatients.filter((patient) => patient.confidence >= 80).length
    const liveAlerts = userAlerts.filter((alert) => alert.severity === 'Urgent' && alert.status !== 'Resolved').length

    return [
      { label: 'Linked Patients', value: String(userPatients.length) },
      { label: 'Healthy Signal Feeds', value: String(healthyPatients) },
      { label: 'Live Alerts', value: String(liveAlerts) },
      { label: 'Selected Device', value: selectedPatient.device },
    ]
  }, [selectedPatient.device])

  const switchRole = (nextRole) => {
    setRole(nextRole)
    setActivePage(nextRole === 'admin' ? adminPages[0] : userPages[0])
  }

  const handleSignIn = () => {
    setIsAuthenticated(true)
    setActivePage(role === 'admin' ? adminPages[0] : userPages[0])
  }

  const handleSignOut = () => {
    setIsAuthenticated(false)
  }

  const pageContent =
    role === 'admin'
      ? {
          'Statistics / Analytics': <AdminStatisticsPage adminStats={adminStats} fleetDevices={fleetDevices} alerts={alerts} />,
          'User Management': <AdminUsersPage users={users} />,
          Alerts: <AdminAlertsPage alerts={alerts} />,
          Complaints: <AdminComplaintsPage complaints={complaints} />,
          Settings: <AdminSettingsPage />,
        }
      : {
          Overview: (
            <UserOverviewPage
              selectedPatient={selectedPatient}
              userPatients={userPatients}
              userAlerts={userAlerts}
              onSelectPatient={setActivePatient}
              userStats={userStats}
            />
          ),
          Patients: <UserPatientsPage userPatients={userPatients} selectedPatient={selectedPatient} />,
          Analytics: <UserAnalyticsPage userSessions={userSessions} userPatients={userPatients} />,
          Alerts: <UserAlertsPage userAlerts={userAlerts} />,
          Support: <UserSupportPage selectedPatient={selectedPatient} userPatients={userPatients} supportTickets={supportTickets} />,
          Settings: <UserSettingsPage />,
        }

  if (!isAuthenticated) {
    return <LoginPage role={role} onSelectRole={switchRole} onLogin={handleSignIn} />
  }

  return (
    <div className={role === 'admin' ? 'admin-shell' : 'app-shell'}>
      <AppSidebar
        role={role}
        pages={currentPages}
        activePage={activePage}
        onNavigate={setActivePage}
        onSignOut={handleSignOut}
      />

      <main className="content">
        <header className="content-head">
          <div>
            <p className="muted">{role === 'admin' ? 'Oversight Console' : 'Patient Monitor'}</p>
            <h2>{activePage}</h2>
          </div>
          <button type="button" className="ghost-btn">
            {role === 'admin' ? 'Export' : 'Share Snapshot'}
          </button>
        </header>
        {pageContent[activePage]}
      </main>
    </div>
  )
}

export default App