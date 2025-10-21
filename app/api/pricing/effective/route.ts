export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { readFile } from 'node:fs/promises'
import { computeEffective } from '@/utils/effectivePricing'

async function readDb(){
  try{
    const raw = await readFile(process.cwd()+'/data/products.json','utf8')
    return JSON.parse(raw||'{}')
  }catch{ return { products:[] } }
}

export async function GET(req:Request){
  const url = new URL(req.url)
  const id = url.searchParams.get('id') || ''
  const db = await readDb()
  const product = (db.products||[]).find((p:any)=> String(p.id)===String(id))
  if(!product) return NextResponse.json({ error:'not found'},{ status:404 })

  let rules:any[]=[]
  try{
    const raw = await readFile(process.cwd()+'/data/pricing.json','utf8')
    const pj = JSON.parse(raw||'{}')
    rules = Array.isArray(pj.rules)? pj.rules : []
  }catch{}

  const effective = computeEffective(product, rules)
  return NextResponse.json({ productId:id, effective, rules: rules.filter((r:any)=>!r.productId || String(r.productId)===String(id)) })
}
