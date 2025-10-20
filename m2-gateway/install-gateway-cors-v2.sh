#!/usr/bin/env bash
set -euo pipefail

echo "➡️  Dir: $(pwd)"

# 1) Sørg for CORS_ORIGIN i .env (idempotent)
touch .env
if ! grep -qE '^CORS_ORIGIN=' .env; then
  echo 'CORS_ORIGIN=http://localhost:3000' >> .env
  echo "✅ .env: lagt til CORS_ORIGIN=http://localhost:3000"
else
  echo "ℹ️  .env: CORS_ORIGIN finnes allerede"
fi

# 2) Skriv enkel CORS-middleware som egen fil (idempotent)
if [ ! -f cors-lite.js ]; then
cat > cors-lite.js <<'JS'
/** Lightweight CORS middleware (no deps) */
const ORIGIN = process.env.CORS_ORIGIN || '*';

function corsLite(req, res, next) {
  res.setHeader('Access-Control-Allow-Origin', ORIGIN);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
}

module.exports = corsLite;
JS
  echo "✅ Skrev cors-lite.js"
else
  echo "ℹ️  cors-lite.js finnes – beholder"
fi

# 3) Patch server.js til å bruke cors-lite (idempotent)
[ -f server.js ] || { echo "❌ Fant ikke server.js"; exit 1; }

if ! grep -q "require('./cors-lite')" server.js; then
  # Sett inn require rett etter express-requiret
  /usr/bin/perl -0777 -pe "s|(const\\s+express\\s*=\\s*require\\(['\"]express['\"]\\);\\s*)|\\1\nconst corsLite = require('./cors-lite');\n|s" -i server.js
  echo "✅ La til require('./cors-lite') i server.js"
else
  echo "ℹ️  server.js har allerede require('./cors-lite')"
fi

if ! grep -q "app.use(corsLite)" server.js; then
  # Sett inn app.use(corsLite) rett etter const app = express();
  /usr/bin/perl -0777 -pe "s|(const\\s+app\\s*=\\s*express\\(\\);\\s*)|\\1\napp.use(corsLite);\n|s" -i server.js
  echo "✅ La til app.use(corsLite) i server.js"
else
  echo "ℹ️  server.js har allerede app.use(corsLite)"
fi

# 4) Restart gateway og sanity-test
pkill -f "node server.js" 2>/dev/null || true
node server.js & sleep 1

echo "— sanity —"
curl -sS http://localhost:3044/health/magento || true
echo
echo "— preflight —"
curl -sS -i -X OPTIONS "http://localhost:3044/ops/category/replace" \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type" \
  | sed -n '1,20p' || true

echo "✅ Ferdig."
