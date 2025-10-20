import { NextResponse } from 'next/server'
import { readPricing, writePricing } from '@/utils/pricingStore'

export async function GET(){
  const rules = await readPricing()
  return NextResponse.json({ rules })
}

export async function PUT(req: Request){
  const body = await req.json().catch(()=>null) as any
  const rules = Array.isArray(body?.rules) ? body.rules : null
  if(!rules) return NextResponse.json({ error:'rules must be an array' }, { status:400 })
  await writePricing(rules)
  const saved = await readPricing() // confirm persisted
  return NextResponse.json({ ok:true, rules: saved })
}
