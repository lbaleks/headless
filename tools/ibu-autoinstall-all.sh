#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# --- 0. Load env (strict) ---
ENV_FILE=".env.local"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Fant ikke $ENV_FILE"; exit 1
fi
eval "$(
  awk -F= '/^MAGENTO_/ && $2 {
    gsub(/\r/,"",$2); gsub(/^["'"'"']|["'"'"']$/,"",$2);
    printf("export %s=\"%s\"\n",$1,$2)
  }' "$ENV_FILE"
)"
echo "✅ Leste env fra: $(pwd)/$ENV_FILE"
echo "   MAGENTO_URL=$MAGENTO_URL"
echo "   Admin user: $([[ -n "${MAGENTO_ADMIN_USERNAME:-}" ]] && echo ja || echo nei)"
echo "   Admin pass: $([[ -n "${MAGENTO_ADMIN_PASSWORD:-}" ]] && echo ja || echo nei)"
echo "   Fast token: $([[ -n "${MAGENTO_TOKEN:-}" ]] && echo ja || echo nei)"

# --- 1. Ensure API routes with IBU fallback ---
mkdir -p app/api/products/[sku] app/api/products/merged
cat > app/api/products/[sku]/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

const IBU_ATTRS = ['ibu','ibu2']
type M2Product = { sku?: string; custom_attributes?: Array<{attribute_code:string,value:any}>|null }

export async function GET(_: Request, ctx: { params: { sku: string } }) {
  const { sku } = ctx.params
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
  const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) return NextResponse.json({ error:`Magento GET ${res.status}` },{status:500})
  const data: M2Product = await res.json().catch(()=>({}))
  const ca = Array.isArray(data?.custom_attributes) ? data.custom_attributes! : []
  const attrs = Object.fromEntries(ca.map(x=>[x.attribute_code,x.value]))
  const ibu = IBU_ATTRS.map(k=>attrs[k]).find(v=>v!=null) ?? null
  return NextResponse.json({ ...(data||{}), ibu, _attrs: attrs })
}
TS

cat > app/api/products/merged/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

const IBU_ATTRS = ['ibu','ibu2']
type M2Product = { sku?: string; custom_attributes?: Array<{attribute_code:string,value:any}>|null }

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')||1
  const size = Number(searchParams.get('size')||'50')||50
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
  const url = `${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`
  const res = await fetch(url,{headers:{Authorization:`Bearer ${jwt}`},cache:'no-store'})
  if(!res.ok)return NextResponse.json({error:`Magento GET ${res.status}`},{status:500})
  const data = await res.json().catch(()=>({}))
  const items: M2Product[] = Array.isArray(data?.items)?data.items:[]
  const lifted = items.map(p=>{
    const ca = Array.isArray(p?.custom_attributes)?p!.custom_attributes!:[]
    const attrs = Object.fromEntries(ca.map(x=>[x.attribute_code,x.value]))
    const ibu = IBU_ATTRS.map(k=>attrs[k]).find(v=>v!=null) ?? null
    return {...(p||{}),ibu,_attrs:attrs}
  })
  return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
}
TS
echo "🛠  Oppdatert API-ruter med IBU fallback"

# --- 2. Secure attributes + write + reindex/flush + smoke ---
V1="${MAGENTO_URL%/}/V1"
SKU="${1:-TEST-RED}"
VAL="${2:-37}"

echo "🔐 Henter admin-token…"
ADMIN_JWT="$(curl -sS -X POST "$V1/integration/admin/token" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"${MAGENTO_ADMIN_USERNAME:-}"'","password":"'"${MAGENTO_ADMIN_PASSWORD:-}"'"}' | tr -d '"')"
if [[ -z "$ADMIN_JWT" || "$ADMIN_JWT" == null ]]; then echo "❌ Fikk ikke token"; exit 1; fi
echo "✅ Admin-token klart"

ensure_attr() {
  local code="$1"
  echo "🔎 Sikrer attributt '$code'…"
  resp="$(curl -s -X GET "$V1/products/attributes/$code" -H "Authorization: Bearer $ADMIN_JWT")"
  if echo "$resp" | jq -e '.attribute_code' >/dev/null 2>&1; then
    echo "✓ Attributt '$code' finnes"; return
  fi
  echo "🧩 Lager attributt '$code'…"
  curl -s -X POST "$V1/products/attributes" \
    -H "Authorization: Bearer $ADMIN_JWT" -H 'Content-Type: application/json' \
    --data '{"attribute": {"attribute_code":"'"$code"'","frontend_input":"text","default_frontend_label":"'"$code"'","is_user_defined":true,"is_visible":true,"used_in_product_listing":1,"apply_to":[]}}' >/dev/null
}
ensure_attr ibu
ensure_attr ibu2

echo "✍️  Oppdaterer $SKU → ibu=$VAL, ibu2=$VAL"
curl -s -X PATCH "http://localhost:3000/api/products/update-attributes" \
  -H 'Content-Type: application/json' \
  -d '{"sku":"'"$SKU"'","attributes":{"ibu":"'"$VAL"'","ibu2":"'"$VAL"'"}}' | jq '.success' | grep -q true

echo "🧹 Reindex + flush"
tools/ibu-reindex-and-flush.sh >/dev/null || true

echo "🔎 GET single"
curl -s "http://localhost:3000/api/products/$SKU" | jq '{sku, ibu, _attrs:{ibu:._attrs.ibu, ibu2:._attrs.ibu2}}'
echo "🔎 GET merged"
curl -s "http://localhost:3000/api/products/merged?page=1&size=200" \
  | jq '.items[]? | select(.sku=="'"$SKU"'") | {sku, ibu, _attrs:{ibu:._attrs.ibu, ibu2:._attrs.ibu2}}'

echo "🎉 Ferdig – alt OK"
