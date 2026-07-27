import { useEffect, useMemo, useRef, useState } from 'react'
import './AdminComplaintsPage.css'
import { resolveComplaint, sendComplaintMessage } from '../../../services/adminApi'

const normalizeStatus = (status) => {
  const value = String(status ?? '').toLowerCase()
  if (value.includes('resolve')) return 'resolved'
  if (value.includes('progress')) return 'in_progress'
  return 'open'
}

const STATUS_META = {
  open: { label: 'Open', tone: 'amber' },
  in_progress: { label: 'In progress', tone: 'teal' },
  resolved: { label: 'Resolved', tone: 'green' },
}

const initialsOf = (name) =>
  String(name || '?')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('') || '?'

const firstNameOf = (name) => String(name || 'the user').trim().split(/\s+/)[0]

const formatTime = (ms) => {
  const date = new Date(ms)
  if (Number.isNaN(date.getTime())) return ''
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

const normalizeMessages = (rawMessages, fallbackText) => {
  const toMessage = (message, fallbackId) => ({
    id: message.id ?? fallbackId,
    senderUid: message.senderUid ?? 'admin',
    senderRole: message.senderRole === 'admin' ? 'admin' : 'app_user',
    text: message.text ?? '',
    sentAt: message.sentAt ?? Date.now(),
  })

  if (Array.isArray(rawMessages)) {
    return rawMessages
      .filter(Boolean)
      .map((message) => toMessage(message, `${message.senderUid ?? 'msg'}-${message.sentAt ?? Date.now()}`))
      .filter((message) => message.text.trim())
      .sort((left, right) => left.sentAt - right.sentAt)
  }

  if (rawMessages && typeof rawMessages === 'object') {
    return Object.entries(rawMessages)
      .map(([messageId, entry]) => toMessage(entry && typeof entry === 'object' ? entry : {}, messageId))
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

function StatusPill({ status }) {
  const meta = STATUS_META[status] ?? STATUS_META.open
  return <span className={`c-pill c-pill--${meta.tone}`}>{meta.label}</span>
}

function AdminComplaintsPage({ complaints = [], accessToken, onComplaintsChanged }) {
  const [complaintState, setComplaintState] = useState(() => (complaints ?? []).map(normalizeComplaint))
  const [detailId, setDetailId] = useState(null)      // complaint open in the detail modal
  const [chatId, setChatId] = useState(null)          // complaint open in the docked chat
  const [chatMinimized, setChatMinimized] = useState(false)
  const [draft, setDraft] = useState('')
  const threadRef = useRef(null)

  useEffect(() => {
    setComplaintState((previous) => (complaints ?? [])
      .map((complaint, index) => {
        const normalized = normalizeComplaint(complaint, index)
        const existing = previous.find((item) => item.id === normalized.id)
        if (!existing) return normalized

        // Server is the source of truth for messages. Keep only optimistic
        // local messages the server hasn't echoed back yet (an admin reply we
        // just sent, before the poll returns its real push-key copy) so nothing
        // flickers out and back in. An optimistic message is considered echoed
        // once the server has a message with the same role + text at/after its
        // send time — then we drop the optimistic copy to avoid a duplicate.
        const pendingLocal = existing.messages.filter((message) => {
          if (!message.optimistic) return false
          const echoed = normalized.messages.some((server) =>
            server.senderRole === message.senderRole &&
            server.text === message.text &&
            server.sentAt >= message.sentAt - 60000)
          return !echoed
        })
        const mergedMessages = [...normalized.messages, ...pendingLocal]
          .sort((left, right) => left.sentAt - right.sentAt)

        return { ...normalized, messages: mergedMessages }
      })
      .sort((left, right) => (right.createdAt ?? 0) - (left.createdAt ?? 0)))
  }, [complaints])

  useEffect(() => {
    if (!onComplaintsChanged) return undefined
    const timer = window.setInterval(() => onComplaintsChanged(), 5000)
    return () => window.clearInterval(timer)
  }, [onComplaintsChanged])

  const detailComplaint = useMemo(
    () => complaintState.find((complaint) => complaint.id === detailId) ?? null,
    [complaintState, detailId],
  )
  const chatComplaint = useMemo(
    () => complaintState.find((complaint) => complaint.id === chatId) ?? null,
    [complaintState, chatId],
  )

  const counts = useMemo(() => complaintState.reduce((acc, complaint) => {
    acc[complaint.status] = (acc[complaint.status] ?? 0) + 1
    return acc
  }, {}), [complaintState])

  // keep the docked thread pinned to the newest message
  useEffect(() => {
    if (chatMinimized || !threadRef.current) return
    threadRef.current.scrollTop = threadRef.current.scrollHeight
  }, [chatId, chatMinimized, chatComplaint?.messages.length])

  const chatResolved = chatComplaint?.status === 'resolved'

  const openChat = (complaint) => {
    setChatId(complaint.id)
    setChatMinimized(false)
    setDraft('')
  }

  const closeChat = () => {
    setChatId(null)
    setDraft('')
  }

  const handleSendMessage = async () => {
    if (!chatComplaint || !draft.trim() || !accessToken || chatResolved) return
    const text = draft.trim()

    const nextMessage = {
      id: `optimistic-admin-${Date.now()}`,
      optimistic: true,
      senderUid: chatComplaint.uid || 'admin',
      senderRole: 'admin',
      text,
      sentAt: Date.now(),
    }

    setComplaintState((previous) => previous.map((complaint) => (
      complaint.id === chatComplaint.id
        ? {
            ...complaint,
            status: complaint.status === 'open' ? 'in_progress' : complaint.status,
            updatedAt: Date.now(),
            messages: [...complaint.messages, nextMessage],
          }
        : complaint
    )))
    setDraft('')

    try {
      await sendComplaintMessage(accessToken, chatComplaint.id, { text })
      if (onComplaintsChanged) await onComplaintsChanged()
    } catch (error) {
      console.error('Unable to send complaint message', error)
    }
  }

  const handleResolve = async (complaint) => {
    const target = complaint ?? chatComplaint ?? detailComplaint
    if (!target || !accessToken || target.status === 'resolved') return

    setComplaintState((previous) => previous.map((item) => (
      item.id === target.id ? { ...item, status: 'resolved', updatedAt: Date.now() } : item
    )))

    try {
      await resolveComplaint(accessToken, target.id)
      if (onComplaintsChanged) await onComplaintsChanged()
    } catch (error) {
      console.error('Unable to resolve complaint', error)
    }
  }

  const onComposerKeyDown = (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault()
      handleSendMessage()
    }
  }

  return (
    <section className="page-grid admin-complaints-page page-fade">
      <div className="card card-span-3 complaints-queue-card">
        <div className="queue-head">
          <h2>Complaints Queue</h2>
          <div className="queue-tally">
            <span className="tally tally--amber">{counts.open ?? 0} open</span>
            <span className="tally tally--teal">{counts.in_progress ?? 0} in progress</span>
            <span className="tally tally--green">{counts.resolved ?? 0} resolved</span>
          </div>
        </div>

        {complaintState.length === 0 ? (
          <div className="queue-empty">No complaints in the queue.</div>
        ) : (
          <div className="complaint-list">
            {complaintState.map((complaint) => (
              <button
                type="button"
                key={complaint.id}
                className="complaint-item"
                onClick={() => setDetailId(complaint.id)}
              >
                <span className="complaint-item__avatar" aria-hidden>
                  {initialsOf(complaint.user)}
                </span>
                <span className="complaint-item__main">
                  <span className="complaint-item__subject">{complaint.subject}</span>
                  <span className="complaint-item__sub">
                    {complaint.user} · {complaint.patient} · {complaint.category}
                  </span>
                </span>
                <span className="complaint-item__side">
                  <StatusPill status={complaint.status} />
                  <span className="complaint-item__time">{complaint.submitted}</span>
                </span>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* ---- detail modal ---- */}
      {detailComplaint ? (
        <div className="c-modal-backdrop" onClick={() => setDetailId(null)}>
          <div className="c-modal" onClick={(event) => event.stopPropagation()}>
            <header className="c-modal__header">
              <div className="c-modal__title">
                <span className="c-modal__avatar" aria-hidden>{initialsOf(detailComplaint.user)}</span>
                <div>
                  <h3>{detailComplaint.subject}</h3>
                  <p className="c-modal__meta">
                    <StatusPill status={detailComplaint.status} />
                    <span>{detailComplaint.user}</span>
                  </p>
                </div>
              </div>
              <button type="button" className="c-icon-btn" onClick={() => setDetailId(null)} aria-label="Close">✕</button>
            </header>

            <div className="c-modal__body">
              <dl className="c-details">
                <div><dt>Category</dt><dd>{detailComplaint.category}</dd></div>
                <div><dt>App user</dt><dd>{detailComplaint.user}</dd></div>
                <div><dt>Patient</dt><dd>{detailComplaint.patient}</dd></div>
                <div><dt>Submitted</dt><dd>{detailComplaint.submitted}</dd></div>
              </dl>
              <div className="c-description">
                <span className="c-description__label">Description</span>
                <p>{detailComplaint.description}</p>
              </div>

              <div className="c-modal__actions">
                <button
                  type="button"
                  className="c-btn c-btn--primary"
                  onClick={() => { openChat(detailComplaint); setDetailId(null) }}
                >
                  {detailComplaint.status === 'resolved' ? 'View conversation' : 'Reply to user'}
                </button>
                <button
                  type="button"
                  className="c-btn c-btn--ghost"
                  onClick={() => handleResolve(detailComplaint)}
                  disabled={detailComplaint.status === 'resolved'}
                >
                  {detailComplaint.status === 'resolved' ? 'Resolved' : 'Mark as resolved'}
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {/* ---- docked chat (bottom-right, Messenger/IG style) ---- */}
      {chatComplaint ? (
        <div className={`c-dock ${chatMinimized ? 'is-min' : ''}`}>
          <header
            className="c-dock__bar"
            onClick={() => chatMinimized && setChatMinimized(false)}
          >
            <span className="c-dock__avatar" aria-hidden>{initialsOf(chatComplaint.user)}</span>
            <span className="c-dock__id">
              <span className="c-dock__name">{chatComplaint.user}</span>
              <span className="c-dock__subject">{chatComplaint.subject}</span>
            </span>
            <span className="c-dock__controls">
              <StatusPill status={chatComplaint.status} />
              <button
                type="button"
                className="c-dock__btn"
                onClick={(event) => { event.stopPropagation(); setChatMinimized((value) => !value) }}
                aria-label={chatMinimized ? 'Expand chat' : 'Minimize chat'}
              >
                {chatMinimized ? '▲' : '▁'}
              </button>
              <button
                type="button"
                className="c-dock__btn"
                onClick={(event) => { event.stopPropagation(); closeChat() }}
                aria-label="Close chat"
              >
                ✕
              </button>
            </span>
          </header>

          {!chatMinimized ? (
            <>
              <div className="c-dock__thread" ref={threadRef}>
                {chatComplaint.messages.length === 0 ? (
                  <p className="c-dock__empty">
                    No messages yet — start the conversation with {firstNameOf(chatComplaint.user)}.
                  </p>
                ) : (
                  chatComplaint.messages.map((message) => {
                    const mine = message.senderRole === 'admin'
                    return (
                      <div key={message.id} className={`c-bubble-row ${mine ? 'is-admin' : 'is-user'}`}>
                        <div className="c-bubble">
                          <p className="c-bubble__text">{message.text}</p>
                          <span className="c-bubble__time">
                            {mine ? 'You' : firstNameOf(chatComplaint.user)} · {formatTime(message.sentAt)}
                          </span>
                        </div>
                      </div>
                    )
                  })
                )}
              </div>

              {chatResolved ? (
                <div className="c-dock__closed">
                  Resolved — the conversation is closed. History is preserved above.
                </div>
              ) : (
                <div className="c-dock__composer">
                  <textarea
                    rows={1}
                    value={draft}
                    onChange={(event) => setDraft(event.target.value)}
                    onKeyDown={onComposerKeyDown}
                    placeholder="Write a reply…"
                  />
                  <button
                    type="button"
                    className="c-dock__send"
                    onClick={handleSendMessage}
                    disabled={!draft.trim()}
                    aria-label="Send reply"
                  >
                    Send
                  </button>
                </div>
              )}

              {!chatResolved ? (
                <button
                  type="button"
                  className="c-dock__resolve"
                  onClick={() => handleResolve(chatComplaint)}
                >
                  Mark as resolved
                </button>
              ) : null}
            </>
          ) : null}
        </div>
      ) : null}
    </section>
  )
}

export default AdminComplaintsPage
