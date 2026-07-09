import './UserAnalyticsPage.css'

function UserAnalyticsPage({ userSessions, userPatients }) {
  return (
    <section className="page-grid user-analytics-page page-fade">
      <div className="card card-span-2">
        <h2>Session Logs</h2>
        <table>
          <thead>
            <tr>
              <th>Session</th><th>Patient</th><th>Average BPM</th><th>Duration</th><th>Low Signal</th><th>Anomalies</th><th>Quality</th>
            </tr>
          </thead>
          <tbody>
            {userSessions.map((session) => (
              <tr key={`${session.session}-${session.patient}`}>
                <td>{session.session}</td>
                <td>{session.patient}</td>
                <td>{session.avg}</td>
                <td>{session.duration}</td>
                <td>{session.lowSignal}</td>
                <td>{session.anomalies}</td>
                <td>{session.quality}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Rate Distribution</h2>
        <div className="trend-list">
          <div><span>Normal range</span><div className="bar"><i style={{ width: '74%' }} /></div></div>
          <div><span>Watch range</span><div className="bar"><i style={{ width: '38%' }} /></div></div>
          <div><span>Low confidence</span><div className="bar"><i style={{ width: '22%' }} /></div></div>
        </div>
      </div>

      <div className="card">
        <h2>Trend Notes</h2>
        <div className="metric-stack">
          <div className="metric-row"><span>Best signal</span><strong>{userPatients[3].name}</strong></div>
          <div className="metric-row"><span>Most alerts</span><strong>{userPatients[1].name}</strong></div>
          <div className="metric-row"><span>Low-valid windows</span><strong>{userPatients[2].name}</strong></div>
          <div className="metric-row"><span>Chart source</span><strong>On-device DSP</strong></div>
        </div>
      </div>

      <div className="card card-span-3">
        <h2>Night and Day View</h2>
        <div className="stats-grid stats-grid--wide">
          <article className="stat-tile"><p>Night average</p><strong>17.9</strong></article>
          <article className="stat-tile"><p>Day average</p><strong>20.4</strong></article>
          <article className="stat-tile"><p>Confidence floor</p><strong>38%</strong></article>
          <article className="stat-tile"><p>Longest stable run</p><strong>7h</strong></article>
        </div>
      </div>
    </section>
  )
}

export default UserAnalyticsPage