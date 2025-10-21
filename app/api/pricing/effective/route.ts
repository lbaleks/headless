export const runtime = 'nodejs'
import { NextResponse } from 'next/server'
import { quoteLine, type QuoteLine } from '../../../../data/pricing'

export async function GET() {
  // Minimal “ingenting å regne på ennå”-respons
  return NextResponse.json({
    ok: true,
    pricing: { lines: [], total: 0 }
  })
}

export async function POST(req: Request) {
  try {
    const body = await req.json().catch(() => ({}))
    const lines: QuoteLine[] = Array.isArray(body?.lines) ? body.lines : []

    const priced = lines.map(quoteLine)
    const total = priced.reduce((acc, l) => acc + (l.price ?? 0) * (l.qty ?? 0), 0)

    return NextResponse.json({
      ok: true,
      pricing: { lines: priced, total }
    })
  } catch (err) {
    return NextResponse.json({ ok: false, error: (err as Error).message }, { status: 400 })
  }
}
