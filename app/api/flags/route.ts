export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'
const dbPath = path.join(process.cwd(),'data','flags.json')
async function readDb(){ try{ return JSON.parse(await fs.readFile(dbPath,'utf8')) }catch(e:any){ if(e.code==='ENOENT') return {flags:[]} ; throw e } }
async function writeDb(d:any){ await fs.mkdir(path.dirname(dbPath),{recursive:true}); await fs.writeFile(dbPath, JSON.stringify(d,null,2),'utf8') }

export async function GET(){ const db=await readDb(); return NextResponse.json(db) }

export async function POST(req:Request){
  const b = await req.json()
  if(!b?.key) return NextResponse.json({error:'key required'},{status:400})
  const db=await readDb()
  if(db.flags.some((f:any)=>f.key===b.key)) return NextResponse.json({error:'exists'},{status:409})
  db.flags.push({ key:b.key, name:b.name||b.key, enabled:!!b.enabled, desc:b.desc||'' })
  await writeDb(db); return NextResponse.json({ok:true},{status:201})
}

export async function PUT(req:Request){
  const b = await req.json()
  if(!b?.key) return NextResponse.json({error:'key required'},{status:400})
  const db=await readDb()
  const i = db.flags.findIndex((f:any)=>f.key===b.key)
  if(i===-1) return NextResponse.json({error:'not found'},{status:404})
  db.flags[i] = {...db.flags[i], ...b}
  await writeDb(db); return NextResponse.json(db.flags[i])
}

export async function DELETE(req:Request){
  const { searchParams } = new URL(req.url)
  const key = searchParams.get('key')
  const db=await readDb()
  db.flags = db.flags.filter((f:any)=>f.key!==key)
  await writeDb(db)
  return NextResponse.json({ok:true})
}
