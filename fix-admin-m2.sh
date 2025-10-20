#!/usr/bin/env bash
set -euo pipefail

# 1) Finn admin-dir (Next.js) automatisk
ADMIN_DIR="$(
  find "$HOME/Documents/M2" -type f -name package.json 2>/dev/null \
  | while read -r f; do
      if jq -e '.dependencies.next // .devDependencies.next' "$f" >/dev/null 2>&1; then
        dirname "$f"; break
      fi
    done
)"
[ -n "${ADMIN_DIR:-}" ] || { echo "❌ Fant ikke admin-prosjektet med Next.js under ~/Documents/M2"; exit 1; }

echo "➡️  Admin: $ADMIN_DIR"

# 2) Sørg for at .env.local har riktig gateway-base
ENV_FILE="$ADMIN_DIR/.env.local"
GW_DEFAULT="http://localhost:3044"
mkdir -p "$ADMIN_DIR"
touch "$ENV_FILE"
if grep -q '^NEXT_PUBLIC_GATEWAY_BASE=' "$ENV_FILE"; then
  sed -i '' -E "s|^NEXT_PUBLIC_GATEWAY_BASE=.*|NEXT_PUBLIC_GATEWAY_BASE=${GW_DEFAULT}|" "$ENV_FILE"
else
  printf "\nNEXT_PUBLIC_GATEWAY_BASE=%s\n" "$GW_DEFAULT" >> "$ENV_FILE"
fi
# (valgfritt) fjern gammel nøkkel
sed -i '' -E '/^NEXT_PUBLIC_GATEWAY=/{d;}' "$ENV_FILE"

echo "✅ Oppdatert $ENV_FILE"

# 3) Skriv lib/api.ts (fetch-basert, null axios)
mkdir -p "$ADMIN_DIR/lib"
cat > "$ADMIN_DIR/lib/api.ts" <<'TS'
export const GW_BASE =
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  process.env.NEXT_PUBLIC_GATEWAY || // legacy fallback
  "http://localhost:3044";

type Json = any;

export async function getJson(path: string): Promise<Json> {
  const url = path.startsWith("http") ? path : `${GW_BASE}${path}`;
  const res = await fetch(url, { cache: "no-store" });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      const body = await res.text();
      msg += `: ${body}`;
    } catch {}
    throw new Error(msg);
  }
  return res.json();
}
TS
echo "✅ Skrevet: lib/api.ts"

# 4) Skriv / overskriv app/m2/page.tsx
mkdir -p "$ADMIN_DIR/app/m2"
cat > "$ADMIN_DIR/app/m2/page.tsx" <<'TSX'
"use client";

import { useEffect, useState } from "react";
import { getJson, GW_BASE } from "@/lib/api";

export default function M2Page() {
  const [health, setHealth] = useState<any>(null);
  const [stats, setStats] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [h, s] = await Promise.all([
          getJson("/health/magento"),
          getJson("/ops/stats/summary"),
        ]);
        if (!alive) return;
        setHealth(h);
        setStats(s);
      } catch (e: any) {
        if (!alive) return;
        setError(e?.message || String(e));
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  return (
    <main className="p-6 space-y-6">
      <h1 className="text-2xl font-semibold">🔗 Gateway / Magento</h1>

      <div className="text-sm text-gray-500">
        Gateway base: <code>{GW_BASE}</code>
      </div>

      <section className="space-y-2">
        <h2 className="text-xl font-medium">Health</h2>
        <pre className="bg-neutral-100 p-3 rounded">{JSON.stringify(health, null, 2)}</pre>
      </section>

      <section className="space-y-2">
        <h2 className="text-xl font-medium">Stats</h2>
        {stats?.totals ? (
          <pre className="bg-neutral-100 p-3 rounded">{JSON.stringify(stats, null, 2)}</pre>
        ) : (
          <div>Ingen statistikk tilgjengelig.</div>
        )}
      </section>

      {error && (
        <section className="space-y-2">
          <h2 className="text-xl font-medium text-red-600">Error</h2>
          <pre className="bg-red-50 p-3 rounded border border-red-200">
            {error}
          </pre>
        </section>
      )}
    </main>
  );
}
TSX
echo "✅ Skrevet: app/m2/page.tsx"

echo "🎉 Ferdig. Start/refresh Next.js dev-server og åpne http://localhost:3000/m2"
