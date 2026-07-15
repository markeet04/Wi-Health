import { useMemo, useState } from 'react'
import './AdminUsersPage.css'
import { createAdminUser, deleteAdminUser, updateAdminUser } from '../../../services/adminApi'

const emptyForm = {
  email: '',
  password: '',
  name: '',
  role: 'app_user',
}

function validatePassword(password) {
  if (!password) {
    return 'Password is required.'
  }

  if (password.length < 8) {
    return 'Password must be at least 8 characters long.'
  }

  if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/\d/.test(password)) {
    return 'Password must include uppercase, lowercase, and a number.'
  }

  return ''
}

function AdminUsersPage({ users = [], accessToken, currentAdminEmail, currentAdminUid, onUsersChanged }) {
  const [form, setForm] = useState(emptyForm)
  const [modalMode, setModalMode] = useState('create')
  const [selectedUser, setSelectedUser] = useState(null)
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [pendingDeleteUser, setPendingDeleteUser] = useState(null)
  const [statusMessage, setStatusMessage] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const sortedUsers = useMemo(() => {
    return [...users].sort((left, right) => left.name.localeCompare(right.name))
  }, [users])

  const resetForm = () => {
    setForm(emptyForm)
    setSelectedUser(null)
    setStatusMessage('')
  }

  const openCreateModal = () => {
    resetForm()
    setModalMode('create')
    setIsModalOpen(true)
  }

  const openEditModal = (user) => {
    setModalMode('update')
    setSelectedUser(user)
    setForm({
      email: user.email ?? '',
      password: '',
      name: user.name ?? '',
      role: user.role === 'Admin' ? 'admin' : 'app_user',
    })
    setStatusMessage('')
    setIsModalOpen(true)
  }

  const closeModal = () => {
    setIsModalOpen(false)
    resetForm()
  }

  const handleChange = (event) => {
    const { name, value } = event.target
    setForm((current) => ({ ...current, [name]: value }))
  }

  const handleSubmit = async (event) => {
    event.preventDefault()
    if (!accessToken) {
      setStatusMessage('Admin session is missing.')
      return
    }

    const trimmedEmail = form.email.trim()
    const trimmedName = form.name.trim()
    const passwordError = validatePassword(modalMode === 'create' ? form.password : form.password || 'StrongPass1')

    if (modalMode === 'create' && (!trimmedEmail || !trimmedName || !form.password)) {
      setStatusMessage('Email, password, and name are required.')
      return
    }

    if (modalMode === 'update' && !trimmedEmail) {
      setStatusMessage('Email is required.')
      return
    }

    if (modalMode === 'update' && form.password && passwordError) {
      setStatusMessage(passwordError)
      return
    }

    if (modalMode === 'create' && passwordError) {
      setStatusMessage(passwordError)
      return
    }

    setIsSubmitting(true)
    setStatusMessage('')

    try {
      if (modalMode === 'update' && selectedUser?.uid) {
        const payload = {
          ...(trimmedEmail && trimmedEmail !== selectedUser.email ? { email: trimmedEmail } : {}),
          ...(trimmedName && trimmedName !== selectedUser.name ? { name: trimmedName } : {}),
          ...(form.password ? { password: form.password } : {}),
        }

        if (Object.keys(payload).length === 0) {
          setStatusMessage('No changes were made.')
          return
        }

        await updateAdminUser(accessToken, selectedUser.uid, payload)
        setStatusMessage('User updated successfully.')
      } else {
        const payload = {
          email: trimmedEmail,
          password: form.password,
          name: trimmedName,
          role: form.role,
        }

        await createAdminUser(accessToken, payload)
        setStatusMessage('User created successfully.')
      }

      closeModal()
      await onUsersChanged?.()
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to save user.')
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleDelete = (user) => {
    if (!accessToken || !user?.uid) {
      setStatusMessage('Unable to delete that user.')
      return
    }

    const isSelfDelete = user.uid === currentAdminUid ||
      user.email?.toLowerCase() === currentAdminEmail?.toLowerCase()

    if (isSelfDelete) {
      setStatusMessage('You cannot delete your own account.')
      return
    }

    setPendingDeleteUser(user)
  }

  const confirmDelete = async () => {
    if (!accessToken || !pendingDeleteUser?.uid) {
      setStatusMessage('Unable to delete that user.')
      return
    }

    setIsSubmitting(true)
    setStatusMessage('')

    try {
      await deleteAdminUser(accessToken, pendingDeleteUser.uid)
      setStatusMessage('User deleted successfully.')
      setPendingDeleteUser(null)
      await onUsersChanged?.()
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to delete user.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <section className="page-grid admin-users-page page-fade">
      <div className="card card-span-2">
        <div className="users-header-row">
          <h2>Users and Assignments</h2>
          <div className="users-header-actions">
            <span className="pill">{sortedUsers.length} Users</span>
            <button type="button" className="create-btn" onClick={openCreateModal}>Create User</button>
          </div>
        </div>

        <table>
          <thead>
            <tr>
              <th>User</th>
              <th>Role</th>
              <th>Patient Links</th>
              <th>Device Mapping</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {sortedUsers.map((user) => {
              const isCurrentUserRow = user.uid === currentAdminUid ||
                user.email?.toLowerCase() === currentAdminEmail?.toLowerCase()

              return (
                <tr key={user.uid ?? user.name}>
                  <td>
                    <div className="name-cell">
                      <strong>{user.name}</strong>
                      <span>{user.email ?? user.name}</span>
                    </div>
                  </td>
                  <td>{user.role}</td>
                  <td>{user.patients}</td>
                  <td>{user.devices}</td>
                  <td>{user.status}</td>
                  <td>
                    <div className="table-actions">
                      <button type="button" className="ghost-btn" onClick={() => openEditModal(user)}>Edit</button>
                      {!isCurrentUserRow ? (
                        <button type="button" className="delete-btn" onClick={() => handleDelete(user)}>Delete</button>
                      ) : null}
                    </div>
                  </td>
                </tr>
              )
            })}
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

      {pendingDeleteUser ? (
        <div className="modal-backdrop" onClick={() => setPendingDeleteUser(null)}>
          <div className="modal-card confirmation-card" onClick={(event) => event.stopPropagation()}>
            <div className="modal-card__head">
              <h3>Confirm Deletion</h3>
              <button type="button" className="ghost-btn" onClick={() => setPendingDeleteUser(null)}>Close</button>
            </div>

            <p className="hint-text">
              Are you sure you want to permanently delete <strong>{pendingDeleteUser.name ?? pendingDeleteUser.email ?? 'this user'}</strong>?
            </p>

            <div className="form-actions">
              <button type="button" className="delete-btn" disabled={isSubmitting} onClick={confirmDelete}>
                {isSubmitting ? 'Deleting...' : 'Delete User'}
              </button>
              <button type="button" className="ghost-btn" onClick={() => setPendingDeleteUser(null)}>Cancel</button>
            </div>
          </div>
        </div>
      ) : null}

      {isModalOpen ? (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal-card" onClick={(event) => event.stopPropagation()}>
            <div className="modal-card__head">
              <h3>{modalMode === 'update' ? 'Update User' : 'Create User'}</h3>
              <button type="button" className="ghost-btn" onClick={closeModal}>Close</button>
            </div>

            <form className="stacked-form modal-form" noValidate onSubmit={handleSubmit}>
              <label>
                Email
                <input name="email" type="email" value={form.email} onChange={handleChange} placeholder="email@example.com" />
              </label>
              <label>
                Password
                <input name="password" type="password" value={form.password} onChange={handleChange} placeholder={modalMode === 'update' ? 'Leave blank to keep current password' : 'Enter password'} />
              </label>
              <label>
                Name
                <input name="name" type="text" value={form.name} onChange={handleChange} placeholder="Full name" />
              </label>

              {modalMode === 'create' ? (
                <label>
                  Role
                  <select name="role" value={form.role} onChange={handleChange}>
                    <option value="app_user">User</option>
                    <option value="admin">Admin</option>
                  </select>
                </label>
              ) : null}

              {statusMessage ? <p className="form-message">{statusMessage}</p> : null}

              <div className="form-actions">
                <button type="submit" disabled={isSubmitting}>{isSubmitting ? 'Saving...' : modalMode === 'update' ? 'Update User' : 'Add User'}</button>
                <button type="button" className="ghost-btn" onClick={closeModal}>Cancel</button>
              </div>
            </form>
          </div>
        </div>
      ) : null}
    </section>
  )
}

export default AdminUsersPage