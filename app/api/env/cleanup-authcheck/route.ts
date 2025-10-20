// app/api/env/cleanup-authcheck/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const runtime = 'nodejs'

export async function POST() {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    const sku = '__authcheck__'
    const getUrl = magentoUrl(baseUrl, 'products/' + encodeURIComponent(sku))
    const delUrl = getUrl
    // Finnes?
    const getRes = await fetch(getUrl, { headers: { Authorization: 'Bearer ' + token } })
    if (getRes.status === 404) {
      return NextResponse.json({ ok:true, deleted:false, reason:'not_found' })
    }
    if (!getRes.ok) {
      return NextResponse.json({ ok:false, step:'get', status:getRes.status, detail: await getRes.text() }, { status:getRes.status })
    }
    // Slett
    const delRes = await fetch(delUrl, { method:'DELETE', headers: { Authorization: 'Bearer ' + token } })
    if (!delRes.ok) {
      return NextResponse.json({ ok:false, step:'delete', status:delRes.status, detail: await delRes.text() }, { status:delRes.status })
    }
    return NextResponse.json({ ok:true, deleted:true })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:String(e?.message||e) }, { status: 500 })
  }
}
