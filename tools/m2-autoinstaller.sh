#!/usr/bin/env bash
set -euo pipefail

# ---------- utils ----------
normalize_text() { perl -CSDA -pe 's/\r//g; s/\x{FEFF}//g; s/\p{Cf}//g'; }
here() { cat <<'EOF'
EOF
}
say() { printf "%b\n" "$*"; }
fail() { printf "❌ %s\n" "$*\n" >&2; exit 1; }
ok() { printf "✓ %s\n" "$*\n"; }

export LANG=C.UTF-8 LC_ALL=C.UTF-8

# ---------- env ----------
ROOT="$(pwd)"
mkdir -p "$ROOT/tools" "$ROOT/app/api/debug/env/magento" "$ROOT/app/api/products/update-attributes" "$ROOT/app/api/products/[sku]" "$ROOT/app/api/products/merged" "$ROOT/lib"

# ensure .env.local exists
touch "$ROOT/.env.local"

# write lib/env.ts
cat > "$ROOT/lib/env.ts" <<'TS' 
export type MagentoEnv = {
  baseUrl: string
  token?: string
  adminUser?: string
  adminPass?: string
  preferAdminToken?: boolean
}
export function getMagentoConfig(): MagentoEnv {
  const rawBase = process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || ''
  if (!rawBase) throw new Error('Missing MAGENTO_URL/MAGENTO_BASE_URL')
  const baseUrl = rawBase.replace(/\/+$/,'')
  const token = process.env.MAGENTO_TOKEN || ''
  const adminUser = process.env.MAGENTO_ADMIN_USERNAME || ''
  const adminPass = process.env.MAGENTO_ADMIN_PASSWORD || ''
  const preferAdminToken = (process.env.MAGENTO_PREFER_ADMIN_TOKEN || '0') !== '0'
  return { baseUrl, token, adminUser, adminPass, preferAdminToken }
}
export async function getAdminToken(baseUrl: string, user: string, pass: string) {
  if (!user || !pass) throw new Error('Missing admin creds')
  const url = `${baseUrl}/V1/integration/admin/token`
  const res = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ username:user, password:pass }) })
  if (!res.ok) throw new Error(`Admin token failed: ${res.status}`)
  const t = await res.json()
  // Magento returnerer raw string
  return typeof t === 'string' ? t : String(t)
}
export function v1(baseUrl: string) {
  const b = baseUrl.replace(/\/+$/,'')
  return `${b}/V1`
}
TS
ok "skrev lib/env.ts"

# tsconfig alias
if [ -f "$ROOT/tsconfig.json" ]; then
  node <<'NODE'
const fs=require('fs');const p='tsconfig.json';
const j=JSON.parse(fs.readFileSync(p,'utf8')); j.compilerOptions=j.compilerOptions||{};
j.compilerOptions.baseUrl=j.compilerOptions.baseUrl||'.';
j.compilerOptions.paths=j.compilerOptions.paths||{};
j.compilerOptions.paths['@/*']=j.compilerOptions.paths['@/*']||['./*'];
fs.writeFileSync(p,JSON.stringify(j,null,2));
NODE
  ok "tsconfig alias @/*"
fi

# ---------- /api/debug/env/magento ----------
cat > "$ROOT/app/api/debug/env/magento/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0
export async function GET() {
  try {
    const cfg = getMagentoConfig()
    return NextResponse.json({
      ok: true,
      MAGENTO_URL_preview: cfg.baseUrl.replace(/\/V1$/,'').replace(/\/rest$/,'/rest'),
      MAGENTO_TOKEN_masked: cfg.token ? cfg.token.slice(0,3)+'…'+cfg.token.slice(-3) : '<empty>',
      hasAdminCreds: !!(cfg.adminUser && cfg.adminPass)
    })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e.message }, { status: 500 })
  }
}
TS
ok "skrev /api/debug/env/magento"

