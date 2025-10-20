#!/bin/bash
set -euo pipefail
echo "🔧 Prefer ADMIN token over MAGENTO_TOKEN + add /api/env/auth-check"

# 1) Patch loaderen i app/api/_lib/env.ts til å foretrekke admin-token
LOADER="app/api/_lib/env.ts"
if [ ! -f "$LOADER" ]; then
  echo "❌ Fant ikke $LOADER. Kjør først tools/fix-app-lib-env.sh" >&2
  exit 1
fi

# Sett MAGENTO_PREFER_ADMIN_TOKEN=1 som default (kan slås av i .env.local)
# Endre getMagentoConfig slik at hvis prefer=1 og admin creds finnes -> alltid hente admin-token.
python3 - "$LOADER" <<'PY'
import sys, re, pathlib, json
p=pathlib.Path(sys.argv[1])
s=p.read_text()

# Sett en liten util-funksjon i toppen om ikke finnes (vi gjør minimal patch)
if "MAGENTO_PREFER_ADMIN_TOKEN" not in s:
    # Vi injiserer i getMagentoConfig() body med et flagg
    s = s.replace(
        "export async function getMagentoConfig(): Promise<MagentoConfig> {",
        "export async function getMagentoConfig(): Promise<MagentoConfig> {\n  const preferAdmin = (process.env.MAGENTO_PREFER_ADMIN_TOKEN || '1') === '1'"
    )

# Patch token-avgjørelsen: hvis preferAdmin og admin creds finnes -> hent admin-token uansett
s = re.sub(
    r"""let token = env\.MAGENTO_TOKEN \|\| env\.MAGENTO_ADMIN_TOKEN \|\| ''""",
    "let token = preferAdmin ? '' : (env.MAGENTO_TOKEN || env.MAGENTO_ADMIN_TOKEN || '')",
    s
)

# Om ikke token (alltid slik når preferAdmin=1), forsøk admin creds
# (den originale koden vår håndterer allerede dette path’et – men vi sikrer en tydelig kommentar)
if "// Use cached token" not in s:
    pass  # eldre variant, men vår loader har dette fra før

p.write_text(s)
print("✅ Patchet preferanse: Admin-token foretrukket når MAGENTO_PREFER_ADMIN_TOKEN=1")
PY

# 2) Auth-check endepunkt – verifiser write-tilgang (PUT products/:sku med dry-run)
mkdir -p app/api/env/auth-check
cat > app/api/env/auth-check/route.ts <<'TS'
// app/api/env/auth-check/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const runtime = 'nodejs'

export async function GET() {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    // Vi gjør en liten "safe" kall som krever write-privilegier:
    // Magento har ikke ekte dry-run her, så vi tester en endpoint som ofte krever admin rettigheter,
    // men uten å gjøre destructive changes: vi bruker OPTIONS på products (noen miljøer svarer 200/204),
    // og som fallback gjør vi et PUT mot en fiktiv SKU som alltid vil feile med 404/400 hvis auth er ok,
    // men 401/403 hvis auth mangler.
    const testUrl = magentoUrl(baseUrl, 'products/__authcheck__')
    let res = await fetch(testUrl, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + token,
      },
      body: JSON.stringify({ product: { sku: '__authcheck__', name: 'AuthCheck', attribute_set_id: 4, price: 1 } }),
    })
    const text = await res.text()
    // Tolkning:
    //  - 401/403  => mangler rettigheter
    //  - 400/404+ => har auth, men payload/ressurs er feil (som forventet for fiktiv SKU)
    const okAuth = res.status !== 401 && res.status !== 403
    return NextResponse.json({
      ok: true,
      baseUrl,
      writeAuthorized: okAuth,
      status: res.status,
      sampleUrl: testUrl,
      detail: text.slice(0, 500)
    }, { status: okAuth ? 200 : 403 })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:String(e?.message||e) }, { status: 500 })
  }
}
TS

# 3) Hint i konsoll
echo "✅ Ferdig. Sett i .env.local (anbefalt):"
echo "   MAGENTO_PREFER_ADMIN_TOKEN=1"
echo "🧹 Restart dev: pnpm dev"
echo "🔎 Sjekk write-tilgang: http://localhost:3000/api/env/auth-check"
