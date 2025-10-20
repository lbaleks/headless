import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''
const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

type ProductDTO = {
  id: number | string
  sku: string
  name: string
  type: string
  price: number
  status: number
  visibility: number
  created_at?: string
  updated_at?: string
  image?: string | null
  tax_class_id?: string | number | null
  has_options?: boolean
  required_options?: boolean
  source: 'magento' | 'local-stub'
}

async function ensureVarDir() {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
}
async function readDev(): Promise<ProductDTO[]> {
  try {
    await ensureVarDir()
    const raw = await fs.readFile(DEV_FILE, 'utf8').catch(() => '[]')
    const j = JSON.parse(raw)
    if (Array.isArray(j)) return j
    if (j && Array.isArray(j.items)) return j.items
    return []
  } catch { return [] }
}
async function writeDev(items: ProductDTO[]) {
  await ensureVarDir()
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

async function m2<T>(verb: string, frag: string, body?: any): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('missing env')
  const url = `${M2_BASE.replace(/\/+$/, '')}/${frag.replace(/^\/+/, '')}`
  const res = await fetch(url, {
    method: verb,
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${M2_TOKEN}` },
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  })
  if (!res.ok) throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${await res.text()}`)
  return res.json() as Promise<T>
}

function mapM2Products(m: any): ProductDTO[] {
  const items = Array.isArray(m?.items) ? m.items : []
  return items.map((p: any) => ({
    id: p.id ?? p.sku,
    sku: String(p.sku ?? ''),
    name: String(p.name ?? ''),
    type: String(p.type_id ?? p.type ?? 'simple'),
    price: Number(p.price ?? 0),
    status: Number(p.status ?? 2),
    visibility: Number(p.visibility ?? 4),
    created_at: p.created_at,
    updated_at: p.updated_at,
    image: p.custom_attributes?.find?.((a: any) => a.attribute_code === 'image')?.value ?? null,
    tax_class_id: p.custom_attributes?.find?.((a: any) => a.attribute_code === 'tax_class_id')?.value ?? null,
    has_options: Boolean(p.has_options ?? false),
    required_options: Boolean(p.required_options ?? false),
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
      const url = `V1/products?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`
      const data = await m2<any>('GET', url)
      let list = mapM2Products(data)
      if (q) list = list.filter(p => p.sku.toLowerCase().includes(q) || p.name.toLowerCase().includes(q))
      const { total, items } = paginate(list, 1, size)
      return NextResponse.json({ total, items })
    }
    throw new Error('missing env')
  } catch {
    const all = await readDev()
    const filtered = q ? all.filter(p =>
      p.sku.toLowerCase().includes(q) || p.name.toLowerCase().includes(q)
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
    const mk = (i: number): ProductDTO => ({
      id: i,
      sku: `SEED-${i}`,
      name: `Seed produkt ${i}`,
      type: 'simple',
      price: 199 + i,
      status: 1,
      visibility: 4,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      image: null,
      tax_class_id: 2,
      has_options: false,
      required_options: false,
      source: 'local-stub',
    })
    const cur = await readDev()
    for (let i = 1; i <= n; i++) cur.unshift(mk(i))
    await writeDev(cur)
    return NextResponse.json({ ok: true, total: cur.length })
  }

  return NextResponse.json({ ok: false, error: 'Unsupported DELETE. Use ?action=reset|seed' }, { status: 400 })
}