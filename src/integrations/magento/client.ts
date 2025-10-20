
import { promises as fs } from 'fs'
import path from 'path'

const BASE = process.env.MAGENTO_BASE_URL || ''
const TOKEN = process.env.MAGENTO_TOKEN || ''
const MOCK_DIR = path.join(process.cwd(), 'data', 'magento')

async function mockRead(file:string){
  const p = path.join(MOCK_DIR, file)
  const raw = await fs.readFile(p, 'utf8')
  return JSON.parse(raw)
}
async function apiGet(endpoint:string, qs:Record<string,any> = {}){
  if(!BASE || !TOKEN){ // fallback
    if(endpoint.includes('orders')) return mockRead('orders.json')
    if(endpoint.includes('products')) return mockRead('products.json')
    return { ok:false, mock:true }
  }
  const u = new URL(endpoint, BASE)
  Object.entries(qs).forEach(([k,v])=> v!=null && u.searchParams.set(k,String(v)))
  const r = await fetch(u.toString(), {
    headers: { 'Authorization': 'Bearer '+TOKEN, 'Content-Type':'application/json' }
  })
  if(!r.ok) throw new Error(`Magento GET ${u} -> ${r.status}`)
  return r.json()
}

export async function health(){
  try{
    if(!BASE || !TOKEN){
      // mock health
      const ok = true
      return { ok, mock:true, base: BASE, ts: new Date().toISOString() }
    }
    // liten “ping” – bruk en lett endpoint (store/storeConfigs? eller self)
    const ts = new Date().toISOString()
    return { ok:true, mock:false, base: BASE, ts }
  }catch(e:any){
    return { ok:false, error:e?.message||String(e), base: BASE }
  }
}

export type M2Product = { id:string; sku:string; name:string; price:number; status?:string; stock?:number; category?:string }
export type M2Order = {
  id:string; increment_id?:string; status:string; created_at:string;
  currency?:string; grand_total:number; items:{ sku:string; name:string; qty:number; price:number }[]
}

export async function fetchProducts():Promise<M2Product[]>{
  const data:any = await apiGet('/rest/V1/products', { searchCriteria:'{}' }).catch(()=>apiGet('/products'))
  // normalisering for mock/real
  if(Array.isArray(data?.items)){
    return data.items.map((x:any)=>({
  id:String(x.id),
  sku:x.sku,
  name:x.name,
  price:Number(x.price||0),
  status:String(x.status||'active'),
  stock:Number(x.extension_attributes?.stock_item?.qty ?? 0),
  // ny: innkjøpspris
  cost: Number(
    (x.custom_attributes||[]).find((a:any)=>a.attribute_code==='cost')?.value ?? 0
  ) || 0
}))
  }
  if(Array.isArray(data?.products)){
    return data.products
  }
  return []
}

export async function fetchOrders():Promise<M2Order[]>{
  const data:any = await apiGet('/rest/V1/orders', { searchCriteria:'{}' }).catch(()=>apiGet('/orders'))
  if(Array.isArray(data?.items)){
    return data.items.map((o:any)=>({
      id:String(o.entity_id||o.id), increment_id:o.increment_id, status:o.status||'processing', created_at:o.created_at||new Date().toISOString(),
      currency:o.order_currency_code||'NOK', grand_total:Number(o.grand_total||0),
      items:(o.items||[]).map((i:any)=>({ sku:i.sku, name:i.name, qty:Number(i.qty_ordered||1), price:Number(i.price||0) }))
    }))
  }
  if(Array.isArray(data?.orders)) return data.orders
  return []
}
