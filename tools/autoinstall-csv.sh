#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

mkdir -p app/api/products/export app/api/products/import var

log "API: /api/products/export (CSV)"
cat > app/api/products/export/route.ts <<'TS'
import { NextResponse } from 'next/server'

function toCSVRow(vals:any[]){return vals.map(v=>{
  if(v==null) return ''
  const s=String(v)
  return /[",\n]/.test(s) ? `"${s.replace(/"/g,'""')}"` : s
}).join(',')}

export async function GET(req: Request){
  const url=new URL(req.url)
  const page = Number(url.searchParams.get('page')||1)
  const size = Number(url.searchParams.get('size')||1000)
  const fieldsParam = url.searchParams.get('fields') || 'sku,name,price,status,visibility,family,image'
  const fields = fieldsParam.split(',').map(s=>s.trim()).filter(Boolean)

  const mergedRes = await fetch(new URL(`/api/products/merged?page=${page}&size=${size}`, req.url),{cache:'no-store'})
  if(!mergedRes.ok) return NextResponse.json({ok:false,error:'failed merged'}, {status:500})
  const merged = await mergedRes.json() as {items:any[]}
  const rows = [toCSVRow(fields)]
  for(const p of (merged.items||[])){
    const line = fields.map(f=>{
      // prefer attributes overlay if exists
      if(p?.attributes && f in p.attributes) return p.attributes[f]
      return p?.[f]
    })
    rows.push(toCSVRow(line))
  }
  const body = rows.join('\n')+'\n'
  return new NextResponse(body, { headers: {'content-type':'text/csv; charset=utf-8','content-disposition':'attachment; filename="products.csv"'}})
}
TS

log "API: /api/products/import (CSV -> var/products.dev.json overrides)"
cat > app/api/products/import/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

async function readBodyAsText(req: Request): Promise<string>{
  const ct = req.headers.get('content-type')||''
  if(ct.startsWith('multipart/form-data')){
    const form = await req.formData()
    const f = form.get('file')
    if(f && typeof f!=='string'){
      return await (f as File).text()
    }
    // also allow paste in "text" field
    const t = form.get('text')
    if(typeof t==='string') return t
    return ''
  }
  return await req.text()
}

function parseCSV(txt:string): {headers:string[], rows:string[][]}{
  const out:string[][]=[]; const headers:string[]=[]
  if(!txt.trim()) return {headers,rows:out}
  const lines = txt.replace(/\r\n/g,'\n').replace(/\r/g,'\n').split('\n').filter(l=>l.length>0)
  // very small RFC4180-ish split (handles quotes and escaped quotes)
  const split = (line:string)=>{
    const cells:string[]=[]; let cur=''; let q=false
    for(let i=0;i<line.length;i++){
      const ch=line[i]
      if(q){
        if(ch==='"' && line[i+1]==='"'){ cur+='"'; i++; continue }
        if(ch==='\"'){ q=false; continue }
        cur+=ch
      }else{
        if(ch===','){ cells.push(cur); cur=''; continue }
        if(ch==='\"'){ q=true; continue }
        cur+=ch
      }
    }
    cells.push(cur)
    return cells
  }
  const first = split(lines[0]).map(h=>h.trim())
  headers.push(...first)
  for(let i=1;i<lines.length;i++){
    const row = split(lines[i]).map(v=>v.trim())
    if(row.every(v=>v==='')) continue
    out.push(row)
  }
  return {headers, rows: out}
}

function asNumberMaybe(v:any){
  if(v===''||v==null) return undefined
  const n=Number(v); return Number.isFinite(n) ? n : v
}

export async function POST(req: Request){
  try{
    const txt = await readBodyAsText(req)
    if(!txt) return NextResponse.json({ok:false,error:'empty'}, {status:400})
    const {headers, rows} = parseCSV(txt)
    const skuIx = headers.findIndex(h=>h.toLowerCase()==='sku')
    if(skuIx<0) return NextResponse.json({ok:false,error:'missing sku column'}, {status:400})

    const OV_PATH = path.join(process.cwd(),'var','products.dev.json')
    let data:any[]=[]
    try{
      const raw = await fs.readFile(OV_PATH,'utf8')
      data = JSON.parse(raw)
      if(!Array.isArray(data)) data=[]
    }catch{}

    let updated=0, created=0
    for(const r of rows){
      const sku = r[skuIx]
      if(!sku) continue
      const patch:any = { sku, source:'local-override' }
      // copy recognized columns (except sku)
      headers.forEach((h,idx)=>{
        if(idx===skuIx) return
        const key = h
        const val = r[idx]
        if(['price','status','visibility'].includes(key)) patch[key]=asNumberMaybe(val)
        else if(['name','image','family','type'].includes(key)) patch[key]=val||undefined
        else {
          // other columns go into attributes overlay
          patch.attributes = patch.attributes||{}
          patch.attributes[key]=asNumberMaybe(val)
        }
      })
      const i = data.findIndex(p=>(p?.sku||'').toLowerCase()===sku.toLowerCase())
      if(i>=0){ data[i] = {...data[i], ...patch, updated_at: new Date().toISOString()}; updated++ }
      else { data.push({...patch, created_at:new Date().toISOString(), updated_at:new Date().toISOString()}); created++ }
    }

    await fs.mkdir(path.dirname(OV_PATH), {recursive:true})
    await fs.writeFile(OV_PATH, JSON.stringify(data,null,2), 'utf8')

    return NextResponse.json({ok:true, updated, created, total:data.length})
  }catch(e:any){
    return NextResponse.json({ok:false, error: String(e?.message||e)}, {status:500})
  }
}
TS

log "UI: knapper for Export/Import i /admin/products (idempotent)"
node - <<'JS'
const fs=require('fs'); const p='app/admin/products/page.tsx'
if(!fs.existsSync(p)) process.exit(0)
let s=fs.readFileSync(p,'utf8'), b=s
// importer liten client-komponent inline
if(!/function CsvBar/.test(s)){
  s = s.replace(/export default async function ProductsPage[^\{]+\{/,
`$&
  function CsvBar(){
    return (
      <div className="flex items-center gap-3 mb-4">
        <a href="/api/products/export" className="rounded-lg border px-3 py-1 text-sm hover:bg-neutral-50">Export CSV</a>
        <form action="/api/products/import" method="post" encType="multipart/form-data" className="flex items-center gap-2">
          <input name="file" type="file" accept=".csv,text/csv" className="text-sm"/>
          <button type="submit" className="rounded-lg border px-3 py-1 text-sm hover:bg-neutral-50">Import</button>
        </form>
      </div>
    )
  }
`)
}
if(!/CsvBar \/\>/.test(s)){
  s = s.replace(/(<main[^>]*>)/, `$1\n      <CsvBar />`)
}
if(s!==b){ fs.writeFileSync(p,s); console.log('• CSV bar lagt til i admin/products') } else { console.log('• CSV bar fantes (ok)') }
JS

log "Smoke: export CSV"
code=$(curl -s -o /tmp/products.csv -w "%{http_code}" 'http://localhost:3000/api/products/export')
if [ "$code" = "200" ]; then head -n 2 /tmp/products.csv | sed 's/^/    /'; else echo "    export HTTP $code"; fi

log "Ferdig ✅  Åpne /admin/products (øverst: Export/Import)"
