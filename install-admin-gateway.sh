#!/usr/bin/env bash
set -euo pipefail

# === Konfig med fornuftige defaults (kan overrides via env) ===
ADMIN_PORT="${ADMIN_PORT:-3000}"
GATEWAY_PORT="${GATEWAY_PORT:-3044}"
ROOT_SCAN_DIR="${ROOT_SCAN_DIR:-$HOME/Documents/M2}"
AUTOSTART="${AUTOSTART:-1}"            # 1 = start servere automatisk
FORCE_WRITE_PAGE="${FORCE_WRITE_PAGE:-0}" # 1 = overskriv eksisterende /m2-side hvis finnes

say() { printf "\033[1;96m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m%s\033[0m\n" "$*"; }
err() { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

need() { command -v "$1" >/dev/null || { err "Mangler $1. Installer og prøv igjen."; exit 1; }; }

need jq
need node

# === Finn admin- og gateway-prosjektene ===
if [ -n "${ADMIN_DIR:-}" ] && [ -d "$ADMIN_DIR" ]; then
  :
else
  ADMIN_DIR="$(
    find "$ROOT_SCAN_DIR" -type f -name package.json 2>/dev/null \
    | while read -r f; do
        # Finn Next.js-app
        if jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1; then
          dirname "$f"; break
        fi
      done
  )"
fi

if [ -z "${ADMIN_DIR}" ] || [ ! -d "$ADMIN_DIR" ]; then
  err "Fant ikke admin-prosjektet (Next.js) under $ROOT_SCAN_DIR. Sett ADMIN_DIR=/sti/til/admin og kjør igjen."
  exit 1
fi

if [ -n "${GATEWAY_DIR:-}" ] && [ -d "$GATEWAY_DIR" ]; then
  :
else
  # Heuristikk: repo/folder som har server.js og refererer til MAGENTO_ vars
  GATEWAY_DIR="$(
    find "$ROOT_SCAN_DIR" -maxdepth 2 -type f -name server.js 2>/dev/null \
    | while read -r f; do
        if grep -qE 'MAGENTO_BASE|m2-gateway up' "$f"; then
          dirname "$f"; break
        fi
      done
  )"
fi

if [ -z "${GATEWAY_DIR}" ] || [ ! -d "$GATEWAY_DIR" ]; then
  err "Fant ikke gateway-prosjektet (server.js) under $ROOT_SCAN_DIR. Sett GATEWAY_DIR=/sti/til/m2-gateway og kjør igjen."
  exit 1
fi

say "➡️  Admin:   $ADMIN_DIR    (port $ADMIN_PORT)"
say "➡️  Gateway: $GATEWAY_DIR  (port $GATEWAY_PORT)"

# === Oppdater gateway .env ===
(
  cd "$GATEWAY_DIR"
  touch .env
  # Les eksisterende
  OLD_ENV="$(cat .env || true)"

  # Hent evt. eksisterende MAGENTO_* verdier
  MAGENTO_BASE="${MAGENTO_BASE:-$(awk -F= '/^MAGENTO_BASE=/{sub(/^MAGENTO_BASE=/,"");print}' .env || true)}"
  MAGENTO_TOKEN="${MAGENTO_TOKEN:-$(awk -F= '/^MAGENTO_TOKEN=/{sub(/^MAGENTO_TOKEN=/,"");print}' .env || true)}"

  # Prøv fallback fra gamle M2_ variabler i overliggende .env (som noen repoer har)
  if [ -z "$MAGENTO_BASE" ] && [ -f ../../.env ]; then
    MAGENTO_BASE="$(awk -F= '/^M2_BASE_URL=/{sub(/^M2_BASE_URL=/,"");print}' ../../.env || true)"
  fi
  if [ -z "$MAGENTO_TOKEN" ] && [ -f ../../.env ]; then
    MAGENTO_TOKEN="$(awk -F= '/^M2_ADMIN_TOKEN=/{sub(/^M2_ADMIN_TOKEN=/,"");print}' ../../.env || true)"
    # Prefix med Bearer om nødvendig
    if [ -n "$MAGENTO_TOKEN" ] && ! printf '%s' "$MAGENTO_TOKEN" | grep -q '^Bearer '; then
      MAGENTO_TOKEN="Bearer $MAGENTO_TOKEN"
    fi
  fi

  cat > .env <<EOF
PORT=$GATEWAY_PORT
CORS_ORIGIN=http://localhost:$ADMIN_PORT
MAGENTO_BASE=${MAGENTO_BASE}
MAGENTO_TOKEN=${MAGENTO_TOKEN}
MAGENTO_TIMEOUT_MS=25000
EOF

  say "✅ Gateway .env oppdatert:"
  awk '{print "  " $0}' .env

  if [ -z "$MAGENTO_BASE" ] || [ -z "$MAGENTO_TOKEN" ]; then
    warn "⚠️  MAGENTO_BASE eller MAGENTO_TOKEN er tomt. Sett disse i $GATEWAY_DIR/.env (eller i ../../.env som M2_BASE_URL / M2_ADMIN_TOKEN)."
  fi
)

