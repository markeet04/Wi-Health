/* backfill-alert-notified.mjs — one-time migration for the FCM alert-push
 * feature. The push watcher (app.service.ts watchAlertsForPush) skips any
 * alert that already has notifiedAt set, so backend restarts don't resend
 * pushes for old alerts. But the very first deploy of this feature would
 * otherwise see every pre-existing alert as "new" and push all of them at
 * once. Run this once, right before deploying the watcher, to mark every
 * alert that exists so far as already notified — the feature then only
 * fires for alerts raised after this point.
 *
 * Usage: node scripts/backfill-alert-notified.mjs
 */
import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app'
import { getDatabase } from 'firebase-admin/database'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

try {
  const here = dirname(fileURLToPath(import.meta.url))
  const t = readFileSync(resolve(here, '..', '.env'), 'utf8')
  for (const l of t.split(/\r?\n/)) { const m = l.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/); if (m) { let v = m[2].replace(/^["']|["']$/g, ''); if (process.env[m[1]] === undefined) process.env[m[1]] = v } }
} catch {}

const pid = process.env.FIREBASE_PROJECT_ID || 'wi-health-faa5d'
const app = getApps()[0] || initializeApp({ credential: applicationDefault(), projectId: pid, databaseURL: process.env.FIREBASE_DATABASE_URL || `https://${pid}-default-rtdb.asia-southeast1.firebasedatabase.app` })
const db = getDatabase(app)

const snapshot = await db.ref('alerts').get()
const alerts = snapshot.val() || {}
const now = Date.now()
let updated = 0

for (const [deviceId, deviceAlerts] of Object.entries(alerts)) {
  for (const [alertId, alert] of Object.entries(deviceAlerts || {})) {
    if (alert && !alert.notifiedAt) {
      await db.ref(`alerts/${deviceId}/${alertId}/notifiedAt`).set(now)
      updated++
    }
  }
}

console.log(`Backfilled notifiedAt on ${updated} existing alert(s). New alerts raised from now on will trigger a push.`)
process.exit(0)
