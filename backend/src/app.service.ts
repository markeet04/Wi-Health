import { ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common'
import crypto from 'node:crypto'
import { applicationDefault, initializeApp, getApps, type App as FirebaseApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getDatabase } from 'firebase-admin/database'

export type LoginRequest = {
  email: string
  password: string
}

type AdminRole = 'admin'

type AdminUser = {
  uid: string
  name: string
  email: string
  role: AdminRole
}

type AdminSession = {
  accessToken: string
  source: 'firebase' | 'demo'
  user: AdminUser
}

type DashboardResponse = {
  stats: {
    monitoredPatients: number
  }
  fleetDevices: Array<{
    id: string
    patient: string
    status: string
    health: string
    updated: string
  }>
  users: Array<{
    name: string
    role: string
    patients: string
    devices: string
    status: string
  }>
  alerts: Array<{
    time: string
    patient: string
    device: string
    anomaly: string
    severity: string
    status: string
  }>
  complaints: Array<{
    id: string
    user: string
    patient: string
    issue: string
    status: string
    submitted: string
  }>
}

const demoSession: AdminSession = {
  accessToken: 'demo-admin-token',
  source: 'demo',
  user: {
    uid: 'admin-ops',
    name: 'Admin Ops',
    email: 'admin@wi-netra.health',
    role: 'admin',
  },
}

const demoDashboard: DashboardResponse = {
  stats: { monitoredPatients: 4 },
  fleetDevices: [
    { id: 'WH-2101', patient: 'Patient A', status: 'Online', health: 'Good', updated: '10s ago' },
    { id: 'WH-2102', patient: 'Patient B', status: 'Online', health: 'Good', updated: '16s ago' },
    { id: 'WH-2103', patient: 'Patient C', status: 'Offline', health: 'Needs check', updated: '8m ago' },
    { id: 'WH-2104', patient: 'Patient D', status: 'Online', health: 'Warning', updated: '35s ago' },
  ],
  users: [
    { name: 'Anita Rao', role: 'App User', patients: '2 linked', devices: 'WH-2101, WH-2102', status: 'Active' },
    { name: 'Mohan Iyer', role: 'App User', patients: '1 linked', devices: 'WH-2104', status: 'Active' },
    { name: 'Admin Ops', role: 'Admin', patients: '-', devices: 'All devices', status: 'Active' },
    { name: 'Leela Das', role: 'App User', patients: '1 linked', devices: 'WH-2103', status: 'Pending verification' },
  ],
  alerts: [
    { time: '11:12 AM', patient: 'Patient D', device: 'WH-2104', anomaly: 'Tachypnea', severity: 'Urgent', status: 'Open' },
    { time: '10:50 AM', patient: 'Patient B', device: 'WH-2102', anomaly: 'Bradypnea', severity: 'Info', status: 'Acknowledged' },
    { time: '09:41 AM', patient: 'Patient C', device: 'WH-2103', anomaly: 'No valid breathing', severity: 'Urgent', status: 'In review' },
    { time: '09:08 AM', patient: 'Patient A', device: 'WH-2101', anomaly: 'Tachypnea', severity: 'Info', status: 'Resolved' },
  ],
  complaints: [
    { id: 'CMP-102', user: 'Anita Rao', patient: 'Patient A', issue: 'Frequent disconnect alerts', status: 'Open', submitted: 'Today, 10:02 AM' },
    { id: 'CMP-101', user: 'Leela Das', patient: 'Patient C', issue: 'Pairing failed after restart', status: 'In-progress', submitted: 'Today, 08:45 AM' },
    { id: 'CMP-097', user: 'Mohan Iyer', patient: 'Patient D', issue: 'Delayed notifications', status: 'Resolved', submitted: 'Yesterday, 07:38 PM' },
  ],
}

@Injectable()
export class AppService {
  private readonly sessions = new Map<string, AdminSession>()
  private readonly firebaseApp = this.initFirebaseApp()
  private readonly demoEmail = process.env.ADMIN_DEMO_EMAIL ?? demoSession.user.email
  private readonly demoPassword = process.env.ADMIN_DEMO_PASSWORD ?? 'demo-password'
  private readonly adminEmailAllowlist = (process.env.ADMIN_EMAIL_ALLOWLIST ?? this.demoEmail)
    .split(',')
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean)

  health() {
    return {
      ok: true,
      mode: this.firebaseEnabled() ? 'firebase' : 'demo',
      backend: 'nest',
    }
  }

  async login(body: LoginRequest) {
    const email = body.email.trim().toLowerCase()
    const password = body.password.trim()

    if (!email || !password) {
      throw new UnauthorizedException('Email and password are required.')
    }

    if (this.firebaseEnabled()) {
      return this.loginWithFirebase(email, password)
    }

    if (email !== this.demoEmail || password !== this.demoPassword) {
      throw new UnauthorizedException('Invalid admin credentials.')
    }

    this.sessions.set(demoSession.accessToken, demoSession)
    return demoSession
  }

  async restoreSession(accessToken: string): Promise<AdminSession> {
    // With Firebase configured, EVERY session must verify against Firebase.
    // The demo token/session paths exist only for env-less development —
    // never alongside real auth.
    if (this.firebaseEnabled()) {
      const user = await this.verifyFirebaseToken(accessToken)
      return { accessToken, source: 'firebase', user }
    }

    const cached = this.sessions.get(accessToken)
    if (cached) {
      return cached
    }

    if (accessToken === demoSession.accessToken) {
      this.sessions.set(accessToken, demoSession)
      return demoSession
    }

    throw new UnauthorizedException('Invalid or expired session.')
  }

  logout(accessToken: string) {
    this.sessions.delete(accessToken)
  }

  async getDashboard(accessToken: string): Promise<DashboardResponse> {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (!this.firebaseEnabled()) {
      return demoDashboard
    }

    const realDashboard = await this.loadFirebaseDashboard().catch(() => demoDashboard)
    return realDashboard
  }

  private firebaseEnabled() {
    return Boolean(this.firebaseApp && process.env.FIREBASE_WEB_API_KEY)
  }

  private initFirebaseApp(): FirebaseApp | null {
    const existing = getApps()[0]
    if (existing) {
      return existing
    }

    const projectId = process.env.FIREBASE_PROJECT_ID ?? 'wi-health-faa5d'
    // RTDB instance lives in asia-southeast1 — regional instances use
    // firebasedatabase.app, not the legacy firebaseio.com US domain.
    const databaseURL =
      process.env.FIREBASE_DATABASE_URL ??
      `https://${projectId}-default-rtdb.asia-southeast1.firebasedatabase.app`

    if (!projectId || !databaseURL) {
      return null
    }

    try {
      return initializeApp(
        {
          credential: applicationDefault(),
          projectId,
          databaseURL,
        },
        'wi-netra-admin-backend',
      )
    } catch {
      return null
    }
  }

  private async loginWithFirebase(email: string, password: string): Promise<AdminSession> {
    const apiKey = process.env.FIREBASE_WEB_API_KEY
    if (!apiKey) {
      throw new UnauthorizedException('Firebase API key is not configured.')
    }

    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, returnSecureToken: true }),
      },
    )

    const payload = (await response.json().catch(() => ({}))) as {
      idToken?: string
      localId?: string
      displayName?: string
      email?: string
      error?: { message?: string }
    }

    if (!response.ok || !payload.idToken || !payload.localId) {
      throw new UnauthorizedException(payload.error?.message ?? 'Firebase sign-in failed.')
    }

    const user = await this.verifyFirebaseToken(payload.idToken)
    if (user.role !== 'admin') {
      throw new ForbiddenException('Admin role required.')
    }

    return {
      accessToken: payload.idToken,
      source: 'firebase',
      user: {
        uid: payload.localId,
        name: payload.displayName ?? user.name,
        email: payload.email ?? email,
        role: 'admin',
      },
    }
  }

  private async verifyFirebaseToken(accessToken: string): Promise<AdminUser> {
    if (!this.firebaseApp) {
      const email = this.adminEmailAllowlist[0] ?? demoEmailFallback()
      return {
        uid: 'firebase-admin',
        name: 'Firebase Admin',
        email,
        role: 'admin',
      }
    }

    const decoded = await getAuth(this.firebaseApp).verifyIdToken(accessToken, true)
    const email = (decoded.email ?? '').toLowerCase()

    // Custom claims are authoritative once set; until then fall back to
    // /users/$uid/role in RTDB (see shared/contracts/auth-rbac.json).
    let role = (decoded.role as string | undefined) ?? null
    if (!role) {
      role = await this.lookupDatabaseRole(decoded.uid)
    }

    if (role !== 'admin' && !this.adminEmailAllowlist.includes(email)) {
      throw new ForbiddenException('Admin role required.')
    }

    // Promote the DB role into a custom claim so future tokens carry it —
    // this is the backend's side of the RBAC contract. Token refresh picks
    // it up; the current (already-verified) session continues unchanged.
    if (role === 'admin' && !decoded.role) {
      await getAuth(this.firebaseApp)
        .setCustomUserClaims(decoded.uid, { role: 'admin' })
        .catch(() => undefined)
    }

    return {
      uid: decoded.uid,
      name: decoded.name ?? decoded.email ?? 'Admin',
      email: decoded.email ?? 'admin@wi-netra.health',
      role: 'admin',
    }
  }

  private async lookupDatabaseRole(uid: string): Promise<string | null> {
    if (!this.firebaseApp) {
      return null
    }

    try {
      const snapshot = await getDatabase(this.firebaseApp).ref(`users/${uid}/role`).get()
      return snapshot.exists() ? String(snapshot.val()) : null
    } catch {
      return null
    }
  }

  private async loadFirebaseDashboard(): Promise<DashboardResponse> {
    if (!this.firebaseApp) {
      return demoDashboard
    }

    const database = getDatabase(this.firebaseApp)
    const [usersSnap, devicesSnap, alertsSnap, complaintsSnap] = await Promise.all([
      database.ref('users').get(),
      database.ref('devices').get(),
      database.ref('alerts').get(),
      database.ref('complaints').get(),
    ])

    const userRecords = this.normalizeUsers(usersSnap.val())
    const deviceRecords = this.normalizeDevices(devicesSnap.val(), userRecords)
    const alertRecords = this.normalizeAlerts(alertsSnap.val(), userRecords)
    const complaintRecords = this.normalizeComplaints(complaintsSnap.val(), userRecords)

    return {
      stats: {
        monitoredPatients: userRecords.filter((user) => user.role === 'App User').length,
      },
      fleetDevices: deviceRecords,
      users: userRecords,
      alerts: alertRecords,
      complaints: complaintRecords,
    }
  }

  private normalizeUsers(rawUsers: unknown) {
    if (!rawUsers || typeof rawUsers !== 'object') {
      return demoDashboard.users
    }

    const entries = Object.entries(rawUsers as Record<string, unknown>)
    return entries.map(([uid, value]) => {
      const user = (value as Record<string, unknown>) ?? {}
      const profile = (user.profile as Record<string, unknown>) ?? {}
      const role = String(user.role ?? 'app_user').toLowerCase() === 'admin' ? 'Admin' : 'App User'
      const deviceIds = Object.keys((user.devices as Record<string, unknown>) ?? {})

      return {
        name: String(profile.name ?? uid),
        role,
        patients: role === 'Admin' ? '-' : `${deviceIds.length} linked`,
        devices: deviceIds.length ? deviceIds.join(', ') : role === 'Admin' ? 'All devices' : '-',
        status: 'Active',
      }
    })
  }

  private normalizeDevices(rawDevices: unknown, users: DashboardResponse['users']) {
    if (!rawDevices || typeof rawDevices !== 'object') {
      return demoDashboard.fleetDevices
    }

    return Object.entries(rawDevices as Record<string, unknown>).map(([deviceId, value]) => {
      const device = (value as Record<string, unknown>) ?? {}
      const meta = (device.meta as Record<string, unknown>) ?? {}
      const live = (device.live as Record<string, unknown>) ?? {}
      const linkedUser = users.find((user) => user.devices.includes(deviceId))

      return {
        id: deviceId,
        patient: linkedUser?.name ?? 'Unassigned',
        status: String(live.status ?? 'offline').toLowerCase() === 'ok' ? 'Online' : 'Offline',
        health:
          String(live.status ?? '').toLowerCase() === 'no_breathing'
            ? 'Needs check'
            : String(meta.normalHigh ?? 0) > '0'
              ? 'Good'
              : 'Warning',
        updated: this.formatAge(live.updatedAt),
      }
    })
  }

  private normalizeAlerts(rawAlerts: unknown, users: DashboardResponse['users']) {
    if (!rawAlerts || typeof rawAlerts !== 'object') {
      return demoDashboard.alerts
    }

    const alerts: DashboardResponse['alerts'] = []
    for (const [deviceId, deviceAlerts] of Object.entries(rawAlerts as Record<string, unknown>)) {
      if (!deviceAlerts || typeof deviceAlerts !== 'object') continue

      const linkedUser = users.find((user) => user.devices.includes(deviceId))
      for (const [alertId, value] of Object.entries(deviceAlerts as Record<string, unknown>)) {
        const alert = (value as Record<string, unknown>) ?? {}
        alerts.push({
          time: this.formatTimestamp(alert.createdAt ?? alert.updatedAt),
          patient: linkedUser?.name ?? 'Unknown',
          device: deviceId,
          anomaly: String(alert.type ?? alert.anomaly ?? alertId),
          severity: String(alert.severity ?? 'Info').replace(/^./, (char) => char.toUpperCase()),
          status: String(alert.status ?? (alert.acknowledged ? 'Acknowledged' : 'Open')).replace(/^./, (char) => char.toUpperCase()),
        })
      }
    }

    return alerts.length ? alerts : demoDashboard.alerts
  }

  private normalizeComplaints(rawComplaints: unknown, users: DashboardResponse['users']) {
    if (!rawComplaints || typeof rawComplaints !== 'object') {
      return demoDashboard.complaints
    }

    return Object.entries(rawComplaints as Record<string, unknown>).map(([complaintId, value]) => {
      const complaint = (value as Record<string, unknown>) ?? {}
      const linkedUser = users.find((user) => user.name === String(complaint.user ?? complaint.uid ?? ''))
      return {
        id: complaintId,
        user: String(complaint.user ?? linkedUser?.name ?? complaint.uid ?? 'Unknown'),
        patient: String(complaint.patient ?? 'Unknown'),
        issue: String(complaint.issue ?? complaint.subject ?? complaint.message ?? 'No details provided'),
        status: this.prettyStatus(String(complaint.status ?? 'open')),
        submitted: this.formatTimestamp(complaint.createdAt ?? complaint.submittedAt),
      }
    })
  }

  private formatAge(timestamp: unknown) {
    if (typeof timestamp !== 'number') {
      return 'unknown'
    }

    const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000))
    if (seconds < 60) return `${seconds}s ago`
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ago`
    return `${Math.floor(minutes / 60)}h ago`
  }

  private formatTimestamp(timestamp: unknown) {
    if (typeof timestamp !== 'number') {
      return 'Unknown'
    }

    const date = new Date(timestamp)
    return date.toLocaleString('en-IN', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: true,
    })
  }

  private prettyStatus(status: string) {
    return status
      .split(/[-_\s]+/)
      .filter(Boolean)
      .map((part) => part[0].toUpperCase() + part.slice(1).toLowerCase())
      .join('-')
  }
}

function demoEmailFallback() {
  return 'admin@wi-netra.health'
}