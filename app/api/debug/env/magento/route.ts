import { NextResponse } from 'next/server'
import { getMagentoConfig } from '@/lib/env'
export const runtime = 'nodejs'; export const revalidate = 0
export async function GET() {
  const cfg = getMagentoConfig()
  return NextResponse.json({
    ok: !!cfg.baseUrl,
    MAGENTO_URL_preview: cfg.baseUrl || null,
    MAGENTO_TOKEN_masked: cfg.token ? '***' : '<empty>',
    hasAdminCreds: !!(cfg.adminUser && cfg.adminPass),
  })
}
