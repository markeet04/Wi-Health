import './AdminComplaintsPage.css'

function AdminComplaintsPage({ complaints }) {
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
        <form className="stacked-form">
          <label>
            Complaint ID
            <input type="text" defaultValue="CMP-102" />
          </label>
          <label>
            Update Status
            <select defaultValue="In-progress"><option>Open</option><option>In-progress</option><option>Resolved</option></select>
          </label>
          <label>
            Response
            <textarea rows={4} defaultValue="We are checking device connectivity logs and will update shortly." />
          </label>
          <button type="button">Submit Update</button>
        </form>
      </div>
    </section>
  )
}

export default AdminComplaintsPage