# === Oppdater admin .env.local ===
(
  cd "$ADMIN_DIR"
  touch .env.local
  # Fjern evt. eksisterende linje og skriv ny
  grep -v '^NEXT_PUBLIC_GATEWAY_BASE=' .env.local 2>/dev/null > .env.local.tmp || true
  mv .env.local.tmp .env.local
  echo "NEXT_PUBLIC_GATEWAY_BASE=http://localhost:$GATEWAY_PORT" >> .env.local
  say "✅ Admin .env.local oppdatert:"
  awk '{print "  " $0}' .env.local
)

# === Lag/oppdater lib/api.ts i admin ===
(
  cd "$ADMIN_DIR"
  mkdir -p lib
  if [ -f lib/api.ts ]; then
    say "ℹ️  lib/api.ts finnes – overskriver ikke."
  else
    cat > lib/api.ts <<'TS'
export const API_BASE =
  process.env.NEXT_PUBLIC_GATEWAY_BASE || "http://localhost:3044";

export async function getJson(path: string) {
  const res = await fetch(`${API_BASE}${path}`, { cache: "no-store" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}
TS
    say "✅ Opprettet lib/api.ts"
  fi
)

# === Lag en trygg side på /m2 som viser health + stats ===
(
  cd "$ADMIN_DIR"
  PAGE_DIR="app/m2"
  PAGE_FILE="$PAGE_DIR/page.tsx"
  mkdir -p "$PAGE_DIR"

  if [ -f "$PAGE_FILE" ] && [ "$FORCE_WRITE_PAGE" != "1" ]; then
    say "ℹ️  $PAGE_FILE finnes – overskriver ikke (sett FORCE_WRITE_PAGE=1 for å tvinge)."
  else
    cat > "$PAGE_FILE" <<'TSX'
"use client";
import { useEffect, useState } from "react";
import { getJson } from "../../lib/api";

export default function M2Dashboard() {
  const [health, setHealth] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const h = await getJson("/health/magento");
        setHealth(h);
        const s = await getJson("/ops/stats/summary");
        setStats(s);
      } catch (e: any) {
        setErr(e?.message || String(e));
      }
    })();
  }, []);

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-bold">🔗 Gateway / Magento</h1>

      <div className="grid gap-4 md:grid-cols-2">
        <Card title="Health">
          <pre className="text-xs">{JSON.stringify(health, null, 2)}</pre>
        </Card>

        <Card title="Stats">
          {stats?.ok ? (
            <div className="grid gap-3 md:grid-cols-3">
              <Stat label="Products" value={stats.totals?.products} />
              <Stat label="Categories" value={stats.totals?.categories} />
              <Stat label="Variants" value={stats.totals?.variants} />
            </div>
          ) : (
            <div>Ingen statistikk tilgjengelig.</div>
          )}
        </Card>
      </div>

      {err && <div className="text-red-600">Error: {err}</div>}
    </div>
  );
}

function Card({ title, children }: { title: string; children: any }) {
  return (
    <div className="rounded-xl border p-4 shadow-sm">
      <div className="text-sm text-gray-500 mb-2">{title}</div>
      {children}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border p-4">
      <div className="text-xs text-gray-500">{label}</div>
      <div className="text-2xl font-semibold">{value ?? 0}</div>
    </div>
  );
}
TSX
    say "✅ Opprettet admin-side: /m2"
  fi
)

# === Start tjenester (valgfritt) ===
if [ "$AUTOSTART" = "1" ]; then
  say "🚀 Starter gateway (port $GATEWAY_PORT)…"
  ( cd "$GATEWAY_DIR" && pkill -f "node server.js" 2>/dev/null || true; nohup node server.js >/dev/null 2>&1 & )
  sleep 1

  say "🚀 Starter admin (Next.js port $ADMIN_PORT)…"
  (
    cd "$ADMIN_DIR"
    # bruk npm scripts om de finnes, ellers fallback til npx next
    if jq -e '.scripts.dev' package.json >/dev/null 2>&1; then
      # prøv å tvinge port via env
      PORT="$ADMIN_PORT" nohup npm run dev >/dev/null 2>&1 &
    else
      npx --yes next dev -p "$ADMIN_PORT" >/dev/null 2>&1 &
    fi
  )
  sleep 2
fi

# === Sanity tester ===
say "🧪 Sanity:"
set +e
curl -sS "http://localhost:$GATEWAY_PORT/health/magento" | jq . 2>/dev/null || curl -sS "http://localhost:$GATEWAY_PORT/health/magento"
curl -sS "http://localhost:$GATEWAY_PORT/ops/stats/summary" | jq . 2>/dev/null || curl -sS "http://localhost:$GATEWAY_PORT/ops/stats/summary"
set -e

say "➡️  Admin:   http://localhost:$ADMIN_PORT/m2"
say "➡️  Gateway: http://localhost:$GATEWAY_PORT"
say "✅ Ferdig."