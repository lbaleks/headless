export const runtime = 'nodejs';
/* eslint-disable 'no-constant-binary-expression' */
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''
const M2_USER  = process.env.MAGENTO_ADMIN_USERNAME || ''
const M2_PASS  = process.env.MAGENTO_ADMIN_PASSWORD || ''
const DEV_FILE = path.join(process.cwd(), 'var', 'orders.dev.json')

async function ensureVarDir(){ await fs.mkdir(path.dirname(DEV_FILE),{recursive:true}) }
async function writeDev(items:any[]){ await ensureVarDir(); await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2)) }

async function m2(verb:string, frag:string, token:string){
  const url = `${M2_BASE.replace(/\/+$/,'')}/${frag.replace(/^\/+/,'')}`
  const r = await fetch(url, { method:verb, headers:{Authorization:`Bearer ${token}`}, cache:'no-store' })
  const text = await r.text()
  let json:any = null; try{ json = text ? JSON.parse(text) : null }catch{ json = text }
  return { ok:r.ok, status:r.status, json, url }
}
async function getAdminToken():Promise<string|null>{
  if(!M2_USER || !M2_PASS || !M2_BASE) return null
  const url = `${M2_BASE.replace(/\/+$/,'')}/V1/integration/admin/token`
  const r = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({username:M2_USER, password:M2_PASS}) })
  if(!r.ok) return null
  const t = await r.json().catch(()=>null)
  return typeof t === 'string' && t.length>0 ? t : null
}

// Map Magento order -> vårt dev-format
function mapM2Orders(m:any){
  const items = Array.isArray(m?.items) ? m.items : []
  return items.map((o:any)=>{
    const first = Array.isArray(o.items) && o.items[0] ? o.items[0] : null
    const line = first ? {
      sku: first.sku,
      productId: first.product_id ?? null,
      name: first.name,
      qty: Number(first.qty_ordered ?? first.qty ?? 0),
      price: Number(first.price ?? 0),
      rowTotal: Number(first.row_total ?? (Number(first.price ?? 0) * Number(first.qty_ordered ?? 0)) ?? 0),
      i: 0,
    } : null
    const email = o.customer_email || o.billing_address?.email || null
    return {
      id: String(o.increment_id || o.entity_id || `ORD-${o.created_at||Date.now()}`),
      increment_id: String(o.increment_id || o.entity_id || ''),
      status: String(o.status || o.state || 'new'),
      created_at: o.created_at || new Date().toISOString(),
      customer: email ? { email } : {},
      lines: line ? [line] : [],
      notes: '',
      total: Number(o.grand_total ?? 0),
      source: 'magento'
    }
  })
}

export async function POST(){
  try{
    if(!M2_BASE) return NextResponse.json({ok:false, error:'missing MAGENTO_BASE_URL / M2_BASE_URL'}, {status:400})

    let token = M2_TOKEN || ''
    if(!token){
      token = await getAdminToken() || ''
    }
    if(!token) return NextResponse.json({ok:false, error:'no token available (env or admin login)'}, {status:401})

    // hent siste 50 ordre, sortert nyest først
    const frag = 'V1/orders?searchCriteria[currentPage]=1&searchCriteria[pageSize]=50&searchCriteria[sortOrders][0][field]=created_at&searchCriteria[sortOrders][0][direction]=DESC'
    let resp = await m2('GET', frag, token)

    if(resp.status === 401){
      const fresh = await getAdminToken()
      if(fresh){
        token = fresh
        resp = await m2('GET', frag, token)
      }
    }
    if(!resp.ok) return NextResponse.json({ ok:false, error:`Magento GET failed: ${resp.status}`, detail:resp.json }, {status:resp.status||500})

    const mapped = mapM2Orders(resp.json)
    // Skriv direkte som array (matcher deres nåværende orders-store)
    await writeDev(mapped)
    return NextResponse.json({ ok:true, saved: mapped.length })
  }catch(e:any){
    return NextResponse.json({ ok:false, error:String(e) }, { status: 500 })
  }
}
