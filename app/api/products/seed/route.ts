import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const DEV_FILE = path.join(process.cwd(), 'var', 'products.dev.json')

async function readStore(): Promise<any[]> {
  try {
    const txt = await fs.readFile(DEV_FILE, 'utf8')
    const j = JSON.parse(txt)
    return Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : [])
  } catch { return [] }
}

async function writeStore(items: any[]) {
  await fs.mkdir(path.dirname(DEV_FILE), { recursive: true })
  await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2))
}

function now() { return new Date().toISOString() }
function mkSeed(i:number) {
  const id = 100000 + i
  return {
    id,
    sku: `SEED-${Date.now()}-${i}`,
    name: `Seed produkt ${i}`,
    type: 'simple',
    price: 199 + (i * 10),
    status: 1,
    visibility: 4,
    created_at: now(),
    updated_at: now(),
    image: null,
    tax_class_id: '2',
    has_options: false,
    required_options: false,
    source: 'local-override'
  }
}

export async function GET() {
  const items = await readStore()
  return NextResponse.json({ ok:true, total: items.length, items })
}

// Idempotent: append n seed-produkt til var/products.dev.json
export async function POST(req: Request) {
  const { searchParams } = new URL(req.url)
  const n = Math.max(1, Math.min(100, Number(searchParams.get('n') || 5)))

  const items = await readStore()
  const seeds = Array.from({ length: n }, (_, i) => mkSeed(i+1))
  const merged = [...seeds, ...items]
  await writeStore(merged)

  return NextResponse.json({ ok: true, total: merged.length })
}
