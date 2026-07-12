import './UserOverviewPage.css'

function UserOverviewPage({ selectedPatient, userPatients, userAlerts, onSelectPatient, userStats }) {
  return (
    <section className="page-grid user-overview-page page-fade">
      <article className="card hero-card card-span-2">
        <div className="hero-card__top">
          <div>
            <p className="muted">Live Monitor</p>
            <h2>{selectedPatient.name}</h2>
          </div>
          <div className="hero-status">
            <span className={`pill ${selectedPatient.connection === 'Online' ? 'pill-online' : 'pill-neutral'}`}>{selectedPatient.connection}</span>
            <span className="hero-note">{selectedPatient.update}</span>
          </div>
        </div>

        <div className="hero-readout">
          <div className="bpm-display">
            <span>Breaths per minute</span>
            <strong>{selectedPatient.rate}</strong>
            <p>{selectedPatient.state}</p>
          </div>

          <div className="monitor-visual">
            <div className="monitor-ring"><div className="monitor-core" /></div>
            <div className="monitor-copy">
              <span>Confidence</span>
              <strong>{selectedPatient.confidence}%</strong>
              <p>{selectedPatient.signal}</p>
            </div>
          </div>
        </div>

        <div className="patient-switcher" aria-label="Patient switcher">
          {userPatients.map((patient) => (
            <button key={patient.name} type="button" className={patient.name === selectedPatient.name ? 'patient-chip active' : 'patient-chip'} onClick={() => onSelectPatient(patient.name)}>
              <span>{patient.name}</span>
              <small>{patient.device}</small>
            </button>
          ))}
        </div>
      </article>

      <div className="card">
        <h2>Signal Summary</h2>
        <div className="metric-stack">
          <div className="metric-row"><span>Caregiver link</span><strong>{selectedPatient.caregiver}</strong></div>
          <div className="metric-row"><span>Room setup</span><strong>{selectedPatient.room}</strong></div>
          <div className="metric-row"><span>Battery level</span><strong>{selectedPatient.battery}</strong></div>
          <div className="metric-row"><span>Device state</span><strong>{selectedPatient.connection}</strong></div>
        </div>
      </div>

      <div className="card">
        <h2>Today&apos;s Summary</h2>
        <div className="mini-list">
          {userStats.map((item) => (
            <div key={item.label} className="metric-row">
              <span>{item.label}</span>
              <strong>{item.value}</strong>
            </div>
          ))}
        </div>
      </div>

      <div className="card card-span-2">
        <h2>Breathing Trend</h2>
        <div className="trend-list trend-list--wide">
          {selectedPatient.trend.map((value, index) => (
            <div key={`${selectedPatient.name}-trend-${index}`}>
              <span>Window {index + 1}</span>
              <div className="bar"><i style={{ width: `${Math.min(value, 100)}%` }} /></div>
            </div>
          ))}
        </div>
      </div>

      <div className="card">
        <h2>Recent Signals</h2>
        <div className="timeline timeline--compact">
          {userAlerts.slice(0, 3).map((alert) => (
            <div key={`${alert.time}-${alert.device}`} className="timeline-item">
              <div className="timeline-head">
                <strong>{alert.anomaly}</strong>
                <span>{alert.time}</span>
              </div>
              <p>{alert.status} for {alert.patient}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}

export default UserOverviewPage