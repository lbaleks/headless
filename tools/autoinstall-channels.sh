#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# --- API: /api/akeneo/channels (GET)
mkdir -p app/api/akeneo/channels
log "API: /api/akeneo/channels"
cat > app/api/akeneo/channels/route.ts <<'TS'
import { NextResponse } from 'next/server'
export async function GET() {
  // kan senere hentes fra ekstern PIM – holdes lokalt nå
  return NextResponse.json({
    channels: [
      { code: 'ecommerce', label: 'E-commerce', locales: ['en_US','nb_NO'] },
      { code: 'admin',     label: 'Admin',     locales: ['en_US'] }
    ],
    default: { channel: 'ecommerce', locale: 'nb_NO' }
  })
}
TS

# --- API: /api/akeneo/families (dummy hvis mangler)
if [ ! -f app/api/akeneo/families/route.ts ]; then
  mkdir -p app/api/akeneo/families
  log "API: /api/akeneo/families (stub)"
  cat > app/api/akeneo/families/route.ts <<'TS'
import { NextResponse } from 'next/server'
export async function GET() {
  return NextResponse.json({
    families: { default:{label:'Default'}, beer:{label:'Beer'} },
    default: 'default'
  })
}
TS
fi

# --- API: oppdatér completeness til å respektere channel/locale (query)
log "Patch: completeness channel/locale"
node <<'JS'
const fs=require('fs'), p='app/api/products/completeness/route.ts'
if(!fs.existsSync(p)) process.exit(0)
let s=fs.readFileSync(p,'utf8'), b=s
// sørg for at vi leser channel/locale fra query, faller tilbake til /api/akeneo/channels default
if(!/q\.get\('channel'\)/.test(s) || !/q\.get\('locale'\)/.test(s)){
  s=s.replace(/const q = new URL\(req\.url\)\.searchParams[^]*?\n/, m=>m+`\
  // channel/locale fra query med fallback til akeneo/channels
  const chQ = q.get('channel'); const locQ = q.get('locale');
  const chRes = await fetch(new URL('/api/akeneo/channels', req.url), {cache:'no-store'});
  const chJson = chRes.ok ? await chRes.json() : {default:{channel:'ecommerce', locale:'nb_NO'}};
  const channel = chQ || chJson?.default?.channel || 'ecommerce';
  const locale  = locQ || chJson?.default?.locale  || 'nb_NO';
`)
  // og bruk variablene i output-strukturen
  s=s.replace(/channel:\s*['"]ecommerce['"]/g, 'channel')
  s=s.replace(/locale:\s*['"]nb_NO['"]/g, 'locale')
  s=s.replace(/channel:\s*['"][\w-]+['"]/g, 'channel')
  s=s.replace(/locale:\s*['"][\w-]+['"]/g, 'locale')
  // toppfelt
  s=s.replace(/channel:\s*['"][\w-]+['"],\s*\n\s*locale:\s*['"][\w-]+['"],/,
              'channel: channel,\n      locale: locale,')
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• Patchet completeness route for channel/locale') }
else { console.log('• Completeness route allerede channel/locale-aware') }
JS

# --- UI: Scope/Locale-velger og wiring i admin/completeness + products-panelet
log "UI: Scope/Locale picker"
mkdir -p src/components
cat > src/components/ScopeLocalePicker.tsx <<'TSX'
'use client'
import useSWR from 'swr'
const fetcher=(u:string)=>fetch(u).then(r=>r.json())
export function ScopeLocalePicker({
  value, onChange
}:{value:{channel:string,locale:string}, onChange:(v:{channel:string,locale:string})=>void}){
  const {data}=useSWR('/api/akeneo/channels', fetcher)
  const channels = data?.channels||[]
  return (
    <div className="flex items-center gap-2 text-sm">
      <select value={value.channel} onChange={e=>onChange({channel:e.target.value, locale:value.locale})}
        className="border rounded px-2 py-1">
        {channels.map((c:any)=><option key={c.code} value={c.code}>{c.label||c.code}</option>)}
      </select>
      <select value={value.locale} onChange={e=>onChange({channel:value.channel, locale:e.target.value})}
        className="border rounded px-2 py-1">
        {(channels.find((c:any)=>c.code===value.channel)?.locales||['nb_NO']).map((l:string)=>
          <option key={l} value={l}>{l}</option>)}
      </select>
    </div>
  )
}
TSX

# Inject i admin/completeness (panel-side)
if [ -f app/admin/completeness/page.tsx ]; then
node <<'JS'
const fs=require('fs'); const p='app/admin/completeness/page.tsx'
let s=fs.readFileSync(p,'utf8'), b=s
if(!s.includes("ScopeLocalePicker")){
  s = s.replace(/^/,"import { ScopeLocalePicker } from '@/src/components/ScopeLocalePicker'\n")
  s = s.replace(/export default function CompletenessPage\(\)\s*\{/, 
`export default function CompletenessPage(){
  const [sl, setSl] = React.useState<{channel:string,locale:string}>({channel:'ecommerce',locale:'nb_NO'});`)
  if(!/React\.useState/.test(s)) s = "import * as React from 'react'\n"+s
  s = s.replace(/fetch\('(\/api\/products\/completeness)[^']*'\)/g,
                "fetch(`$1?page=1&size=20&channel=${sl.channel}&locale=${sl.locale}`)")
  s = s.replace(/(<main[^>]*>)/, `$1
      <div className="mb-4"><ScopeLocalePicker value={sl} onChange={setSl} /></div>`)
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• Picker lagt til i admin/completeness') } else { console.log('• Picker fantes (ok)') }
JS
fi

# Inject i products-list (dersom completeness-badge bruker APIet)
if [ -f app/admin/products/page.tsx ]; then
node <<'JS'
const fs=require('fs'); const p='app/admin/products/page.tsx'
let s=fs.readFileSync(p,'utf8'), b=s
if(!s.includes("ScopeLocalePicker")){
  s = s.replace(/^/,"import { ScopeLocalePicker } from '@/src/components/ScopeLocalePicker'\n")
  if(!/function CsvBar/.test(s)) s = s.replace(/(<main[^>]*>)/, `$1\n      <div className="mb-4"><ScopeLocalePicker value={{channel:'ecommerce',locale:'nb_NO'}} onChange={()=>{}} /></div>`)
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• Picker injisert i admin/products') } else { console.log('• Picker allerede på plass (ok)') }
JS
fi

# --- Smoke
log "Smoke: channels"
curl -s 'http://localhost:3000/api/akeneo/channels' | jq -r '.default.channel + "/" + .default.locale' || true
log "Smoke: completeness w/ channel/locale"
curl -s 'http://localhost:3000/api/products/completeness?page=1&size=5&channel=ecommerce&locale=nb_NO' | jq '.items[0].channel,.items[0].locale' || true

log "Ferdig ✅  Åpne: /admin/completeness (velg scope/locale)"
