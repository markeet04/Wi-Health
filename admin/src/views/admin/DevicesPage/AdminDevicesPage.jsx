import { useEffect, useMemo, useState } from 'react'
import './AdminDevicesPage.css'
import {
  assignAdminDevice,
  createDevicePairingCode,
  declineAdminDeviceRequest,
  deleteAdminDevice,
  fetchAdminDevices,
  registerAdminDevice,
  unassignAdminDevice,
} from '../../../services/adminApi'

const emptyForm = {
  deviceId: '',
  uid: '',
  patientName: '',
  patientRelation: 'self',
  room: '',
  normalLow: 8,
  normalHigh: 30,
  requestId: '',
}

function AdminDevicesPage({ accessToken }) {
  const [devices, setDevices] = useState([])
  const [appUsers, setAppUsers] = useState([])
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [form, setForm] = useState(emptyForm)
  const [modalMode, setModalMode] = useState('assign')
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [pendingUnassign, setPendingUnassign] = useState(null)
  const [pendingDelete, setPendingDelete] = useState(null)
  const [statusMessage, setStatusMessage] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  // Pairing-code modal: { deviceId, code, expiresAt } once generated.
  const [pairing, setPairing] = useState(null)
  const [pairingBusy, setPairingBusy] = useState('')
  const [registering, setRegistering] = useState(false)

  const loadDevices = async () => {
    if (!accessToken) {
      setLoading(false)
      return
    }

    const data = await fetchAdminDevices(accessToken)
    setDevices(data?.devices ?? [])
    setAppUsers(data?.appUsers ?? [])
    setRequests(data?.requests ?? [])
    setLoading(false)
  }

  useEffect(() => {
    let cancelled = false

    async function run() {
      if (!accessToken) {
        setLoading(false)
        return
      }
      const data = await fetchAdminDevices(accessToken)
      if (cancelled) return
      setDevices(data?.devices ?? [])
      setAppUsers(data?.appUsers ?? [])
      setRequests(data?.requests ?? [])
      setLoading(false)
    }

    run()
    return () => {
      cancelled = true
    }
  }, [accessToken])

  const sortedDevices = useMemo(() => [...devices].sort((left, right) => left.id.localeCompare(right.id)), [devices])

  const userName = (uid) => appUsers.find((user) => user.uid === uid)?.name ?? appUsers.find((user) => user.uid === uid)?.email ?? uid

  const resetForm = () => {
    setForm(emptyForm)
    setStatusMessage('')
  }

  const openAssignNewModal = () => {
    resetForm()
    setModalMode('assign')
    setIsModalOpen(true)
  }

  const openReassignModal = (device) => {
    setModalMode('reassign')
    setForm({
      deviceId: device.id,
      uid: device.ownerUid || '',
      patientName: device.patientName || '',
      patientRelation: device.patientRelation || 'self',
      room: device.room || '',
      normalLow: device.normalLow || 8,
      normalHigh: device.normalHigh || 30,
      requestId: '',
    })
    setStatusMessage('')
    setIsModalOpen(true)
  }

  // Fulfil a device request: open the assign modal pre-filled with the
  // requester's uid + patient details. Admin only needs to pick a device ID.
  const openFulfilModal = (req) => {
    setModalMode('fulfil')
    setForm({
      deviceId: '',
      uid: req.uid,
      patientName: req.patientName || '',
      patientRelation: req.patientRelation || 'self',
      room: req.room || '',
      normalLow: 8,
      normalHigh: 30,
      requestId: req.id,
    })
    setStatusMessage('')
    setIsModalOpen(true)
  }

  const declineRequest = async (req) => {
    if (!accessToken) return
    setIsSubmitting(true)
    try {
      await declineAdminDeviceRequest(accessToken, req.id)
      await loadDevices()
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to decline request.')
    } finally {
      setIsSubmitting(false)
    }
  }

  // Register a new device — the backend allocates a unique Dev-N id so admins
  // never type one (and two devices can't collide). Then reloads the list.
  const registerDevice = async () => {
    if (!accessToken) return
    setRegistering(true)
    setStatusMessage('')
    try {
      const res = await registerAdminDevice(accessToken)
      await loadDevices()
      setStatusMessage(`Registered new device: ${res.deviceId}. Generate a pairing code to hand to the user.`)
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to register device.')
    } finally {
      setRegistering(false)
    }
  }

  // Generate a pairing code for a device and show it so the admin can hand it
  // to the caretaker (who enters it during the device's WiFi setup).
  const generatePairingCode = async (deviceId) => {
    if (!accessToken) return
    setPairingBusy(deviceId)
    try {
      const res = await createDevicePairingCode(accessToken, deviceId)
      setPairing({ deviceId, code: res.code, expiresAt: res.expiresAt })
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to generate pairing code.')
    } finally {
      setPairingBusy('')
    }
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

    const deviceId = form.deviceId.trim()
    const uid = form.uid.trim()
    const patientName = form.patientName.trim()

    if (!deviceId || !uid || !patientName) {
      setStatusMessage('Device ID, App User, and patient name are required.')
      return
    }

    const normalLow = Number(form.normalLow)
    const normalHigh = Number(form.normalHigh)
    if (!Number.isFinite(normalLow) || !Number.isFinite(normalHigh) || normalHigh <= normalLow) {
      setStatusMessage('Enter valid breathing-rate bounds (high must exceed low).')
      return
    }

    setIsSubmitting(true)
    setStatusMessage('')

    try {
      await assignAdminDevice(accessToken, deviceId, {
        uid,
        patientName,
        patientRelation: form.patientRelation.trim() || 'self',
        room: form.room.trim(),
        normalLow,
        normalHigh,
        ...(form.requestId ? { requestId: form.requestId } : {}),
      })
      setStatusMessage('Device assigned successfully.')
      closeModal()
      await loadDevices()
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to assign device.')
    } finally {
      setIsSubmitting(false)
    }
  }

  const confirmUnassign = async () => {
    if (!accessToken || !pendingUnassign) return

    setIsSubmitting(true)
    try {
      await unassignAdminDevice(accessToken, pendingUnassign.id)
      setPendingUnassign(null)
      await loadDevices()
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to unassign device.')
    } finally {
      setIsSubmitting(false)
    }
  }

  const confirmDelete = async () => {
    if (!accessToken || !pendingDelete) return

    setIsSubmitting(true)
    try {
      await deleteAdminDevice(accessToken, pendingDelete.id)
      setPendingDelete(null)
      await loadDevices()
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : 'Unable to delete device.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <section className="page-grid admin-devices-page page-fade">
      {requests.length > 0 ? (
        <div className="card card-span-3">
          <div className="devices-header-row">
            <h2>Pending Device Requests</h2>
            <span className="pill">{requests.length} Pending</span>
          </div>
          <table>
            <thead>
              <tr>
                <th>Requested By</th>
                <th>Patient</th>
                <th>Room</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {requests.map((req) => (
                <tr key={req.id}>
                  <td>
                    <div className="name-cell">
                      <strong>{req.userName}</strong>
                      <span>{req.userEmail}</span>
                    </div>
                  </td>
                  <td>{req.patientName}{req.patientRelation ? ` · ${req.patientRelation}` : ''}</td>
                  <td>{req.room || '-'}</td>
                  <td>
                    <div className="table-actions">
                      <button type="button" className="create-btn" onClick={() => openFulfilModal(req)}>Assign Device</button>
                      <button type="button" className="delete-btn" disabled={isSubmitting} onClick={() => declineRequest(req)}>Decline</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      <div className="card card-span-3">
        <div className="devices-header-row">
          <h2>Device Assignment</h2>
          <div className="devices-header-actions">
            <span className="pill">{sortedDevices.length} Devices</span>
            <button type="button" className="ghost-btn" onClick={registerDevice} disabled={registering}>
              {registering ? 'Registering…' : '+ Register Device'}
            </button>
            <button type="button" className="create-btn" onClick={openAssignNewModal}>Assign Device</button>
          </div>
        </div>

        {statusMessage && !isModalOpen ? (
          <p className="hint-text" style={{ marginBottom: '0.75rem' }}>{statusMessage}</p>
        ) : null}

        {loading ? (
          <p className="hint-text">Loading devices…</p>
        ) : sortedDevices.length === 0 ? (
          <p className="hint-text">
            No devices yet. Click "Register Device" to create one (it gets a unique Dev-N id), then generate a pairing code to hand to the user.
          </p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Device ID</th>
                <th>Patient</th>
                <th>Owner Account</th>
                <th>Room</th>
                <th>Normal Range</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {sortedDevices.map((device) => (
                <tr key={device.id}>
                  <td>{device.id}</td>
                  <td>{device.patientName || <span className="muted">Unassigned</span>}</td>
                  <td>{device.ownerUid ? userName(device.ownerUid) : <span className="muted">-</span>}</td>
                  <td>{device.room || '-'}</td>
                  <td>{device.normalLow}-{device.normalHigh} bpm</td>
                  <td>{device.status}</td>
                  <td>
                    <div className="table-actions">
                      <button type="button" className="ghost-btn" onClick={() => openReassignModal(device)}>
                        {device.ownerUid ? 'Reassign' : 'Assign'}
                      </button>
                      <button
                        type="button"
                        className="ghost-btn"
                        disabled={pairingBusy === device.id}
                        onClick={() => generatePairingCode(device.id)}
                      >
                        {pairingBusy === device.id ? 'Generating…' : 'Pairing Code'}
                      </button>
                      {device.ownerUid ? (
                        <button type="button" className="delete-btn" onClick={() => setPendingUnassign(device)}>Unassign</button>
                      ) : null}
                      <button type="button" className="delete-btn" onClick={() => setPendingDelete(device)}>Delete</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {pairing ? (
        <div className="modal-backdrop" onClick={() => setPairing(null)}>
          <div className="modal-card confirmation-card" onClick={(event) => event.stopPropagation()}>
            <div className="modal-card__head">
              <h3>Device Pairing Code</h3>
              <button type="button" className="ghost-btn" onClick={() => setPairing(null)}>Close</button>
            </div>
            <p className="hint-text">
              Give this code to the caretaker. They enter it during the device’s
              WiFi setup for <strong>{pairing.deviceId}</strong> — no token flashing needed.
            </p>
            <div className="pairing-code">{pairing.code}</div>
            <p className="hint-text">
              Expires {pairing.expiresAt ? new Date(pairing.expiresAt).toLocaleTimeString() : 'in ~30 min'} · single use.
            </p>
            <div className="form-actions">
              <button
                type="button"
                onClick={() => navigator.clipboard?.writeText(pairing.code)}
              >
                Copy Code
              </button>
              <button type="button" className="ghost-btn" onClick={() => setPairing(null)}>Done</button>
            </div>
          </div>
        </div>
      ) : null}

      {pendingDelete ? (
        <div className="modal-backdrop" onClick={() => setPendingDelete(null)}>
          <div className="modal-card confirmation-card" onClick={(event) => event.stopPropagation()}>
            <div className="modal-card__head">
              <h3>Delete device</h3>
              <button type="button" className="ghost-btn" onClick={() => setPendingDelete(null)}>Close</button>
            </div>
            <p className="hint-text">
              Permanently remove <strong>{pendingDelete.id}</strong> from the fleet
              (its assignment, live data, alerts and history). This cannot be undone.
              A device that is still powered on may reappear on its next write.
            </p>
            <div className="form-actions">
              <button type="button" className="delete-btn" disabled={isSubmitting} onClick={confirmDelete}>
                {isSubmitting ? 'Deleting...' : 'Delete Device'}
              </button>
              <button type="button" className="ghost-btn" onClick={() => setPendingDelete(null)}>Cancel</button>
            </div>
          </div>
        </div>
      ) : null}

      {pendingUnassign ? (
        <div className="modal-backdrop" onClick={() => setPendingUnassign(null)}>
          <div className="modal-card confirmation-card" onClick={(event) => event.stopPropagation()}>
            <div className="modal-card__head">
              <h3>Confirm Unassign</h3>
              <button type="button" className="ghost-btn" onClick={() => setPendingUnassign(null)}>Close</button>
            </div>
            <p className="hint-text">
              Unlink <strong>{pendingUnassign.id}</strong> from{' '}
              <strong>{userName(pendingUnassign.ownerUid)}</strong>? The patient will no longer see this device in the app.
            </p>
            <div className="form-actions">
              <button type="button" className="delete-btn" disabled={isSubmitting} onClick={confirmUnassign}>
                {isSubmitting ? 'Unassigning...' : 'Unassign Device'}
              </button>
              <button type="button" className="ghost-btn" onClick={() => setPendingUnassign(null)}>Cancel</button>
            </div>
          </div>
        </div>
      ) : null}

      {isModalOpen ? (
        <div className="modal-backdrop" onClick={closeModal}>
          <div className="modal-card" onClick={(event) => event.stopPropagation()}>
            <div className="modal-card__head">
              <h3>{modalMode === 'reassign' ? 'Reassign Device' : modalMode === 'fulfil' ? 'Fulfil Request' : 'Assign Device'}</h3>
              <button type="button" className="ghost-btn" onClick={closeModal}>Close</button>
            </div>

            <form className="stacked-form modal-form" noValidate onSubmit={handleSubmit}>
              <label>
                Device ID
                <input
                  name="deviceId"
                  type="text"
                  value={form.deviceId}
                  onChange={handleChange}
                  placeholder="e.g. test-device-1"
                  disabled={modalMode === 'reassign'}
                />
              </label>
              <label>
                App User
                <select name="uid" value={form.uid} onChange={handleChange} disabled={modalMode === 'fulfil'}>
                  <option value="">Select an account…</option>
                  {appUsers.map((user) => (
                    <option key={user.uid} value={user.uid}>{user.name} ({user.email})</option>
                  ))}
                </select>
              </label>
              <label>
                Patient Name
                <input name="patientName" type="text" value={form.patientName} onChange={handleChange} placeholder="Patient's name" />
              </label>
              <label>
                Relation to Account
                <input name="patientRelation" type="text" value={form.patientRelation} onChange={handleChange} placeholder="self, parent, child, …" />
              </label>
              <label>
                Room
                <input name="room" type="text" value={form.room} onChange={handleChange} placeholder="Bedroom" />
              </label>
              <div className="form-row">
                <label>
                  Normal Low (bpm)
                  <input name="normalLow" type="number" value={form.normalLow} onChange={handleChange} min="1" max="59" />
                </label>
                <label>
                  Normal High (bpm)
                  <input name="normalHigh" type="number" value={form.normalHigh} onChange={handleChange} min="2" max="60" />
                </label>
              </div>

              {statusMessage ? <p className="form-message">{statusMessage}</p> : null}

              <div className="form-actions">
                <button type="submit" disabled={isSubmitting}>
                  {isSubmitting ? 'Saving...' : modalMode === 'reassign' ? 'Update Assignment' : modalMode === 'fulfil' ? 'Assign & Fulfil' : 'Assign Device'}
                </button>
                <button type="button" className="ghost-btn" onClick={closeModal}>Cancel</button>
              </div>
            </form>
          </div>
        </div>
      ) : null}
    </section>
  )
}

export default AdminDevicesPage
