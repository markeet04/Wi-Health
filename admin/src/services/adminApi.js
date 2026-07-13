import { alerts, complaints, fleetDevices, users } from '../data/appData'

const TOKEN_KEY = 'wi-netra-admin-token'
const SESSION_KEY = 'wi-netra-admin-session'
const BASE_URL = import.meta.env.VITE_ADMIN_API_BASE_URL ?? '/api'

const demoSession = {
  accessToken: 'demo-admin-token',
  source: 'demo',
  user: {
    uid: 'admin-ops',
    name: 'Admin Ops',
    email: 'admin@wi-netra.health',
    role: 'admin',
  },
}

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

function readSession() {
  try {
    const raw = localStorage.getItem(SESSION_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

function fallbackDashboard() {
  return {
    stats: { monitoredPatients: 4 },
    fleetDevices,
    users,
    alerts,
    complaints,
  }
}

export async function signInAdmin({ email, password }) {
  try {
    const session = await request('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })

    persistSession(session)
    return session
  } catch (error) {
    const isDemoAccount = email.trim().toLowerCase() === demoSession.user.email && password.trim().length > 0

    if (!isDemoAccount) {
      throw error
    }

    persistSession(demoSession)
    return demoSession
  }
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
    if (storedSession.accessToken === demoSession.accessToken) {
      return storedSession
    }

    localStorage.removeItem(SESSION_KEY)
    localStorage.removeItem(TOKEN_KEY)
    return null
  }
}

export async function fetchAdminData(accessToken) {
  if (!accessToken) return fallbackDashboard()

  try {
    return await request('/admin/dashboard', {
      method: 'GET',
      token: accessToken,
    })
  } catch {
    return fallbackDashboard()
  }
}

export async function signOutAdmin(accessToken) {
  if (accessToken && accessToken !== demoSession.accessToken) {
    try {
      await request('/auth/logout', {
        method: 'POST',
        token: accessToken,
      })
    } catch {
      // Logout is best-effort; local session clearing still wins.
    }
  }

  localStorage.removeItem(SESSION_KEY)
  localStorage.removeItem(TOKEN_KEY)
}