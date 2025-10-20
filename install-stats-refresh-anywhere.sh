#!/usr/bin/env bash
set -euo pipefail

# 1) Finn gateway-root (katalogen som har server.js)
find_gateway() {
  local base="${HOME}/Documents/M2"
  local cand
  # Prøv noen smarte søk
  while IFS= read -r cand; do
    if grep -q "m2-gateway up" "$cand" 2>/dev/null; then
      dirname "$cand"; return 0
    fi
  done < <(find "$base" -type f -name server.js 2>/dev/null)

  # Fallback til standardmappe
  if [ -f "$base/m2-gateway/server.js" ]; then
    echo "$base/m2-gateway"; return 0
  fi

  echo ""
  return 1
}

GW_DIR="$(find_gateway || true)"
if [ -z "${GW_DIR:-}" ]; then
  echo "❌ Fant ikke m2-gateway/server.js under ~/Documents/M2"
  exit 1
fi

echo "➡️  Gateway: ${GW_DIR}"
cd "$GW_DIR"

F="server.js"
[ -f "$F" ] || { echo "❌ Fant ikke $F i ${GW_DIR}"; exit 1; }

# 2) Legg til /ops/stats/refresh hvis det mangler
if grep -q "/ops/stats/refresh" "$F"; then
  echo "ℹ️  /ops/stats/refresh finnes allerede."
else
  echo "➡️  Legger til /ops/stats/refresh (GET/POST)…"
  cat >> "$F" <<'JS'

// --- injected: stats refresh endpoints (idempotent) ---
app.post('/ops/stats/refresh', (req, res) => {
  try {
    if (typeof CACHE !== 'undefined') {
      CACHE.stats = null;
      CACHE.ts = 0;
    } else if (typeof global !== 'undefined' && global.CACHE) {
      global.CACHE.stats = null;
      global.CACHE.ts = 0;
    }
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e?.message || String(e) });
  }
});

app.get('/ops/stats/refresh', (req, res) => {
  try {
    if (typeof CACHE !== 'undefined') {
      CACHE.stats = null;
      CACHE.ts = 0;
    } else if (typeof global !== 'undefined' && global.CACHE) {
      global.CACHE.stats = null;
      global.CACHE.ts = 0;
    }
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e?.message || String(e) });
  }
});
// --- end injected ---
JS
fi

# 3) Finn port (fra .env), default 3044
PORT="$(awk -F= '/^PORT=/{print $2}' .env 2>/dev/null | tr -d '[:space:]' || true)"
[ -n "${PORT:-}" ] || PORT=3044

# 4) Restart gateway
echo "🚀 Restarter gateway på port ${PORT}…"
pkill -f "node server.js" 2>/dev/null || true
(node server.js >/dev/null 2>&1 &)
sleep 1

# 5) Test
echo "🧪 Tester:"
curl -sS "http://localhost:${PORT}/ops/stats/summary" | jq . || true
curl -sS -X POST "http://localhost:${PORT}/ops/stats/refresh" | jq . || true
curl -sS "http://localhost:${PORT}/ops/stats/summary" | jq . || true
echo "✅ Ferdig."
