export const runtime = 'nodejs';
// app/api/env/check-loader/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig } from '../../../../lib/env'


export async function GET() {
  try {
    const cfg = await getMagentoConfig()
    const masked = cfg.token ? (cfg.token.length>6 ? cfg.token.slice(0,3)+'...'+cfg.token.slice(-3) : '***') : '<empty>'
    return NextResponse.json({
      ok: true,
      source: 'loader',
      baseUrl: cfg.baseUrl,
      rawBase: cfg.rawBase,
      tokenMasked: masked
    })
  } catch (e: any) {
    return NextResponse.json({ ok:false, error: String(e?.message || e) }, { status: 500 })
  }
}
