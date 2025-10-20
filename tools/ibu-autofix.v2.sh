#!/bin/bash
set -euo pipefail

echo "🔧 IBU autofix v2: env-helpers, imports, tsconfig, cache"

# 1) lib/env.ts
mkdir -p lib
ENV_FILE="lib/env.ts"
cat > "$ENV_FILE" <<'TS'
// Auto-created by IBU autofix v2
export function getMagentoConfig() {
  const base = (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/+$/,'');
  const token = process.env.MAGENTO_TOKEN || '';
  return { baseUrl: base, token };
}

export async function getAdminToken(): Promise<string> {
  const u = process.env.MAGENTO_ADMIN_USERNAME;
  const p = process.env.MAGENTO_ADMIN_PASSWORD;
  const base = (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/+$/,'');
  if (!u || !p || !base) return '';
  try {
    const res = await fetch(`${base}/V1/integration/admin/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: u, password: p }),
      cache: 'no-store',
    });
    if (!res.ok) return '';
    return await res.text();
  } catch {
    return '';
  }
}
TS
echo "✓ Skrevet lib/env.ts"

# 2) tsconfig alias @/* og baseUrl
if [ -f tsconfig.json ]; then
  node - <<'NODE'
const fs = require('fs');
const p = 'tsconfig.json';
const j = JSON.parse(fs.readFileSync(p,'utf8'));
j.compilerOptions ||= {};
j.compilerOptions.baseUrl ||= '.';
j.compilerOptions.paths ||= {};
j.compilerOptions.paths['@/*'] ||= ['./*'];
fs.writeFileSync(p, JSON.stringify(j, null, 2));
console.log('✓ Oppdatert tsconfig.json (baseUrl, @/*)');
NODE
else
  echo "ℹ️ tsconfig.json ikke funnet – hopper over"
fi

# 3) Fiks import-stier i API-ruter
fix_import() {
  local file="$1"
  local target="$2"
  [ -f "$file" ] || { echo "• skip (finnes ikke): $file"; return 0; }
  node - "$file" "$target" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
const target=process.argv[3];
let s=fs.readFileSync(file,'utf8');
s = s.replace(/from\s+['"]@\/lib\/env['"]/g, `from "${target}"`);
s = s.replace(/from\s+['"][.\/]+lib\/env['"]/g, `from "${target}"`);
fs.writeFileSync(file,s);
console.log(`✓ ${file} → import "${target}"`);
NODE
}

fix_import "app/api/products/update-attributes/route.ts" "../../../../lib/env";
fix_import "app/api/products/route.ts"                   "../../../lib/env";
fix_import "app/api/products/merged/route.ts"            "../../../../lib/env";

# 4) Rydd cache
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
echo "🧹 Ryddet .next/.cache"

echo "✅ Ferdig. Start dev på nytt: pnpm dev"
echo "Deretter test:"
echo "  curl -s http://localhost:3000/api/debug/env/magento | jq"
echo "  curl -i -X PATCH 'http://localhost:3000/api/products/update-attributes' -H 'Content-Type: application/json' -d '{\"sku\":\"TEST-RED\",\"attributes\":{\"ibu\":\"37\"}}'"
