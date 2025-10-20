
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'
const dbPath = path.join(process.cwd(),'data','integrations.json')
async function readDb(){ try{ return JSON.parse(await fs.readFile(dbPath,'utf8')) }catch(e:any){ if(e.code==='ENOENT') return {providers:[]} ; throw e } }
async function writeDb(d:any){ await fs.mkdir(path.dirname(dbPath),{recursive:true}); await fs.writeFile(dbPath, JSON.stringify(d,null,2),'utf8') }

export async function GET(){ const db=await readDb(); return NextResponse.json(db) }

export async function POST(req:Request){ // upsert
  const body = await req.json()
  if(!body?.key) return NextResponse.json({error:'key required'},{status:400})
  const db=await readDb()
  const i = db.providers.findIndex((p:any)=>p.key===body.key)
  if(i===-1) db.providers.push(body)
  else db.providers[i] = {...db.providers[i], ...body}
  await writeDb(db)
  return NextResponse.json(db.providers.find((p:any)=>p.key===body.key), { status: i===-1?201:200 })
}

export async function PUT(req:Request){ // strict update
  const body = await req.json()
  if(!body?.key) return NextResponse.json({error:'key required'},{status:400})
  const db=await readDb()
  const i = db.providers.findIndex((p:any)=>p.key===body.key)
  if(i===-1) return NextResponse.json({error:'Not found'},{status:404})
  db.providers[i] = {...db.providers[i], ...body}
  await writeDb(db)
  return NextResponse.json(db.providers[i])
}

export async function DELETE(req:Request){
  const { searchParams } = new URL(req.url)
  const key = searchParams.get('key')
  if(!key) return NextResponse.json({error:'key required'},{status:400})
  const db=await readDb()
  const before = db.providers.length
  db.providers = db.providers.filter((p:any)=>p.key!==key)
  if(db.providers.length===before) return NextResponse.json({error:'Not found'},{status:404})
  await writeDb(db)
  return NextResponse.json({ok:true})
}
