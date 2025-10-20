#!/usr/bin/env bash
# Autoinstaller: seed route for products, optional legacy DELETE seed,
# unique React key patch for customers page, Makefile + sync-all.
# Idempotent. Safe to re-run.

set -euo pipefail
export LC_ALL=C

say() { printf "→ %s\n" "$*"; }
ok()  { printf "  %s\n" "$*"; }
err() { printf "!! %s\n" "$*" >&2; }

need() { command -v "$1" >/dev/null || { err "Missing dependency: $1"; exit 1; }; }

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

need node; need npm; need jq

mkdir -p var app/api/products app/api/products/seed tools

# ---------- 1) /api/products/seed (POST) ----------
seed_route="app/api/products/seed/route.ts"
if [ ! -f "$seed_route" ]; then
  say "Installerer /api/products/seed (POST)…"
  cat > "$seed_route" <<'TS'
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function readStore(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}
async function writeStore(items:any[]) {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}
function mk(i:number, baseId:number){
  const now = Date.now()
  return {
    id: baseId + i,
    sku: `SEED-${now}-${i}`,
    name: `Seed Product ${i}`,
    type: 'simple',
    price: 199 + i,
    status: 1,
    visibility: 4,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    image: null,
    tax_class_id: '2',
    has_options: false,
    required_options: false,
    source: 'local-stub',
  }
}

export async function POST(req: Request) {
  const { searchParams } = new URL(req.url)
  const n = Math.max(1, Math.min(100, Number(searchParams.get('n') || 5)))
  const items = await readStore()
  const baseId = (items.reduce((m, p:any) => Math.max(m, Number(p?.id||0)), 0) || 0)
  for (let i = 1; i <= n; i++) items.unshift(mk(i, baseId))
  await writeStore(items)
  return NextResponse.json({ ok:true, total:n })
}
TS
  ok "Opprettet $seed_route"
else
  ok "$seed_route finnes – hopper over"
fi

# ---------- 2) Legacy: /api/products (DELETE ?action=seed) ----------
# Guard all names carefully to avoid set -u issues.
products_route="app/api/products/route.ts"
if [ -f "$products_route" ]; then
  if ! grep -q "export async function DELETE" "$products_route"; then
    say "Legger til DELETE-handler i $products_route…"
    cat >> "$products_route" <<'TS'

