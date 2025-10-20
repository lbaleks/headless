#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
FILE="$ROOT/app/api/orders/[id]/route.ts"

if [ ! -f "$FILE" ]; then
  echo "Fant ikke $FILE. Sørg for at mappen og GET-handleren eksisterer." >&2
  exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%s)"

cat > "$FILE" <<'TS'
import { NextResponse } from 'next/server'

const M2_BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN

// Del minne-stub med liste-endepunktet
const STUBS = (globalThis as any).__ORD_STUBS__ ||= new Map<string, any>()

async function m2Fetch<T>(verb: 'GET'|'POST', path: string, body?: any): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('missing env MAGENTO_BASE_URL/MAGENTO_ADMIN_TOKEN')
  const url = `${M2_BASE.replace(/\/+$/,'')}/${path.replace(/^\/+/,'')}`
  const res = await fetch(url, {
    method: verb,
    headers: { Authorization: `Bearer ${M2_TOKEN}`, 'content-type': 'application/json' },
    cache: 'no-store',
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const txt = await res.text().catch(()=>'')
    throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${txt}`)
  }
  // No content
  if (res.status === 204) return undefined as unknown as T
  return await res.json()
}

async function m2Get<T>(path: string){ return m2Fetch<T>('GET', path) }
async function m2Post<T>(path: string, body: any){ return m2Fetch<T>('POST', path, body) }

// --- GET: behold eksisterende logikk ---
export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctx.params
    if (id.startsWith('ORD-') && STUBS.has(id)) {
      return NextResponse.json(STUBS.get(id), { status: 200 })
    }
    // direkte forsøk
    const direct = await m2Get<any>(`V1/orders/${encodeURIComponent(id)}`).catch(()=>null)
    if (direct?.entity_id) return NextResponse.json(direct, { status: 200 })
    // søk på increment_id
    const raw = await m2Get<any>(`V1/orders?searchCriteria[filter_groups][0][filters][0][field]=increment_id&searchCriteria[filter_groups][0][filters][0][value]=${encodeURIComponent(id)}&searchCriteria[filter_groups][0][filters][0][condition_type]=eq`)
    const items = Array.isArray(raw?.items) ? raw.items : []
    const data = items[0] || null
    if (!data) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    return NextResponse.json(data, { status: 200 })
  } catch (err: any) {
    console.error('[GET /api/orders/[id]] 500', err?.stack || err)
    return NextResponse.json({ error: 'Internal error', detail: String(err?.message || err) }, { status: 500 })
  }
}

// --- Hjelper: finn Magento entity_id fra id/increment_id ---
async function resolveEntityId(id: string): Promise<number|null> {
  // Hvis id ser ut som tall, prøv direkte først
  if (/^\d+$/.test(id)) {
    const direct = await m2Get<any>(`V1/orders/${id}`).catch(()=>null)
    if (direct?.entity_id) return Number(direct.entity_id)
  }
  // ellers slå opp på increment_id
  const raw = await m2Get<any>(`V1/orders?searchCriteria[filter_groups][0][filters][0][field]=increment_id&searchCriteria[filter_groups][0][filters][0][value]=${encodeURIComponent(id)}&searchCriteria[filter_groups][0][filters][0][condition_type]=eq`)
  const items = Array.isArray(raw?.items) ? raw.items : []
  const hit = items[0]
  return hit?.entity_id ? Number(hit.entity_id) : null
}

// --- PATCH: oppdater stub-lokalt, eller legg til kommentar/status i Magento ---
export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctx.params
    const p = await req.json().catch(()=> ({} as any))
    const status = typeof p?.status === 'string' ? p.status : undefined
    const note = (typeof p?.notes === 'string' && p.notes) ? p.notes
               : (typeof p?.comment === 'string' && p.comment) ? p.comment
               : ''

    // ORD-… → lokal stub
    if (id.startsWith('ORD-')) {
      const current = STUBS.get(id) || {
        id, increment_id: id, status: 'new', created_at: new Date().toISOString(),
        lines: [], customer: null, source: 'local-stub'
      }
      const updated = {
        ...current,
        ...(status ? { status } : {}),
        ...(note   ? { notes: note } : {}),
        updated_at: new Date().toISOString(),
      }
      STUBS.set(id, updated)
      return NextResponse.json(updated, { status: 200 })
    }

    // Magento → legg kommentar (og ev. status) via /comments
    const entityId = await resolveEntityId(id)
    if (!entityId) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 })
    }

    // Bare hvis vi faktisk har noe å sende som kommentar/status
    if (status || note) {
      await m2Post<any>(`V1/orders/${entityId}/comments`, {
        status: status || undefined,
        comment: note || '',
        is_visible_on_front: 0,
        is_customer_notified: 0,
      })
    }

    // Returner enkel OK + echo av det vi gjorde
    return NextResponse.json({
      ok: true,
      entity_id: entityId,
      applied: { status: status ?? null, comment: note || null }
    }, { status: 200 })
  } catch (err: any) {
    console.error('[PATCH /api/orders/[id]] 500', err?.stack || err)
    return NextResponse.json({ error: 'Internal error', detail: String(err?.message || err) }, { status: 500 })
  }
}
TS

echo "→ Rydder .next cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Restart dev (npm run dev / yarn dev / pnpm dev)."
