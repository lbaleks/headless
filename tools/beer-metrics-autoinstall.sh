#!/usr/bin/env bash
set -euo pipefail

# ---------- Config / args ----------
SKU="${1:-TEST-RED}"
SRM_VAL="${2:-12}"       # farge (SRM)
HOP_IDX="${3:-75}"       # humle-indeks
MALT_IDX="${4:-55}"      # malt-/grain-indeks

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env.local"

if [[ ! -f "$ENV_FILE" ]]; then
  echo " Fant ikke .env.local i $ROOT"
  exit 1
fi

# Rens BOM/CR og eksporter MAGENTO_*
perl -CSDA -pe 's/\r//g; s/\x{FEFF}//g; s/\p{Cf}//g' -i "$ENV_FILE"
eval "$(
  awk -F= '/^MAGENTO_/ && $2 {
    gsub(/\r/,"",$2); gsub(/^["'"'"']|["'"'"']$/,"",$2);
    printf("export %s=\"%s\"\n",$1,$2)
  }' "$ENV_FILE"
)"
V1="${MAGENTO_URL%/}/V1"

echo " Leste env fra: $ENV_FILE"
echo "   MAGENTO_URL=$MAGENTO_URL"
echo "   Admin user: $([[ -n "${MAGENTO_ADMIN_USERNAME:-}" ]] && echo ja || echo nei)"
echo "   Admin pass: $([[ -n "${MAGENTO_ADMIN_PASSWORD:-}" ]] && echo ja || echo nei)"

need_admin() {
  if [[ -z "${MAGENTO_ADMIN_USERNAME:-}" || -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    echo " Denne installasjonen krever admin brukernavn/passord i .env.local"
    exit 1
  fi
}

# ---------- Helpers ----------
admin_jwt() {
  need_admin
  curl -sS -X POST "$V1/integration/admin/token" \
    -H 'Content-Type: application/json' \
    --data '{"username":"'"$MAGENTO_ADMIN_USERNAME"'","password":"'"$MAGENTO_ADMIN_PASSWORD"'"}' \
  | tr -d '"'
}

ensure_attr() {
  # $1=code  $2=label  $3=input  $4=backend_type  $5=JWT
  local code="$1" label="$2" input="${3:-text}" bt="${4:-varchar}" JWT="${5:-}"
  if [[ -z "$JWT" ]]; then echo " Missing JWT (ensure_attr)"; exit 1; fi

  if curl -sf -H "Authorization: Bearer $JWT" "$V1/products/attributes/$code" >/dev/null; then
    echo " Attributt '$code' finnes"
    return 0
  fi

  echo " Oppretter attributt '$code'"
  curl -sS -X POST "$V1/products/attributes" \
    -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
    --data '{
      "attribute": {
        "attribute_code": "'"$code"'",
        "default_frontend_label": "'"$label"'",
        "frontend_input": "'"$input"'",
        "backend_type": "'"$bt"'",
        "is_required": false,
        "is_user_defined": true,
        "is_unique": false,
        "is_visible": true,
        "is_searchable": false,
        "is_comparable": false,
        "used_in_product_listing": 1,
        "is_visible_on_front": 1,
        "apply_to": [],
        "frontend_labels": [{ "store_id": 0, "label": "'"$label"'" }]
      }
    }' >/dev/null
  echo " Opprettet '$code'"
}

assign_to_set() {
  # $1=code  $2=setId  $3=groupId  $4=sort  $5=JWT
  local code="$1"
  local setId="$2"
  local groupId="$3"
  local sort="${4:-10}"
  local JWT="${5:-}"
  if [[ -z "$JWT" ]]; then echo " Missing JWT (assign_to_set)"; exit 1; fi

  local exists
  exists="$(curl -sS -H "Authorization: Bearer $JWT" \
    "$V1/products/attribute-sets/$setId/attributes" \
    | jq -re '.[]?|select(.attribute_code=="'"$code"'")|1' || true)"
  if [[ "$exists" == "1" ]]; then
    echo " '$code' allerede tilordnet set=$setId"
    return 0
  fi

  echo " Tilordner '$code' til set=$setId group=$groupId"
  curl -sS -X POST "$V1/products/attribute-sets/attributes" \
    -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
    --data '{
      "attributeSetId": '"$setId"',
      "attributeGroupId": '"$groupId"',
      "attributeCode": "'"$code"'",
      "sortOrder": '"$sort"'
    }' >/dev/null
  echo " Tilordnet '$code'"
}

patch_product_attrs() {
  # $1=sku  $2=json { "a":"v", "b":"v2" }
  local sku="$1" kv_json="$2"
  curl -sS -X PATCH "http://localhost:3000/api/products/update-attributes" \
    -H 'Content-Type: application/json' \
    --data '{"sku":"'"$sku"'","attributes":'"$kv_json"'}' >/dev/null
}

reindex_flush() {
  if [[ -x "$ROOT/tools/ibu-reindex-and-flush.sh" ]]; then
    "$ROOT/tools/ibu-reindex-and-flush.sh" >/dev/null || true
  fi
}

