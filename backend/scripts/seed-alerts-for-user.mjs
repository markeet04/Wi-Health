/* seed-alerts-for-user.mjs — push a handful of fresh, undismissed test alerts
 * onto every device linked to a given account, so the mobile app's Alert Feed
 * has something to show/dismiss during testing. Adds new alert nodes only —
 * never touches or clears existing alerts.
 *
 * Usage:
 *   node scripts/seed-alerts-for-user.mjs <userEmail> [count]
 *   e.g. node scripts/seed-alerts-for-user.mjs qaimmaajid@gmail.com 5
 */
import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getDatabase } from 'firebase-admin/database'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

try {
  const here = dirname(fileURLToPath(import.meta.url))
  const t = readFileSync(resolve(here, '..', '.env'), 'utf8')
  for (const l of t.split(/\r?\n/)) { const m = l.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/); if (m) { let v = m[2].replace(/^["']|["']$/g, ''); if (process.env[m[1]] === undefined) process.env[m[1]] = v } }
} catch {}

const email = process.argv[2]
const count = Number(process.argv[3]) || 5
if (!email) { console.error('usage: node scripts/seed-alerts-for-user.mjs <userEmail> [count]'); process.exit(1) }

const pid = process.env.FIREBASE_PROJECT_ID || 'wi-health-faa5d'
const app = getApps()[0] || initializeApp({ credential: applicationDefault(), projectId: pid, databaseURL: process.env.FIREBASE_DATABASE_URL || `https://${pid}-default-rtdb.asia-southeast1.firebasedatabase.app` })

const user = await getAuth(app).getUserByEmail(email)
const uid = user.uid
console.log(`user: ${email} -> uid ${uid}`)

const db = getDatabase(app)
const devicesSnap = await db.ref(`users/${uid}/devices`).get()
const deviceIds = devicesSnap.exists() ? Object.keys(devicesSnap.val()) : []
if (deviceIds.length === 0) {
  console.error(`no devices linked to ${email}; link one first with scripts/link-device.mjs`)
  process.exit(1)
}

// Rotating set of realistic alert templates, one severity/type per index.
const templates = [
  {
    type: 'apnea',
    severity: 'urgent',
    summary: 'No valid breathing detected (possible apnea).',
    detail: (deviceId) => ({ device: deviceId, currentBpm: '0', threshold: '10 bpm' }),
  },
  {
    type: 'tachypnea',
    severity: 'urgent',
    summary: 'Elevated breathing rate detected.',
    detail: (deviceId) => ({ device: deviceId, currentBpm: '27.5', threshold: '24 bpm' }),
  },
  {
    type: 'bradypnea',
    severity: 'warning',
    summary: 'Breathing rate below normal range (bradypnea).',
    detail: (deviceId) => ({ device: deviceId, currentBpm: '7.2', threshold: '10 bpm' }),
  },
  {
    type: 'low_signal',
    severity: 'warning',
    summary: 'Signal quality dropped below reliable threshold.',
    detail: (deviceId) => ({ device: deviceId, signalQuality: '0.41' }),
  },
  {
    type: 'device_offline',
    severity: 'info',
    summary: 'Device went offline briefly during the night.',
    detail: (deviceId) => ({ device: deviceId, offlineSeconds: '95' }),
  },
]

const now = Date.now()
let written = 0

for (const deviceId of deviceIds) {
  for (let i = 0; i < count; i++) {
    const template = templates[i % templates.length]
    const raisedAt = now - (count - i) * 15 * 60 * 1000 // spaced 15 min apart, most recent last
    const ref = db.ref(`alerts/${deviceId}`).push()
    await ref.set({
      type: template.type,
      severity: template.severity,
      summary: template.summary,
      detail: template.detail(deviceId),
      raisedAt,
      votes: '3/3',
      acknowledged: false,
      acknowledgedBy: null,
    })
    written++
  }
  console.log(`seeded ${count} alert(s) on device ${deviceId}`)
}

console.log(`\nDone. Wrote ${written} new alert(s) for ${email}. Open the Alert Feed in the app to see them.`)
process.exit(0)
