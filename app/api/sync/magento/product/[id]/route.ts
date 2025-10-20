import { NextResponse } from 'next/server'
import { magentoPing } from '@/integrations/magento'

export async function POST(_req:Request, { params }:{ params:{ id:string } }){
  const ping = await magentoPing()
  if(!ping.ok) return NextResponse.json(ping, { status: 400 })
  // TODO: hent produkt, map til Magento, push
  return NextResponse.json({ ok:true, message:'Stub – ready to implement' })
}
