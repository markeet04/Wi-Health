import './UserAlertsPage.css'

function UserAlertsPage({ userAlerts }) {
  return (
    <section className="page-grid user-alerts-page page-fade">
      <div className="card card-span-3">
        <h2>Alert Timeline</h2>
        <div className="filters">
          <button type="button" className="active">All</button>
          <button type="button">Patient A</button>
          <button type="button">Patient B</button>
          <button type="button">Patient C</button>
          <button type="button">Patient D</button>
        </div>
        <table>
          <thead>
            <tr>
              <th>Time</th><th>Patient</th><th>Device</th><th>Anomaly</th><th>Severity</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {userAlerts.map((alert) => (
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

export default UserAlertsPage