patch_routes() {
  # Lft og speil flere felter (IBU/SRM/HOP/MALT) i bde single/merged
  cat > "$ROOT/tools/beer-routes-patch.sh" <<'RS'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

write_single() {
cat > "$ROOT/app/api/products/[sku]/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string|null; custom_attributes?: CA[]|null }

const ALIASES: Record<string,string[]> = {
  ibu: ['ibu','ibu2'],
  srm: ['srm','ebc'],
  hop_index: ['hop_index','hopint'],
  malt_index: ['malt_index','grain_index'],
}

function pickFirst(attrs: Record<string,any>, list: string[]) {
  for (const k of list) if (attrs[k] != null) return attrs[k]
  return null
}

export async function GET(_: Request, ctx: { params: { sku: string } }) {
  const { sku } = ctx.params
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)
  const url = `${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) {
    const err = await res.text().catch(()=>res.statusText)
    return NextResponse.json({ error: `Magento GET ${res.status}`, detail: err }, { status: 500 })
  }
  const data: M2Product = await res.json().catch(()=>({}))
  const ca = Array.isArray(data?.custom_attributes) ? data!.custom_attributes! : []
  const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))

  const ibu  = pickFirst(attrs, ALIASES.ibu)
  const srm  = pickFirst(attrs, ALIASES.srm)
  const hop  = pickFirst(attrs, ALIASES.hop_index)
  const malt = pickFirst(attrs, ALIASES.malt_index)

  return NextResponse.json({ ...(data||{}), ibu, srm, hop_index: hop, malt_index: malt, _attrs: attrs })
}
TS
}

write_merged() {
cat > "$ROOT/app/api/products/merged/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { getMagentoConfig, v1, getAdminToken } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0

type CA = { attribute_code: string; value: any }
type M2Product = { sku?: string|null; custom_attributes?: CA[]|null }

const ALIASES: Record<string,string[]> = {
  ibu: ['ibu','ibu2'],
  srm: ['srm','ebc'],
  hop_index: ['hop_index','hopint'],
  malt_index: ['malt_index','grain_index'],
}

function pickFirst(attrs: Record<string,any>, list: string[]) {
  for (const k of list) if (attrs[k] != null) return attrs[k]
  return null
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')||1
  const size = Number(searchParams.get('size')||'50')||50
  const cfg = getMagentoConfig()
  const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass)

  const url = `${v1(cfg.baseUrl)}/products?searchCriteria[current_page]=${page}&searchCriteria[page_size]=${size}&storeId=0`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` }, cache: 'no-store' })
  if (!res.ok) {
    const err = await res.text().catch(()=>res.statusText)
    return NextResponse.json({ error: `Magento GET ${res.status}`, detail: err }, { status: 500 })
  }

  const data = await res.json().catch(()=>({}))
  const items: M2Product[] = Array.isArray(data?.items) ? data.items : []

  const lifted = items.map(p => {
    const ca = Array.isArray(p?.custom_attributes) ? p!.custom_attributes! : []
    const attrs = Object.fromEntries(ca.filter(Boolean).map(x => [x.attribute_code, x.value]))
    const ibu  = pickFirst(attrs, ALIASES.ibu)
    const srm  = pickFirst(attrs, ALIASES.srm)
    const hop  = pickFirst(attrs, ALIASES.hop_index)
    const malt = pickFirst(attrs, ALIASES.malt_index)
    return { ...(p||{}), ibu, srm, hop_index: hop, malt_index: malt, _attrs: attrs }
  })

  return NextResponse.json({ items: lifted, page, size, total: data?.total_count ?? lifted.length })
}
TS
}

write_single
write_merged
echo " Patchet /api/products/[sku] og /merged (lfter ibu/srm/hop_index/malt_index)"
RS
  bash "$ROOT/tools/beer-routes-patch.sh"
}

smoke() {
  echo " Smoke:"
  echo "  PATCH -> SRM=$SRM_VAL HOP=$HOP_IDX MALT=$MALT_IDX"
  patch_product_attrs "$SKU" '{"srm":"'"$SRM_VAL"'","hop_index":"'"$HOP_IDX"'","malt_index":"'"$MALT_IDX"'"}'
  reindex_flush
  echo "  GET single:"
  curl -s "http://localhost:3000/api/products/$SKU" | jq '{sku, ibu, srm, hop_index, malt_index, _attrs:{ibu:._attrs.ibu, srm:._attrs.srm, hop_index:._attrs.hop_index, malt_index:._attrs.malt_index}}'
  echo "  GET merged:"
  curl -s "http://localhost:3000/api/products/merged?page=1&size=200" \
    | jq '.items[]? | select(.sku=="'"$SKU"'") | {sku, ibu, srm, hop_index, malt_index, _attrs:{ibu:._attrs.ibu, srm:._attrs.srm, hop_index:._attrs.hop_index, malt_index:._attrs.malt_index}}'
}

# ---------- Run ----------
echo " Henter admin-token"
JWT="$(admin_jwt)"
echo " Admin-token klart"

echo "  Ensure attributter (srm, hop_index, malt_index)"
ensure_attr "srm"        "SRM"        "text" "varchar" "$JWT"
ensure_attr "hop_index"  "Hop Index"  "text" "varchar" "$JWT"
ensure_attr "malt_index" "Malt Index" "text" "varchar" "$JWT"

# Standard sett/gruppe (samme som IBU): setId=4, groupId=20
assign_to_set "srm"        4 20 12 "$JWT"
assign_to_set "hop_index"  4 20 13 "$JWT"
assign_to_set "malt_index" 4 20 14 "$JWT"
echo " Attributter klare"

echo "  Skriver testverdier via app-route"
patch_product_attrs "$SKU" '{"srm":"'"$SRM_VAL"'","hop_index":"'"$HOP_IDX"'","malt_index":"'"$MALT_IDX"'"}'
reindex_flush

echo " Patcher API-ruter (lfting + aliaser)"
patch_routes

smoke
echo " Ferdig."
