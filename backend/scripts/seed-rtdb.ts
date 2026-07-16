// ============================================================
// RTDB SEED SCRIPT — THIS IS THE RTDB-SIDE CLEANUP HALF.
// Keep this script in sync with the SEED DATA warning comment in
// backend/src/app.service.ts. Once ESP32 hardware is writing to
// /devices, /alerts, and /complaints in the shared Firebase project,
// delete the SEED_DATA block and the firebaseEnabled() fallback
// branches in app.service.ts, then use this script's --clear flag
// to remove the seed payload from RTDB as part of the migration.
// ============================================================

import path from 'node:path'
import readline from 'node:readline/promises'
import { stdin as input, stdout as output } from 'node:process'
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app'
import { getDatabase } from 'firebase-admin/database'

const args = new Set(process.argv.slice(2))
const clearOnly = args.has('--clear')
const yes = args.has('--yes')

const databaseURL = process.env.FIREBASE_DATABASE_URL
const projectId = process.env.FIREBASE_PROJECT_ID ?? 'wi-health-faa5d'
const fallbackDatabaseURL = `https://${projectId}-default-rtdb.asia-southeast1.firebasedatabase.app`
const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS ?? path.resolve(__dirname, '../secrets/serviceAccount.json')

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialPath
}

const adminApp = getApps().length
  ? getApps()[0]
  : initializeApp({
      credential: applicationDefault(),
      databaseURL: databaseURL ?? fallbackDatabaseURL,
    })

const db = getDatabase(adminApp)

const seededDevices = {
  'seed-device-1': {
    meta: {
      model: 'esp32-s3',
      firmware: 'v0.4.2',
      room: 'ICU-01',
      patientName: 'Patient A',
      patientRelation: 'Lead Caregiver',
      normalLow: 12,
      normalHigh: 24,
      ownerUid: 'seed-user-1',
    },
    live: {
      bpm: 18.4,
      confidence: 0.94,
      signalQuality: 0.91,
      status: 'ok',
      updatedAt: 1715748650000,
    },
    sessions: {
      'seed-session-1': {
        startedAt: 1715748000000,
        endedAt: 1715748650000,
        avgBpm: 18.2,
        minBpm: 15,
        maxBpm: 21,
        validPct: 92,
      },
    },
    health: {
      online: true,
      lastSeen: 1715748650000,
    },
  },
  'seed-device-2': {
    meta: {
      model: 'esp32-s3',
      firmware: 'v0.4.2',
      room: 'ICU-02',
      patientName: 'Patient B',
      patientRelation: 'Family Member',
      normalLow: 11,
      normalHigh: 22,
      ownerUid: 'seed-user-2',
    },
    live: {
      bpm: 0,
      confidence: 0.0,
      signalQuality: 0.42,
      status: 'no_breathing',
      updatedAt: 1715748700000,
    },
    sessions: {
      'seed-session-1': {
        startedAt: 1715748300000,
        endedAt: 1715748700000,
        avgBpm: 0,
        minBpm: 0,
        maxBpm: 0,
        validPct: 0,
      },
    },
    health: {
      online: true,
      lastSeen: 1715748700000,
    },
  },
  'seed-device-3': {
    meta: {
      model: 'esp32-s3',
      firmware: 'v0.4.2',
      room: 'ICU-03',
      patientName: 'Patient C',
      patientRelation: 'Primary Contact',
      normalLow: 12,
      normalHigh: 26,
      ownerUid: 'seed-user-3',
    },
    live: {
      bpm: 9.6,
      confidence: 0.72,
      signalQuality: 0.63,
      status: 'low_signal',
      updatedAt: 1715748750000,
    },
    sessions: {
      'seed-session-1': {
        startedAt: 1715748400000,
        endedAt: 1715748750000,
        avgBpm: 10,
        minBpm: 8,
        maxBpm: 13,
        validPct: 68,
      },
    },
    health: {
      online: false,
      lastSeen: 1715748750000,
    },
  },
  'seed-device-4': {
    meta: {
      model: 'esp32-s3',
      firmware: 'v0.4.2',
      room: 'ICU-04',
      patientName: 'Patient D',
      patientRelation: 'Guardian',
      normalLow: 10,
      normalHigh: 20,
      ownerUid: 'seed-user-4',
    },
    live: {
      bpm: 23.1,
      confidence: 0.88,
      signalQuality: 0.89,
      status: 'ok',
      updatedAt: 1715748830000,
    },
    sessions: {
      'seed-session-1': {
        startedAt: 1715748500000,
        endedAt: 1715748830000,
        avgBpm: 22.5,
        minBpm: 20,
        maxBpm: 24,
        validPct: 89,
      },
    },
    health: {
      online: true,
      lastSeen: 1715748830000,
    },
  },
}

