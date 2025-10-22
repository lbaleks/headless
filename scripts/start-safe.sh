#!/usr/bin/env bash
set -euo pipefail

# Hint om Node-versjon
NODE_MAJ=$(node -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJ" -ge 22 ] || [ "$NODE_MAJ" -lt 18 ]; then
  echo "⚠️  Node $(node -v) er utenfor anbefalt område (>=18.18 <22). Tips: nvm use 20"
fi

# Drep alt på 3000 (prod) og 3001 (dev) for å unngå port-kræsj
for PORT in 3000 3001; do
  PIDS="$(lsof -ti :$PORT || true)"
  if [ -n "$PIDS" ]; then
    echo "🔪 Stopper prosess(er) på port $PORT: $PIDS"
    kill -9 $PIDS || true
  fi
done

# Bygg hvis mangler
if [ ! -d ".next" ] || [ -z "$(ls -A .next 2>/dev/null)" ]; then
  echo "🧱 Ingen build funnet. Kjører pnpm run build ..."
  pnpm run build
fi

echo "▶️  Starter prod på port 3000…"
pnpm exec next start -p 3000 &

echo "⏳ Venter på http://localhost:3000 ..."
for i in {1..60}; do
  if nc -z localhost 3000 2>/dev/null; then
    echo "✅ Server lytter på port 3000"
    break
  fi
  sleep 0.5
done

echo "🧪 Tester endpoints:"
curl -fsS http://localhost:3000/api/health | jq . || true
curl -fsS http://localhost:3000/api/pricing/effective | jq . || true
curl -fsS -X POST http://localhost:3000/api/pricing/effective \
  -H 'content-type: application/json' \
  -d '{"lines":[{"sku":"TEST","qty":2,"price":199},{"sku":"ABC","qty":1,"price":50}]}' | jq . || true

echo "✅ Ferdig!"
