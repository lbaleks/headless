export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import fs from 'fs/promises'
import path from 'path'

const M2_BASE  = process.env.MAGENTO_BASE_URL || process.env.M2_BASE_URL || ''
const M2_TOKEN = process.env.MAGENTO_ADMIN_TOKEN || process.env.M2_ADMIN_TOKEN || ''
const M2_USER  = process.env.MAGENTO_ADMIN_USERNAME || ''
const M2_PASS  = process.env.MAGENTO_ADMIN_PASSWORD || ''
const DEV_FILE = path.join(process.cwd(), 'var', 'customers.dev.json')

async function ensureVarDir(){ await fs.mkdir(path.dirname(DEV_FILE),{recursive:true}) }
async function writeDev(items:any[]){ await ensureVarDir(); await fs.writeFile(DEV_FILE, JSON.stringify(items, null, 2)) }

async function m2<T>(verb:string, frag:string, token:string):Promise<{ok:boolean,status:number,json:any}>{
  const url = `${M2_BASE.replace(/\/+$/,'')}/${frag.replace(/^\/+/,'')}`
  const r = await fetch(url, { method:verb, headers:{Authorization:`Bearer ${token}`}, cache:'no-store' })
  const text = await r.text()
  let json:any = null
  try { json = text ? JSON.parse(text) : null } catch { json = text }
  return { ok:r.ok, status:r.status, json }
}

async function getAdminToken():Promise<string|null>{
  if(!M2_USER || !M2_PASS) return null
  const url = `${M2_BASE.replace(/\/+$/,'')}/V1/integration/admin/token`
  const r = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({username:M2_USER, password:M2_PASS}) })
  if(!r.ok) return null
  const t = await r.json().catch(()=>null)
  return typeof t === 'string' && t.length > 0 ? t : null
}

function mapM2Customers(m:any){
  const items = Array.isArray(m?.items) ? m.items : []
  return items.map((c:any)=>({
    id: c.id ?? c.entity_id ?? c.email,
    email: String(c.email ?? ''),
    firstname: c.firstname,
    lastname: c.lastname,
    name: [c.firstname, c.lastname].filter(Boolean).join(' ') || c.email,
    created_at: c.created_at,
    group_id: c.group_id,
    is_subscribed: c.extension_attributes?.is_subscribed ?? false,
    source: 'magento',
  }))
}

export async function POST(){
  try{
    if(!M2_BASE) return NextResponse.json({ok:false, error:'missing MAGENTO_BASE_URL / M2_BASE_URL'}, {status:400})
    let token = M2_TOKEN
    if(!token && M2_USER && M2_PASS){
      token = await getAdminToken() || ''
    }
    if(!token) return NextResponse.json({ok:false, error:'no token available (env or admin login)'}, {status:401})

    // 1. forsøk
    let resp = await m2<any>('GET', 'V1/customers/search?searchCriteria[currentPage]=1&searchCriteria[pageSize]=100', token)

    // Hvis 401 -> forsøk å hente admin-token og retry
    if(resp.status === 401){
      const fresh = await getAdminToken()
      if(fresh){
        token = fresh
        resp = await m2<any>('GET', 'V1/customers/search?searchCriteria[currentPage]=1&searchCriteria[pageSize]=100', token)
      }
    }

    if(!resp.ok) return NextResponse.json({ ok:false, error:`Magento GET failed: ${resp.status}`, detail:resp.json }, {status:resp.status||500})

    const items = mapM2Customers(resp.json)
    await writeDev(items)
    return NextResponse.json({ ok:true, saved: items.length })
  }catch(e:any){
    return NextResponse.json({ ok:false, error:String(e) }, { status: 500 })
  }
}
