import { useEffect, useState } from 'react'
import './AppSidebar.css'

function AppSidebar({ pages, activePage, onNavigate, onSignOut, session }) {
  const [isMenuOpen, setIsMenuOpen] = useState(false)

  // Escape closes the mobile menu, same as the modals elsewhere in the panel.
  useEffect(() => {
    if (!isMenuOpen) return undefined
    const handleKeyDown = (event) => {
      if (event.key === 'Escape') setIsMenuOpen(false)
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isMenuOpen])

  const handleNavigate = (page) => {
    onNavigate(page)
    setIsMenuOpen(false)
  }

  const handleSignOut = () => {
    setIsMenuOpen(false)
    onSignOut()
  }

  return (
    <aside className={`sidebar app-sidebar${isMenuOpen ? ' is-open' : ''}`}>
      <div className="sidebar-top-row">
        <div>
          <p className="muted">Wi-Netra Health</p>
          <h1>Admin Panel</h1>
        </div>

        <button
          type="button"
          className="sidebar-menu-toggle"
          onClick={() => setIsMenuOpen((open) => !open)}
          aria-expanded={isMenuOpen}
          aria-label={isMenuOpen ? 'Close menu' : 'Open menu'}
        >
          <span className="sidebar-menu-toggle__bar" />
          <span className="sidebar-menu-toggle__bar" />
          <span className="sidebar-menu-toggle__bar" />
        </button>
      </div>

      <div className="sidebar-collapsible">
        <p className="sidebar-copy">
          Fleet oversight, user assignments, alerts, complaints, and settings.
        </p>

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
              onClick={() => handleNavigate(page)}
            >
              {page}
            </button>
          ))}
        </nav>

        <div className="sidebar-footer">
          <p className="muted">Realtime fleet feed</p>
          <strong>Firebase oversight</strong>
          <button type="button" className="sidebar-signout" onClick={handleSignOut}>
            Sign Out
          </button>
        </div>
      </div>

      {isMenuOpen ? (
        <button
          type="button"
          className="sidebar-backdrop"
          aria-label="Close menu"
          onClick={() => setIsMenuOpen(false)}
        />
      ) : null}
    </aside>
  )
}

export default AppSidebar
