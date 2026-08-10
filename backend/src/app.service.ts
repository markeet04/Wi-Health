import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  InternalServerErrorException,
  Logger,
  UnauthorizedException,
  type OnModuleInit,
} from '@nestjs/common'
import crypto from 'node:crypto'
import { applicationDefault, cert, initializeApp, getApps, type App as FirebaseApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getDatabase } from 'firebase-admin/database'
import { getMessaging } from 'firebase-admin/messaging'

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

export type DeviceAssignRequest = {
  uid: string
  patientName?: string
  patientRelation?: string
  room?: string
  normalLow?: number
  normalHigh?: number
  // When set, this assignment fulfils a device request — its status is marked
  // 'fulfilled' (with the assigned device id) as part of the same operation.
  requestId?: string
}

type AdminDeviceRecord = {
  id: string
  ownerUid: string
  patientName: string
  patientRelation: string
  room: string
  normalLow: number
  normalHigh: number
  status: string
  updated: string
}

type AdminAppUser = {
  uid: string
  email: string
  name: string
}

type AdminDeviceRequest = {
  id: string
  uid: string
  userName: string
  userEmail: string
  patientName: string
  patientRelation: string
  room: string
  status: string
  createdAt: number
}

type AdminDevicesResponse = {
  devices: AdminDeviceRecord[]
  appUsers: AdminAppUser[]
  requests: AdminDeviceRequest[]
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
  // Long-lived refresh token (Firebase). Sent to the panel so it can obtain a
  // fresh ID token when the ~1h one expires, instead of forcing a re-login.
  // Absent in demo mode.
  refreshToken?: string
  source: 'firebase' | 'demo'
  user: AdminUser
}

type ComplaintMessage = {
  id: string
  senderUid: string
  senderRole: 'app_user' | 'admin'
  text: string
  sentAt: number
}

type DashboardComplaint = {
  id: string
  user: string
  patient: string
  issue: string
  status: string
  submitted: string
  category?: string
  subject?: string
  description?: string
  uid?: string
  createdAt?: number
  updatedAt?: number
  messages?: ComplaintMessage[]
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
  complaints: DashboardComplaint[]
}

