import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'
const dbPath = path.join(process.cwd(),'data','users.json')
export async function readUsers(){ try{ return JSON.parse(await fs.readFile(dbPath,'utf8')) }catch(e:any){ if(e.code==='ENOENT') return {users:[]} ; throw e}}
export async function writeUsers(data){ await fs.mkdir(path.dirname(dbPath),{recursive:true}); await fs.writeFile(dbPath,JSON.stringify(data,null,2),'utf8') }

export async function GET(req:Request){
  const { searchParams } = new URL(req.url)
  const q=(searchParams.get('q')||'').toLowerCase(), page=parseInt(searchParams.get('page')||'1'), size=parseInt(searchParams.get('size')||'10')
  const db=await readUsers()
  let users=db.users
  if(q) users=users.filter((u:any)=>u.name.toLowerCase().includes(q)||u.email.toLowerCase().includes(q))
  const total=users.length, start=(page-1)*size, end=start+size
  return NextResponse.json({ users:users.slice(start,end), total })
}

export async function POST(req:Request){
  const body=await req.json()
  const db=await readUsers()
  if(db.users.find((u:any)=>u.id===body.id)) return NextResponse.json({error:'ID exists'},{status:409})
  db.users.push(body)
  await writeUsers(db)
  return NextResponse.json(body,{status:201})
}

export async function PUT(req:Request){
  const body=await req.json()
  const db=await readUsers()
  const i=db.users.findIndex((u:any)=>u.id===body.id)
  if(i===-1) return NextResponse.json({error:'Not found'},{status:404})
  db.users[i]=body
  await writeUsers(db)
  return NextResponse.json(body)
}

export async function DELETE(req:Request){
  const { searchParams } = new URL(req.url)
  const id=searchParams.get('id')
  const db=await readUsers()
  db.users=db.users.filter((u:any)=>u.id!==id)
  await writeUsers(db)
  return NextResponse.json({ok:true})
}
