export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { readFile, writeFile } from 'node:fs/promises'
import { unwrapParams } from '@/utils/route'

async function readDb(){ try{ return JSON.parse(await readFile(process.cwd()+'/data/db.json','utf8')) }catch{ return {orders:[]} } }
async function writeDb(db:any){ await writeFile(process.cwd()+'/data/db.json', JSON.stringify(db,null,2)) }

export async function GET(_req:Request, { params }:{ params: Promise<{id:string}> }){
  const { id } = await unwrapParams(params)
  const db = await readDb()
  const o = (db.orders||[]).find((x:any)=>String(x.id)===String(id))
  if(!o) return NextResponse.json({error:'not found'},{status:404})
  return NextResponse.json({ returns: o.returns||[] })
}

export async function POST(req:Request, { params }:{ params: Promise<{id:string}> }){
  const { id } = await unwrapParams(params)
  const body = await req.json().catch(()=>null)
  if(!body || !Array.isArray(body.items) || !body.items.length){
    return NextResponse.json({error:'invalid body (need items:[])'},{status:400})
  }
  const db = await readDb()
  const idx = (db.orders||[]).findIndex((x:any)=>String(x.id)===String(id))
  if(idx<0) return NextResponse.json({error:'not found'},{status:404})
  const order = db.orders[idx]
  order.returns = Array.isArray(order.returns)? order.returns : []
  const ret = {
    id: String(Date.now()),
    createdAt: new Date().toISOString(),
    status: 'requested',
    items: body.items.map((i:any)=>({ sku:i.sku, qty:Number(i.qty||0), reason:i.reason||'' }))
  }
  order.returns.push(ret)
  await writeDb(db)
  return NextResponse.json(ret, {status:201})
}
