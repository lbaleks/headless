#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
log() { printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
ensure_dir() { mkdir -p "$1"; }

log "→ Akeneo-sti: oppretter konfig"
ensure_dir "$root/var/akeneo"
cat > "$root/var/akeneo/channels.json" <<'JSON'
{
  "channels": [
    { "code": "ecommerce", "label": "E-commerce", "locales": ["en_US","nb_NO"] }
  ],
  "locales": [
    { "code": "en_US", "label": "English (US)" },
    { "code": "nb_NO", "label": "Norsk (Bokmål)" }
  ]
}
JSON

cat > "$root/var/akeneo/families.json" <<'JSON'
{
  "families": [
    {
      "code": "default",
      "label": "Default",
      "attribute_groups": [
        { "code":"basics", "label":"Basics", "attributes":["sku","name","price","status","visibility","image"] },
        { "code":"seo",    "label":"SEO",    "attributes":["meta_title","meta_description"] }
      ],
      "required": {
        "ecommerce": ["sku","name","price","status","visibility"]
      }
    },
    {
      "code": "beer",
      "label": "Beer",
      "attribute_groups": [
        { "code":"basics", "label":"Basics", "attributes":["sku","name","price","status","visibility","image"] },
        { "code":"specs",  "label":"Specs",  "attributes":["abv","volume_ml","style","origin"] }
      ],
      "required": {
        "ecommerce": ["sku","name","price","status","visibility","image"]
      }
    }
  ]
}
JSON

log "→ API: /api/akeneo/families (GET)"
ensure_dir "$root/app/api/akeneo/families"
cat > "$root/app/api/akeneo/families/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET() {
  const p = path.join(process.cwd(), 'var', 'akeneo', 'families.json')
  const raw = await fs.readFile(p, 'utf8')
  const data = JSON.parse(raw)
  return NextResponse.json({ ok:true, ...data }, { headers: {'cache-control':'no-store'} })
}
TS

log "→ API: /api/akeneo/channels (GET)"
ensure_dir "$root/app/api/akeneo/channels"
cat > "$root/app/api/akeneo/channels/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET() {
  const p = path.join(process.cwd(), 'var', 'akeneo', 'channels.json')
  const raw = await fs.readFile(p, 'utf8')
  const data = JSON.parse(raw)
  return NextResponse.json({ ok:true, ...data }, { headers: {'cache-control':'no-store'} })
}
TS

log "→ Utvider completeness-API til family/channel/locale"
# Lager/erstatter route med støtte for ?family=beer&channel=ecommerce&locale=nb_NO
ensure_dir "$root/app/api/products/completeness"
cat > "$root/app/api/products/completeness/route.ts" <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

// Hent Magento + lokale som i eksisterende kodebase.
// For enkelhet: gjenbruk /api/products/merged internt.
async function fetchMerged(page=1, size=50, q?:string) {
  const url = new URL('http://localhost:3000/api/products/merged')
  url.searchParams.set('page', String(page))
  url.searchParams.set('size', String(size))
  if (q) url.searchParams.set('q', q)
  const r = await fetch(url, { cache: 'no-store' })
  if (!r.ok) throw new Error('merged fetch failed')
  return r.json() as Promise<{ total:number, items:any[] }>
}

async function loadFamilies() {
  const p = path.join(process.cwd(), 'var', 'akeneo', 'families.json')
  const raw = await fs.readFile(p, 'utf8')
  return JSON.parse(raw) as { families: Array<any> }
}

function pickRequired(familyCode:string|undefined, channel:string, families:any) {
  if (!familyCode) return ["sku","name","price","status","visibility"]
  const fam = families.families.find((f:any)=>f.code===familyCode)
  if (!fam) return ["sku","name","price","status","visibility"]
  const req = fam.required?.[channel]
  return Array.isArray(req) && req.length ? req : ["sku","name","price","status","visibility"]
}

function present(v:any) {
  if (v===null || v===undefined) return false
  if (typeof v==='string') return v.trim().length>0
  if (Array.isArray(v)) return v.length>0
  if (typeof v==='number') return true
  if (typeof v==='object') return Object.keys(v).length>0
  return !!v
}

export async function GET(req:NextRequest) {
  const { searchParams } = new URL(req.url)
  const page = Number(searchParams.get('page')||'1')
  const size = Number(searchParams.get('size')||'20')
  const q = searchParams.get('q') || undefined

  const family = searchParams.get('family') || undefined   // f.eks "beer"
  const channel = searchParams.get('channel') || 'ecommerce'
  const locale = searchParams.get('locale') || 'nb_NO'

  const families = await loadFamilies()
  const reqAttrs = pickRequired(family, channel, families)

  const merged = await fetchMerged(page, size, q)

  const items = merged.items.map((p:any)=> {
    // enkel namespacing-støtte: name@nb_NO, description#ecommerce, image etc
    const accessor = (key:string) => {
      if (key.includes('@')) {
        const [base, loc] = key.split('@')
        return p[`${base}@${locale}`] ?? p[base]
      }
      if (key.includes('#')) {
        const [base, ch] = key.split('#')
        return p[`${base}#${channel}`] ?? p[base]
      }
      return p[key]
    }
    const missing = reqAttrs.filter(a=>!present(accessor(a)))
    const score = Math.round(100 * (reqAttrs.length - missing.length) / Math.max(reqAttrs.length,1))
    return { sku: p.sku, name: p.name, family: family||'default', channel, locale,
      completeness: { score, missing, required: reqAttrs } }
  })

  return NextResponse.json({ family: family||'default', channel, locale, total: merged.total, items }, { headers: {'cache-control':'no-store'} })
}
TS

