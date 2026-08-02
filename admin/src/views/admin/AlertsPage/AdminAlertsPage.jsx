import { useMemo, useState } from 'react'
import './AdminAlertsPage.css'

// Filter buttons -> the predicate each one applies to an alert row. "All" keeps
// everything; the rest match on severity/status (case-insensitive so backend
// casing differences don't silently drop rows).
const FILTERS = [
  { key: 'all', label: 'All', match: () => true },
  { key: 'urgent', label: 'Urgent', match: (alert) => String(alert.severity).toLowerCase() === 'urgent' },
  { key: 'acknowledged', label: 'Acknowledged', match: (alert) => String(alert.status).toLowerCase() === 'acknowledged' },
  { key: 'resolved', label: 'Resolved', match: (alert) => String(alert.status).toLowerCase() === 'resolved' },
]

function AdminAlertsPage({ alerts }) {
  const [activeFilter, setActiveFilter] = useState('all')

  const visibleAlerts = useMemo(() => {
    const filter = FILTERS.find((item) => item.key === activeFilter) ?? FILTERS[0]
    return alerts.filter(filter.match)
  }, [alerts, activeFilter])

  return (
    <section className="page-grid admin-alerts-page page-fade">
      <div className="card card-span-3">
        <h2>Fleet Alerts Log</h2>
        <div className="filters">
          {FILTERS.map((filter) => (
            <button
              type="button"
              key={filter.key}
              className={activeFilter === filter.key ? 'active' : ''}
              onClick={() => setActiveFilter(filter.key)}
            >
              {filter.label}
            </button>
          ))}
        </div>
        {visibleAlerts.length === 0 ? (
          <p className="hint-text">
            {alerts.length === 0 ? 'No alerts recorded yet.' : 'No alerts match this filter.'}
          </p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Time</th><th>Patient</th><th>Device</th><th>Anomaly</th><th>Severity</th><th>Status</th>
              </tr>
            </thead>
            <tbody>
              {visibleAlerts.map((alert) => (
                <tr key={`${alert.time}-${alert.device}`}>
                  <td>{alert.time}</td>
                  <td>{alert.patient}</td>
                  <td>{alert.device}</td>
                  <td>{alert.anomaly}</td>
                  <td><span className={`pill ${alert.severity === 'Urgent' ? 'pill-urgent' : 'pill-neutral'}`}>{alert.severity}</span></td>
                  <td>{alert.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </section>
  )
}

export default AdminAlertsPage
