#!/bin/bash
set -euo pipefail
echo "🔧 Making auth-check non-destructive and adding cleanup route"

# 1) Bytt auth-check til GET på eksisterende endpoint (krever write via en 'privileged' call, men skader ikke data).
cat > app/api/env/auth-check/route.ts <<'TS'
// app/api/env/auth-check/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const runtime = 'nodejs'

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
TS

# 2) Legg til oppryddings-endepunkt for å slette __authcheck__ om den eksisterer
mkdir -p app/api/env/cleanup-authcheck
cat > app/api/env/cleanup-authcheck/route.ts <<'TS'
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
TS

echo "✅ Auth-check gjort trygg. Cleanup-endepunkt lagt inn."
echo "➡  Restart: pnpm dev"
echo "➡  Rydd opp (valgfritt): curl -X POST http://localhost:3000/api/env/cleanup-authcheck"
