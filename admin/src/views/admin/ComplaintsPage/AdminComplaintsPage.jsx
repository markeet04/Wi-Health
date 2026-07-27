import { useEffect, useMemo, useState } from 'react'
import './AdminComplaintsPage.css'
import { resolveComplaint, sendComplaintMessage } from '../../../services/adminApi'

const normalizeStatus = (status) => {
  const value = String(status ?? '').toLowerCase()
  if (value.includes('resolve')) return 'resolved'
  if (value.includes('progress')) return 'in_progress'
  return 'open'
}

const normalizeMessages = (rawMessages, fallbackText) => {
  if (Array.isArray(rawMessages)) {
    return rawMessages
      .filter(Boolean)
      .map((message) => ({
        id: message.id ?? `${message.senderUid ?? 'msg'}-${message.sentAt ?? Date.now()}`,
        senderUid: message.senderUid ?? 'admin',
        senderRole: message.senderRole === 'admin' ? 'admin' : 'app_user',
        text: message.text ?? '',
        sentAt: message.sentAt ?? Date.now(),
      }))
      .filter((message) => message.text.trim())
      .sort((left, right) => left.sentAt - right.sentAt)
  }

  if (rawMessages && typeof rawMessages === 'object') {
    return Object.entries(rawMessages)
      .map(([messageId, entry]) => {
        const message = entry && typeof entry === 'object' ? entry : {}
        return {
          id: messageId,
          senderUid: message.senderUid ?? 'admin',
          senderRole: message.senderRole === 'admin' ? 'admin' : 'app_user',
          text: message.text ?? '',
          sentAt: message.sentAt ?? Date.now(),
        }
      })
      .filter((message) => message.text.trim())
      .sort((left, right) => left.sentAt - right.sentAt)
  }

  if (fallbackText) {
    return [{
      id: `initial-${Date.now()}`,
      senderUid: 'admin',
      senderRole: 'admin',
      text: fallbackText,
      sentAt: Date.now(),
    }]
  }

  return []
}

const normalizeComplaint = (complaint, index) => {
  const fallbackText = complaint?.adminResponse ? `Legacy admin response: ${complaint.adminResponse}` : ''
  return {
    id: complaint?.id ?? `complaint-${index + 1}`,
    uid: complaint?.uid ?? '',
    user: complaint?.user ?? 'Unknown user',
    patient: complaint?.patient ?? complaint?.subject ?? 'Unknown patient',
    category: complaint?.category ?? 'Other',
    subject: complaint?.subject ?? complaint?.issue ?? 'No subject',
    description: complaint?.description ?? complaint?.issue ?? 'No details provided',
    status: normalizeStatus(complaint?.status),
    submitted: complaint?.submitted ?? 'Recently opened',
    createdAt: complaint?.createdAt ?? Date.now(),
    updatedAt: complaint?.updatedAt ?? complaint?.createdAt ?? Date.now(),
    messages: normalizeMessages(complaint?.messages, fallbackText),
  }
}

