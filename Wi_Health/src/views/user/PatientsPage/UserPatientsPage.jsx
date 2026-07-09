import './UserPatientsPage.css'

function UserPatientsPage({ userPatients, selectedPatient }) {
  return (
    <section className="page-grid user-patients-page page-fade">
      <div className="card card-span-2">
        <h2>Linked Patients</h2>
        <table>
          <thead>
            <tr>
              <th>Patient</th><th>Device</th><th>Caregiver Link</th><th>Rate</th><th>Confidence</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {userPatients.map((patient) => (
              <tr key={patient.name}>
                <td>{patient.name}</td>
                <td>{patient.device}</td>
                <td>{patient.caregiver}</td>
                <td>{patient.rate}</td>
                <td>{patient.confidence}%</td>
                <td><span className={`pill ${patient.connection === 'Online' ? 'pill-online' : 'pill-neutral'}`}>{patient.connection}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Pairing Health</h2>
        <div className="metric-stack">
          <div className="metric-row"><span>Primary device</span><strong>{selectedPatient.device}</strong></div>
          <div className="metric-row"><span>Last sync</span><strong>{selectedPatient.update}</strong></div>
          <div className="metric-row"><span>Room geometry</span><strong>Optimized</strong></div>
          <div className="metric-row"><span>Packet cadence</span><strong>10 Hz</strong></div>
        </div>
      </div>

      <div className="card">
        <h2>App User Role</h2>
        <p className="body-copy">One account can switch between multiple patients, with each device linked to a single patient feed.</p>
        <div className="badge-row">
          <span className="pill pill-neutral">Multi-patient switcher</span>
          <span className="pill pill-neutral">Linked device access</span>
          <span className="pill pill-neutral">Realtime updates</span>
        </div>
      </div>
    </section>
  )
}

export default UserPatientsPage