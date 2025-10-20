// app/api/orders/route.ts
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

// ---------- Konfig / hjelpefunksjoner ----------
const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''

const DEV_FILE = path.join(process.cwd(), 'var', 'orders.dev.json')

type OrderLine = {
  sku: string
  productId?: number | null
  name?: string
  qty: number
  price?: number
  rowTotal?: number
  i?: number
}

type OrderDTO = {
  id: string
  increment_id: string
  status: string
  created_at: string
  updated_at?: string
  customer: { email: string; firstname?: string; lastname?: string }
  lines: OrderLine[]
  notes?: string
  total: number
  source: 'magento' | 'local-stub'
}

async function ensureVarDir() {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
}

async function readDev(): Promise<OrderDTO[]> {
  try {
    await ensureVarDir()
    const raw = await fs.readFile(DEV_FILE, 'utf8').catch(() => '[]')
    const j = JSON.parse(raw)
    if (Array.isArray(j)) return j
    if (j && Array.isArray(j.items)) return j.items
    return []
  } catch {
    return []
  }
}

async function writeDev(items: OrderDTO[]) {
  await ensureVarDir()
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

function calcTotals(lines: OrderLine[]) {
  const withTotals = (lines || []).map((l, i) => {
    const price = Number(l.price ?? 0)
    const qty   = Number(l.qty ?? 0)
    return { ...l, name: l.name ?? l.sku, rowTotal: price * qty, i }
  })
  const total = withTotals.reduce((s, l) => s + Number(l.rowTotal ?? 0), 0)
  return { lines: withTotals, total }
}

function paginate<T>(arr: T[], page: number, size: number) {
  const start = (page - 1) * size
  const items = arr.slice(start, start + size)
  return { total: arr.length, items }
}

async function m2<T>(verb: string, pathFrag: string, body?: any): Promise<T> {
  if (!M2_BASE || !M2_TOKEN) throw new Error('missing env')
  const url = `${M2_BASE.replace(/\/+$/, '')}/${pathFrag.replace(/^\/+/, '')}`
  const res = await fetch(url, {
    method: verb,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${M2_TOKEN}`,
    },
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  })
  if (!res.ok) {
    const sample = await res.text().catch(() => '')
    throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${sample}`)
  }
  return res.json() as Promise<T>
}

function magentoOrdersToDTO(m: any): OrderDTO[] {
  const items = Array.isArray(m?.items) ? m.items : []
  return items.map((o: any) => {
    const id = String(o.increment_id || o.entity_id || o.id || `M2-${o?.created_at || Date.now()}`)
    const lines: OrderLine[] = Array.isArray(o.items)
      ? o.items.map((it: any, i: number) => ({
          sku: String(it.sku ?? ''),
          productId: it.product_id ?? null,
          name: String(it.name ?? it.sku ?? ''),
          qty: Number(it.qty_ordered ?? it.qty ?? 0),
          price: Number(it.price ?? 0),
          rowTotal: Number(it.row_total ?? (Number(it.price ?? 0) * Number(it.qty_ordered ?? 0))),
          i,
        }))
      : []
    const total =
      Number(o.grand_total ?? 0) ||
      lines.reduce((s, l) => s + Number(l.rowTotal ?? 0), 0)

    return {
      id,
      increment_id: id,
      status: String(o.status ?? 'new'),
      created_at: String(o.created_at ?? new Date().toISOString()),
      updated_at: o.updated_at ? String(o.updated_at) : undefined,
      customer: {
        email: String(o.customer_email ?? ''),
        firstname: o.customer_firstname,
        lastname: o.customer_lastname,
      },
      lines,
      notes: '',
      total,
      source: 'magento',
    }
  })
}

// ---------- GET: liste ordrer ----------
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const page = Math.max(1, Number(searchParams.get('page') || 1))
  const size = Math.max(1, Number(searchParams.get('size') || 25))
  const q    = (searchParams.get('q') || '').trim().toLowerCase()

  // Prøv Magento først – soft-fail til dev
  try {
    if (M2_BASE && M2_TOKEN) {
      const sort = 'searchCriteria[sortOrders][0]'
      const url  = `V1/orders?searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}&${sort}[field]=created_at&${sort}[direction]=DESC`
      const data = await m2<any>('GET', url)
      let list  = magentoOrdersToDTO(data)

      if (q) {
        list = list.filter(o =>
          o.increment_id.toLowerCase().includes(q) ||
          o.customer.email.toLowerCase().includes(q) ||
          o.lines.some(l => l.sku.toLowerCase().includes(q))
        )
      }
      const { total, items } = paginate(list, 1, size) // Magento leverte allerede side, men filtrering lokalt kan påvirke
      return NextResponse.json({ total, items })
    }
    throw new Error('missing env')
  } catch {
    // Dev fallback
    const all = await readDev()
    const filtered = q
      ? all.filter(o =>
          o.increment_id.toLowerCase().includes(q) ||
          (o.customer?.email || '').toLowerCase().includes(q) ||
          (o.lines || []).some(l => (l.sku || '').toLowerCase().includes(q))
        )
      : all
    const { total, items } = paginate(filtered, page, size)
    return NextResponse.json({ total, items })
  }
}

