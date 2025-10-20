#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
API_DIR="$ROOT/app/api/orders"
FILE="$API_DIR/route.ts"
FILE_ID="$API_DIR/[id]/route.ts"

mkdir -p "$API_DIR" "$API_DIR/[id]"

# Backup eksisterende filer
[ -f "$FILE" ] && cp "$FILE" "$FILE.bak.$(date +%s)"
[ -f "$FILE_ID" ] && cp "$FILE_ID" "$FILE_ID.bak.$(date +%s)"

# Skriv /api/orders (liste + post)
cat > "$FILE" <<'TS'
import { NextResponse } from 'next/server'

const M2_BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN

// --- In-memory stub store (resettes ved server-restart) ---
const STUBS = (globalThis as any).__ORD_STUBS__ ||= new Map<string, any>()

async function m2Get<T>(path: string): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('missing env MAGENTO_BASE_URL/MAGENTO_ADMIN_TOKEN')
  const url = `${M2_BASE.replace(/\/+$/,'')}/${path.replace(/^\/+/,'')}`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${M2_TOKEN}` }, cache: 'no-store' })
  if (!res.ok) {
    const txt = await res.text().catch(()=>'')
    throw new Error(`Magento GET ${url} failed: ${res.status} ${txt}`)
  }
  return await res.json()
}

function normalizeOrders(m: any) {
  const total = m?.total_count ?? 0
  const items = Array.isArray(m?.items) ? m.items : []
  return { total, items }
}

// GET /api/orders  (prepend stubs på page=1)
export async function GET(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    const page = Math.max(1, Number(searchParams.get('page') ?? '1') || 1)
    const size = Math.max(1, Number(searchParams.get('size') ?? '25') || 25)
    const q = (searchParams.get('q') || '').trim()

    // Magento query
    const params: string[] = [
      `searchCriteria[currentPage]=${page}`,
      `searchCriteria[pageSize]=${size}`,
      `searchCriteria[sortOrders][0][field]=created_at`,
      `searchCriteria[sortOrders][0][direction]=DESC`,
    ]
    if (q) {
      params.push(`searchCriteria[filter_groups][0][filters][0][field]=increment_id`)
      params.push(`searchCriteria[filter_groups][0][filters][0][value]=%25${encodeURIComponent(q)}%25`)
      params.push(`searchCriteria[filter_groups][0][filters][0][condition_type]=like`)
    }
    const raw = await m2Get<any>('V1/orders?' + params.join('&'))
    const { total, items } = normalizeOrders(raw)

    // Stubs (filtrert og sortert, nyest først)
    let stubItems = Array.from(STUBS.values())
      .filter(s => (q ? String(s.increment_id||s.id||'').includes(q) : true))
      .sort((a,b)=> String(b.created_at).localeCompare(String(a.created_at)))

    // På side 1, prepender vi stubs foran Magento-resultater
    let mergedItems = items
    if (page === 1 && stubItems.length) {
      // Begrens til "size" totalt når vi prepender
      const takeStub = Math.min(size, stubItems.length)
      mergedItems = [...stubItems.slice(0, takeStub), ...items].slice(0, size)
    }

    return NextResponse.json({ total: total + stubItems.length, items: mergedItems }, { status: 200 })
  } catch (err: any) {
    console.error('[GET /api/orders] 500', err?.stack || err)
    return NextResponse.json({ error: 'Internal error', detail: String(err?.message || err) }, { status: 500 })
  }
}

// POST /api/orders  (lagrer stub + returnerer 201)
export async function POST(req: Request) {
  const t0 = Date.now()
  try {
    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object') {
      return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
    }
    const { customer, lines, notes } = body as { customer?: any, lines?: any[], notes?: string }
    if (!Array.isArray(lines) || lines.length === 0) {
      return NextResponse.json({ error: 'lines[] is required' }, { status: 400 })
    }

    const normLines = lines.map((l: any, i: number) => ({
      sku: l?.sku ?? null,
      productId: l?.productId ?? null,
      name: String(l?.name ?? ''),
      qty: Number(l?.qty ?? 1) || 1,
      price: Number(l?.price ?? 0) || 0,
      rowTotal: (Number(l?.qty ?? 1) || 1) * (Number(l?.price ?? 0) || 0),
      i,
    }))

    const id = `ORD-${Date.now()}`
    const payload = {
      id,
      increment_id: id,
      status: 'new',
      created_at: new Date().toISOString(),
      customer: customer ?? null,
      lines: normLines,
      notes: notes ?? null,
      elapsed_ms: Date.now() - t0,
      source: 'local-stub',
    }
    STUBS.set(id, payload)
    return NextResponse.json(payload, { status: 201 })
  } catch (err: any) {
    console.error('[POST /api/orders] 500', err?.stack || err)
    return NextResponse.json({ error: 'Internal error', detail: String(err?.message || err) }, { status: 500 })
  }
}
TS

# Skriv /api/orders/[id]/route.ts  (stub → direkte, ellers Magento)
cat > "$FILE_ID" <<'TS'
import { NextResponse } from 'next/server'

const M2_BASE = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN

const STUBS = (globalThis as any).__ORD_STUBS__ ||= new Map<string, any>()

async function m2Get<T>(path: string): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('missing env MAGENTO_BASE_URL/MAGENTO_ADMIN_TOKEN')
  const url = `${M2_BASE.replace(/\/+$/,'')}/${path.replace(/^\/+/,'')}`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${M2_TOKEN}` }, cache: 'no-store' })
  if (!res.ok) {
    const txt = await res.text().catch(()=>'')
    throw new Error(`Magento GET ${url} failed: ${res.status} ${txt}`)
  }
  return await res.json()
}

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctx.params
    // Stub?
    if (id.startsWith('ORD-') && STUBS.has(id)) {
      return NextResponse.json(STUBS.get(id), { status: 200 })
    }

    // Magento: prøv direkte V1/orders/{id} (entity_id),
    // hvis ikke, gjør søk på increment_id lik id
    let data: any = null
    const tryDirect = await m2Get<any>(`V1/orders/${encodeURIComponent(id)}`).catch(()=>null)
    if (tryDirect && tryDirect?.entity_id) data = tryDirect
    if (!data) {
      const raw = await m2Get<any>(`V1/orders?searchCriteria[filter_groups][0][filters][0][field]=increment_id&searchCriteria[filter_groups][0][filters][0][value]=${encodeURIComponent(id)}&searchCriteria[filter_groups][0][filters][0][condition_type]=eq`)
      const items = Array.isArray(raw?.items) ? raw.items : []
      data = items[0] || null
    }
    if (!data) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    return NextResponse.json(data, { status: 200 })
  } catch (err: any) {
    console.error('[GET /api/orders/[id]] 500', err?.stack || err)
    return NextResponse.json({ error: 'Internal error', detail: String(err?.message || err) }, { status: 500 })
  }
}
TS

echo "→ Rydder .next cache"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true
echo "✓ Ferdig. Restart dev (npm run dev / yarn dev / pnpm dev)."
