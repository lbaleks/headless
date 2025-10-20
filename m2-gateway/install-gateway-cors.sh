#!/usr/bin/env bash
set -euo pipefail

# 1) Sørg for CORS_ORIGIN i .env
touch .env
grep -q '^CORS_ORIGIN=' .env || echo 'CORS_ORIGIN=http://localhost:3000' >> .env

# 2) Patch server.js med enkel CORS (idempotent)
if ! grep -q '/* CORS: allow browser client */' server.js; then
  # Sett inn like etter første 'const express' (tidlig i fila)
  perl -0777 -pe '
    s|(const express\s*=\s*require\([\"\']express[\"\']\);\s*)|\1\n/* CORS: allow browser client */\nconst CORS_ORIGIN = process.env.CORS_ORIGIN || "*";\nfunction corsLite(req,res,next){\n  res.setHeader("Access-Control-Allow-Origin", CORS_ORIGIN);\n  res.setHeader("Vary","Origin");\n  res.setHeader("Access-Control-Allow-Methods","GET,POST,PUT,DELETE,OPTIONS");\n  res.setHeader("Access-Control-Allow-Headers","Content-Type, Authorization");\n  if (req.method === "OPTIONS") return res.sendStatus(200);\n  next();\n}\n|s
  ' -i server.js
fi

# 3) Sørg for at CORS brukes før routes
if ! grep -q 'app.use(corsLite)' server.js; then
  perl -0777 -pe 's|(const app\s*=\s*express\(\);\s*)|\1\napp.use(corsLite);\n|s' -i server.js
fi

# 4) Restart gateway og sanity-test
pkill -f "node server.js" 2>/dev/null || true
node server.js & sleep 1

echo "— sanity —"
curl -sS http://localhost:3044/health/magento | jq 2>/dev/null || curl -sS http://localhost:3044/health/magento
# Preflight-test (simulerer nettleser)
curl -sS -i -X OPTIONS "http://localhost:3044/ops/category/replace" \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type" | sed -n '1,20p'