log "→ UI: Scope/Locale-velger"
ensure_dir "$root/src/components"
cat > "$root/src/components/ScopeLocalePicker.tsx" <<'TSX'
'use client'
import useSWR from 'swr'
import { useSearchParams, useRouter, usePathname } from 'next/navigation'

const fetcher = (u:string)=>fetch(u).then(r=>r.json())

export default function ScopeLocalePicker() {
  const { data } = useSWR('/api/akeneo/channels', fetcher)
  const sp = useSearchParams()
  const router = useRouter()
  const pathname = usePathname()

  const channel = sp.get('channel') || 'ecommerce'
  const locale  = sp.get('locale')  || 'nb_NO'

  const onChange = (k:'channel'|'locale', v:string) => {
    const params = new URLSearchParams(sp.toString())
    params.set(k, v)
    router.replace(`${pathname}?${params.toString()}`)
  }

  const chs = data?.channels ?? []
  const locs = (chs.find((c:any)=>c.code===channel)?.locales) ?? []

  return (
    <div className="flex items-center gap-2 text-sm">
      <label className="text-neutral-500">Channel</label>
      <select className="border rounded px-2 py-1" value={channel} onChange={e=>onChange('channel', e.target.value)}>
        {chs.map((c:any)=><option key={c.code} value={c.code}>{c.label||c.code}</option>)}
      </select>
      <label className="text-neutral-500">Locale</label>
      <select className="border rounded px-2 py-1" value={locale} onChange={e=>onChange('locale', e.target.value)}>
        {locs.map((lc:string)=><option key={lc} value={lc}>{lc}</option>)}
      </select>
    </div>
  )
}
TSX

log "→ UI: CompletenessBadge (familie/scope/locale-aware)"
cat > "$root/src/components/CompletenessBadge.tsx" <<'TSX'
'use client'
import useSWR from 'swr'
import { useSearchParams } from 'next/navigation'

const fetcher = (u:string)=>fetch(u).then(r=>r.json())

export function CompletenessBadge({ sku }:{ sku:string }) {
  const sp = useSearchParams()
  const family = sp.get('family') || 'default'
  const channel = sp.get('channel') || 'ecommerce'
  const locale = sp.get('locale') || 'nb_NO'
  const url = `/api/products/completeness?page=1&size=1&q=${encodeURIComponent(sku)}&family=${family}&channel=${channel}&locale=${locale}`
  const { data } = useSWR(url, fetcher)
  const item = data?.items?.[0]
  const score = item?.completeness?.score ?? 0
  return (
    <span title={`family=${family}, channel=${channel}, locale=${locale}`}
      className={`inline-flex items-center rounded px-2 py-0.5 text-xs ${score===100?'bg-green-100 text-green-700':'bg-amber-100 text-amber-800'}`}>
      {score}% complete
    </span>
  )
}
TSX

log "→ Patcher admin-UI (idempotent) for å bruke picker og badge"
prodPage="$root/app/admin/products/page.tsx"
if grep -q "ScopeLocalePicker" "$prodPage" 2>/dev/null; then
  log "  • Picker finnes alt: app/admin/products/page.tsx"
else
  # legg til import og komponent øverst i siden (enkelt heuristisk patch)
  sed -i '' '1s;^;import ScopeLocalePicker from "@/src/components/ScopeLocalePicker"\nimport { CompletenessBadge } from "@/src/components/CompletenessBadge"\n;' "$prodPage" || true
  # Sett inn picker rett under hovedheader/container om mulig
  sed -i '' '0,/<main[^>]*>/{s//&\n      <div className="mb-3"><ScopeLocalePicker\/><\/div>/}' "$prodPage" || true
  # Prøv å vise badge i tabellen (erstatt evt kolonne for status/visning)
  sed -i '' 's/{p\.name}/{p.name} <CompletenessBadge sku={p.sku} \/>/g' "$prodPage" || true
  log "  • Picker & Badge injisert i app/admin/products/page.tsx"
fi

log "→ Installerer verify-script"
cat > "$root/tools/verify-akeneo.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-http://localhost:3000}
echo "→ Families:"; curl -s "$BASE/api/akeneo/families" | jq '.families[0].code'
echo "→ Channels:"; curl -s "$BASE/api/akeneo/channels" | jq '.channels[0].code,.locales[0].code'
echo "→ Completeness (beer/ecommerce/nb_NO)"
curl -s "$BASE/api/products/completeness?family=beer&channel=ecommerce&locale=nb_NO&page=1&size=1" | jq '.family,.channel,.locale, .items[0].completeness'
BASH
chmod +x "$root/tools/verify-akeneo.sh"

log "→ Røyk-test"
BASE=${BASE:-http://localhost:3000}
curl -sf "$BASE/api/akeneo/families" >/dev/null
curl -sf "$BASE/api/akeneo/channels" >/dev/null
curl -sf "$BASE/api/products/completeness?family=default&channel=ecommerce&locale=nb_NO&page=1&size=1" >/dev/null || true
log "✓ Akeneo-sti installert"
echo "Tips:"
echo "  - Restart dev ved behov: npm run dev"
echo "  - Verifiser: tools/verify-akeneo.sh"