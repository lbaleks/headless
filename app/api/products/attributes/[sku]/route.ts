export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import fs from 'node:fs/promises'
import path from 'node:path'

export async function GET(
  _req: Request,
  { params }: { params: { sku: string } }
) {
  const sku = decodeURIComponent(params.sku || '').trim()
  if (!sku) return NextResponse.json({ ok:false, error:'Missing sku' }, { status: 400 })

  // Attributes priority: var/attributes/<SKU>.json (overrides) → product.attributes
  const filePath = path.join(process.cwd(), 'var', 'attributes', `${sku}.json`)
  let fileAttrs: Record<string, any> = {}
  try {
    const buf = await fs.readFile(filePath)
    fileAttrs = JSON.parse(buf.toString())
  } catch { /* no local override file - fine */ }

  // Also surface merged product (if present)
  let product: any = null
  try {
    const r = await fetch(new URL(`/api/products/${encodeURIComponent(sku)}`, 'http://localhost'), { cache: 'no-store' })
    if (r.ok) product = await r.json()
  } catch { /* ignore */ }

  const merged: Record<string, any> = {
    ...(product?.attributes ?? {}),
    ...fileAttrs, // local file wins
  }

  return NextResponse.json({ ok:true, sku, attributes: merged })
}
