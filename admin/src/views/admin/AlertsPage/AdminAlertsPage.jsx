import './AdminAlertsPage.css'

function AdminAlertsPage({ alerts }) {
  return (
    <section className="page-grid admin-alerts-page page-fade">
      <div className="card card-span-3">
        <h2>Fleet Alerts Log</h2>
        <div className="filters">
          <button type="button" className="active">All</button>
          <button type="button">Urgent</button>
          <button type="button">Acknowledged</button>
          <button type="button">Resolved</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>Time</th><th>Patient</th><th>Device</th><th>Anomaly</th><th>Severity</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {alerts.map((alert) => (
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
      </div>
    </section>
  )
}

export default AdminAlertsPage