const seededAlerts = {
  'seed-device-1': {
    'seed-alert-1': {
      type: 'tachypnea',
      severity: 'urgent',
      summary: 'Elevated breathing rate detected for Patient A',
      detail: {
        device: 'seed-device-1',
        currentBpm: '18.4',
        threshold: '22 bpm',
      },
      raisedAt: 1715748650000,
      votes: '3/3',
      acknowledged: false,
      acknowledgedBy: null,
    },
  },
  'seed-device-2': {
    'seed-alert-2': {
      type: 'bradypnea',
      severity: 'info',
      summary: 'Breathing signal stopped for Patient B',
      detail: {
        device: 'seed-device-2',
        currentBpm: '0',
        status: 'no_breathing',
      },
      raisedAt: 1715748700000,
      votes: '2/3',
      acknowledged: true,
      acknowledgedBy: 'seed-admin-uid',
    },
  },
  'seed-device-3': {
    'seed-alert-3': {
      type: 'low_signal',
      severity: 'warning',
      summary: 'Signal quality dropped for Patient C',
      detail: {
        device: 'seed-device-3',
        signalQuality: '0.63',
        lastSeen: '1715748750000',
      },
      raisedAt: 1715748750000,
      votes: '1/3',
      acknowledged: false,
      acknowledgedBy: null,
    },
  },
  'seed-device-4': {
    'seed-alert-4': {
      type: 'apnea',
      severity: 'urgent',
      summary: 'Apnea trigger threshold exceeded for Patient D',
      detail: {
        device: 'seed-device-4',
        apneicSeconds: '21',
      },
      raisedAt: 1715748830000,
      votes: '3/3',
      acknowledged: true,
      acknowledgedBy: 'seed-admin-uid',
    },
  },
}

const seededComplaints = {
  'seed-complaint-1': {
    uid: 'seed-user-1',
    category: 'Alert accuracy',
    subject: 'Noisy alert on device seed-device-1',
    description: 'The device produced an urgent alert even though the patient is stable and moving normally.',
    status: 'open',
    adminResponse: null,
    createdAt: 1715748750000,
    updatedAt: 1715748750000,
  },
  'seed-complaint-2': {
    uid: 'seed-user-3',
    category: 'Device issue',
    subject: 'Offline period on seed-device-3',
    description: 'The device stayed offline for several minutes after the last session update.',
    status: 'in_progress',
    adminResponse: 'We are checking the last heartbeat and will update the owner shortly.',
    createdAt: 1715748800000,
    updatedAt: 1715748850000,
  },
  'seed-complaint-3': {
    uid: 'seed-user-4',
    category: 'App issue',
    subject: 'Delayed notifications for seed-device-4',
    description: 'The app pushed the alert after a delay and the user was not notified in time.',
    status: 'resolved',
    adminResponse: 'The notification queue is now back to normal.',
    createdAt: 1715748900000,
    updatedAt: 1715748950000,
  },
}

async function confirmOrAbort() {
  if (yes) {
    return
  }

  const rl = readline.createInterface({ input, output })
  const answer = await rl.question(
    'This will overwrite /devices, /alerts, /complaints in the REAL Firebase project. Continue? (Ctrl+C to abort, or pass --yes to skip this prompt) ',
  )
  rl.close()

  if (!/^y(es)?$/i.test(answer.trim())) {
    throw new Error('Seed aborted by user.')
  }
}

async function clearSeedRoots() {
  await Promise.all([
    db.ref('devices').remove(),
    db.ref('alerts').remove(),
    db.ref('complaints').remove(),
  ])
  console.log('Cleared /devices, /alerts, and /complaints in the connected Firebase RTDB.')
}

async function writeSeedData() {
  await Promise.all([
    db.ref('devices').set(seededDevices),
    db.ref('alerts').set(seededAlerts),
    db.ref('complaints').set(seededComplaints),
  ])

  console.log('Seeded /devices, /alerts, /complaints with deterministic placeholder data.')
}

async function main() {
  if (clearOnly) {
    await confirmOrAbort()
    await clearSeedRoots()
    return
  }

  await confirmOrAbort()
  await writeSeedData()
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
