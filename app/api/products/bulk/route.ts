import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'
import { auditProductChange } from '@/lib/audit'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')
async function readLocal(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}
async function writeLocal(items:any[]){
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}
function idx(items:any[], sku:string){ return items.findIndex(p => String(p.sku).toLowerCase()===sku.toLowerCase()) }

export async function PATCH(req:Request){
  const body = await req.json().catch(()=>null)
  if(!body || !Array.isArray(body.items)) return NextResponse.json({ ok:false, error:'Expect {items:[{sku, changes:{...}}]}' }, { status:400 })
  const items = await readLocal()
  let updated = 0
  for(const row of body.items){
    const sku = String(row.sku||'')
    const changes = row.changes && typeof row.changes==='object' ? row.changes : {}
    if(!sku || !Object.keys(changes).length) continue
    let i = idx(items, sku)
    if(i===-1){
      const obj = { sku, ...changes, created_at:new Date().toISOString(), updated_at:new Date().toISOString(), source:'local-override' }
      items.push(obj); i = items.length-1
      auditProductChange(sku, null, obj)
      updated++
    }else{
      const before = items[i]
      items[i] = { ...items[i], ...changes, updated_at:new Date().toISOString(), source: items[i].source || 'local-override' }
      auditProductChange(sku, before, items[i])
      updated++
    }
  }
  await writeLocal(items)
  return NextResponse.json({ ok:true, updated })
}