function AdminComplaintsPage({ complaints = [], accessToken, onComplaintsChanged }) {
  const [complaintState, setComplaintState] = useState(() => (complaints ?? []).map(normalizeComplaint))
  const [selectedComplaintId, setSelectedComplaintId] = useState(null)
  const [draft, setDraft] = useState('')
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [isChatOpen, setIsChatOpen] = useState(false)

  useEffect(() => {
    setComplaintState((previous) => {
      const next = (complaints ?? [])
        .map((complaint, index) => {
          const existing = previous.find((item) => item.id === (complaint?.id ?? `complaint-${index + 1}`))
          return existing
            ? { ...normalizeComplaint(complaint, index), messages: existing.messages }
            : normalizeComplaint(complaint, index)
        })
        .sort((left, right) => {
          const leftTime = left.createdAt ?? 0
          const rightTime = right.createdAt ?? 0
          return rightTime - leftTime
        })

      return next
    })
  }, [complaints])

  useEffect(() => {
    if (!onComplaintsChanged) return undefined

    const timer = window.setInterval(() => {
      onComplaintsChanged()
    }, 5000)

    return () => window.clearInterval(timer)
  }, [onComplaintsChanged])

  const selectedComplaint = useMemo(() => {
    if (!complaintState.length) return null
    return complaintState.find((complaint) => complaint.id === selectedComplaintId) ?? complaintState[0]
  }, [complaintState, selectedComplaintId])

  const openModal = (complaint) => {
    setSelectedComplaintId(complaint.id)
    setDraft('')
    setIsModalOpen(true)
  }

  const closeModal = () => {
    setIsModalOpen(false)
    setIsChatOpen(false)
    setDraft('')
  }

  const handleSendMessage = async () => {
    if (!selectedComplaint || !draft.trim() || !accessToken) return

    const nextMessage = {
      id: `admin-${Date.now()}`,
      senderUid: selectedComplaint.uid || 'admin',
      senderRole: 'admin',
      text: draft.trim(),
      sentAt: Date.now(),
    }

    setComplaintState((previous) => previous.map((complaint) => {
      if (complaint.id !== selectedComplaint.id) return complaint
      return {
        ...complaint,
        status: complaint.status === 'open' ? 'in_progress' : complaint.status,
        updatedAt: Date.now(),
        messages: [...complaint.messages, nextMessage],
      }
    }))

    try {
      await sendComplaintMessage(accessToken, selectedComplaint.id, { text: draft.trim() })
      if (onComplaintsChanged) {
        await onComplaintsChanged()
      }
    } catch (error) {
      console.error('Unable to send complaint message', error)
    } finally {
      setDraft('')
    }
  }

  const handleResolve = async () => {
    if (!selectedComplaint || !accessToken) return

    setComplaintState((previous) => previous.map((complaint) => {
      if (complaint.id !== selectedComplaint.id) return complaint
      return {
        ...complaint,
        status: 'resolved',
        updatedAt: Date.now(),
      }
    }))

    try {
      await resolveComplaint(accessToken, selectedComplaint.id)
      if (onComplaintsChanged) {
        await onComplaintsChanged()
      }
    } catch (error) {
      console.error('Unable to resolve complaint', error)
    }
  }

  return (
    <section className="page-grid admin-complaints-page page-fade">
      <div className="card card-span-3 complaints-queue-card">
        <h2>Complaints Queue</h2>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>App User</th><th>Patient</th><th>Issue</th><th>Status</th><th>Submitted</th>
            </tr>
          </thead>
          <tbody>
            {complaintState.map((complaint) => (
              <tr key={complaint.id} className="complaint-row" onClick={() => openModal(complaint)}>
                <td>{complaint.id}</td>
                <td>{complaint.user}</td>
                <td>{complaint.patient}</td>
                <td>{complaint.subject}</td>
                <td>{complaint.status}</td>
                <td>{complaint.submitted}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {isModalOpen && selectedComplaint ? (
        <div className="complaint-modal-backdrop" onClick={closeModal}>
          <div className="complaint-modal" onClick={(event) => event.stopPropagation()}>
            <div className="complaint-modal__header">
              <div>
                <p className="muted">Complaint detail</p>
                <h3>{selectedComplaint.subject}</h3>
              </div>
              <button type="button" className="ghost-btn" onClick={closeModal}>Close</button>
            </div>

            <div className="complaint-modal__body">
              <div className="card complaint-modal__details">
                <h4>Details</h4>
                <div className="detail-row"><span>Category</span><strong>{selectedComplaint.category}</strong></div>
                <div className="detail-row"><span>App user</span><strong>{selectedComplaint.user}</strong></div>
                <div className="detail-row"><span>Patient</span><strong>{selectedComplaint.patient}</strong></div>
                <div className="detail-row"><span>Status</span><strong>{selectedComplaint.status}</strong></div>
                <div className="detail-row"><span>Submitted</span><strong>{selectedComplaint.submitted}</strong></div>
                <div className="detail-row detail-row--stacked"><span>Description</span><p>{selectedComplaint.description}</p></div>

                <div className="detail-actions">
                  <button
                    type="button"
                    className="primary-btn"
                    onClick={() => setIsChatOpen(true)}
                    disabled={selectedComplaint.status === 'resolved'}
                  >
                    Admin reply
                  </button>
                  <button
                    type="button"
                    className="ghost-btn"
                    onClick={handleResolve}
                    disabled={selectedComplaint.status === 'resolved'}
                  >
                    Mark as resolved
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {isChatOpen && selectedComplaint ? (
        <div className="complaint-modal-backdrop" onClick={() => setIsChatOpen(false)}>
          <div className="complaint-modal complaint-chat-modal" onClick={(event) => event.stopPropagation()}>
            <div className="complaint-modal__header">
              <div>
                <p className="muted">Admin reply</p>
                <h3>Chat with user</h3>
              </div>
              <button type="button" className="ghost-btn" onClick={() => setIsChatOpen(false)}>Close</button>
            </div>

            <div className="complaint-modal__chat">
              <div className="chat-thread">
                {selectedComplaint.messages.length === 0 ? (
                  <p className="muted">No messages yet — start the conversation with your first reply.</p>
                ) : (
                  selectedComplaint.messages.map((message) => (
                    <div key={message.id} className={`chat-bubble ${message.senderRole === 'admin' ? 'chat-bubble--admin' : ''}`}>
                      <div className="chat-bubble__meta">
                        <strong>{message.senderRole === 'admin' ? 'Admin' : 'App user'}</strong>
                        <span>{new Date(message.sentAt).toLocaleString()}</span>
                      </div>
                      <p>{message.text}</p>
                    </div>
                  ))
                )}
              </div>

              <textarea
                rows={4}
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                disabled={selectedComplaint.status === 'resolved'}
                placeholder={selectedComplaint.status === 'resolved' ? 'This complaint is resolved and the chat is closed.' : 'Type an admin reply...'}
              />

              <div className="chat-actions">
                <button
                  type="button"
                  className="primary-btn"
                  onClick={handleSendMessage}
                  disabled={!draft.trim() || selectedComplaint.status === 'resolved'}
                >
                  Send admin reply
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  )
}

export default AdminComplaintsPage