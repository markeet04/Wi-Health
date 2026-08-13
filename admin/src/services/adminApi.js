const TOKEN_KEY = 'wi-netra-admin-token'
const SESSION_KEY = 'wi-netra-admin-session'
const BASE_URL = import.meta.env.VITE_ADMIN_API_BASE_URL ?? '/api'

// NOTE: all demo/fallback behaviour lives in the BACKEND and only activates
// when Firebase env is missing there. The frontend never fakes a session or
// dashboard data — a rejected login is a rejected login.

// Firebase ID tokens expire ~1h. When an authorized request comes back 401,
// we transparently exchange the stored refresh token for a fresh ID token
// (POST /auth/refresh) and retry the original request ONCE — so the admin stays
// signed in without a manual re-login. `_retry` guards against loops.
async function request(path, options = {}) {
  // Prefer the freshest stored token over a (possibly stale) caller-passed one,
  // so after a silent refresh subsequent calls don't keep hitting 401s with an
  // expired token held in App state.
  const authToken = options.token
    ? (localStorage.getItem(TOKEN_KEY) ?? options.token)
    : undefined

  const response = await fetch(`${BASE_URL}${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
      ...(options.headers ?? {}),
    },
    ...options,
  })

  if (response.status === 401 && options.token && !options._retry) {
    const freshToken = await tryRefreshToken()
    if (freshToken) {
      return request(path, { ...options, token: freshToken, _retry: true })
    }
  }

  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    throw new Error(payload?.message ?? 'Request failed.')
  }

  return payload
}

// Exchange the stored refresh token for a fresh session. Returns the new access
// token on success, or null (caller then surfaces the 401 / bounces to login).
// Serialized so concurrent 401s don't fire multiple refreshes.
let refreshInFlight = null
async function tryRefreshToken() {
  const stored = readSession()
  if (!stored?.refreshToken) return null

  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      try {
        const res = await fetch(`${BASE_URL}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken: stored.refreshToken }),
        })
        if (!res.ok) return null
        const session = await res.json().catch(() => null)
        if (!session?.accessToken) return null
        persistSession(session)
        return session.accessToken
      } catch {
        return null
      } finally {
        refreshInFlight = null
      }
    })()
  }
  return refreshInFlight
}

function persistSession(session) {
  // Preserve an existing refresh token if this session object doesn't carry one
  // (e.g. /auth/session returns the user + access token but no refresh token).
  const existing = readSession()
  const merged = {
    ...session,
    refreshToken: session.refreshToken ?? existing?.refreshToken,
  }
  localStorage.setItem(SESSION_KEY, JSON.stringify(merged))
  localStorage.setItem(TOKEN_KEY, merged.accessToken)
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

export async function fetchAdminSettings(accessToken) {
  if (!accessToken) return null

  try {
    return await request('/admin/settings', {
      method: 'GET',
      token: accessToken,
    })
  } catch {
    return null
  }
}

export async function updateAdminSettings(accessToken, payload) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request('/admin/settings', {
    method: 'PATCH',
    token: accessToken,
    body: JSON.stringify(payload),
  })
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

export async function fetchAdminDevices(accessToken) {
  if (!accessToken) return null

  try {
    return await request('/admin/devices', {
      method: 'GET',
      token: accessToken,
    })
  } catch {
    return null
  }
}

export async function assignAdminDevice(accessToken, deviceId, payload) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/devices/${deviceId}/assign`, {
    method: 'POST',
    token: accessToken,
    body: JSON.stringify(payload),
  })
}

export async function unassignAdminDevice(accessToken, deviceId) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/devices/${deviceId}/unassign`, {
    method: 'POST',
    token: accessToken,
  })
}

export async function deleteAdminDevice(accessToken, deviceId) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/devices/${deviceId}`, {
    method: 'DELETE',
    token: accessToken,
  })
}

export async function declineAdminDeviceRequest(accessToken, requestId) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/device-requests/${requestId}/decline`, {
    method: 'POST',
    token: accessToken,
  })
}

// Generate a short single-use pairing code for a device. The caretaker enters
// it during the device's WiFi setup to provision it — no token flashing.
export async function createDevicePairingCode(accessToken, deviceId) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/devices/${deviceId}/pairing-code`, {
    method: 'POST',
    token: accessToken,
  })
}

export async function sendComplaintMessage(accessToken, complaintId, payload) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/complaints/${complaintId}/messages`, {
    method: 'POST',
    token: accessToken,
    body: JSON.stringify(payload),
  })
}

export async function resolveComplaint(accessToken, complaintId) {
  if (!accessToken) {
    throw new Error('Admin session is required.')
  }

  return request(`/admin/complaints/${complaintId}/resolve`, {
    method: 'PATCH',
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
