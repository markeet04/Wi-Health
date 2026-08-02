import './AdminStatisticsPage.css'

// Turn an array of row objects into a downloadable CSV. Values are quoted and
// inner quotes doubled so commas/quotes in patient names or anomalies can't
// break the columns.
function downloadCsv(filename, columns, rows) {
  const escape = (value) => `"${String(value ?? '').replace(/"/g, '""')}"`
  const header = columns.map((column) => escape(column.label)).join(',')
  const body = rows.map((row) => columns.map((column) => escape(row[column.key])).join(',')).join('\n')
  const csv = `${header}\n${body}`

  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

function AdminStatisticsPage({ adminStats, fleetDevices, alerts }) {
  const exportSnapshot = () => {
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')
    downloadCsv(
      `wi-health-fleet-${stamp}.csv`,
      [
        { key: 'id', label: 'Device' },
        { key: 'patient', label: 'Patient' },
        { key: 'status', label: 'Status' },
        { key: 'health', label: 'Health' },
        { key: 'updated', label: 'Last Update' },
      ],
      fleetDevices,
    )
  }

  const anomalyCountMap = alerts.reduce((accumulator, alert) => {
    const key = alert.anomaly
    accumulator[key] = (accumulator[key] ?? 0) + 1
    return accumulator
  }, {})

  const trendItems = Object.entries(anomalyCountMap)
    .map(([label, count]) => ({ label, count }))
    .sort((left, right) => right.count - left.count)

  const maxCount = Math.max(...trendItems.map((item) => item.count), 1)

  return (
    <section className="page-grid admin-statistics-page page-fade">
      <div className="card card-span-3">
        <div className="stats-header-row">
          <h2>Fleet Snapshot</h2>
          <button
            type="button"
            className="ghost-btn"
            onClick={exportSnapshot}
            disabled={fleetDevices.length === 0}
          >
            Export CSV
          </button>
        </div>
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
          {trendItems.length === 0 ? (
            <p className="hint-text">No live anomaly data is available yet.</p>
          ) : (
            trendItems.map((item) => (
              <div key={item.label}>
                <span>{item.label}</span>
                <div className="bar"><i style={{ width: `${Math.max(8, (item.count / maxCount) * 100)}%` }} /></div>
              </div>
            ))
          )}
        </div>
      </div>

      <div className="card card-span-2">
        <h2>Device Fleet View</h2>
        {fleetDevices.length === 0 ? (
          <p className="hint-text">No devices registered yet.</p>
        ) : (
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
        )}
      </div>

      <div className="card card-span-3">
        <h2>Live Alert Context</h2>
        {alerts.length === 0 ? (
          <p className="hint-text">No alerts recorded yet.</p>
        ) : (
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
        )}
      </div>
    </section>
  )
}

export default AdminStatisticsPage
