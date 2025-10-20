
import { NextResponse } from 'next/server'
import { fetchOrders } from '@/integrations/magento/client'
import { promises as fs } from 'fs'
import path from 'path'
const p = path.join(process.cwd(),'data','orders.json')
export async function POST(){
  const orders = await fetchOrders()
  await fs.mkdir(path.dirname(p),{recursive:true}); await fs.writeFile(p, JSON.stringify({orders},null,2),'utf8')
  return NextResponse.json({ ok:true, count:orders.length })
}
