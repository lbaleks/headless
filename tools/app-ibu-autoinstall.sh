#!/usr/bin/env bash
set -euo pipefail

# --- config / paths
ROOT="$(pwd)"
API_DIR="$ROOT/app/api"
LIB_DIR="$ROOT/lib"
ENV_FILE="$LIB_DIR/env.ts"

mkdir -p "$API_DIR/debug/env/magento" "$API_DIR/products/update-attributes" "$API_DIR/products/[sku]" "$API_DIR/products/merged" "$LIB_DIR"

# --- write lib/env.ts
cat > "$ENV_FILE" <<'TS'
export type MagentoConfig = {
  baseUrl: string
  token?: string
  adminUser?: string
  adminPass?: string
}

export function v1(baseUrl: string) {
  const b = baseUrl.replace(/\/+$/, '')
  return `${b}/V1`
}

export function getMagentoConfig(): MagentoConfig {
  const baseRaw = process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || ''
  const token = process.env.MAGENTO_TOKEN || ''
  const adminUser = process.env.MAGENTO_ADMIN_USERNAME || ''
  const adminPass = process.env.MAGENTO_ADMIN_PASSWORD || ''
  return {
    baseUrl: baseRaw,
    token: token || undefined,
    adminUser: adminUser || undefined,
    adminPass: adminPass || undefined,
  }
}

export async function getAdminToken(baseUrl: string, user?: string, pass?: string) {
  if (!user || !pass) return null
  const res = await fetch(`${v1(baseUrl)}/integration/admin/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: user, password: pass }),
    cache: 'no-store',
  })
  if (!res.ok) return null
  const t = await res.text().catch(()=>'')
  return t.replace(/^"+|"+$/g,'') || null
}
TS

# --- tsconfig alias @/*
if [ -f "$ROOT/tsconfig.json" ]; then
  node - <<'JS' "$ROOT/tsconfig.json"
const fs=require('fs'); const p=process.argv[2];
const j=JSON.parse(fs.readFileSync(p,'utf8'));
j.compilerOptions ||= {};
j.compilerOptions.baseUrl = j.compilerOptions.baseUrl || ".";
j.compilerOptions.paths ||= {};
j.compilerOptions.paths["@/*"] = ["./*"];
fs.writeFileSync(p, JSON.stringify(j,null,2));
console.log("tsconfig alias ok");
JS
fi

# --- debug env route
cat > "$API_DIR/debug/env/magento/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0
export async function GET() {
  const cfg = getMagentoConfig()
  return NextResponse.json({
    ok: !!cfg.baseUrl,
    MAGENTO_URL_preview: cfg.baseUrl || null,
    MAGENTO_TOKEN_masked: cfg.token ? '***' : '<empty>',
    hasAdminCreds: !!(cfg.adminUser && cfg.adminPass),
  })
}
TS

# --- update-attributes route
cat > "$API_DIR/products/update-attributes/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type UpdatePayload = { sku: string; attributes: Record<string,string|number|null> }

export async function PATCH(req: Request) {
  try {
    const cfg = getMagentoConfig()
    if (!cfg.baseUrl) return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })

    const preferAdmin = (req.headers.get('x-magento-auth')||'').toLowerCase() === 'admin'
    let jwt = cfg.token || null
    if (!jwt && preferAdmin) {
      jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
      if (!jwt) return NextResponse.json({ error: 'Admin token failed (401)' }, { status: 500 })
    }
    if (!jwt) return NextResponse.json({ error: 'Missing Magento token' }, { status: 500 })

    const body = await req.json().catch(()=>null) as UpdatePayload|null
    const sku = body?.sku?.trim()
    const attributes = body?.attributes || {}
    if (!sku || !Object.keys(attributes).length) {
      return NextResponse.json({ error: 'Bad payload' }, { status: 400 })
    }

    // read attribute_set_id so Magento will actually persist custom_attributes
    const getRes = await fetch(`${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0&fields=attribute_set_id`, {
      headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store'
    })
    if (!getRes.ok) {
      const t = await getRes.text().catch(()=> '')
      return NextResponse.json({ error: `Magento GET ${getRes.status}`, body: t }, { status: 500 })
    }
    const { attribute_set_id } = await getRes.json() as { attribute_set_id?: number }
    if (!attribute_set_id) return NextResponse.json({ error: 'Missing attribute_set_id' }, { status: 500 })

    const custom_attributes = Object.entries(attributes).map(([attribute_code, value]) => ({ attribute_code, value }))

    const putUrl = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0&saveOptions=1`
    const putRes = await fetch(putUrl, {
      method: 'PUT',
      headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ product: { sku, attribute_set_id, custom_attributes } }),
      cache: 'no-store',
    })
    const magento = await putRes.json().catch(()=> ({}))
    if (!putRes.ok) return NextResponse.json({ error: `Magento PUT ${putRes.status}`, magento }, { status: 500 })

    return NextResponse.json({ success: true, magento })
  } catch (e:any) {
    return NextResponse.json({ error: e?.message || 'unknown' }, { status: 500 })
  }
}
TS

# --- products/[sku] route
cat > "$API_DIR/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type P = { params: Promise<{ sku: string }> }

export async function GET(_: Request, ctx: P) {
  try {
    const { sku } = await ctx.params
    const cfg = getMagentoConfig()
    if (!cfg.baseUrl) return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })

    let jwt = cfg.token || null
    if (!jwt && cfg.adminUser && cfg.adminPass) {
      jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
    }
    if (!jwt) return NextResponse.json({ error: 'Missing Magento token' }, { status: 500 })

    const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
    if (!res.ok) return NextResponse.json({ error: `Magento ${res.status}` }, { status: 500 })
    const data = await res.json()

    return NextResponse.json(data)
  } catch (e:any) {
    return NextResponse.json({ error: e?.message || 'unknown' }, { status: 500 })
  }
}
TS

# --- products/merged route (lift ibu and expose _attrs)
cat > "$API_DIR/products/merged/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

export async function GET(req: Request) {
  try {
    const cfg = getMagentoConfig()
    if (!cfg.baseUrl) return NextResponse.json({ error: 'Missing Magento baseUrl' }, { status: 500 })

    const urlObj = new URL(req.url)
    const page = Math.max(1, parseInt(urlObj.searchParams.get('page') || '1', 10))
    const size = Math.max(1, Math.min(200, parseInt(urlObj.searchParams.get('size') || '50', 10)))

    let jwt = cfg.token || null
    if (!jwt && cfg.adminUser && cfg.adminPass) {
      jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
    }
    if (!jwt) return NextResponse.json({ error: 'Missing Magento token' }, { status: 500 })

    const url = `${v1(cfg.baseUrl)}/products?storeId=0&searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`
    const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
    if (!res.ok) return NextResponse.json({ error: `Magento ${res.status}` }, { status: 500 })
    const data = await res.json().catch(()=> ({} as any))

    const items = Array.isArray(data?.items) ? data.items : []
    const lifted = items.map((p: any) => {
      const ca = Array.isArray(p?.custom_attributes) ? p.custom_attributes : []
      const caMap = Object.fromEntries(ca.filter((x:any)=>x && x.attribute_code).map((x:any)=>[x.attribute_code, x.value]))
      const ibu = caMap['ibu'] ?? null
      return { ...p, ibu, _attrs: caMap }
    })

    return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
  } catch (e:any) {
    return NextResponse.json({ error: e?.message || 'unknown' }, { status: 500 })
  }
}
TS

echo "OK"
