#!/usr/bin/env bash
set -euo pipefail
UI="apps/api/src/plugins/admin.ui.js"
LOG=".api.dev.log"
PIDF=".api.pid"
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

# 1) Sørg for at whoami bruker api() (ikke fetch)
node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')

s = s.replace(/fetch\('\/v2\/auth\/whoami'\)/g, "api('/v2/auth/whoami')")
s = s.replace(/await fetch\('\/v2\/auth\/whoami'\)/g, "await api('/v2/auth/whoami')")

// ekstra: hvis showRole fortsatt definerer fetch manuelt, bytt ut der også
s = s.replace(/const r = await fetch\('\/v2\/auth\/whoami'\);/g, "const r = await api('/v2/auth/whoami');")

fs.writeFileSync(f,s,'utf8')
console.log('Patched whoami → api() so x-role applies.')
NODE

# 2) Restart API
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd apps/api && nohup npm run start > "../../$LOG" 2>&1 & echo $! > "../../$PIDF" )
sleep 1.5

echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "👤 Whoami (admin via UI header expected):"; curl -sS --max-time 6 -H 'x-role: admin' "http://127.0.0.1:$PORT/v2/auth/whoami" || true; echo
