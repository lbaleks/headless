import { NextResponse } from 'next/server'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const sku = (url.searchParams.get('sku') || '').trim()
  if (!sku) return NextResponse.json({ ok:false, error:'Missing sku' }, { status: 400 })
  return NextResponse.redirect(new URL(`/api/products/attributes/${encodeURIComponent(sku)}`, req.url), { status: 307 })
}
