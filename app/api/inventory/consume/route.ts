import { NextResponse } from 'next/server'
import { readDb, writeDb } from '@/utils/db'
import { consumeInventory } from '@/utils/inventory'

/* body: { items: Array<{ productId:string; variantId?:string; qty:number }> } */
export async function POST(req:Request){
  const body = await req.json().catch(()=>null) as any
  if(!body || !Array.isArray(body.items)) return NextResponse.json({error:'bad request'},{status:400})
  const db = await readDb()
  const byProduct:Record<string, any> = {}
  for(const it of body.items){
    const pid = String(it.productId||'')
    if(!pid) continue
    byProduct[pid] = byProduct[pid] || (db.products||[]).find((p:any)=>String(p.id)===pid)
    const p = byProduct[pid]
    if(!p) continue
    consumeInventory(p, it.variantId, Number(it.qty||0))
  }
  await writeDb(db)
  return NextResponse.json({ok:true})
}
