#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F=server.js
[ -f "$F" ] || { echo "❌ Fant ikke $F"; exit 1; }

# Hvis refresh-endpointet finnes fra før, gjør ingenting
if grep -q "/ops/stats/refresh" "$F"; then
  echo "ℹ️  /ops/stats/refresh finnes allerede."
else
  echo "➡️  Legger til /ops/stats/refresh (POST og GET)…"
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

echo "🚀 Restarter gateway…"
pkill -f "node server.js" 2>/dev/null || true
(node server.js >/dev/null 2>&1 &)
sleep 1

echo "🧪 Tester:"
curl -sS http://localhost:3044/ops/stats/summary | jq .
curl -sS -X POST http://localhost:3044/ops/stats/refresh | jq .
curl -sS http://localhost:3044/ops/stats/summary | jq .
echo "✅ Ferdig."
