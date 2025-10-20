import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'customers.dev.json')

async function ensureVarDir(){ await fs.mkdir(path.dirname(DEV_FILE),{recursive:true}) }
async function readDev():Promise<any[]>{
  try{
    await ensureVarDir()
    const raw = await fs.readFile(DEV_FILE,'utf8').catch(()=> '[]')
    const j = JSON.parse(raw)
    if(Array.isArray(j)) return j
    if(j && Array.isArray(j.items)) return j.items
    return []
  }catch{ return [] }
}
async function writeDev(items:any[]){ await ensureVarDir(); await fs.writeFile(DEV_FILE, JSON.stringify(items,null,2)) }

export async function GET(_req:Request, { params }: { params: { id: string } }){
  const id = params.id
  const all = await readDev()
  const found = all.find((c)=> String(c.id) === String(id)) || null
  if(!found) return NextResponse.json({ ok:false, error:'Not found' }, { status: 404 })
  return NextResponse.json(found)
}

export async function PATCH(req:Request, { params }: { params:{ id:string } }){
  const id = params.id
  const body = await req.json().catch(()=> ({}))
  const all = await readDev()
  const idx = all.findIndex((c)=> String(c.id) === String(id))
  if(idx < 0) return NextResponse.json({ ok:false, error:'Not found' }, { status: 404 })

  // Tillat enkle felt i dev
  const allowed = ['firstname','lastname','name','group_id','is_subscribed']
  for(const k of allowed){
    if(k in body) all[idx][k] = body[k]
  }
  await writeDev(all)
  return NextResponse.json(all[idx])
}
