import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''
const DEV_FILE = path.join(process.cwd(), 'var', 'customers.dev.json')

type CustomerDTO = {
  id: number | string
  email: string
  firstname?: string
  lastname?: string
  name?: string
  created_at?: string
  group_id?: number
  is_subscribed?: boolean
  source: 'magento' | 'local-stub'
}

async function ensureVarDir() { await fs.mkdir(path.dirname(DEV_FILE), { recursive: true }) }
async function readDev(): Promise<CustomerDTO[]> {
  try {
    await ensureVarDir()
    const raw = await fs.readFile(DEV_FILE, 'utf8').catch(() => '[]')
    const j = JSON.parse(raw)
    if (Array.isArray(j)) return j
    if (j && Array.isArray(j.items)) return j.items
    return []
  } catch { return [] }
}
async function writeDev(items: CustomerDTO[]) {
  await ensureVarDir()
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

async function m2<T>(verb: string, frag: string): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('missing env')
  const url = `${M2_BASE.replace(/\/+$/, '')}/${frag.replace(/^\/+/, '')}`
  const res = await fetch(url, {
    method: verb,
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${M2_TOKEN}` },
    cache: 'no-store',
  })
  if (!res.ok) throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${await res.text()}`)
  return res.json() as Promise<T>
}

function mapM2Customers(m: any): CustomerDTO[] {
  const items = Array.isArray(m?.items) ? m.items : []
  return items.map((c: any) => ({
    id: c.id ?? c.entity_id ?? c.email,
    email: String(c.email ?? ''),
    firstname: c.firstname,
    lastname: c.lastname,
    name: [c.firstname, c.lastname].filter(Boolean).join(' ') || c.email,
    created_at: c.created_at,
    group_id: c.group_id,
    is_subscribed: c.extension_attributes?.is_subscribed ?? false,
    source: 'magento',
  }))
}

function paginate<T>(arr: T[], page: number, size: number) {
  const start = (page - 1) * size
  const items = arr.slice(start, start + size)
  return { total: arr.length, items }
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Math.max(1, Number(searchParams.get('page') || 1))
  const size = Math.max(1, Number(searchParams.get('size') || 25))
  const q = (searchParams.get('q') || '').trim().toLowerCase()

  try {
    if (M2_BASE && M2_TOKEN) {
      const url = `V1/customers/search?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`
      const data = await m2<any>('GET', url)
      let list = mapM2Customers(data)
      if (q) list = list.filter(c => c.email.toLowerCase().includes(q) || (c.name || '').toLowerCase().includes(q))
      const { total, items } = paginate(list, 1, size)
      return NextResponse.json({ total, items })
    }
    throw new Error('missing env')
  } catch {
    const all = await readDev()
    const filtered = q ? all.filter(c =>
      c.email.toLowerCase().includes(q) || (c.name || '').toLowerCase().includes(q)
    ) : all
    const { total, items } = paginate(filtered, page, size)
    return NextResponse.json({ total, items })
  }
}

export async function DELETE(req: Request) {
  const { searchParams } = new URL(req.url)
  const action = (searchParams.get('action') || '').toLowerCase()

  if (action === 'reset') {
    await writeDev([])
    return NextResponse.json({ ok: true, reset: true })
  }
  if (action === 'seed') {
    const n = Math.max(1, Number(searchParams.get('n') || 5))
    const mk = (i: number): CustomerDTO => ({
      id: i,
      email: `seed+${i}@example.com`,
      firstname: 'Seed',
      lastname: `User ${i}`,
      name: `Seed User ${i}`,
      created_at: new Date().toISOString(),
      group_id: 1,
      is_subscribed: false,
      source: 'local-stub',
    })
    const cur = await readDev()
    for (let i = 1; i <= n; i++) cur.unshift(mk(i))
    await writeDev(cur)
    return NextResponse.json({ ok: true, total: cur.length })
  }

  return NextResponse.json({ ok: false, error: 'Unsupported DELETE. Use ?action=reset|seed' }, { status: 400 })
}