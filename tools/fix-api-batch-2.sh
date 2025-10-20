#!/bin/bash
set -euo pipefail

echo "🧭 Litebrygg – API batch 2 (Magento URL fix, products proxy, customers save, NOW cleanup)"

ROOT="$(pwd)"

# 0) Fjern duplikate NOW-linjer i kunder (sikkerhetsrydding)
if [ -d "app/admin/customers" ]; then
  grep -rl "const NOW = NOW" app/admin/customers 2>/dev/null | while read -r file; do
    echo "🧹 Rydder duplikate NOW i $file"
    sed -i.bak '/const NOW = NOW/d' "$file"
  done
fi

mkdir -p app/api/products/[sku] app/api/products/update-attributes app/api/customers/[id]

###############################################
# 1) PRODUCTS UPDATE (PATCH/POST) – trygg URL-join, inkluder sku i body, revalidate
###############################################
cat > app/api/products/update-attributes/route.ts <<'TS'
// app/api/products/update-attributes/route.ts
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'

export const runtime = 'nodejs'

type UpdatePayload = {
  sku: string
  attributes: Record<string, any>
}

function joinMagento(base: string, path: string): string {
  // Normaliserer base (fjerner trailing slashes)
  let b = (base || '').replace(/\/+$/, '')
  const p = (path || '').replace(/^\/+/, '')

  // Hvis base allerede slutter med /rest eller /rest/V1, ikke legg til en ny /rest
  if (/\/rest(\/v1|\/V1)?$/i.test(b)) {
    if (/^v1\//i.test(p)) return b + '/' + p.replace(/^v1\//i, 'V1/')
    return b + '/V1/' + p
  }
  // Base uten /rest → legg til /rest/V1
  if (/^v1\//i.test(p)) return b + '/rest/' + p.replace(/^v1\//i, 'V1/')
  return b + '/rest/V1/' + p
}

async function handleUpdate(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload
    if (!body || !body.sku || !body.attributes) {
      return NextResponse.json(
        { error: 'Missing "sku" or "attributes" in body' },
        { status: 400 },
      )
    }

    const magentoUrl = process.env.MAGENTO_URL || ''
    const magentoToken = process.env.MAGENTO_TOKEN || ''
    if (!magentoUrl || !magentoToken) {
      return NextResponse.json(
        { error: 'Missing MAGENTO_URL or MAGENTO_TOKEN env vars' },
        { status: 500 },
      )
    }

    const url = joinMagento(magentoUrl, 'products/' + encodeURIComponent(body.sku))

    const result = await fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + magentoToken,
      },
      // Inkluder sku i product-body for Magento-kompatibilitet
      body: JSON.stringify({ product: { sku: body.sku, ...body.attributes } }),
    })

    if (!result.ok) {
      const text = await result.text()
      return NextResponse.json(
        { error: 'Magento update failed', detail: text, url },
        { status: result.status || 500 },
      )
    }

    // Revalidate bredt + SKU-spesifikt
    try { revalidateTag('products') } catch {}
    try { revalidateTag('product:' + body.sku) } catch {}
    try { revalidateTag('completeness:' + body.sku) } catch {}

    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json(
      { error: 'Update attributes failed', detail: String(e?.message || e) },
      { status: 500 },
    )
  }
}

export async function PATCH(req: Request) { return handleUpdate(req) }
export async function POST(req: Request)  { return handleUpdate(req) }
TS

###############################################
# 2) PRODUCTS BY SKU (GET) – proxy til Magento, korrekt await på ctx.params
###############################################
cat > app/api/products/[sku]/route.ts <<'TS'
// app/api/products/[sku]/route.ts
import { NextResponse } from 'next/server'

export const runtime = 'nodejs'

function joinMagento(base: string, path: string): string {
  let b = (base || '').replace(/\/+$/, '')
  const p = (path || '').replace(/^\/+/, '')
  if (/\/rest(\/v1|\/V1)?$/i.test(b)) {
    if (/^v1\//i.test(p)) return b + '/' + p.replace(/^v1\//i, 'V1/')
    return b + '/V1/' + p
  }
  if (/^v1\//i.test(p)) return b + '/rest/' + p.replace(/^v1\//i, 'V1/')
  return b + '/rest/V1/' + p
}

export async function GET(_req: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params
    const magentoUrl = process.env.MAGENTO_URL || ''
    const magentoToken = process.env.MAGENTO_TOKEN || ''
    if (!magentoUrl || !magentoToken) {
      return NextResponse.json({ error: 'Missing MAGENTO_URL or MAGENTO_TOKEN' }, { status: 500 })
    }

    const url = joinMagento(magentoUrl, 'products/' + encodeURIComponent(sku))
    const res = await fetch(url, {
      headers: { Authorization: 'Bearer ' + magentoToken }
    })

    if (!res.ok) {
      const text = await res.text()
      return NextResponse.json({ error: 'Magento fetch failed', detail: text, url }, { status: res.status })
    }

    const data = await res.json()
    return NextResponse.json(data)
  } catch (e: any) {
    return NextResponse.json({ error: 'Product GET failed', detail: String(e?.message || e) }, { status: 500 })
  }
}
TS

###############################################
# 3) CUSTOMERS BY ID – await params + PUT/PATCH med enkel dev-lagring
###############################################
cat > app/api/customers/[id]/route.ts <<'TS'
// app/api/customers/[id]/route.ts
import { NextResponse } from 'next/server'
import { readFile, writeFile, mkdir } from 'fs/promises'
import { dirname } from 'path'

export const runtime = 'nodejs'

// Enkel dev-lagring lokalt. Sett egen sti via DEV_CUSTOMERS_FILE om ønskelig.
const FILE = process.env.DEV_CUSTOMERS_FILE || 'data/dev/customers.json'

async function readDev(): Promise<any[]> {
  try {
    const buf = await readFile(FILE)
    return JSON.parse(String(buf))
  } catch {
    return []
  }
}

async function writeDev(all: any[]) {
  await mkdir(dirname(FILE), { recursive: true })
  await writeFile(FILE, JSON.stringify(all, null, 2))
}

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctx.params
    const all = await readDev()
    const found = all.find(c => String(c.id) === String(id)) || null
    if (!found) return NextResponse.json({ ok: false, error: 'Not found' }, { status: 404 })
    return NextResponse.json(found)
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: String(e?.message || e) }, { status: 500 })
  }
}

async function handleUpdate(req: Request, ctx: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await ctx.params
    const patch = await req.json()

    const all = await readDev()
    const idx = all.findIndex(c => String(c.id) === String(id))
    if (idx === -1) return NextResponse.json({ ok: false, error: 'Not found' }, { status: 404 })

    const updated = { ...all[idx], ...patch }
    all[idx] = updated
    await writeDev(all)

    return NextResponse.json({ ok: true, customer: updated })
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: String(e?.message || e) }, { status: 500 })
  }
}

export async function PATCH(req: Request, ctx: { params: Promise<{ id: string }> }) {
  return handleUpdate(req, ctx)
}

export async function PUT(req: Request, ctx: { params: Promise<{ id: string }> }) {
  // Tillat PUT ved å bruke samme logikk som PATCH
  return handleUpdate(req, ctx)
}
TS

# 4) Fjern eventuelle backup-filer
find app -name "*.bak" -delete || true

echo "✅ Batch 2 ferdig. Tips:"
echo "1) Sørg for at .env.local har MAGENTO_URL og MAGENTO_TOKEN satt."
echo "   - MAGENTO_URL kan være med eller uten '/rest'. Koden håndterer begge."
echo "2) Start server på nytt: pnpm dev"