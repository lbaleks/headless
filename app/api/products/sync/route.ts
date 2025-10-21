export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''
const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function ensureVarDir(){ await fs.mkdir(path.dirname(DEV_FILE),{recursive:true}) }
async function writeDev(items:any[]){ await ensureVarDir(); await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2)) }

async function m2<T>(verb:string, frag:string):Promise<T>{
  if(!M2_BASE || !M2_TOKEN) throw new Error('missing env')
  const url = `${M2_BASE.replace(/\/+$/,'')}/${frag.replace(/^\/+/,'')}`
  const r = await fetch(url, { method:verb, headers:{Authorization:`Bearer ${M2_TOKEN}`}, cache:'no-store' })
  if(!r.ok) throw new Error(`Magento ${verb} ${url} failed: ${r.status} ${await r.text()}`)
  return r.json() as Promise<T>
}

function mapM2Products(m:any){
  const items = Array.isArray(m?.items) ? m.items : []
  return items.map((p:any)=>({
    id: p.id,
    sku: p.sku,
    name: p.name,
    type: p.type_id,
    price: p.price,
    status: p.status,
    visibility: p.visibility,
    created_at: p.created_at,
    updated_at: p.updated_at,
    image: (p.custom_attributes||[]).find((a:any)=>a.attribute_code==='image')?.value || null,
    tax_class_id: (p.custom_attributes||[]).find((a:any)=>a.attribute_code==='tax_class_id')?.value || null,
    has_options: p.has_options === 1 || p.has_options === true,
    required_options: p.required_options === 1 || p.required_options === true,
    source: 'magento',
  }))
}

export async function POST(){
  try{
    const raw = await m2<any>('GET', 'V1/products?searchCriteria[currentPage]=1&searchCriteria[pageSize]=200')
    const items = mapM2Products(raw)
    await writeDev(items)
    return NextResponse.json({ ok:true, saved: items.length })
  }catch(e:any){
    return NextResponse.json({ ok:false, error:String(e) }, { status: 500 })
  }
}
