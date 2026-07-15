import { BadRequestException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common'
import crypto from 'node:crypto'
import { applicationDefault, initializeApp, getApps, type App as FirebaseApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getDatabase } from 'firebase-admin/database'

export type LoginRequest = {
  email: string
  password: string
}

export type UserMutationRequest = {
  email: string
  password: string
  name: string
  role: 'admin' | 'app_user'
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
    uid?: string
    email?: string
    password?: string
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

type DemoUserRecord = {
  uid: string
  email: string
  name: string
  role: 'admin' | 'app_user'
  password: string
  patients: string
  devices: string
  status: string
}

const demoUsersSeed: DemoUserRecord[] = [
  {
    uid: 'demo-anita',
    email: 'anita@wi-health.local',
    name: 'Anita Rao',
    role: 'app_user',
    password: 'demo-password',
    patients: '2 linked',
    devices: 'WH-2101, WH-2102',
    status: 'Active',
  },
  {
    uid: 'demo-mohan',
    email: 'mohan@wi-health.local',
    name: 'Mohan Iyer',
    role: 'app_user',
    password: 'demo-password',
    patients: '1 linked',
    devices: 'WH-2104',
    status: 'Active',
  },
  {
    uid: 'demo-admin',
    email: 'admin@wi-netra.health',
    name: 'Admin Ops',
    role: 'admin',
    password: 'demo-password',
    patients: '-',
    devices: 'All devices',
    status: 'Active',
  },
  {
    uid: 'demo-leela',
    email: 'leela@wi-health.local',
    name: 'Leela Das',
    role: 'app_user',
    password: 'demo-password',
    patients: '1 linked',
    devices: 'WH-2103',
    status: 'Pending verification',
  },
]

const demoDashboard: DashboardResponse = {
  stats: { monitoredPatients: 4 },
  fleetDevices: [
    { id: 'WH-2101', patient: 'Patient A', status: 'Online', health: 'Good', updated: '10s ago' },
    { id: 'WH-2102', patient: 'Patient B', status: 'Online', health: 'Good', updated: '16s ago' },
    { id: 'WH-2103', patient: 'Patient C', status: 'Offline', health: 'Needs check', updated: '8m ago' },
    { id: 'WH-2104', patient: 'Patient D', status: 'Online', health: 'Warning', updated: '35s ago' },
  ],
  users: [
    { uid: 'demo-anita', email: 'anita@wi-health.local', name: 'Anita Rao', role: 'App User', patients: '2 linked', devices: 'WH-2101, WH-2102', status: 'Active' },
    { uid: 'demo-mohan', email: 'mohan@wi-health.local', name: 'Mohan Iyer', role: 'App User', patients: '1 linked', devices: 'WH-2104', status: 'Active' },
    { uid: 'demo-admin', email: 'admin@wi-netra.health', name: 'Admin Ops', role: 'Admin', patients: '-', devices: 'All devices', status: 'Active' },
    { uid: 'demo-leela', email: 'leela@wi-health.local', name: 'Leela Das', role: 'App User', patients: '1 linked', devices: 'WH-2103', status: 'Pending verification' },
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
  private readonly demoUsers = new Map<string, DemoUserRecord>(demoUsersSeed.map((user) => [user.uid, user]))
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
      return this.buildDemoDashboard()
    }

    const realDashboard = await this.loadFirebaseDashboard().catch(() => this.buildDemoDashboard())
    return realDashboard
  }

  async listUsers(accessToken: string): Promise<DashboardResponse['users']> {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (!this.firebaseEnabled()) {
      return this.buildDemoDashboard().users
    }

    const dashboard = await this.loadFirebaseDashboard().catch(() => this.buildDemoDashboard())
    return dashboard.users
  }

  async createUser(accessToken: string, body: UserMutationRequest) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const email = body.email?.trim().toLowerCase()
    const password = body.password?.trim()
    const name = body.name?.trim()
    const role: 'admin' | 'app_user' = body.role === 'admin' ? 'admin' : 'app_user'

    if (!email || !name || !password) {
      throw new BadRequestException('Email, password, name, and role are required.')
    }

    const passwordError = this.validatePassword(password)
    if (passwordError) {
      throw new BadRequestException(passwordError)
    }

    if (this.firebaseEnabled()) {
      const firebaseApp = this.firebaseApp
      if (!firebaseApp) {
        throw new BadRequestException('Firebase is not configured.')
      }

      let authUser
      try {
        authUser = await getAuth(firebaseApp).createUser({
          email,
          password,
          displayName: name,
        })
      } catch (error) {
        throw new BadRequestException(this.normalizeAuthError(error))
      }

      await getDatabase(firebaseApp)
        .ref(`users/${authUser.uid}`)
        .set({
          profile: {
            name,
            email,
            createdAt: Date.now(),
          },
          role,
          devices: {},
          settings: {
            pushEnabled: true,
            urgentOnly: false,
            soundEnabled: true,
          },
        })

      await getAuth(firebaseApp).setCustomUserClaims(authUser.uid, { role }).catch(() => undefined)

      return this.formatDashboardUser({
        uid: authUser.uid,
        email,
        name,
        role,
        password,
        patients: role === 'admin' ? '-' : '0 linked',
        devices: role === 'admin' ? 'All devices' : '-',
        status: 'Active',
      })
    }

    const existing = Array.from(this.demoUsers.values()).find((user) => user.email === email)
    if (existing) {
      throw new BadRequestException('That email already exists.')
    }

    const user: DemoUserRecord = {
      uid: `demo-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      email,
      name,
      role,
      password,
      patients: role === 'admin' ? '-' : '0 linked',
      devices: role === 'admin' ? 'All devices' : '-',
      status: 'Active',
    }

    this.demoUsers.set(user.uid, user)
    return this.formatDashboardUser(user)
  }

  async updateUser(accessToken: string, uid: string, body: Partial<UserMutationRequest>) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const email = body.email?.trim().toLowerCase() || undefined
    const password = body.password?.trim() || undefined
    const name = body.name?.trim() || undefined
    const role = body.role === 'admin' ? 'admin' : body.role === 'app_user' ? 'app_user' : undefined

    if (!uid) {
      throw new BadRequestException('User id is required.')
    }

    if (password) {
      const passwordError = this.validatePassword(password)
      if (passwordError) {
        throw new BadRequestException(passwordError)
      }
    }

    if (this.firebaseEnabled()) {
      const firebaseApp = this.firebaseApp
      if (!firebaseApp) {
        throw new BadRequestException('Firebase is not configured.')
      }

      const auth = getAuth(firebaseApp)
      const db = getDatabase(firebaseApp)
      const current = await auth.getUser(uid).catch(() => null)
      if (!current) {
        throw new BadRequestException('User was not found.')
      }

      try {
        await auth.updateUser(uid, {
          email: email ?? current.email,
          displayName: name ?? current.displayName,
          password,
        })
      } catch (error) {
        throw new BadRequestException(this.normalizeAuthError(error))
      }

      const nextProfile = {
        profile: {
          name: name ?? current.displayName ?? current.email,
          email: email ?? current.email,
          createdAt: Date.now(),
        },
      }

      if (role) {
        await db.ref(`users/${uid}`).update({
          ...nextProfile,
          role,
        })
        await auth.setCustomUserClaims(uid, { role }).catch(() => undefined)
      } else {
        await db.ref(`users/${uid}`).update(nextProfile)
      }

      const nextRole = role ?? (String(current.customClaims?.role ?? 'app_user') === 'admin' ? 'admin' : 'app_user')

      return this.formatDashboardUser({
        uid,
        email: email ?? current.email ?? '',
        name: name ?? current.displayName ?? current.email ?? 'User',
        role: nextRole,
        password: password ?? '',
        patients: nextRole === 'admin' ? '-' : '0 linked',
        devices: nextRole === 'admin' ? 'All devices' : '-',
        status: 'Active',
      })
    }

    const existing = this.demoUsers.get(uid)
    if (!existing) {
      throw new BadRequestException('User was not found.')
    }

    const nextRole = role ?? existing.role

    const nextUser: DemoUserRecord = {
      ...existing,
      email: email ?? existing.email,
      name: name ?? existing.name,
      role: nextRole,
      password: password ?? existing.password,
      patients: nextRole === 'admin' ? '-' : existing.patients || '0 linked',
      devices: nextRole === 'admin' ? 'All devices' : existing.devices || '-',
    }

    this.demoUsers.set(uid, nextUser)
    return this.formatDashboardUser(nextUser)
  }

  async deleteUser(accessToken: string, uid: string) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (this.firebaseEnabled()) {
      const firebaseApp = this.firebaseApp
      if (!firebaseApp) {
        throw new BadRequestException('Firebase is not configured.')
      }

      await getAuth(firebaseApp).deleteUser(uid).catch(() => undefined)
      await getDatabase(firebaseApp).ref(`users/${uid}`).remove().catch(() => undefined)
      return { ok: true }
    }

    if (!this.demoUsers.has(uid)) {
      throw new BadRequestException('User was not found.')
    }

    this.demoUsers.delete(uid)
    return { ok: true }
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
    const claimRole = (decoded.role as string | undefined) ?? null

    // /users/$uid/role in RTDB is the operational source of truth — it's
    // what admins actually edit. The custom claim is a synced cache of it.
    // Consulting the DB on every verify means promotions AND demotions take
    // effect on the next request instead of waiting for (or surviving past)
    // a token refresh.
    const dbRole = await this.lookupDatabaseRole(decoded.uid)
    const role = dbRole ?? claimRole ?? 'app_user'

    if (role !== claimRole) {
      await getAuth(this.firebaseApp)
        .setCustomUserClaims(decoded.uid, { role })
        .catch(() => undefined)
    }

    if (role !== 'admin' && !this.adminEmailAllowlist.includes(email)) {
      throw new ForbiddenException('Admin role required.')
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

  private buildDemoDashboard(): DashboardResponse {
    const users = Array.from(this.demoUsers.values()).map((user) => this.formatDashboardUser(user))

    return {
      ...demoDashboard,
      stats: {
        monitoredPatients: users.filter((user) => user.role === 'App User').length,
      },
      users,
    }
  }

  private validatePassword(password: string) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters long.'
    }

    if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/\d/.test(password)) {
      return 'Password must include uppercase, lowercase, and a number.'
    }

    return ''
  }

  private normalizeAuthError(error: unknown) {
    if (error && typeof error === 'object' && 'code' in error) {
      const errorCode = String((error as { code?: string }).code ?? '')
      if (errorCode === 'auth/email-already-exists') {
        return 'The email address is already in use by another account.'
      }
      if (errorCode === 'auth/weak-password') {
        return 'Password must be at least 8 characters long and include uppercase, lowercase, and a number.'
      }
    }

    return 'Unable to update user account.'
  }

  private formatDashboardUser(user: DemoUserRecord) {
    return {
      uid: user.uid,
      email: user.email,
      password: user.password,
      name: user.name,
      role: user.role === 'admin' ? 'Admin' : 'App User',
      patients: user.patients,
      devices: user.devices,
      status: user.status,
    }
  }

  private async loadFirebaseDashboard(): Promise<DashboardResponse> {
    if (!this.firebaseApp) {
      return this.buildDemoDashboard()
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
      return this.buildDemoDashboard().users
    }

    const entries = Object.entries(rawUsers as Record<string, unknown>)
    return entries.map(([uid, value]) => {
      const user = (value as Record<string, unknown>) ?? {}
      const profile = (user.profile as Record<string, unknown>) ?? {}
      const role = String(user.role ?? 'app_user').toLowerCase() === 'admin' ? 'Admin' : 'App User'
      const deviceIds = Object.keys((user.devices as Record<string, unknown>) ?? {})

      return {
        uid,
        email: String(profile.email ?? uid),
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