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
const pid = process.env.FIREBASE_PROJECT_ID || 'wi-health-faa5d'
const app = getApps()[0] || initializeApp({ credential: applicationDefault(), projectId: pid, databaseURL: process.env.FIREBASE_DATABASE_URL || `https://${pid}-default-rtdb.asia-southeast1.firebasedatabase.app` })
const list = await getAuth(app).listUsers(50)
console.log('=== Firebase Auth users ===')
for (const u of list.users) console.log(`  ${u.uid}  ${u.email || '(no email)'}  claims=${JSON.stringify(u.customClaims || {})}`)
const usersSnap = await getDatabase(app).ref('users').get()
console.log('\n=== /users nodes (uid -> role, linked devices) ===')
const uv = usersSnap.val() || {}
for (const [uid, rec] of Object.entries(uv)) console.log(`  ${uid}  role=${rec.role || '?'}  devices=${JSON.stringify(rec.devices || {})}`)
process.exit(0)
