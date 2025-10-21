export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import fs from 'node:fs/promises'
import path from 'node:path'

const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN

async function m2(verb: string, subpath: string, body?: any) {
  if (!M2_BASE || !M2_TOKEN) throw new Error('Missing Magento env')
  const url = `${M2_BASE.replace(/\/+$/, '')}/${subpath.replace(/^\/+/, '')}`
  const res = await fetch(url, {
    method: verb,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${M2_TOKEN}`,
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(`Magento ${verb} ${subpath} failed: ${res.status}`)
  return res.json()
}

// --- GET /api/orders ---
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Math.max(1, Number(searchParams.get('page') || 1))
  const size = Math.max(1, Math.min(200, Number(searchParams.get('size') || 25)))
  const q = (searchParams.get('q') || '').trim().toLowerCase()

  try {
    const params = new URLSearchParams()
    params.set('searchCriteria[currentPage]', String(page))
    params.set('searchCriteria[pageSize]', String(size))
    params.set('searchCriteria[sortOrders][0][field]', 'created_at')
    params.set('searchCriteria[sortOrders][0][direction]', 'DESC')
    const data = await m2('GET', `V1/orders?${params.toString()}`)
    const items = Array.isArray(data?.items) ? data.items : []
    return NextResponse.json({ total: data?.total_count ?? items.length, items })
  } catch {
    try {
      const file = path.join(process.cwd(), 'var', 'orders.dev.json')
      const raw = JSON.parse(await fs.readFile(file, 'utf8'))
      const all: any[] = Array.isArray(raw) ? raw : (Array.isArray(raw.items) ? raw.items : [])
      const filtered = q
        ? all.filter(o => String(o?.increment_id || o?.id || '').toLowerCase().includes(q))
        : all
      const start = (page - 1) * size
      const items = filtered.slice(start, start + size)
      return NextResponse.json({ total: filtered.length, items })
    } catch {
      return NextResponse.json({ total: 0, items: [] })
    }
  }
}

// --- POST /api/orders ---
export async function POST(req: Request) {
  try {
    const p = await req.json()
    const now = new Date().toISOString()
    const id = `ORD-${Date.now()}`
    const order = {
      id,
      increment_id: id,
      status: 'new',
      created_at: now,
      customer: p.customer || {},
      lines: (p.lines || []).map((l: any, i: number) => ({
        ...l,
        rowTotal: l.price ? l.qty * l.price : 0,
        i,
      })),
      notes: p.notes || '',
      total: (p.lines || []).reduce((s: number, l: any) => s + (l.qty * (l.price || 0)), 0),
      source: 'local-stub',
    }

    const file = path.join(process.cwd(), 'var', 'orders.dev.json')
    let arr: any[] = []
    try {
      const raw = JSON.parse(await fs.readFile(file, 'utf8'))
      arr = Array.isArray(raw) ? raw : (Array.isArray(raw.items) ? raw.items : [])
    } catch {}
    arr.unshift(order)
    await fs.mkdir(path.dirname(file), { recursive: true })
    await fs.writeFile(file, JSON.stringify(arr, null, 2))

    return NextResponse.json(order, { status: 201 })
  } catch (err: any) {
    return NextResponse.json({ error: err.message || 'POST failed' }, { status: 500 })
  }
}

// --- PATCH /api/orders ---
export async function PATCH(req: Request) {
  try {
    const url = new URL(req.url)
    const id = url.searchParams.get('id')
    if (!id) return NextResponse.json({ error: 'Missing id' }, { status: 400 })

    const patch = await req.json()
    const file = path.join(process.cwd(), 'var', 'orders.dev.json')
    const raw = JSON.parse(await fs.readFile(file, 'utf8'))
    const arr: any[] = Array.isArray(raw) ? raw : (Array.isArray(raw.items) ? raw.items : [])

    const i = arr.findIndex(o => o.id === id)
    if (i === -1) return NextResponse.json({ error: 'Not found' }, { status: 404 })

    arr[i] = { ...arr[i], ...patch, updated_at: new Date().toISOString() }
    await fs.writeFile(file, JSON.stringify(arr, null, 2))
    return NextResponse.json(arr[i])
  } catch (err: any) {
    return NextResponse.json({ error: err.message || 'PATCH failed' }, { status: 500 })
  }
}

// --- DELETE /api/orders ---
export async function DELETE() {
  try {
    const file = path.join(process.cwd(), 'var', 'orders.dev.json')
    await fs.writeFile(file, '[]')
    return NextResponse.json({ ok: true })
  } catch (err: any) {
    return NextResponse.json({ ok: false, error: err.message })
  }
}
