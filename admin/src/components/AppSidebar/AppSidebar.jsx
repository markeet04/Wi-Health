import './AppSidebar.css'

function AppSidebar({ pages, activePage, onNavigate, onSignOut, session }) {
  return (
    <aside className="sidebar app-sidebar">
      <div>
        <p className="muted">Wi-Netra Health</p>
        <h1>Admin Panel</h1>
        <p className="sidebar-copy">
          Fleet oversight, user assignments, alerts, complaints, and settings.
        </p>
      </div>

      <div className="sidebar-role-badge">
        {session?.source === 'firebase' ? 'Firebase admin session' : 'Admin session'}
      </div>

      <div className="sidebar-identity">
        <strong>{session?.user?.name ?? 'Admin Ops'}</strong>
        <span>{session?.user?.email ?? 'admin@wi-netra.health'}</span>
      </div>

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
        <p className="muted">Realtime fleet feed</p>
        <strong>Firebase oversight</strong>
        <button type="button" className="sidebar-signout" onClick={onSignOut}>
          Sign Out
        </button>
      </div>
    </aside>
  )
}

export default AppSidebar
