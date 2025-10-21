export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { fetchProducts } from '@/integrations/magento/client'
import { promises as fs } from 'fs'
import path from 'path'
const p = path.join(process.cwd(),'data','products.json')
export async function POST(){
  const items = await fetchProducts()
  const mapped = items.map(p=>({ id:p.id, sku:p.sku, name:p.name, price:p.price, margin:0.3, stock:p.stock??0, status:(p.status as any)||'active', category:p.category||'' }))
  const db = { products: mapped }
  await fs.mkdir(path.dirname(p),{recursive:true}); await fs.writeFile(p, JSON.stringify(db,null,2),'utf8')
  return NextResponse.json({ ok:true, count:mapped.length })
}
