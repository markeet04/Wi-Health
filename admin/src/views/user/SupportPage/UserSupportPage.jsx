import './UserSupportPage.css'

function UserSupportPage({ selectedPatient, userPatients, supportTickets }) {
  return (
    <section className="page-grid user-support-page page-fade">
      <div className="card card-span-2">
        <h2>Submit a Complaint</h2>
        <form className="stacked-form">
          <label>
            Patient
            <select defaultValue={selectedPatient.name}>
              {userPatients.map((patient) => (
                <option key={patient.name}>{patient.name}</option>
              ))}
            </select>
          </label>
          <label>
            Issue Type
            <select defaultValue="Device issue">
              <option>Device issue</option>
              <option>Signal issue</option>
              <option>Notification issue</option>
              <option>Account issue</option>
            </select>
          </label>
          <label>
            Priority
            <select defaultValue="Normal">
              <option>Low</option>
              <option>Normal</option>
              <option>High</option>
            </select>
          </label>
          <label>
            Details
            <textarea rows={5} defaultValue="The device stopped syncing after a router restart and I need help reconnecting it." />
          </label>
          <button type="button">Raise Request</button>
        </form>
      </div>

      <div className="card">
        <h2>Open Support Tickets</h2>
        <div className="timeline timeline--compact">
          {supportTickets.map((ticket) => (
            <div key={ticket.id} className="timeline-item">
              <div className="timeline-head">
                <strong>{ticket.id}</strong>
                <span>{ticket.status}</span>
              </div>
              <p>{ticket.subject}</p>
              <small>{ticket.patient} - {ticket.updated}</small>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}

export default UserSupportPage