export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

export async function GET() {
  const p = path.join(process.cwd(), 'var', 'akeneo', 'families.json')
  const raw = await fs.readFile(p, 'utf8')
  const data = JSON.parse(raw)
  return NextResponse.json({ ok:true, ...data }, { headers: {'cache-control':'no-store'} })
}
