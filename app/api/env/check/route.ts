// app/api/env/check/route.ts
import { NextResponse } from 'next/server'
export const runtime = 'nodejs'

export async function GET() {
  const u = process.env.MAGENTO_URL || ''
  const t = process.env.MAGENTO_TOKEN || ''
  // mask token for display
  const masked = t ? (t.length > 6 ? t.slice(0,3) + '...' + t.slice(-3) : '***') : '<empty>'
  return NextResponse.json({
    ok: true,
    MAGENTO_URL_present: Boolean(u),
    MAGENTO_TOKEN_present: Boolean(t),
    MAGENTO_URL_preview: u ? (u.replace(/https?:\/\//,'').slice(0,60)) : '<empty>',
    MAGENTO_TOKEN_masked: masked,
    note: 'If these are false/empty, restart dev after editing .env.local'
  })
}
