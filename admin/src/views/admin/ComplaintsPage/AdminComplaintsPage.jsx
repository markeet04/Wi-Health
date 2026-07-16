import './AdminComplaintsPage.css'

function AdminComplaintsPage({ complaints }) {
  const selectedComplaint = complaints[0] ?? null

  return (
    <section className="page-grid admin-complaints-page page-fade">
      <div className="card card-span-2">
        <h2>Complaints Queue</h2>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>App User</th><th>Patient</th><th>Issue</th><th>Status</th><th>Submitted</th>
            </tr>
          </thead>
          <tbody>
            {complaints.map((complaint) => (
              <tr key={complaint.id}>
                <td>{complaint.id}</td>
                <td>{complaint.user}</td>
                <td>{complaint.patient}</td>
                <td>{complaint.issue}</td>
                <td>{complaint.status}</td>
                <td>{complaint.submitted}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Response Panel</h2>
        {selectedComplaint ? (
          <div className="stacked-form">
            <label>
              Complaint ID
              <input type="text" readOnly value={selectedComplaint.id} />
            </label>
            <label>
              Status
              <input type="text" readOnly value={selectedComplaint.status} />
            </label>
            <label>
              App User
              <input type="text" readOnly value={selectedComplaint.user} />
            </label>
            <label>
              Issue
              <textarea rows={4} readOnly value={selectedComplaint.issue} />
            </label>
          </div>
        ) : (
          <p className="muted">No complaint data is available yet.</p>
        )}
      </div>
    </section>
  )
}

export default AdminComplaintsPage