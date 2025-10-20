import { NextResponse } from 'next/server'

type Line = { sku: string, name: string, qty: number, price: number, rowTotal: number }
type DevOrder = {
  id: string, increment_id: string, status: string, created_at: string,
  customer: { email: string, firstname?: string, lastname?: string },
  lines: Line[], notes?: string, total: number, source: 'local-stub'
}

function mk(idNum:number): DevOrder {
  const id = `ORD-${Date.now()}-${idNum}`
  const qty = (idNum % 3) + 1
  const price = 199 + (idNum % 4) * 50
  const line = { sku:'TEST', name:'TEST', qty, price, rowTotal: qty*price }
  return {
    id, increment_id: id, status: 'new', created_at: new Date().toISOString(),
    customer: { email:`dev+${idNum}@example.com` },
    lines: [line], notes:'seed', total: line.rowTotal, source:'local-stub'
  }
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url)
  const n = Math.max(1, Math.min(100, parseInt(searchParams.get('n') || '5', 10) || 5))
  const fs = await import('fs/promises')
  const p = `${process.cwd()}/var/orders.dev.json`
  const raw = await fs.readFile(p, 'utf8').catch(()=> '[]')
  const arr: DevOrder[] = JSON.parse(raw || '[]')
  const add = Array.from({length:n}, (_,i)=> mk(i+1))
  const next = [...add, ...arr]
  await fs.writeFile(p, JSON.stringify(next, null, 2))
  return NextResponse.json({ ok:true, seeded: n, total: next.length })
}
