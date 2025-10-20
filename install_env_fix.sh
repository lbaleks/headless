#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API_DIR="$ROOT/apps/api"
SV="$API_DIR/src/server.js"
UTIL="$API_DIR/src/plugins/_m2util.js"
ENVLOADER="$API_DIR/src/env-load.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

test -d "$API_DIR/src/plugins" || mkdir -p "$API_DIR/src/plugins"

# 1) Robust env-loader (ESM)
cat > "$ENVLOADER" <<'JS'
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
JS

# 2) Patch: bytt ut "import 'dotenv/config'" med robust loader
patch_import () {
  local FILE="$1"
  if [ -f "$FILE" ]; then
    if grep -q "dotenv/config" "$FILE"; then
      # Fjern eksisterende dotenv/config-linje
      # macOS sed -i '' kompatibelt
      sed -i '' "/dotenv\/config/d" "$FILE"
    fi
    # Sørg for at env-load importeres (en gang)
    if ! grep -q "env-load.js" "$FILE"; then
      sed -i '' '1 a\
import \"../env-load.js\"
' "$FILE"
      # For server.js ligger env-load ett nivå opp
      if [[ "$FILE" == *"/src/server.js" ]]; then
        sed -i '' '1,3 s|import "../env-load.js"|import "./env-load.js"|' "$FILE"
      fi
    fi
  fi
}

patch_import "$SV"
patch_import "$UTIL"

# 3) Valgfritt: legg en .env-symlink i apps/api som peker til roten (safe/idempotent)
if [ -f "$ROOT/.env" ] && [ ! -f "$API_DIR/.env" ]; then
  (cd "$API_DIR" && ln -s ../..//.env .env || true)
fi

# 4) Restart API trygt
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  echo "🧹 Stopper prosess på port $PORT"
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi

: > "$LOG"
echo "🚀 Starter API…"
( cd "$API_DIR" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1.2

echo "ℹ️  ENV loaded from:"
grep "__ENV_LOADED_FROM" "$LOG" || true
echo "🩺 Health:"; curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "🔔 M2 Ping:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/integrations/magento/ping" | jq -c . || true

# Bonus: korte smoke-calls (kan feile hvis M2 ikke svarer, men da ser vi env OK)
echo "👁️  Feature flags:"; curl -sS --max-time 3 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c . || true

echo "✅ env-fix ferdig."
