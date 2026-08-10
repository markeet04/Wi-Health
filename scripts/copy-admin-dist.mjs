// Deploy-time step: copy the built admin panel (admin/dist) into
// backend/dist/public so the backend can serve it as static files alongside
// the /api routes in a single Railway service. See root package.json "build".
import { cpSync, existsSync, rmSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '..')
const source = resolve(root, 'admin', 'dist')
const destination = resolve(root, 'backend', 'dist', 'public')

if (!existsSync(source)) {
  console.error(`copy-admin-dist: ${source} does not exist — did the admin build run first?`)
  process.exit(1)
}

rmSync(destination, { recursive: true, force: true })
cpSync(source, destination, { recursive: true })
console.log(`copy-admin-dist: copied ${source} -> ${destination}`)
