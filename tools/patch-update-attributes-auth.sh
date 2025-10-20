#!/usr/bin/env bash
set -euo pipefail
FILE="app/api/products/update-attributes/route.ts"

echo "�� Patcher $FILE for å foretrekke admin-token…"
if [ ! -f "$FILE" ]; then
  echo "❌ Fant ikke $FILE — kjør først tools/install-ibu-persist.sh"
  exit 1
fi

node - "$FILE" <<'NODE'
// NB: riktig argument er argv[2] (argv[1] == "-")
const fs = require('fs');
const file = process.argv[2];
let s = fs.readFileSync(file, 'utf8');

// 1) Header-sjekk (x-magento-auth: admin)
if (!/function\s+headerWantsAdmin\(/.test(s)) {
  s = s.replace(
    /export async function PATCH\(req: Request\) \{/,
`function headerWantsAdmin(req: Request): boolean {
  try {
    const h = (req.headers?.get('x-magento-auth') || '').toLowerCase().trim();
    return h === 'admin' || h === 'force-admin';
  } catch { return false; }
}

export async function PATCH(req: Request) {`
  );
}

// 2) Bytt ut token-resolusjon med prefer-admin logikk
const re = /let token = process\.env\.MAGENTO_TOKEN \|\| ''[\s\S]*?if \(!token\) return NextResponse\.json\(\{ error: 'Missing MAGENTO_TOKEN and admin creds' \}, \{ status: 500 \}\)/m;
if (!re.test(s)) {
  console.error('⚠️  Fant ikke forventet token-blokk – ingen endring gjort.');
} else {
  s = s.replace(
    re,
`// 💡 Token-resolusjon med preferanse for admin
const preferAdmin = (process.env.MAGENTO_PREFER_ADMIN_TOKEN === '1') || headerWantsAdmin(req);

let token = '';
if (preferAdmin) {
  const adminTry = await getAdminToken(baseV1);
  if (adminTry) token = adminTry;
  if (!token) token = process.env.MAGENTO_TOKEN || '';
} else {
  token = process.env.MAGENTO_TOKEN || '';
  if (!token) {
    const adminTry = await getAdminToken(baseV1);
    if (adminTry) token = adminTry;
  }
}

if (!token) return NextResponse.json({ error: 'Missing MAGENTO_TOKEN and admin creds' }, { status: 500 })`
  );
}

fs.writeFileSync(file, s);
console.log('✅ Patchet:', file);
NODE

echo "✅ Ferdig."
echo "➕ Legg til i .env.local: MAGENTO_PREFER_ADMIN_TOKEN=1"
echo "🔁 Restart: pnpm dev"
echo "🧪 Test: curl -i -X PATCH http://localhost:3000/api/products/update-attributes -H 'Content-Type: application/json' -d '{\"sku\":\"TEST-RED\",\"attributes\":{\"ibu\":\"37\"}}'"
echo "🧪 Eller tving admin per kall: legg til -H 'x-magento-auth: admin'"
