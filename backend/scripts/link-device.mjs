/* link-device.mjs — link a device to an App User account so the mobile app
 * shows it as a patient. This is the step that (in production) the admin panel
 * does when assigning a device -> patient -> account. Run once per device.
 *
 * Writes:
 *   /users/$uid/devices/$deviceId = true      (the patient-switcher link)
 *   /devices/$deviceId/meta.ownerUid = $uid   (device knows its owner)
 *   /devices/$deviceId/meta.patientName ...    (so the app has a label)
 *
 * Usage:
 *   node scripts/link-device.mjs <deviceId> <userEmail> [patientName]
 *   e.g. node scripts/link-device.mjs test-device-1 qaimmaajid@gmail.com "Qasim"
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

const deviceId = process.argv[2]
const email = process.argv[3]
const patientName = process.argv[4] || 'Patient'
if (!deviceId || !email) { console.error('usage: node scripts/link-device.mjs <deviceId> <userEmail> [patientName]'); process.exit(1) }

const pid = process.env.FIREBASE_PROJECT_ID || 'wi-health-faa5d'
const app = getApps()[0] || initializeApp({ credential: applicationDefault(), projectId: pid, databaseURL: process.env.FIREBASE_DATABASE_URL || `https://${pid}-default-rtdb.asia-southeast1.firebasedatabase.app` })

const user = await getAuth(app).getUserByEmail(email)
const uid = user.uid
const role = (user.customClaims && user.customClaims.role) || 'app_user'
console.log(`user: ${email} -> uid ${uid} (role ${role})`)
if (role !== 'app_user') {
  console.warn(`WARNING: ${email} is role=${role}. The mobile app blocks non-app_user accounts from the patient view; link to an app_user account for the app to show the device.`)
}

const db = getDatabase(app)
await db.ref(`users/${uid}/devices/${deviceId}`).set(true)
await db.ref(`devices/${deviceId}/meta`).update({
  ownerUid: uid,
  patientName,
  patientRelation: 'self',
  room: 'Bedroom',
})
console.log(`linked: /users/${uid}/devices/${deviceId}=true, meta.ownerUid=${uid}, patientName="${patientName}"`)
console.log('\nDone. Run the mobile app with --dart-define=USE_FIREBASE=true and log in as this user to see the live device.')
process.exit(0)