// --- Dev seed via DELETE /api/products?action=seed&n=5 ---
import fs from 'fs/promises'
import path from 'path'
const __DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')
async function __readStore(): Promise<any[]> {
  try {
    const txt = await fs.readFile(__DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}
async function __writeStore(items:any[]) {
  await fs.mkdir(path.dirname(__DEV_FILE), { recursive: true })
  await fs.writeFile(__DEV_FILE, JSON.stringify(items, null, 2))
}
function __mk(i:number, baseId:number){
  const now = Date.now()
  return {
    id: baseId + i,
    sku: `SEED-${now}-${i}`,
    name: `Seed Product ${i}`,
    type: 'simple',
    price: 199 + i,
    status: 1,
    visibility: 4,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    image: null,
    tax_class_id: '2',
    has_options: false,
    required_options: false,
    source: 'local-stub',
  }
}
export async function DELETE(req: Request) {
  const { searchParams } = new URL(req.url)
  if (searchParams.get('action') !== 'seed') {
    return NextResponse.json({ error: 'Not allowed' }, { status: 405 })
  }
  const n = Math.max(1, Math.min(100, Number(searchParams.get('n') || 5)))
  const items = await __readStore()
  const baseId = (items.reduce((m, p:any) => Math.max(m, Number(p?.id||0)), 0) || 0)
  for (let i = 1; i <= n; i++) items.unshift(__mk(i, baseId))
  await __writeStore(items)
  return NextResponse.json({ ok:true, total:n })
}
TS
    ok "DELETE-handler lagt til"
  else
    ok "DELETE-handler finnes allerede"
  fi
else
  ok "$products_route finnes ikke – hopper over legacy seed"
fi

# ---------- 3) Customers page: unik React key ----------
cust_page="app/admin/customers/page.tsx"
if [ -f "$cust_page" ]; then
  say "Patcher unik React key i $cust_page…"
  tmp="$(mktemp)"
  # <tr key={id || i} ...>  ->  key={`${
  #   (c as any).source ?? 'src'}:${id ?? c.email ?? ''}:${i}`}
  perl -0777 -pe "s/<tr\s+key=\{id\s*\|\|\s*i\}/<tr key={\`\${(c as any).source ?? 'src'}:\${id ?? (c as any).email ?? ''}:\${i}\`}/g" "$cust_page" > "$tmp" \
    && mv "$tmp" "$cust_page"
  ok "Key patch applied"
else
  ok "$cust_page ikke funnet – hopper over"
fi

# ---------- 4) Makefile ----------
say "Installerer/oppdaterer Makefile…"
cat > Makefile <<'MK'
BASE ?= http://localhost:3000
.PHONY: getp patchp clearp getc seedc cleanc geto1 getoQ geto patcho syncall

getp:
	curl -s "$(BASE)/api/products/$(SKU)" | jq .

patchp:
	@PRICE_JSON=$$( [ -n "$$PRICE" ] && printf '%s' "$$PRICE" || printf 'null' ); \
	 STATUS_JSON=$$( [ -n "$$STATUS" ] && printf '%s' "$$STATUS" || printf 'null' ); \
	 jq -n --arg name "$$NAME" \
	   --argjson price $$PRICE_JSON \
	   --argjson status $$STATUS_JSON \
	   '({} \
	      + (if $price  != null then {price:$price}   else {} end) \
	      + (if $status != null then {status:$status} else {} end) \
	      + (if $name   != ""   then {name:$name}     else {} end))' \
	| curl -s -X PATCH "$(BASE)/api/products/$(SKU)" -H 'content-type: application/json' --data-binary @- | jq .

clearp:
	@SKU="$(SKU)"; \
	F=var/products.dev.json; tmp=$$(mktemp); \
	if [ -f "$$F" ]; then \
	  jq --arg sku "$$SKU" \
	    '(if type=="array" then map(select(.sku|ascii_downcase != ($$sku|ascii_downcase))) \
	      elif type=="object" and .items then .items = (.items|map(select(.sku|ascii_downcase != ($$sku|ascii_downcase)))) \
	      else . end)' "$$F" > "$$tmp" && mv "$$tmp" "$$F"; \
	fi; \
	curl -s "$(BASE)/api/products/$$SKU" | jq '.sku,.price,.name,.source'

getc:
	curl -s "$(BASE)/api/customers?page=1&size=5" | jq .

seedc:
	curl -s -X DELETE "$(BASE)/api/customers?action=seed&n=$(N)" | jq .

cleanc:
	curl -s -X PATCH  "$(BASE)/api/customers/$(CID)" -H 'content-type: application/json' --data-binary '{"group_id":1,"is_subscribed":false}' | jq .

geto1:
	curl -s "$(BASE)/api/orders?page=1&size=1" | jq .

getoQ:
	curl -s "$(BASE)/api/orders?page=1&size=5&q=$(Q)" | jq .

geto:
	curl -s "$(BASE)/api/orders?page=1&size=5" | jq .

patcho:
	jq -n --arg status "$(STATUS)" '({} + (if $status != "" then {status:$status} else {} end))' \
	| curl -s -X PATCH "$(BASE)/api/orders/$(OID)" -H 'content-type: application/json' --data-binary @- | jq .

syncall:
	bash tools/sync-all.sh "$(BASE)" || true
MK
ok "Makefile skrevet"

# ---------- 5) tools/sync-all.sh ----------
sync_sh="tools/sync-all.sh"
cat > "$sync_sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://localhost:3000}"
echo "→ Sync products…"
curl -s -X POST "$BASE/api/products/sync" | jq .
echo "→ Sync customers…"
curl -s -X POST "$BASE/api/customers/sync" | jq .
echo "→ Sync orders…"
curl -s -X POST "$BASE/api/orders/sync" | jq .
echo "→ Totals:"
printf "  products: %s\n" "$(curl -s "$BASE/api/products?page=1&size=1"  | jq -r '.total // 0')"
printf "  customers: %s\n" "$(curl -s "$BASE/api/customers?page=1&size=1" | jq -r '.total // 0')"
printf "  orders:   %s\n" "$(curl -s "$BASE/api/orders?page=1&size=1"    | jq -r '.total // 0')"
BASH
chmod +x "$sync_sh"
ok "tools/sync-all.sh skrevet"

echo
say "Ferdig ✅"
echo "Tips:"
echo "  - Restart dev (om nødvendig): npm run dev"
echo "  - Seed produkter (ny route):  curl -s -X POST 'http://localhost:3000/api/products/seed?n=5' | jq ."
echo "  - Legacy seed (opt.):         curl -s -X DELETE 'http://localhost:3000/api/products?action=seed&n=5' | jq ."
echo "  - Make eksempler:             make getp SKU=TEST | make patchp SKU=TEST PRICE=599 | make patcho OID=000000006 STATUS=processing"