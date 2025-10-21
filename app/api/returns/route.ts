export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { dirname } from 'node:path'
const FILE='data/returns.json'

async function load(){
  try{ return JSON.parse(await readFile(FILE,'utf8')) }catch{ return { returns: [] } }
}
async function save(obj:any){ await mkdir(dirname(FILE),{recursive:true}); await writeFile(FILE, JSON.stringify(obj,null,2)) }

export async function GET(){
  const db = await load()
  return NextResponse.json({ returns: db.returns||[] })
}

export async function POST(req:Request){
  const body = await req.json().catch(()=>null)
  if(!body || !body.orderId) return NextResponse.json({ok:false,error:'bad body'},{status:400})
  const db = await load()
  const r = { id: `R${Date.now()}`, orderId: body.orderId, status:'open', items: body.items||[], created_at: new Date().toISOString() }
  db.returns = [...(db.returns||[]), r]
  await save(db)
  return NextResponse.json({ok:true, return: r})
}
