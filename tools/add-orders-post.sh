#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
FILE="$ROOT/app/api/orders/route.ts"

echo "→ Ensurerer mappe…"
mkdir -p "$(dirname "$FILE")"

if [ ! -f "$FILE" ]; then
  echo "→ Fant ikke $FILE — oppretter ny med GET+POST"
  cat > "$FILE" <<'TS'
import { NextResponse } from 'next/server'

// Minimal GET (passthrough til Magento list) – behold/erstatt senere etter behov
export async function GET(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    const page = Number(searchParams.get('page') || '1')
    const size = Number(searchParams.get('size') || '50')
    const q    = searchParams.get('q') || ''

    // Behold enkel, stabil respons for UI (erstattes av ekte Magento adapter)
    return NextResponse.json({
      items: [],
      total: 0,
      page,
      size,
      q,
    })
  } catch (e:any) {
    return NextResponse.json({ error: e?.message || 'unknown' }, { status: 500 })
  }
}

// NY: POST – stub for å avblokkere UI
export async function POST(req: Request) {
  try {
    const body = await req.json().catch(() => ({}))
    const id = `ORD-${Date.now()}`
    // Returner en minimal "ordre" så UI kan navigere videre
    return NextResponse.json({
      id,
      ok: true,
      received: body ?? null,
    }, { status: 201 })
  } catch (e:any) {
    return NextResponse.json({ error: e?.message || 'invalid payload' }, { status: 400 })
  }
}
TS
else
  if grep -q "export async function POST" "$FILE"; then
    echo "→ POST finnes allerede i $FILE – ingen endring."
  else
    echo "→ Legger til POST nederst i $FILE"
    cat >> "$FILE" <<'TS'

// --- Added by installer: POST handler to unblock UI ---
import { NextResponse } from 'next/server'
export async function POST(req: Request) {
  try {
    const body = await req.json().catch(() => ({}))
    const id = `ORD-${Date.now()}`
    return NextResponse.json({
      id,
      ok: true,
      received: body ?? null,
    }, { status: 201 })
  } catch (e:any) {
    return NextResponse.json({ error: e?.message || 'invalid payload' }, { status: 400 })
  }
}
TS
  fi
fi

echo "→ Rydder .next cache…"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev på nytt (npm run dev) og test å opprette ordre."