// ---------- POST: opprett stub-ordre (dev) ----------
export async function POST(req: Request) {
  try {
    const body = await req.json().catch(() => ({}))
    const customer = body.customer || { email: '' }
    const linesIn  = Array.isArray(body.lines) ? body.lines : []
    const { lines, total } = calcTotals(linesIn)

    const now = new Date().toISOString()
    const id  = `ORD-${Date.now()}`
    const dto: OrderDTO = {
      id,
      increment_id: id,
      status: 'new',
      created_at: now,
      customer: { email: String(customer.email || '') },
      lines,
      notes: String(body.notes || ''),
      total,
      source: 'local-stub',
    }

    const current = await readDev()
    current.unshift(dto)
    await writeDev(current)

    return NextResponse.json(dto, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || 'POST failed' }, { status: 500 })
  }
}

// ---------- PATCH: oppdater stub-ordre (dev) ----------
export async function PATCH(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    const id = searchParams.get('id') || ''
    if (!id) return NextResponse.json({ ok: false, error: 'Missing id' }, { status: 400 })

    const patch = await req.json().catch(() => ({}))
    const list = await readDev()
    const idx = list.findIndex(o => o.id === id)
    if (idx === -1) return NextResponse.json({ ok: false, error: 'Not found' }, { status: 404 })

    const prev = list[idx]
    const updated: OrderDTO = {
      ...prev,
      ...patch,
      lines: patch.lines ? calcTotals(patch.lines).lines : prev.lines,
      total: patch.lines ? calcTotals(patch.lines).total : (patch.total ?? prev.total),
      updated_at: new Date().toISOString(),
    }

    list[idx] = updated
    await writeDev(list)
    return NextResponse.json(updated)
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || 'PATCH failed' }, { status: 500 })
  }
}

// ---------- DELETE: dev-hjelp (reset/seed/slett) ----------
export async function DELETE(req: Request) {
  try {
    const { searchParams } = new URL(req.url)
    const action = (searchParams.get('action') || '').toLowerCase()

    if (action === 'reset') {
      await writeDev([])
      return NextResponse.json({ ok: true, reset: true })
    }

    if (action === 'seed') {
      const n = Math.max(1, Number(searchParams.get('n') || 5))
      const now = () => new Date().toISOString()
      const mk = (i: number): OrderDTO => {
        const qty = (i % 3) + 1
        const price = 199
        const total = qty * price
        const id = `ORD-${Date.now()}-${i}`
        return {
          id,
          increment_id: id,
          status: 'new',
          created_at: now(),
          customer: { email: `dev+${i}@example.com` },
          lines: [{ sku: 'TEST', productId: null, name: 'TEST', qty, price, rowTotal: total, i: 0 }],
          notes: 'seed',
          total,
          source: 'local-stub',
        }
      }
      const current = await readDev()
      for (let i = 1; i <= n; i++) current.unshift(mk(i))
      await writeDev(current)
      return NextResponse.json({ ok: true, total: current.length })
    }

    // delete by id (optional)
    const id = searchParams.get('id')
    if (id) {
      const list = await readDev()
      const next = list.filter(o => o.id !== id)
      await writeDev(next)
      return NextResponse.json({ ok: true, total: next.length })
    }

    return NextResponse.json({ ok: false, error: 'Unsupported DELETE. Use ?action=reset|seed or ?id=' }, { status: 400 })
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || 'DELETE failed' }, { status: 500 })
  }
}