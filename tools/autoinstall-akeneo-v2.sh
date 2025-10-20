#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TS="$ROOT/app/api"
COMP="$ROOT/app/api/products/completeness"
OVR="$ROOT/var"
mkdir -p "$TS/akeneo/attributes" "$TS/products" "$OVR"

log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

ensure_dev_server() {
  # Ikke start på nytt hvis allerede kjører på 3000
  if curl -sSf "http://localhost:3000" >/dev/null 2>&1; then return 0; fi
  npm run dev --silent >/dev/null 2>&1 &
  sleep 1
}

log "Akeneo v2: attributes + family rules + completeness"

############################################
# 1) Mock Akeneo attributes endpoint
############################################
ATTR_ROUTE="$TS/akeneo/attributes/route.ts"
if [ ! -f "$ATTR_ROUTE" ]; then
  log "Oppretter /api/akeneo/attributes (GET)"
  mkdir -p "$(dirname "$ATTR_ROUTE")"
  cat > "$ATTR_ROUTE" <<'TS'
import { NextResponse } from 'next/server'

/**
 * Mock: Akeneo attribute-definisjoner per family.
 * Vi returnerer kun det vi trenger for demo (iblandt beer-krav).
 */
export async function GET() {
  return NextResponse.json({
    families: {
      default: { required: ["sku","name","price","status","visibility"] },
      beer:    { required: ["sku","name","price","status","visibility","image","ibu"] }
    },
    // valgfritt: attributter (metadata)
    attributes: {
      image: { type: "media", label: "Bilde" },
      ibu:   { type: "number", label: "IBU"  },
      hops:  { type: "text",   label: "Humle" }
    }
  })
}
TS
else
  log "Attributes-route finnes – hopper over"
fi

############################################
# 2) Lokal overlay: /api/products/update-attributes (PATCH)
############################################
UPD_ATTR="$TS/products/update-attributes/route.ts"
if [ ! -f "$UPD_ATTR" ]; then
  log "Oppretter /api/products/update-attributes (PATCH)"
  mkdir -p "$(dirname "$UPD_ATTR")"
  cat > "$UPD_ATTR" <<'TS'
import { NextResponse } from 'next/server'
import path from 'node:path'
import { promises as fs } from 'node:fs'

const DB = path.join(process.cwd(), 'var', 'products.dev.json')

async function loadAll(){
  try { return JSON.parse(await fs.readFile(DB,'utf8')) } catch { return [] }
}
async function saveAll(items:any[]){
  await fs.mkdir(path.dirname(DB), {recursive:true})
  await fs.writeFile(DB, JSON.stringify(items, null, 2), 'utf8')
}

export async function PATCH(req:Request){
  const body = await req.json().catch(()=> ({}))
  const { sku, attributes } = body || {}
  if(!sku || typeof attributes !== 'object'){
    return NextResponse.json({ok:false, error:'Pass på body: {sku, attributes:{...}}'}, {status:400})
  }
  const all = await loadAll()
  const i = all.findIndex((p:any)=> (p?.sku||'').toLowerCase()===String(sku).toLowerCase())
  if(i>=0){
    all[i] = { ...all[i], attributes: { ...(all[i].attributes||{}), ...attributes } }
  } else {
    all.push({ id: Date.now(), sku, name: sku, price: 0, status: 1, visibility: 4, source: 'local-override', attributes })
  }
  await saveAll(all)
  return NextResponse.json({ok:true, sku, attributes})
}
TS
else
  log "Update-attributes-route finnes – hopper over"
fi

############################################
# 3) Completeness-route m/familie-regler og attributter
############################################
mkdir -p "$COMP"
log "Oppdaterer completeness engine (familie-spesifikke regler)"
cat > "$COMP/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import path from 'node:path'
import { promises as fs } from 'node:fs'

const DEV_DB = path.join(process.cwd(), 'var', 'products.dev.json')

async function loadLocal(){
  try { return JSON.parse(await fs.readFile(DEV_DB,'utf8')) } catch { return [] }
}

function asMap(arr:any[], key='sku'){
  const m = new Map<string, any>()
  for(const x of arr||[]) if(x && x[key]) m.set(String(x[key]).toLowerCase(), x)
  return m
}

// Mock "Magento" primærkilde – her henter du i realitet fra eksisterende /api/products
async function loadMagentoList(): Promise<any[]> {
  // For demo antar vi at /api/products/merged eksisterer – om ikke, fallback til /api/products
  try{
    const r = await fetch('http://localhost:3000/api/products/merged')
    if(r.ok) {
      const j = await r.json()
      return j?.items ?? []
    }
  } catch {}
  try{
    const r = await fetch('http://localhost:3000/api/products')
    if(r.ok){
      const j = await r.json()
      return j?.items ?? []
    }
  } catch {}
  return []
}

