#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"

# 1) lib/env.ts – ESM, enkel config + v1() + admin-jwt
mkdir -p "$root/lib"
cat > "$root/lib/env.ts" <<'TS'
export function getMagentoConfig() {
  return {
    baseUrl: (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/rest\/?$/,'/rest'),
    adminUser: process.env.MAGENTO_ADMIN_USERNAME || '',
    adminPass: process.env.MAGENTO_ADMIN_PASSWORD || '',
  };
}
export const v1 = (baseUrl: string) => `${baseUrl.replace(/\/$/, '')}/V1`;

export async function getAdminToken(baseUrl: string, user: string, pass: string): Promise<string> {
  if (!baseUrl || !user || !pass) throw new Error('Missing Magento admin creds or baseUrl');
  const res = await fetch(`${v1(baseUrl)}/integration/admin/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: user, password: pass }),
    cache: 'no-store',
  });
  if (!res.ok) {
    const txt = await res.text().catch(()=>res.statusText);
    throw new Error(`Admin token ${res.status}: ${txt}`);
  }
  // Magento returns a JSON string (the token)
  const token = await res.json();
  if (typeof token !== 'string' || !token) throw new Error('Empty admin token');
  return token;
}
TS

# 2) /api/products/update-attributes – PUT via admin JWT (ESM safe)
mkdir -p "$root/app/api/products/update-attributes"
cat > "$root/app/api/products/update-attributes/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type AttrMap = Record<string,string|number|null|undefined>

export async function PATCH(req: Request) {
  try {
    const { sku, attributes } = await req.json() as { sku?: string, attributes?: AttrMap }
    if (!sku || !attributes || typeof attributes !== 'object') {
      return NextResponse.json({ error: 'Bad request: need { sku, attributes }' }, { status: 400 })
    }

    const cfg = getMagentoConfig()
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)

    // Convert to Magento custom_attributes[]
    const custom_attributes = Object.entries(attributes)
      .filter(([_,v]) => v !== undefined)
      .map(([attribute_code, value]) => ({ attribute_code, value: String(value ?? '') }))

    const res = await fetch(`${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ product: { sku, custom_attributes }, saveOptions: true }),
      cache: 'no-store',
    })

    const text = await res.text()
    let json: any = null
    try { json = text ? JSON.parse(text) : null } catch { /* keep raw text */ }

    if (!res.ok) {
      return NextResponse.json({ error: `Magento PUT ${res.status}`, magento: json ?? text }, { status: 500 })
    }
    return NextResponse.json({ success: true, magento: json ?? { ok: true } })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unhandled' }, { status: 500 })
  }
}
TS

# 3) /api/products/[sku] – GET + lift/alias (ESM, no require)
mkdir -p "$root/app/api/products/[sku]"
cat > "$root/app/api/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string; custom_attributes?: CA[] | null }

const ALIASES = ['ibu','ibu2','srm','hop_index','malt_index'] as const

export async function GET(_: Request, ctx: { params: { sku: string } }) {
  const { sku } = ctx.params
  const cfg = getMagentoConfig()
  try {
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
    const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
    const text = await res.text()
    let data: M2Product = {}
    try { data = text ? JSON.parse(text) : {} } catch { /* keep {} */ }

    if (!res.ok) {
      return NextResponse.json({ error: `Magento GET ${res.status}`, detail: text }, { status: 500 })
    }

    const ca = Array.isArray(data?.custom_attributes) ? data!.custom_attributes! : []
    const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
    const lifted: Record<string, any> = {}
    for (const key of ALIASES) lifted[key] = attrs[key] ?? null
    // Prefer ibu if missing but ibu2 exists
    if (lifted['ibu'] == null && attrs['ibu2'] != null) lifted['ibu'] = attrs['ibu2']

    return NextResponse.json({ ...(data||{}), ...lifted, _attrs: attrs })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unhandled' }, { status: 500 })
  }
}
TS

# 4) /api/products/merged – list + lift (ESM, no require)
mkdir -p "$root/app/api/products/merged"
cat > "$root/app/api/products/merged/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string; custom_attributes?: CA[] | null }

const ALIASES = ['ibu','ibu2','srm','hop_index','malt_index'] as const

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')||1
  const size = Number(searchParams.get('size')||'50')||50
  const cfg = getMagentoConfig()

  try {
    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
    const url = `${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
    const text = await res.text()
    const data = text ? JSON.parse(text) : {}
    if (!res.ok) {
      return NextResponse.json({ error: `Magento GET ${res.status}`, detail: data ?? text }, { status: 500 })
    }

    const items: M2Product[] = Array.isArray(data?.items) ? data.items : []
    const lifted = items.map(p => {
      const ca = Array.isArray(p?.custom_attributes) ? p!.custom_attributes! : []
      const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
      const out: Record<string, any> = {}
      for (const k of ALIASES) out[k] = attrs[k] ?? null
      if (out['ibu'] == null && attrs['ibu2'] != null) out['ibu'] = attrs['ibu2']
      return { ...(p||{}), ...out, _attrs: attrs }
    })

    return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'Unhandled' }, { status: 500 })
  }
}
TS

echo "✓ Wrote ESM-safe env + API routes."
