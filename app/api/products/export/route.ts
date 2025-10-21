export const runtime = 'nodejs';
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