# ---------- /api/products/update-attributes ----------
cat > "$ROOT/app/api/products/update-attributes/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0
type UpdatePayload = { sku: string; attributes: Record<string,string|number|null> }
export async function PATCH(req: Request) {
  try {
    const body = await req.json() as UpdatePayload
    const sku = String(body.sku || '').trim()
    const attrs = body.attributes || {}
    if (!sku || !attrs || !Object.keys(attrs).length) {
      return NextResponse.json({ error:'Missing sku/attributes' }, { status:400 })
    }
    const cfg = getMagentoConfig()
    const base = v1(cfg.baseUrl)

    // auth mode
    const forceAdmin = req.headers.get('x-magento-auth') === 'admin'
    let bearer = ''
    if (!forceAdmin && cfg.token) {
      bearer = `Bearer ${cfg.token}`
    } else {
      const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser||'', cfg.adminPass||'')
      bearer = `Bearer ${jwt}`
    }

    // build custom_attributes
    const custom_attributes = Object.entries(attrs).map(([k,v]) => ({
      attribute_code: String(k),
      value: v==null ? '' : String(v)
    }))

    // Try primary PUT
    const res = await fetch(`${base}/products/${encodeURIComponent(sku)}`,{
      method:'PUT',
      headers:{ 'Authorization': bearer, 'Content-Type':'application/json' },
      body: JSON.stringify({ product:{ sku, custom_attributes }})
    })

    if (!res.ok) {
      const txt = await res.text()
      return NextResponse.json({ error:'Magento update failed', detail: { status:res.status, body:txt }}, { status: 400 })
    }

    return NextResponse.json({ success:true })
  } catch (e:any) {
    return NextResponse.json({ error:e.message }, { status:500 })
  }
}
TS
ok "skrev /api/products/update-attributes"

# ---------- /api/products/[sku] ----------
cat > "$ROOT/app/api/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

export async function GET(_: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params // Next 15 krever await
    const cfg = getMagentoConfig()
    const base = v1(cfg.baseUrl)

    // Bruk admin-token hvis ikke vanlig token finnes
    let bearer = ''
    if (cfg.token) bearer = `Bearer ${cfg.token}`
    else {
      const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser||'', cfg.adminPass||'')
      bearer = `Bearer ${jwt}`
    }

    const res = await fetch(`${base}/products/${encodeURIComponent(sku)}`, {
      headers: { 'Authorization': bearer }
    })
    const data = await res.json()
    if (!res.ok) return NextResponse.json(data, { status: res.status })
    return NextResponse.json(data)
  } catch (e:any) {
    return NextResponse.json({ error: e.message }, { status: 500 })
  }
}
TS
ok "skrev /api/products/[sku]"

# ---------- /api/products/merged ----------
cat > "$ROOT/app/api/products/merged/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

export async function GET(req: Request) {
  try {
    const url = new URL(req.url)
    const page = Number(url.searchParams.get('page')||'1')
    const size = Number(url.searchParams.get('size')||'50')
    const cfg = getMagentoConfig()
    const base = v1(cfg.baseUrl)
    let bearer = ''
    if (cfg.token) bearer = `Bearer ${cfg.token}`
    else {
      const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser||'', cfg.adminPass||'')
      bearer = `Bearer ${jwt}`
    }

    // Enkel listing (juster til ditt eget endepunkt om du har annet søk)
    const res = await fetch(`${base}/products?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`, {
      headers: { 'Authorization': bearer }
    })
    const data = await res.json()
    if (!res.ok) return NextResponse.json(data, { status: res.status })

    const items = (data.items||[]).map((it:any) => {
      const map: Record<string, any> = {}
      for (const ca of it.custom_attributes||[]) {
        if (!ca?.attribute_code) continue
        map[ca.attribute_code] = ca.value
      }
      // løft IBU fra flere kandidater
      const ibuCand = map['ibu'] ?? map['cfg_ibu'] ?? map['akeneo_ibu'] ?? map['IBU'] ?? map['ibu_value'] ?? null
      return { ...it, ibu: ibuCand, _attrs: map }
    })
    return NextResponse.json({ items, total_count: data.total_count||items.length })
  } catch (e:any) {
    return NextResponse.json({ error:e.message }, { status:500 })
  }
}
TS
ok "skrev /api/products/merged"

# ---------- Ensure + Update IBU (CLI e2e) ----------
cat > "$ROOT/tools/ibu-ensure-and-update.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8
clean(){ perl -CSDA -pe 's/\r//g; s/\x{FEFF}//g; s/\p{Cf}//g; s/^\s+|\s+$//g'; }

