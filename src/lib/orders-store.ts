import fs from 'fs'
import path from 'path'
import { randomUUID } from 'crypto'

export type OrderLine = {
  productId: string
  variantId?: string
  qty: number
  price?: number
  title?: string
}

export type Order = {
  id: string
  createdAt: string
  customer?: {
    id?: string
    email?: string
    name?: string
    phone?: string
  }
  lines: OrderLine[]
  notes?: string
}

const DATA_DIR = path.join(process.cwd(), 'data')
const FILE = path.join(DATA_DIR, 'orders.json')

function ensureFile() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true })
  if (!fs.existsSync(FILE)) fs.writeFileSync(FILE, '[]', 'utf8')
}

function readAll(): Order[] {
  ensureFile()
  const raw = fs.readFileSync(FILE, 'utf8')
  try {
    const arr = JSON.parse(raw)
    return Array.isArray(arr) ? arr : []
  } catch {
    return []
  }
}

function writeAll(orders: Order[]) {
  ensureFile()
  fs.writeFileSync(FILE, JSON.stringify(orders, null, 2), 'utf8')
}

export function listOrders(): Order[] {
  return readAll().sort((a,b)=> (a.createdAt<b.createdAt?1:-1))
}

export function getOrder(id: string): Order | undefined {
  return readAll().find(o => o.id === id)
}

export function createOrder(input: {
  customer?: Order['customer']
  lines: OrderLine[]
  notes?: string
}): Order {
  const order: Order = {
    id: randomUUID(),
    createdAt: new Date().toISOString(),
    customer: input.customer,
    lines: input.lines || [],
    notes: input.notes?.trim() || undefined
  }
  const all = readAll()
  all.push(order)
  writeAll(all)
  return order
}
