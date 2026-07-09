import './AppSidebar.css'

function AppSidebar({ role, pages, activePage, onNavigate, onSignOut }) {
  return (
    <aside className="sidebar app-sidebar">
      <div>
        <p className="muted">Wi-Netra Health</p>
        <h1>{role === 'admin' ? 'Admin Panel' : 'App User Panel'}</h1>
        <p className="sidebar-copy">
          {role === 'admin'
            ? 'Fleet oversight, user assignments, alerts, complaints, and settings.'
            : 'Multi-patient breathing monitor, alerts, analytics, support, and settings.'}
        </p>
      </div>

      <div className="sidebar-role-badge">{role === 'admin' ? 'Admin session' : 'App User session'}</div>

      <nav className="sidebar-nav">
        {pages.map((page) => (
          <button
            key={page}
            type="button"
            className={activePage === page ? 'active' : ''}
            onClick={() => onNavigate(page)}
          >
            {page}
          </button>
        ))}
      </nav>

      <div className="sidebar-footer">
        <p className="muted">{role === 'admin' ? 'Realtime fleet feed' : 'Realtime patient feed'}</p>
        <strong>{role === 'admin' ? 'Firebase oversight' : 'Patient monitor sync'}</strong>
        <button type="button" className="sidebar-signout" onClick={onSignOut}>
          Sign Out
        </button>
      </div>
    </aside>
  )
}

export default AppSidebar