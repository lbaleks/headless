import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET() {
  const base = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || null
  const token = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || null
  const latestPath = path.join(process.cwd(), 'var', 'jobs', 'latest.json')
  let latestOk = false
  try { await fs.access(latestPath); latestOk = true } catch {}

  return NextResponse.json({
    ok: true,
    env: { base: !!base, token: !!token },
    files: { latestJson: latestOk }
  })
}