SKU="$(printf '%s' "${1:-}" | clean)"
IBU_VAL="$(printf '%s' "${2:-}" | clean)"
[ -n "$SKU" ] || { echo "Usage: $0 <SKU> <IBU>"; exit 2; }
[ -n "$IBU_VAL" ] || { echo "Usage: $0 <SKU> <IBU>"; exit 2; }

BASE="${MAGENTO_URL:-${MAGENTO_BASE_URL:-}}"
[ -n "$BASE" ] || { echo "❌ Sett MAGENTO_URL eller MAGENTO_BASE_URL i .env.local"; exit 1; }
V1="${BASE%/}/V1"

# admin token
if [ -z "${MAGENTO_ADMIN_USERNAME:-}" ] || [ -z "${MAGENTO_ADMIN_PASSWORD:-}" ]; then
  echo "❌ Mangler MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD"; exit 1;
fi
ADMIN_JWT="$(curl -g -sS -X POST "$V1/integration/admin/token" -H 'Content-Type: application/json' \
  --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' | tr -d '"')"

echo "🔎 Sjekker/oppretter attributt 'ibu'…"
CREATE_RES="$(
  curl -g -sS -X POST "$V1/products/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
    --data @- <<JSON
{ "attribute": {
    "attribute_code":"ibu","frontend_input":"text","is_required":false,
    "is_user_defined":true,"default_frontend_label":"IBU","is_unique":false,
    "is_global":1
} }
JSON
)"
# Ignorer “already exists”
echo "$CREATE_RES" | jq -e 'if type=="object" and (.attribute_id? or .message?) then . else empty end' >/dev/null 2>&1 || true
echo "✓ Attributt ok"

SET_ID="$(curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" | jq -r '.attribute_set_id')"
[ -n "$SET_ID" ] && [ "$SET_ID" != "null" ] || { echo "❌ Fant ikke attribute_set_id for $SKU"; exit 1; }

GROUPS="$(curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" \
  "$V1/products/attribute-sets/groups/list?searchCriteria[filterGroups][0][filters][0][field]=attribute_set_id&searchCriteria[filterGroups][0][filters][0][value]=$SET_ID&searchCriteria[filterGroups][0][filters][0][condition_type]=eq&searchCriteria[pageSize]=200")"

GROUP_ID="$(
  echo "$GROUPS" | jq -r '
    if type=="number" then tostring
    elif type=="array" then
      (map(select((.attribute_group_name|tostring|ascii_downcase)=="general"))[0].attribute_group_id
       // .[0].attribute_group_id // empty)
    elif type=="object" then
      ((.items // []) as $a |
       ([$a[]? | select((.attribute_group_name|tostring|ascii_downcase)=="general")][0].attribute_group_id)
       // ($a[0]?.attribute_group_id) // empty)
    else empty end' | head -n1
)"
[ -n "$GROUP_ID" ] || { echo "❌ Fant ikke attribute_group_id for set=$SET_ID"; exit 1; }

# assign ibu to set/group (idempotent)
curl -g -sS -X POST "$V1/products/attribute-sets/attributes" \
  -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
  --data "{\"attributeSetId\":$SET_ID,\"attributeGroupId\":$GROUP_ID,\"attributeCode\":\"ibu\",\"sortOrder\":10}" \
| jq -r '.message? // "OK or already assigned"' >/dev/null 2>&1 || true

# update product
curl -g -sS -X PUT "$V1/products/$SKU" \
  -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
  --data "{\"product\":{\"sku\":\"$SKU\",\"custom_attributes\":[{\"attribute_code\":\"ibu\",\"value\":\"$IBU_VAL\"}]}}" >/dev/null

# verify
curl -g -sS -H "Authorization: Bearer $ADMIN_JWT" "$V1/products/$SKU" \
  | jq '.custom_attributes[]? | select(.attribute_code=="ibu")'
SH
chmod +x "$ROOT/tools/ibu-ensure-and-update.sh"
ok "skrev tools/ibu-ensure-and-update.sh"

say "🎉 Autoinstaller ferdig."
say "👉 Kjør:  tools/ibu-ensure-and-update.sh TEST-RED 37"