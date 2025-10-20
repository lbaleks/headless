#!/bin/bash
set -euo pipefail

echo "🔧 Installing runtime env loader + patching product routes"

mkdir -p lib app/api/products/[sku] app/api/products/update-attributes

# 1) lib/env.ts – manuell env-loader + token-henter
cat > lib/env.ts <<'TS'
// lib/env.ts
// Runtime loader for env + Magento token fetch with in-memory cache.
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'

export type MagentoConfig = {
  baseUrl: string // normalized base like https://host/rest/V1
  rawBase: string // as-provided base (may include /rest)
  token: string
}

function parseDotenvFile(p: string): Record<string,string> {
  try {
    if (!existsSync(p)) return {}
    const txt = readFileSync(p, 'utf8')
    const obj: Record<string,string> = {}
    for (const line of txt.split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/)
      if (!m) continue
      let [, key, val] = m
      // strip surrounding quotes
      val = val.replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1')
      obj[key] = val
    }
    return obj
  } catch {
    return {}
  }
}

function loadEnvFromFiles(): Record<string,string> {
  const root = process.cwd()
  const envLocal = parseDotenvFile(resolve(root, '.env.local'))
  const envBase  = parseDotenvFile(resolve(root, '.env'))
  // priority: process.env > .env.local > .env
  return { ...envBase, ...envLocal, ...process.env as any }
}

function normalizeBase(input: string): { rawBase:string; baseV1:string } {
  let b = (input || '').trim()
  // Remove trailing slashes
  b = b.replace(/\/+$/, '')
  // Already has /rest or /rest/V1?
  if (/\/rest(\/v1|\/V1)?$/i.test(b)) {
    // ensure V1 suffix
    if (/\/rest$/i.test(b)) return { rawBase: b, baseV1: b + '/V1' }
    // already /rest/V1
    return { rawBase: b, baseV1: b }
  }
  // no /rest segment -> add it
  return { rawBase: b, baseV1: b + '/rest/V1' }
}

function joinMagento(baseV1: string, path: string): string {
  const b = baseV1.replace(/\/+$/, '')
  const p = (path || '').replace(/^\/+/, '')
  return b + '/' + p
}

declare global {
  // eslint-disable-next-line no-var
  var __MAGENTO_TOKEN_CACHE: string | undefined
}

async function fetchAdminToken(baseV1: string, username: string, password: string): Promise<string> {
  const url = joinMagento(baseV1, 'integration/admin/token')
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    // Magento krever JSON body: { username, password }
    body: JSON.stringify({ username, password }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Token fetch failed ${res.status}: ${text}`)
  }
  const token = await res.json()
  if (typeof token !== 'string' || !token) {
    throw new Error('Token response invalid')
  }
  return token
}

export async function getMagentoConfig(): Promise<MagentoConfig> {
  const env = loadEnvFromFiles()
  const { rawBase, baseV1 } = normalizeBase(env.MAGENTO_URL || env.MAGENTO_BASE_URL || '')
  let token = env.MAGENTO_TOKEN || env.MAGENTO_ADMIN_TOKEN || ''

  if (!rawBase) {
    throw new Error('MAGENTO_URL/MAGENTO_BASE_URL is missing (env)')
  }

  // Use cached token if available and no explicit env token provided
  if (!token && globalThis.__MAGENTO_TOKEN_CACHE) {
    token = globalThis.__MAGENTO_TOKEN_CACHE
  }

  if (!token) {
    const u = env.MAGENTO_ADMIN_USERNAME || ''
    const p = env.MAGENTO_ADMIN_PASSWORD || ''
    if (!u || !p) {
      throw new Error('Missing MAGENTO_TOKEN and admin credentials (MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD)')
    }
    token = await fetchAdminToken(baseV1, u, p)
    globalThis.__MAGENTO_TOKEN_CACHE = token
  }

  return { baseUrl: baseV1, rawBase, token }
}

export function magentoUrl(baseV1: string, path: string): string {
  return baseV1.replace(/\/+$/, '') + '/' + path.replace(/^\/+/, '')
}
TS

# 2) Patch product update route to use env loader
cat > app/api/products/update-attributes/route.ts <<'TS'
// app/api/products/update-attributes/route.ts
import { NextResponse } from 'next/server'
import { revalidateTag } from 'next/cache'
import { getMagentoConfig, magentoUrl } from '@/lib/env'

export const runtime = 'nodejs'

type UpdatePayload = {
  sku: string
  attributes: Record<string, any>
}

async function handleUpdate(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload
    if (!body || !body.sku || !body.attributes) {
      return NextResponse.json({ error: 'Missing "sku" or "attributes" in body' }, { status: 400 })
    }

    const { baseUrl, token } = await getMagentoConfig()
    const url = magentoUrl(baseUrl, 'products/' + encodeURIComponent(body.sku))

    const result = await fetch(url, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + token,
      },
      // inkluder sku i product-body
      body: JSON.stringify({ product: { sku: body.sku, ...body.attributes } }),
    })

    if (!result.ok) {
      const text = await result.text()
      return NextResponse.json({ error: 'Magento update failed', detail: text, url }, { status: result.status || 500 })
    }

    try { revalidateTag('products') } catch {}
    try { revalidateTag('product:' + body.sku) } catch {}
    try { revalidateTag('completeness:' + body.sku) } catch {}

    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: 'Update attributes failed', detail: String(e?.message || e) }, { status: 500 })
  }
}

export async function PATCH(req: Request) { return handleUpdate(req) }
export async function POST(req: Request)  { return handleUpdate(req) }
TS

# 3) Patch product GET by SKU to use env loader
cat > app/api/products/[sku]/route.ts <<'TS'
// app/api/products/[sku]/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '@/lib/env'

export const runtime = 'nodejs'

export async function GET(_req: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params
    const { baseUrl, token } = await getMagentoConfig()
    const url = magentoUrl(baseUrl, 'products/' + encodeURIComponent(sku))

    const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token } })
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

echo "✅ env loader installed and routes patched."
echo "➡ Restart dev: pnpm dev"
echo "➡ Then check:  http://localhost:3000/api/env/check  (should still work)"
echo "➡ Test:        curl -i http://localhost:3000/api/products/<REAL_SKU>   # use real SKU (no angle brackets)"
echo "➡ Update:      curl -i -X PATCH http://localhost:3000/api/products/update-attributes -H 'Content-Type: application/json' -d '{\"sku\":\"<REAL_SKU>\",\"attributes\":{\"name\":\"HealthCheck\"}}'"