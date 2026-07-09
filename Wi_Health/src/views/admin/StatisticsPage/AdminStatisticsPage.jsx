import './AdminStatisticsPage.css'

function AdminStatisticsPage({ adminStats, fleetDevices, alerts }) {
  return (
    <section className="page-grid admin-statistics-page page-fade">
      <div className="card card-span-2">
        <h2>Fleet Snapshot</h2>
        <div className="stats-grid">
          {adminStats.map((item) => (
            <article key={item.label} className="stat-tile">
              <p>{item.label}</p>
              <strong>{item.value}</strong>
            </article>
          ))}
        </div>
      </div>

      <div className="card">
        <h2>Anomaly Trend (Today)</h2>
        <div className="trend-list">
          <div><span>Tachypnea</span><div className="bar"><i style={{ width: '68%' }} /></div></div>
          <div><span>Bradypnea</span><div className="bar"><i style={{ width: '34%' }} /></div></div>
          <div><span>No valid breathing</span><div className="bar"><i style={{ width: '46%' }} /></div></div>
        </div>
      </div>

      <div className="card card-span-3">
        <h2>Device Fleet View</h2>
        <table>
          <thead>
            <tr>
              <th>Device</th>
              <th>Patient</th>
              <th>Status</th>
              <th>Health</th>
              <th>Last Update</th>
            </tr>
          </thead>
          <tbody>
            {fleetDevices.map((device) => (
              <tr key={device.id}>
                <td>{device.id}</td>
                <td>{device.patient}</td>
                <td><span className={`pill ${device.status === 'Online' ? 'pill-online' : 'pill-offline'}`}>{device.status}</span></td>
                <td>{device.health}</td>
                <td>{device.updated}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card card-span-3">
        <h2>Live Alert Context</h2>
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Patient</th>
              <th>Device</th>
              <th>Anomaly</th>
              <th>Severity</th>
              <th>Status</th>
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

export default AdminStatisticsPage