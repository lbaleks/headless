#!/usr/bin/env bash
set -euo pipefail

log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

root="$(pwd)"
mkdir -p "$root/src/components" "$root/app/admin/completeness"

log "Skriver src/components/CompletenessPanel.tsx"
cat > "$root/src/components/CompletenessPanel.tsx" <<'TSX'
'use client'
import useSWR from 'swr'
import { useMemo, useState, useEffect } from 'react'

const fetcher = (u:string)=>fetch(u, {cache:'no-store'}).then(r=>r.json())

type Row = {
  sku: string
  name?: string
  family: string
  channel: string
  locale: string
  completeness: { score:number, missing:string[], required:string[] }
}

export default function CompletenessPanel() {
  const [sku, setSku] = useState('')
  const [family, setFamily] = useState<string>('all')
  const [q, setQ] = useState('')

  // families hentes fra akeneo-attributes
  const { data:attrs } = useSWR('/api/akeneo/attributes', fetcher)
  const families: string[] = useMemo(()=>{
    const f = Object.keys(attrs?.families ?? {})
    return ['all', ...f]
  }, [attrs])

  // data: enten single (sku) eller paginert liste
  const qs = new URLSearchParams(
    sku ? { sku } : { page:'1', size:'200' }
  ).toString()

  const { data, isLoading } = useSWR(`/api/products/completeness?${qs}`, fetcher, { revalidateOnFocus:false })
  const items: Row[] = (data?.items ?? []) as Row[]

  // filter lokalt på family + fritekst
  const filtered = useMemo(()=>{
    return items.filter(r=>{
      const okFam = family==='all' || r.family===family
      const txt = `${r.sku} ${r.name??''}`.toLowerCase()
      const okQ  = !q || txt.includes(q.toLowerCase())
      return okFam && okQ
    })
  }, [items, family, q])

  const avg = useMemo(()=>{
    if(!filtered.length) return 0
    return Math.round( filtered.reduce((s,r)=>s + (r.completeness?.score??0), 0) / filtered.length )
  }, [filtered])

  useEffect(()=>{
    // sørg for at family finnes i lista – defaults
    if(families.length && family==='all') return
  }, [families, family])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2 items-end">
        <div className="flex flex-col">
          <label className="text-xs text-neutral-500">SKU (valgfritt)</label>
          <input value={sku} onChange={e=>setSku(e.target.value)}
                 placeholder="TEST"
                 className="border rounded px-2 py-1" />
        </div>
        <div className="flex flex-col">
          <label className="text-xs text-neutral-500">Family</label>
          <select value={family} onChange={e=>setFamily(e.target.value)}
                  className="border rounded px-2 py-1">
            {families.map(f=><option key={f} value={f}>{f}</option>)}
          </select>
        </div>
        <div className="flex flex-col grow min-w-[180px]">
          <label className="text-xs text-neutral-500">Søk</label>
          <input value={q} onChange={e=>setQ(e.target.value)}
                 placeholder="fritakst på sku/navn"
                 className="border rounded px-2 py-1" />
        </div>
      </div>

      <div className="flex items-center justify-between">
        <div className="text-sm text-neutral-600">
          {isLoading ? 'Laster…' : `Viser ${filtered.length} av ${items.length} (${family})`}
        </div>
        <div className="text-sm">
          Snittscore: <span className="font-semibold">{avg}%</span>
        </div>
      </div>

      <div className="border rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-neutral-50 text-neutral-600">
            <tr>
              <th className="text-left p-2">SKU</th>
              <th className="text-left p-2">Family</th>
              <th className="text-left p-2">Score</th>
              <th className="text-left p-2">Mangler</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r, i)=>(
              <tr key={r.sku || i} className="border-t hover:bg-neutral-50">
                <td className="p-2 font-mono">{r.sku}</td>
                <td className="p-2">{r.family}</td>
                <td className="p-2">
                  <span className="inline-block min-w-[3ch]">{r.completeness?.score ?? 0}%</span>
                  <div className="h-1.5 bg-neutral-200 rounded mt-1">
                    <div className="h-1.5 bg-emerald-500 rounded" style={{width:`${r.completeness?.score ?? 0}%`}} />
                  </div>
                </td>
                <td className="p-2 text-neutral-700">
                  {r.completeness?.missing?.length
                    ? r.completeness.missing.join(', ')
                    : <span className="text-emerald-600">komplett</span>}
                </td>
              </tr>
            ))}
            {!filtered.length && !isLoading && (
              <tr><td className="p-3 text-neutral-500" colSpan={4}>Ingen treff.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
TSX

log "Skriver app/admin/completeness/page.tsx"
cat > "$root/app/admin/completeness/page.tsx" <<'TSX'
import CompletenessPanel from '@/src/components/CompletenessPanel'

export const dynamic = 'force-dynamic'

export default function Page() {
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold">Completeness</h1>
      <p className="text-neutral-600 text-sm">
        Oversikt over produkt-completeness per familie/attributter (Akeneo-inspirert).
      </p>
      <CompletenessPanel />
    </div>
  )
}
TSX

# Patch admin/layout for å få en lenke til siden (idempotent via liten Node-patcher)
if [ -f "$root/app/admin/layout.tsx" ]; then
  node - <<'JS'
const fs=require('fs'); const p='app/admin/layout.tsx'
let s=fs.readFileSync(p,'utf8'), before=s
if(!/href="\/admin\/completeness"/.test(s)){
  s=s.replace(/(<header[\s\S]*?<\/header>)/, (m)=>{
    if(/Completeness/.test(m)) return m
    return m.replace(/(<\/header>)/,
      `  <nav className="text-sm text-neutral-600">
        <a className="underline hover:no-underline" href="/admin/completeness">Completeness</a>
      </nav>\n$1`)
  })
}
if(s!==before){ fs.writeFileSync(p,s); console.log('• La til lenke i admin/layout.tsx') }
else { console.log('• Lenke fantes fra før (ok)') }
JS
fi

# Rask smoke-test (HTML 200 + har "Completeness")
code=$(curl -s -o /tmp/comp.html -w "%{http_code}" "http://localhost:3000/admin/completeness" || true)
if [ "${code:-000}" != "200" ]; then
  # prøv å trigge dev-server hvis ikke svar
  npm run dev --silent >/dev/null 2>&1 & sleep 1
  curl -s -o /tmp/comp.html -w "%{http_code}" "http://localhost:3000/admin/completeness" >/tmp/comp.code || true
  code=$(cat /tmp/comp.code 2>/dev/null || echo 000)
fi
if grep -q "Completeness" /tmp/comp.html 2>/dev/null; then
  log "UI røyk-test OK (/${code})"
else
  log "⚠ UI side svarer /${code} – åpne /admin/completeness manuelt om dev ikke har hot-reloada"
fi

log "Ferdig ✅"
