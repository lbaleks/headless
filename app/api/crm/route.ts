
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'
const dbPath = path.join(process.cwd(),'data','crm.json')
async function readDb(){ try{ return JSON.parse(await fs.readFile(dbPath,'utf8')) }catch(e:any){ if(e.code==='ENOENT') return {activities:[],tasks:[]}; throw e } }
async function writeDb(db:any){ await fs.mkdir(path.dirname(dbPath),{recursive:true}); await fs.writeFile(dbPath, JSON.stringify(db,null,2)) }

export async function GET(req:Request){
  const { searchParams } = new URL(req.url)
  const type = searchParams.get('type') // 'activities' | 'tasks'
  const cid = searchParams.get('customerId')
  const db = await readDb()
  if(type==='activities'){
    const items=(db.activities||[]).filter((x:any)=>!cid || x.customerId===cid)
    return NextResponse.json({ activities: items })
  }
  if(type==='tasks'){
    const items=(db.tasks||[]).filter((x:any)=>!cid || x.customerId===cid)
    return NextResponse.json({ tasks: items })
  }
  return NextResponse.json({ activities: db.activities||[], tasks: db.tasks||[] })
}

export async function POST(req:Request){
  const body=await req.json()
  const db=await readDb()
  const nowId=()=>String(Date.now())
  if(body.type==='activity'){
    const item={ id: nowId(), ...body.data }
    db.activities = [item, ...(db.activities||[])]
    await writeDb(db); return NextResponse.json({ ok:true, activity:item })
  }
  if(body.type==='task'){
    const item={ id: nowId(), status:'open', ...body.data }
    db.tasks = [item, ...(db.tasks||[])]
    await writeDb(db); return NextResponse.json({ ok:true, task:item })
  }
  return NextResponse.json({error:'Unknown type'},{status:400})
}

export async function PUT(req:Request){
  const body=await req.json()
  const db=await readDb()
  if(body.type==='task'){
    const i=(db.tasks||[]).findIndex((x:any)=>x.id===body.data?.id)
    if(i>-1){ db.tasks[i]={...db.tasks[i],...body.data}; await writeDb(db); return NextResponse.json({ ok:true, task: db.tasks[i] })}
  }
  return NextResponse.json({error:'Not found'},{status:404})
}

export async function DELETE(req:Request){
  const { searchParams } = new URL(req.url)
  const type=searchParams.get('type'); const id=searchParams.get('id')
  const db=await readDb()
  if(type==='task'){
    db.tasks=(db.tasks||[]).filter((x:any)=>x.id!==id); await writeDb(db); return NextResponse.json({ ok:true })
  }
  if(type==='activity'){
    db.activities=(db.activities||[]).filter((x:any)=>x.id!==id); await writeDb(db); return NextResponse.json({ ok:true })
  }
  return NextResponse.json({error:'Unknown type'},{status:400})
}
