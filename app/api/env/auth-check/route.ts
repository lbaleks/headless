export const runtime = 'nodejs';
// app/api/env/auth-check/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'


export async function GET() {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    // Ikke-destruktivt: sjekk en admin-krevd ressurs via GET (for eksempel attribute-sets)
    const testUrl = magentoUrl(baseUrl, 'products/attributes/attribute-sets/list?searchCriteria[currentPage]=1&searchCriteria[pageSize]=1')
    const res = await fetch(testUrl, { headers: { Authorization: 'Bearer ' + token } })
    const text = await res.text()
    const okAuth = res.status !== 401 && res.status !== 403
    return NextResponse.json({
      ok: true,
      baseUrl,
      writeAuthorized: okAuth,
      status: res.status,
      sampleUrl: testUrl,
      detail: text.slice(0, 500),
    }, { status: okAuth ? 200 : 403 })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:String(e?.message||e) }, { status: 500 })
  }
}
