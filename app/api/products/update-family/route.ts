export const runtime = 'nodejs';
import { NextRequest, NextResponse } from 'next/server'
import { promises as fs } from 'fs'
import path from 'path'

type P = Record<string,any>

export async function POST(req:NextRequest) {
  const { sku, family } = await req.json().catch(()=> ({} as any))
  if(!sku) return NextResponse.json({ok:false,error:'missing sku'},{status:400})

  const file = path.join(process.cwd(),'var','products.dev.json')
  let items:P[] = []
  try { items = JSON.parse(await fs.readFile(file,'utf8')) } catch {}

  let touched = false
  items = items.map(p => {
    if (p?.sku === sku) { touched = true; return { ...p, family: family ?? 'default' } }
    return p
  })
  if (!touched) { // create minimal local override if it doesn't exist yet
    items.push({ id: Date.now(), sku, family: family ?? 'default', source:'local-override' })
  }
  await fs.mkdir(path.dirname(file), { recursive:true })
  await fs.writeFile(file, JSON.stringify(items,null,2))

  return NextResponse.json({ ok:true, sku, family: family ?? 'default' })
}
