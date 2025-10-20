#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

log "→ Family per produkt (Akeneo-nivå 1)"

# 1) Utvid merged-API til å inkludere family (leser fra local override)
app_api="$root/app/api/products/merged/route.ts"
if ! grep -q 'family' "$app_api"; then
  log "  • Oppdaterer merged-API for family-felt"
  perl -0777 -pi -e '
    s/return NextResponse\.json\(\s*\{(.+?)items/mg
     /const withFamily = merged.items.map(p=>({...p,family:p.family||"default"}));\n  return NextResponse.json({\1items: withFamily/m' "$app_api"
fi

# 2) Family-felt i local seed / update
ensure_seed(){
  local file="$root/app/api/products/seed/route.ts"
  if ! grep -q 'family' "$file"; then
    log "  • Utvider seed med family"
    perl -0777 -pi -e 's/(const product = {[^}]+)}/\1, family: "default"}/' "$file"
  fi
}
ensure_seed || true

# 3) Family-felt i completeness-API
file="$root/app/api/products/completeness/route.ts"
if grep -q 'family: family' "$file"; then
  log "  • completeness allerede bruker family"
else
  log "  • Patcher completeness til å bruke produktets faktiske family"
  perl -0777 -pi -e 's/const items = merged\.items\.map\(.*?\);/const items = merged.items.map((p:any)=>{\n  const fam = p.family || family;\n  const missing = pickRequired(fam, channel, families).filter(a=>!present(p[a]));\n  const score = Math.round(100*(pickRequired(fam,channel,families).length - missing.length)\/Math.max(pickRequired(fam,channel,families).length,1));\n  return {...p, completeness:{score,missing,required:pickRequired(fam,channel,families)}}\n});/' "$file"
fi

# 4) Admin UI: family-kolonne og dropdown
ui_file="$root/app/admin/products/page.tsx"
if ! grep -q 'FamilyPicker' "$ui_file"; then
  log "  • Legger inn FamilyPicker i admin-UI"
  cat > "$root/src/components/FamilyPicker.tsx" <<'TSX'
'use client'
import useSWR from 'swr'
const fetcher=(u:string)=>fetch(u).then(r=>r.json())
export default function FamilyPicker({ value, sku }:{ value?:string, sku:string }) {
  const { data } = useSWR('/api/akeneo/families', fetcher)
  const families = data?.families || []
  const updateFamily = async (v:string)=>{
    await fetch(`/api/products/update?family=${encodeURIComponent(v)}&sku=${encodeURIComponent(sku)}`,{method:'POST'})
  }
  return (
    <select className="border rounded px-1 text-sm" defaultValue={value||'default'} onChange={e=>updateFamily(e.target.value)}>
      {families.map((f:any)=><option key={f.code} value={f.code}>{f.label}</option>)}
    </select>
  )
}
TSX
  # import + kolonne i tabellen
  perl -pi -e 's/import .*\n/import FamilyPicker from "\@\/src\/components\/FamilyPicker"\n/' "$ui_file"
  perl -pi -e 's/{p\.name}/{p.name} <FamilyPicker sku={p.sku} value={p.family} \/>/g' "$ui_file"
fi

# 5) Opprett update-endpoint for family
ensure_dir(){ mkdir -p "$1"; }
ensure_dir "$root/app/api/products/update"
cat > "$root/app/api/products/update/route.ts" <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function POST(req:NextRequest) {
  const { searchParams } = new URL(req.url)
  const sku = searchParams.get('sku')
  const family = searchParams.get('family')
  if(!sku) return NextResponse.json({ok:false,error:'missing sku'},{status:400})
  const file = path.join(process.cwd(),'var','products.dev.json')
  let products:any[] = []
  try {
    const raw = await fs.readFile(file,'utf8')
    products = JSON.parse(raw)
  } catch {}
  products = products.map(p=>p.sku===sku?{...p,family}:p)
  await fs.writeFile(file,JSON.stringify(products,null,2))
  return NextResponse.json({ok:true,sku,family})
}
TS

log "✓ Family-nivå installert. Restart dev og test i admin"
echo "→ Verifiser:"
echo "  tools/verify-family.sh  (auto genereres nå)"
cat > "$root/tools/verify-family.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
echo "→ Henter merged products (viser family)"
curl -s "$BASE/api/products/merged?page=1&size=2" | jq '.items[0].sku,.items[0].family'
echo "→ Oppdaterer første produkt til family=beer"
SKU=$(curl -s "$BASE/api/products/merged?page=1&size=1" | jq -r '.items[0].sku')
curl -s -X POST "$BASE/api/products/update?sku=$SKU&family=beer" | jq .
echo "→ Verifiser endring:"
curl -s "$BASE/api/products/merged?page=1&size=1" | jq '.items[0].sku,.items[0].family'
BASH
chmod +x "$root/tools/verify-family.sh"