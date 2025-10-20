import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

export async function GET(_:Request, { params }: { params:{ sku:string } }) {
  const file = path.join(process.cwd(), 'var', 'audit', `products.${params.sku}.jsonl`)
  try {
    const txt = await fs.readFile(file, 'utf8')
    const lines = txt.trim().split('\n').slice(-50).map(l => JSON.parse(l))
    return NextResponse.json({ total: lines.length, items: lines })
  } catch {
    return NextResponse.json({ total: 0, items: [] })
  }
}
