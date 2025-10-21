export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { dirname } from 'node:path'

const p = (id:string)=>({file: process.cwd()+'/data/product_meta.json', id})

async function load(){
  try{ const raw=await readFile(p('').file,'utf8'); return JSON.parse(raw||'{}') }catch{ return {} }
}
async function save(obj:any){
  await mkdir(dirname(p('').file),{recursive:true})
  await writeFile(p('').file, JSON.stringify(obj,null,2))
}

export async function GET(_req:Request,{params}:{params:{id:string}}){
  const db = await load()
  const meta = db[params.id] || { attributes:{}, related:[], notes:'' }
  return NextResponse.json(meta)
}
export async function PUT(req:Request,{params}:{params:{id:string}}){
  const body=await req.json().catch(()=>null) as any
  if(!body) return NextResponse.json({ok:false,error:'Bad body'},{status:400})
  const db = await load()
  db[params.id] = {
    attributes: body.attributes && typeof body.attributes==='object' ? body.attributes : {},
    related: Array.isArray(body.related) ? body.related : [],
    notes: String(body.notes||'')
  }
  await save(db)
  return NextResponse.json({ok:true})
}
