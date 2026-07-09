import './AdminUsersPage.css'

function AdminUsersPage({ users }) {
  return (
    <section className="page-grid admin-users-page page-fade">
      <div className="card card-span-2">
        <h2>Users and Assignments</h2>
        <table>
          <thead>
            <tr>
              <th>User</th>
              <th>Role</th>
              <th>Patient Links</th>
              <th>Device Mapping</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user) => (
              <tr key={user.name}>
                <td>{user.name}</td>
                <td>{user.role}</td>
                <td>{user.patients}</td>
                <td>{user.devices}</td>
                <td>{user.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Quick Assignment</h2>
        <form className="stacked-form">
          <label>
            App User
            <select defaultValue="Anita Rao"><option>Anita Rao</option><option>Mohan Iyer</option><option>Leela Das</option></select>
          </label>
          <label>
            Patient
            <select defaultValue="Patient A"><option>Patient A</option><option>Patient B</option><option>Patient C</option><option>Patient D</option></select>
          </label>
          <label>
            Device
            <select defaultValue="WH-2101"><option>WH-2101</option><option>WH-2102</option><option>WH-2103</option><option>WH-2104</option></select>
          </label>
          <button type="button">Save Mapping</button>
        </form>
      </div>
    </section>
  )
}

export default AdminUsersPage