// Only settings the apps actually consume. Landing Page picks the admin's
// initial screen; Refresh Interval drives the live-data poll. Anything nothing
// read (device alert thresholds live on the ESP32, invite/verification/reset
// were never wired) was removed so saving a setting always has a real effect.
export type AdminSettingsResponse = {
  refreshIntervalSeconds: number
  landingPagePreference: string
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

// ============================================================
// SEED DATA — REMOVE ONCE ESP32 HARDWARE INTEGRATION IS LIVE.
// This is the ONLY fallback data in the backend. Once real
// devices are writing to /devices, /alerts, /complaints in
// RTDB (see shared/contracts/device-live-schema.json), delete
// this entire block and the firebaseEnabled() fallback branches
// that reference it in getDashboard()/getSettings(), then
// getDashboard() should throw or return empty state instead of
// silently substituting demo data.
// ============================================================
export const SEED_DATA = {
  users: [
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
  ] as DemoUserRecord[],
  dashboard: {
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
  } satisfies DashboardResponse,
  settings: {
    refreshIntervalSeconds: 5,
    landingPagePreference: 'Statistics / Analytics',
  } satisfies AdminSettingsResponse,
}

@Injectable()
export class AppService implements OnModuleInit {
  private readonly logger = new Logger(AppService.name)
  private readonly sessions = new Map<string, AdminSession>()
  private readonly firebaseApp = this.initFirebaseApp()
  private readonly demoUsers = new Map<string, DemoUserRecord>(SEED_DATA.users.map((user) => [user.uid, user]))
  private readonly demoDeviceMeta = new Map<string, Omit<AdminDeviceRecord, 'id' | 'status' | 'updated'>>(
    SEED_DATA.dashboard.fleetDevices.map((device) => {
      const owner = SEED_DATA.users.find((user) =>
        user.devices.split(',').map((id) => id.trim()).includes(device.id),
      )
      return [
        device.id,
        {
          ownerUid: owner?.uid ?? '',
          patientName: device.patient,
          patientRelation: 'self',
          room: 'Bedroom',
          normalLow: 8,
          normalHigh: 30,
        },
      ]
    }),
  )
  private readonly demoSettings: AdminSettingsResponse = this.cloneSettings(SEED_DATA.settings)
  private readonly demoEmail = process.env.ADMIN_DEMO_EMAIL ?? demoSession.user.email
  private readonly demoPassword = process.env.ADMIN_DEMO_PASSWORD ?? 'demo-password'
  private readonly adminEmailAllowlist = (process.env.ADMIN_EMAIL_ALLOWLIST ?? this.demoEmail)
    .split(',')
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean)

  onModuleInit() {
    if (this.firebaseEnabled()) {
      this.watchAlertsForPush()
    }
  }

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

    try {
      return await this.loadFirebaseDashboard()
    } catch (error) {
      throw new InternalServerErrorException(
        error instanceof Error ? error.message : 'Unable to load dashboard from Firebase.',
      )
    }
  }

  async getSettings(accessToken: string): Promise<AdminSettingsResponse> {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (!this.firebaseEnabled()) {
      return this.buildDemoSettings()
    }

    try {
      return await this.loadFirebaseSettings()
    } catch (error) {
      throw new InternalServerErrorException(
        error instanceof Error ? error.message : 'Unable to load settings from Firebase.',
      )
    }
  }

  async updateSettings(accessToken: string, body: Partial<AdminSettingsResponse>) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const nextSettings = this.normalizeSettings(body)

    if (!this.firebaseEnabled()) {
      this.demoSettings.refreshIntervalSeconds = nextSettings.refreshIntervalSeconds
      this.demoSettings.landingPagePreference = nextSettings.landingPagePreference
      return this.buildDemoSettings()
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    await getDatabase(firebaseApp).ref('settings').set(nextSettings)
    return nextSettings
  }

  async listUsers(accessToken: string): Promise<DashboardResponse['users']> {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (!this.firebaseEnabled()) {
      return this.buildDemoDashboard().users
    }

    try {
      const dashboard = await this.loadFirebaseDashboard()
      return dashboard.users
    } catch (error) {
      throw new InternalServerErrorException(
        error instanceof Error ? error.message : 'Unable to load users from Firebase.',
      )
    }
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

  async sendComplaintMessage(accessToken: string, complaintId: string, body: { text?: string }) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const text = body.text?.trim()
    if (!complaintId || !text) {
      throw new BadRequestException('Complaint id and message text are required.')
    }

    if (!this.firebaseEnabled()) {
      return { ok: true, complaintId }
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    const messageRef = getDatabase(firebaseApp).ref(`complaints/${complaintId}/messages`).push()
    await messageRef.set({
      senderUid: session.user.uid,
      senderRole: 'admin',
      text,
      sentAt: Date.now(),
    })

    await getDatabase(firebaseApp).ref(`complaints/${complaintId}`).update({
      status: 'in_progress',
      updatedAt: Date.now(),
    })

    const complaintSnapshot = await getDatabase(firebaseApp).ref(`complaints/${complaintId}`).get()
    const complaintData = complaintSnapshot.val() as Record<string, unknown> | null
    const ownerUid = complaintData?.uid as string | undefined

    if (ownerUid) {
      const tokensSnapshot = await getDatabase(firebaseApp).ref(`users/${ownerUid}/fcmTokens`).get()
      const tokens = tokensSnapshot.val() as Record<string, unknown> | null
      const tokenList = Object.keys(tokens ?? {})
      if (tokenList.length > 0) {
        await getMessaging(firebaseApp).sendEachForMulticast({
          tokens: tokenList,
          notification: {
            title: 'Support replied',
            body: text,
          },
          data: {
            complaintId,
            type: 'complaint_reply',
          },
        })
      }
    }

    return { ok: true, complaintId }
  }

  async resolveComplaint(accessToken: string, complaintId: string) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (!complaintId) {
      throw new BadRequestException('Complaint id is required.')
    }

    if (!this.firebaseEnabled()) {
      return { ok: true, complaintId }
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    await getDatabase(firebaseApp).ref(`complaints/${complaintId}`).update({
      status: 'resolved',
      updatedAt: Date.now(),
    })

    return { ok: true, complaintId }
  }

  /**
   * Module 4 device provisioning: mint a long-lived Firebase custom token for
   * an ESP32 sensor. uid = deviceId, claim device=true — this is exactly what
   * cloud/database.rules.json requires to write /devices/$deviceId/live
   * (auth.uid === $deviceId && auth.token.device === true).
   *
   * The token is flashed to / configured on the uploader board; it exchanges
   * it for an ID token (signInWithCustomToken) and then writes breathing
   * results to RTDB. Admin-only. Also seeds a minimal /devices/$id/meta so the
   * device is a registered entity (admins later fill in room/patient/owner).
   */
  async mintDeviceToken(accessToken: string, deviceId: string) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const id = (deviceId ?? '').trim()
    if (!id || !/^[A-Za-z0-9_-]{3,128}$/.test(id)) {
      throw new BadRequestException('Valid deviceId required (3-128 chars: A-Z a-z 0-9 _ -).')
    }

    if (!this.firebaseEnabled()) {
      // demo mode: no real token, but report the intended shape
      return { ok: true, deviceId: id, token: null, mode: 'demo' as const }
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    // Mint the custom token with the device claim.
    const token = await getAuth(firebaseApp).createCustomToken(id, { device: true })

    // Register a minimal device meta if none exists (admin fills the rest later).
    const metaRef = getDatabase(firebaseApp).ref(`devices/${id}/meta`)
    const snap = await metaRef.get()
    if (!snap.exists()) {
      await metaRef.set({
        model: 'esp32-s3',
        firmware: 'dsp_live',
        room: '',
        patientName: '',
        patientRelation: '',
        normalLow: 8,
        normalHigh: 30,
        ownerUid: '',
        provisionedAt: Date.now(),
      })
    }

    return { ok: true, deviceId: id, token, mode: 'firebase' as const }
  }

  /**
   * Module 8: device -> patient -> App User assignment. Mirrors
   * backend/scripts/link-device.mjs but admin-authed and callable from the
   * panel. Two writes: /users/$uid/devices/$deviceId=true (patient switcher)
   * and /devices/$deviceId/meta (patient label + thresholds). If the device
   * was previously linked to a different account, that stale link is removed
   * so a device never appears under two owners at once.
   */
  async assignDevice(accessToken: string, deviceId: string, body: DeviceAssignRequest) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const id = (deviceId ?? '').trim()
    if (!id) {
      throw new BadRequestException('deviceId is required.')
    }

    const uid = body.uid?.trim()
    if (!uid) {
      throw new BadRequestException('uid is required.')
    }

    const patientName = body.patientName?.trim() || 'Patient'
    const patientRelation = body.patientRelation?.trim() || 'self'
    const room = body.room?.trim() || ''
    const normalLow = Number(body.normalLow ?? 8)
    const normalHigh = Number(body.normalHigh ?? 30)

    if (!Number.isFinite(normalLow) || normalLow <= 0) {
      throw new BadRequestException('normalLow must be a positive number.')
    }
    if (!Number.isFinite(normalHigh) || normalHigh > 60 || normalHigh <= normalLow) {
      throw new BadRequestException('normalHigh must be greater than normalLow and at most 60.')
    }

    if (!this.firebaseEnabled()) {
      const targetUser = this.demoUsers.get(uid)
      if (!targetUser) {
        throw new BadRequestException('Target user was not found.')
      }
      if (targetUser.role !== 'app_user') {
        throw new BadRequestException('Devices can only be assigned to App User accounts.')
      }

      const previous = this.demoDeviceMeta.get(id)
      if (previous?.ownerUid && previous.ownerUid !== uid) {
        this.detachDemoDeviceFromOwner(id, previous.ownerUid)
      }

      this.demoDeviceMeta.set(id, { ownerUid: uid, patientName, patientRelation, room, normalLow, normalHigh })
      this.attachDemoDeviceToOwner(id, uid)

      return { ok: true, deviceId: id, ownerUid: uid }
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    const auth = getAuth(firebaseApp)
    const db = getDatabase(firebaseApp)

    const targetUser = await auth.getUser(uid).catch(() => null)
    if (!targetUser) {
      throw new BadRequestException('Target user was not found.')
    }

    const metaSnap = await db.ref(`devices/${id}/meta`).get()
    const previousOwnerUid = metaSnap.exists() ? String((metaSnap.val() as Record<string, unknown>).ownerUid ?? '') : ''

    if (previousOwnerUid && previousOwnerUid !== uid) {
      await db.ref(`users/${previousOwnerUid}/devices/${id}`).remove().catch(() => undefined)
    }

    await db.ref(`users/${uid}/devices/${id}`).set(true)
    await db.ref(`devices/${id}/meta`).update({
      ownerUid: uid,
      patientName,
      patientRelation,
      room,
      normalLow,
      normalHigh,
    })

    // If this assignment fulfils a request, close it out.
    const requestId = body.requestId?.trim()
    if (requestId) {
      await db.ref(`deviceRequests/${requestId}`).update({
        status: 'fulfilled',
        fulfilledDeviceId: id,
      }).catch(() => undefined)
    }

    return { ok: true, deviceId: id, ownerUid: uid }
  }

  async declineDeviceRequest(accessToken: string, requestId: string) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }
    const id = (requestId ?? '').trim()
    if (!id) {
      throw new BadRequestException('requestId is required.')
    }
    if (!this.firebaseEnabled()) {
      return { ok: true, requestId: id, mode: 'demo' as const }
    }
    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }
    await getDatabase(firebaseApp).ref(`deviceRequests/${id}`).update({ status: 'declined' })
    return { ok: true, requestId: id }
  }

  async unassignDevice(accessToken: string, deviceId: string) {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    const id = (deviceId ?? '').trim()
    if (!id) {
      throw new BadRequestException('deviceId is required.')
    }

    if (!this.firebaseEnabled()) {
      const previous = this.demoDeviceMeta.get(id)
      if (previous?.ownerUid) {
        this.detachDemoDeviceFromOwner(id, previous.ownerUid)
      }
      this.demoDeviceMeta.set(id, { ownerUid: '', patientName: '', patientRelation: '', room: '', normalLow: 8, normalHigh: 30 })
      return { ok: true, deviceId: id }
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    const db = getDatabase(firebaseApp)
    const metaSnap = await db.ref(`devices/${id}/meta`).get()
    const ownerUid = metaSnap.exists() ? String((metaSnap.val() as Record<string, unknown>).ownerUid ?? '') : ''

    if (ownerUid) {
      await db.ref(`users/${ownerUid}/devices/${id}`).remove().catch(() => undefined)
    }
    await db.ref(`devices/${id}/meta`).update({ ownerUid: '', patientName: '', patientRelation: '', room: '' })

    return { ok: true, deviceId: id }
  }

  async listDevices(accessToken: string): Promise<AdminDevicesResponse> {
    const session = await this.restoreSession(accessToken)
    if (session.user.role !== 'admin') {
      throw new ForbiddenException('Admin access required.')
    }

    if (!this.firebaseEnabled()) {
      const fleetById = new Map(SEED_DATA.dashboard.fleetDevices.map((device) => [device.id, device]))
      const devices: AdminDeviceRecord[] = Array.from(this.demoDeviceMeta.entries()).map(([id, meta]) => ({
        id,
        ...meta,
        status: fleetById.get(id)?.status ?? 'Offline',
        updated: fleetById.get(id)?.updated ?? 'unknown',
      }))
      const appUsers: AdminAppUser[] = Array.from(this.demoUsers.values())
        .filter((user) => user.role === 'app_user')
        .map((user) => ({ uid: user.uid, email: user.email, name: user.name }))

      return { devices, appUsers, requests: [] }
    }

    const firebaseApp = this.firebaseApp
    if (!firebaseApp) {
      throw new BadRequestException('Firebase is not configured.')
    }

    const db = getDatabase(firebaseApp)
    const [devicesSnap, usersSnap, requestsSnap] = await Promise.all([
      db.ref('devices').get(),
      db.ref('users').get(),
      db.ref('deviceRequests').get(),
    ])

    const users = this.normalizeUsers(usersSnap.val())
    const appUsers: AdminAppUser[] = users
      .filter((user) => user.role === 'App User')
      .map((user) => ({ uid: user.uid ?? '', email: user.email ?? '', name: user.name }))
    const usersByUid = new Map(users.map((u) => [u.uid ?? '', u]))

    const rawRequests = (requestsSnap.val() as Record<string, unknown>) ?? {}
    const requests: AdminDeviceRequest[] = Object.entries(rawRequests)
      .map(([id, value]) => {
        const r = (value as Record<string, unknown>) ?? {}
        const uid = String(r.uid ?? '')
        const user = usersByUid.get(uid)
        return {
          id,
          uid,
          userName: user?.name ?? uid,
          userEmail: user?.email ?? '',
          patientName: String(r.patientName ?? ''),
          patientRelation: String(r.patientRelation ?? ''),
          room: String(r.room ?? ''),
          status: String(r.status ?? 'pending'),
          createdAt: Number(r.createdAt ?? 0),
        }
      })
      .filter((r) => r.status === 'pending')
      .sort((a, b) => b.createdAt - a.createdAt)

    const rawDevices = (devicesSnap.val() as Record<string, unknown>) ?? {}
    const devices: AdminDeviceRecord[] = Object.entries(rawDevices).map(([deviceId, value]) => {
      const device = (value as Record<string, unknown>) ?? {}
      const meta = (device.meta as Record<string, unknown>) ?? {}
      const live = (device.live as Record<string, unknown>) ?? {}

      return {
        id: deviceId,
        ownerUid: String(meta.ownerUid ?? ''),
        patientName: String(meta.patientName ?? ''),
        patientRelation: String(meta.patientRelation ?? ''),
        room: String(meta.room ?? ''),
        normalLow: Number(meta.normalLow ?? 8),
        normalHigh: Number(meta.normalHigh ?? 30),
        status: String(live.status ?? 'offline').toLowerCase() === 'ok' ? 'Online' : 'Offline',
        updated: this.formatAge(live.updatedAt),
      }
    })

    return { devices, appUsers, requests }
  }

  private attachDemoDeviceToOwner(deviceId: string, uid: string) {
    const user = this.demoUsers.get(uid)
    if (!user) return
    const ids = new Set(user.devices.split(',').map((value) => value.trim()).filter(Boolean))
    ids.add(deviceId)
    user.devices = Array.from(ids).join(', ')
    user.patients = `${ids.size} linked`
  }

  private detachDemoDeviceFromOwner(deviceId: string, uid: string) {
    const user = this.demoUsers.get(uid)
    if (!user) return
    const ids = new Set(user.devices.split(',').map((value) => value.trim()).filter(Boolean))
    ids.delete(deviceId)
    user.devices = ids.size ? Array.from(ids).join(', ') : '-'
    user.patients = `${ids.size} linked`
  }

  /**
   * Module 7: push the phone when an anomaly fires while the app is
   * backgrounded/closed. In-app alert delivery (live RTDB listener in the
   * mobile app) already works and is untouched by this — this is purely the
   * privileged FCM send, which only the Admin SDK can do.
   *
   * Firebase's child_added listener replays every EXISTING child once at
   * attach time and then fires again for each new one — so attaching to
   * `alerts` picks up every device (present and future) with one listener,
   * and attaching to `alerts/$deviceId` the same way picks up every alert.
   * The replay-on-attach behavior also means a backend restart would resend
   * every historical alert, so each alert is marked `notifiedAt` after its
   * push goes out and already-marked alerts are skipped — this also means a
   * missed push (backend down when the alert fired) is sent once the backend
   * comes back up instead of being silently dropped.
   */
  private watchAlertsForPush() {
    const firebaseApp = this.firebaseApp
    if (!firebaseApp) return

    const db = getDatabase(firebaseApp)
    const watchedDevices = new Set<string>()

    db.ref('alerts').on('child_added', (deviceSnapshot) => {
      const deviceId = deviceSnapshot.key
      if (!deviceId || watchedDevices.has(deviceId)) return
      watchedDevices.add(deviceId)

      db.ref(`alerts/${deviceId}`).on('child_added', async (alertSnapshot) => {
        const alertId = alertSnapshot.key
        const alert = alertSnapshot.val() as Record<string, unknown> | null
        if (!alertId || !alert || alert.notifiedAt) return

        try {
          await this.sendAlertPush(deviceId, alertId, alert)
        } catch (error) {
          this.logger.error(`Failed to send alert push for ${deviceId}/${alertId}`, error instanceof Error ? error.stack : String(error))
        } finally {
          await db.ref(`alerts/${deviceId}/${alertId}/notifiedAt`).set(Date.now()).catch(() => undefined)
        }
      })
    })
  }

  private async sendAlertPush(deviceId: string, alertId: string, alert: Record<string, unknown>) {
    const firebaseApp = this.firebaseApp
    if (!firebaseApp) return

    const db = getDatabase(firebaseApp)
    const metaSnapshot = await db.ref(`devices/${deviceId}/meta`).get()
    const meta = (metaSnapshot.val() as Record<string, unknown>) ?? {}
    const ownerUid = String(meta.ownerUid ?? '')
    if (!ownerUid) return

    const type = String(alert.type ?? 'alert')
    const severity = String(alert.severity ?? 'info')

    // Respect the owner's notification preferences (set in the mobile Settings
    // screen, stored at users/$uid/settings). Push off -> send nothing; urgent
    // only -> drop non-urgent alerts. Missing settings default to allow.
    const settingsSnapshot = await db.ref(`users/${ownerUid}/settings`).get()
    const ownerSettings = (settingsSnapshot.val() as Record<string, unknown>) ?? {}
    if (ownerSettings.pushEnabled === false) return
    if (ownerSettings.urgentOnly === true && severity !== 'urgent') return

    const tokensSnapshot = await db.ref(`users/${ownerUid}/fcmTokens`).get()
    const tokens = Object.keys((tokensSnapshot.val() as Record<string, unknown>) ?? {})
    if (tokens.length === 0) return

    const patientName = String(meta.patientName ?? deviceId)
    const summary = String(alert.summary ?? '')
    const title = `${patientName}: ${this.humanizeAlertType(type)}`
    const body = summary || `${severity === 'urgent' ? 'Urgent' : 'Anomaly'} detected on ${deviceId}.`

    // Respect the owner's "Alert sound" toggle (Settings). Default on.
    const soundOn = ownerSettings.soundEnabled !== false

    const response = await getMessaging(firebaseApp).sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: 'alert',
        alertId,
        patientId: deviceId,
        deviceId,
        severity,
      },
      android: {
        priority: severity === 'urgent' ? 'high' : 'normal',
        notification: {
          sound: soundOn ? 'default' : undefined,
        },
      },
    })

    const deadTokens = response.responses
      .map((result, index) => (!result.success && this.isDeadFcmTokenError(result.error) ? tokens[index] : null))
      .filter((token): token is string => Boolean(token))

    if (deadTokens.length > 0) {
      await Promise.all(
        deadTokens.map((token) => db.ref(`users/${ownerUid}/fcmTokens/${token}`).remove().catch(() => undefined)),
      )
    }
  }

  private isDeadFcmTokenError(error: unknown) {
    const code = (error as { code?: string } | undefined)?.code ?? ''
    return code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token'
  }

  private humanizeAlertType(type: string) {
    return type
      .split('_')
      .map((part) => (part ? part[0].toUpperCase() + part.slice(1) : part))
      .join(' ')
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
      // Railway (and other PaaS hosts) have no local service-account file to
      // point GOOGLE_APPLICATION_CREDENTIALS at — the key is injected as an
      // env var instead. Local dev keeps using the gitignored file via
      // applicationDefault().
      const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      const credential = serviceAccountJson ? cert(JSON.parse(serviceAccountJson)) : applicationDefault()

      return initializeApp(
        {
          credential,
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
      refreshToken?: string
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
      refreshToken: payload.refreshToken,
      source: 'firebase',
      user: {
        uid: payload.localId,
        name: payload.displayName ?? user.name,
        email: payload.email ?? email,
        role: 'admin',
      },
    }
  }

  /**
   * Exchange a Firebase refresh token for a fresh admin session (new ID token).
   * Used by the panel when its ID token expires (~1h) so the admin stays signed
   * in. Verifies the fresh token still carries the admin role.
   */
  async refreshSession(refreshToken: string): Promise<AdminSession> {
    if (!this.firebaseEnabled()) {
      // Demo mode has no real tokens; just return the demo session.
      return demoSession
    }
    const token = (refreshToken ?? '').trim()
    if (!token) {
      throw new UnauthorizedException('Refresh token is required.')
    }
    const apiKey = process.env.FIREBASE_WEB_API_KEY
    if (!apiKey) {
      throw new UnauthorizedException('Firebase API key is not configured.')
    }

    const response = await fetch(
      `https://securetoken.googleapis.com/v1/token?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(token)}`,
      },
    )

    const payload = (await response.json().catch(() => ({}))) as {
      id_token?: string
      refresh_token?: string
      error?: { message?: string } | string
    }

    if (!response.ok || !payload.id_token) {
      throw new UnauthorizedException('Session refresh failed. Please sign in again.')
    }

    const user = await this.verifyFirebaseToken(payload.id_token)
    if (user.role !== 'admin') {
      throw new ForbiddenException('Admin role required.')
    }

    return {
      accessToken: payload.id_token,
      refreshToken: payload.refresh_token ?? token,
      source: 'firebase',
      user,
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
      ...this.cloneSettings(SEED_DATA.dashboard as DashboardResponse),
      stats: {
        monitoredPatients: users.filter((user) => user.role === 'App User').length,
      },
      users,
    }
  }

  private buildDemoSettings(): AdminSettingsResponse {
    return this.cloneSettings(this.demoSettings)
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

  private async loadFirebaseSettings(): Promise<AdminSettingsResponse> {
    if (!this.firebaseApp) {
      return this.buildDemoSettings()
    }

    const rawSettings = await getDatabase(this.firebaseApp).ref('settings').get().catch(() => null)
    return this.normalizeSettings(rawSettings?.val())
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
    const alertRecords = this.normalizeAlerts(alertsSnap.val(), userRecords, devicesSnap.val())
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

  private normalizeSettings(rawSettings: unknown): AdminSettingsResponse {
    const fallback = this.buildDemoSettings()
    if (!rawSettings || typeof rawSettings !== 'object') {
      return fallback
    }

    const settings = rawSettings as Record<string, unknown>

    return {
      refreshIntervalSeconds: Number(settings.refreshIntervalSeconds ?? fallback.refreshIntervalSeconds),
      landingPagePreference: String(settings.landingPagePreference ?? fallback.landingPagePreference),
    }
  }

  private normalizeUsers(rawUsers: unknown) {
    if (!rawUsers || typeof rawUsers !== 'object') {
      return [] as DashboardResponse['users']
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
      return [] as DashboardResponse['fleetDevices']
    }

    return Object.entries(rawDevices as Record<string, unknown>).map(([deviceId, value]) => {
      const device = (value as Record<string, unknown>) ?? {}
      const meta = (device.meta as Record<string, unknown>) ?? {}
      const live = (device.live as Record<string, unknown>) ?? {}
      const ownerUid = String(meta.ownerUid ?? '')
      const linkedUser = users.find((user) => user.devices.includes(deviceId)) ?? users.find((user) => user.uid === ownerUid)

      return {
        id: deviceId,
        patient: String(meta.patientName ?? linkedUser?.name ?? 'Unassigned'),
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

  private normalizeAlerts(rawAlerts: unknown, users: DashboardResponse['users'], rawDevices?: unknown) {
    if (!rawAlerts || typeof rawAlerts !== 'object') {
      return [] as DashboardResponse['alerts']
    }

    const devicesById = new Map<string, { ownerUid?: string; patientName?: string }>()
    if (rawDevices && typeof rawDevices === 'object') {
      for (const [deviceId, value] of Object.entries(rawDevices as Record<string, unknown>)) {
        const device = (value as Record<string, unknown>) ?? {}
        const meta = (device.meta as Record<string, unknown>) ?? {}
        devicesById.set(deviceId, {
          ownerUid: String(meta.ownerUid ?? ''),
          patientName: String(meta.patientName ?? ''),
        })
      }
    }

    const alerts: DashboardResponse['alerts'] = []
    for (const [deviceId, deviceAlerts] of Object.entries(rawAlerts as Record<string, unknown>)) {
      if (!deviceAlerts || typeof deviceAlerts !== 'object') continue

      const linkedUser =
        users.find((user) => user.devices.includes(deviceId)) ??
        users.find((user) => user.uid === devicesById.get(deviceId)?.ownerUid)
      const deviceMeta = devicesById.get(deviceId)
      for (const [alertId, value] of Object.entries(deviceAlerts as Record<string, unknown>)) {
        const alert = (value as Record<string, unknown>) ?? {}
        alerts.push({
          time: this.formatTimestamp(alert.raisedAt ?? alert.createdAt ?? alert.updatedAt),
          patient: String(deviceMeta?.patientName ?? linkedUser?.name ?? 'Unknown'),
          device: deviceId,
          anomaly: String(alert.type ?? alert.anomaly ?? alertId),
          severity: String(alert.severity ?? 'Info').replace(/^./, (char) => char.toUpperCase()),
          status: String(alert.status ?? (alert.acknowledged ? 'Acknowledged' : 'Open')).replace(/^./, (char) => char.toUpperCase()),
        })
      }
    }

    return alerts.length ? alerts : [] as DashboardResponse['alerts']
  }

  private normalizeComplaints(rawComplaints: unknown, users: DashboardResponse['users']) {
    if (!rawComplaints || typeof rawComplaints !== 'object') {
      return [] as DashboardResponse['complaints']
    }

    return Object.entries(rawComplaints as Record<string, unknown>).map(([complaintId, value]) => {
      const complaint = (value as Record<string, unknown>) ?? {}
      const linkedUser = users.find((user) => user.uid === String(complaint.uid ?? ''))
      const createdAt = typeof complaint.createdAt === 'number' ? complaint.createdAt : undefined
      const updatedAt = typeof complaint.updatedAt === 'number' ? complaint.updatedAt : createdAt
      return {
        id: complaintId,
        user: String(complaint.user ?? linkedUser?.name ?? complaint.uid ?? 'Unknown'),
        patient: String(complaint.patient ?? linkedUser?.name ?? 'Unknown'),
        issue: String(complaint.issue ?? complaint.subject ?? complaint.message ?? 'No details provided'),
        status: this.prettyStatus(String(complaint.status ?? 'open')),
        submitted: this.formatTimestamp(createdAt ?? complaint.submittedAt),
        category: String(complaint.category ?? 'Other'),
        subject: String(complaint.subject ?? complaint.issue ?? 'No subject'),
        description: String(complaint.description ?? complaint.issue ?? 'No details provided'),
        uid: typeof complaint.uid === 'string' ? complaint.uid : '',
        createdAt,
        updatedAt,
        messages: this.normalizeComplaintMessages(complaint.messages),
      }
    })
  }

  private normalizeComplaintMessages(rawMessages: unknown): ComplaintMessage[] {
    if (!rawMessages || typeof rawMessages !== 'object') {
      return []
    }

    return Object.entries(rawMessages as Record<string, unknown>)
      .map(([messageId, value]) => {
        const message = (value as Record<string, unknown>) ?? {}
        const sentAt = typeof message.sentAt === 'number' ? message.sentAt : 0
        return {
          id: messageId,
          senderUid: String(message.senderUid ?? ''),
          senderRole: message.senderRole === 'admin' ? 'admin' : 'app_user',
          text: String(message.text ?? ''),
          sentAt,
        } satisfies ComplaintMessage
      })
      .filter((message) => message.text.trim().length > 0)
      .sort((left, right) => left.sentAt - right.sentAt)
  }

  private cloneSettings<T>(value: T): T {
    return JSON.parse(JSON.stringify(value))
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