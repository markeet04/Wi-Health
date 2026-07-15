const TOKEN_KEY = 'wi-netra-admin-token'
const SESSION_KEY = 'wi-netra-admin-session'
const BASE_URL = import.meta.env.VITE_ADMIN_API_BASE_URL ?? '/api'

// NOTE: all demo/fallback behaviour lives in the BACKEND and only activates
// when Firebase env is missing there. The frontend never fakes a session or
// dashboard data — a rejected login is a rejected login.

async function request(path, options = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
      ...(options.headers ?? {}),
    },
    ...options,
  })

  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    throw new Error(payload?.message ?? 'Request failed.')
  }

  return payload
}

function persistSession(session) {
  localStorage.setItem(SESSION_KEY, JSON.stringify(session))
  localStorage.setItem(TOKEN_KEY, session.accessToken)
}

function clearSession() {
  localStorage.removeItem(SESSION_KEY)
  localStorage.removeItem(TOKEN_KEY)
}

function readSession() {
  try {
    const raw = localStorage.getItem(SESSION_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

export async function signInAdmin({ email, password }) {
  const session = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  })

  persistSession(session)
  return session
}

export async function restoreAdminSession() {
  const storedSession = readSession()
  if (!storedSession?.accessToken) return null

  try {
    const session = await request('/auth/session', {
      method: 'GET',
      token: storedSession.accessToken,
    })

    persistSession(session)
    return session
  } catch {
    clearSession()
    return null
  }
}

export async function fetchAdminData(accessToken) {
  if (!accessToken) return null

  try {
    return await request('/admin/dashboard', {
      method: 'GET',
      token: accessToken,
    })
  } catch {
    // Surface empty states rather than fake data.
    return null
  }
}

export async function fetchAdminUsers(accessToken) {
  if (!accessToken) return []

  try {
    return await request('/admin/users', {
      method: 'GET',
      token: accessToken,
    })
  } catch {
    return []
  }
}

export async function createAdminUser(accessToken, payload) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request('/admin/users', {
    method: 'POST',
    token: accessToken,
    body: JSON.stringify(payload),
  })
}

export async function updateAdminUser(accessToken, uid, payload) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/users/${uid}`, {
    method: 'PATCH',
    token: accessToken,
    body: JSON.stringify(payload),
  })
}

export async function deleteAdminUser(accessToken, uid) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/users/${uid}`, {
    method: 'DELETE',
    token: accessToken,
  })
}

export async function signOutAdmin(accessToken) {
  if (accessToken) {
    try {
      await request('/auth/logout', {
        method: 'POST',
        token: accessToken,
      })
    } catch {
      // Logout is best-effort; local session clearing still wins.
    }
  }

  clearSession()
}
