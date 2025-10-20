import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import dotenv from 'dotenv'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const cwd = process.cwd()

const candidates = [
  path.resolve(cwd, '.env'),                 // apps/api/.env (hvis finnes)
  path.resolve(__dirname, '../../.env'),     // repo-root/.env (vanligst)
  path.resolve(__dirname, '../../../.env')   // fallback for annen struktur
]

let loadedFrom = null
for (const p of candidates) {
  try {
    if (fs.existsSync(p)) {
      dotenv.config({ path: p })
      loadedFrom = p
      break
    }
  } catch {}
}

if (!loadedFrom) {
  // Siste fallback: prøv standard dotenv-resolver (cwd)
  dotenv.config()
  loadedFrom = '(default resolver / cwd)'
}

if (!process.env.M2_BASE_URL || !process.env.M2_ADMIN_TOKEN) {
  // Behold videre, men noter for debugging
  process.env.__ENV_WARN = `Missing M2 vars. Loaded from: ${loadedFrom}`
}
process.env.__ENV_LOADED_FROM = loadedFrom
export const ENV_LOADED_FROM = loadedFrom