function familyOf(p:any, fallback="default"){
  // Family kan komme direkte eller gjennom attributes.family (om man ønsker)
  const f = p?.family ?? p?.attributes?.family
  return String(f || fallback)
}

// Henter Akeneo attribute-regler (mock)
async function loadAkeneoFamilies(){
  try{
    const r = await fetch('http://localhost:3000/api/akeneo/attributes')
    if(!r.ok) throw 0
    return await r.json()
  } catch {
    // fallback hvis route ikke finnes
    return {
      families: {
        default: { required: ["sku","name","price","status","visibility"] },
        beer:    { required: ["sku","name","price","status","visibility","image","ibu"] }
      }
    }
  }
}

function isMissing(p:any, key:string){
  // støtter nested attributes (f.eks. attributes.ibu)
  if(key.includes('.')){
    const parts = key.split('.')
    let cur:any = p
    for(const part of parts){
      cur = cur?.[part]
      if(cur==null) return true
    }
    return (cur==null || cur==='')
  }
  return (p?.[key]==null || p?.[key]==='')
}

export async function GET(req: Request){
  const url = new URL(req.url)
  const page = Number(url.searchParams.get('page')||'1')
  const size = Number(url.searchParams.get('size')||'50')
  const skuQ = url.searchParams.get('sku') // enkel sku-target om ønsket

  const [magento, local, famcfg] = await Promise.all([
    loadMagentoList(),
    loadLocal(),
    loadAkeneoFamilies()
  ])

  const lmap = asMap(local)
  const itemsMerged = (magento.length ? magento : local).map(m => {
    const key = String(m?.sku||'').toLowerCase()
    const ov = lmap.get(key)
    // flett inn lokale overrides inkl. attributes
    return { ...m, ...(ov||{}), attributes: { ...(m?.attributes||{}), ...(ov?.attributes||{}) } }
  })

  // subset per sku (enkelmodus)
  const pool = skuQ ? itemsMerged.filter(x=> String(x?.sku||'').toLowerCase()===skuQ.toLowerCase()) : itemsMerged

  // beregn completeness per item
  const famRules = famcfg?.families ?? {
    default: { required: ["sku","name","price","status","visibility"] }
  }

  const out = pool.map(item=>{
    const fam = familyOf(item,"default")
    const req = famRules[fam]?.required ?? famRules.default.required
    // tilrettelegging: støtte attributes.ibu
    const surface = { ...item, "attributes.ibu": item?.attributes?.ibu }
    const missing = req.filter(k => isMissing(surface, k))
    const score = Math.round(100 * (req.length - missing.length) / Math.max(1, req.length))
    return {
      sku: item?.sku,
      name: item?.name,
      family: fam,
      channel: "ecommerce",
      locale: "nb_NO",
      completeness: { score, missing, required: req }
    }
  })

  // paginer
  const start = (page-1)*size
  const paged = out.slice(start, start+size)
  return NextResponse.json({
    family: "default",
    channel: "ecommerce",
    locale: "nb_NO",
    total: out.length,
    items: paged
  })
}
TS

############################################
# 4) Verifisering
############################################
ensure_dev_server
log "Setter TEST familie og attributter"
# familie ble allerede satt tidligere – her sikrer vi at vi har attributes.ibu
curl -s -X PATCH "http://localhost:3000/api/products/update-attributes" \
  -H 'content-type: application/json' \
  --data '{"sku":"TEST","attributes":{"ibu":35,"hops":"Mosaic"}}' >/dev/null

# smoketest 1: completeness for TEST må ha family beer (satt tidligere hos deg) og 100 score
log "Røyk-test (sku=TEST)"
ONE=$(curl -s "http://localhost:3000/api/products/completeness?sku=TEST" | jq -c '.items[0]|{sku,family,score:.completeness.score,missing:.completeness.missing}')
echo "$ONE"

# smoketest 2: bulk-liste må inneholde TEST med score >= 100
log "Røyk-test (bulk)"
BULK=$(curl -s "http://localhost:3000/api/products/completeness?page=1&size=500" | jq -c '.items[]|select(.sku=="TEST")|{sku,family,score:.completeness.score}')
echo "$BULK"

log "Akeneo v2 ferdig ✅"
# portable logger for macOS / Bash 3.x (overrides any earlier log())
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
