import { NextResponse } from 'next/server'
import { BASE } from '@/lib/magento'

export async function GET() {
  return NextResponse.json({
    ok: true,
    hasBase: !!BASE,
    hasToken: !!process.env.MAGENTO_ADMIN_TOKEN || !!process.env.M2_ADMIN_TOKEN || !!process.env.M2_TOKEN,
    base: BASE,
    tokenPrefix: (process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || process.env.M2_TOKEN || '').slice(0, 6) + '…',
  })
}
