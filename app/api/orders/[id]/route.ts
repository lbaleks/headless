import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'orders.dev.json')
async function readStore(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch {
    return []
  }
}
async function writeStore(items: any[]) {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}
function findIndex(items:any[], id:string){
  return items.findIndex(o => String(o.id)===id || String(o.increment_id)===id)
}

export async function GET(_: Request, ctx: { params: { id: string } }) {
  const id = decodeURIComponent(ctx.params.id)
  const items = await readStore()
  const i = findIndex(items, id)
  if (i === -1) {
    return NextResponse.json({ ok:false, error:'Not found in dev store', id }, { status: 404 })
  }
  return NextResponse.json(items[i])
}

export async function PATCH(req: Request, ctx: { params: { id: string } }) {
  const id = decodeURIComponent(ctx.params.id)
  const body = await req.json().catch(() => ({}))
  const items = await readStore()
  const i = findIndex(items, id)
  if (i === -1) {
    return NextResponse.json({ ok:false, error:'Not found in dev store', id }, { status: 404 })
  }
  const src = items[i] || {}
  const next = {
    ...src,
    status: body.status ?? src.status,
    notes:  body.notes  ?? src.notes,
    updated_at: new Date().toISOString(),
  }
  items[i] = next
  await writeStore(items)
  return NextResponse.json(next)
}
