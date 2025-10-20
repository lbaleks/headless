#!/bin/bash
set -euo pipefail

echo "🔧 IBU autofix: env-helpers, imports, tsconfig, cache"

ROOT_DIR="$(pwd)"

# 1) Sørg for at lib/env.ts finnes med nødvendige exports
mkdir -p lib
ENV_FILE="lib/env.ts"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'TS'
export function getMagentoConfig() {
  const base = (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/+$/,'');
  const token = process.env.MAGENTO_TOKEN || '';
  return { baseUrl: base, token };
}

export async function getAdminToken() {
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
  echo "✓ Opprettet $ENV_FILE"
else
  # Legg til manglende eksport(er) dersom de ikke finnes
  NEED_WRITE=0
  grep -q "export function getMagentoConfig" "$ENV_FILE" || NEED_WRITE=1
  grep -q "export async function getAdminToken" "$ENV_FILE" || NEED_WRITE=1
  if [ $NEED_WRITE -eq 1 ]; then
    cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
    cat >> "$ENV_FILE" <<'TS'

/** Auto-appended by IBU autofix */
export function getMagentoConfig() {
  const base = (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\/+$/,'');
  const token = process.env.MAGENTO_TOKEN || '';
  return { baseUrl: base, token };
}

export async function getAdminToken() {
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
    echo "✓ Oppdatert $ENV_FILE (append manglende exports)"
  else
    echo "✓ $ENV_FILE finnes og har nødvendige exports"
  fi
fi

# 2) Sikre tsconfig alias @/*
if [ -f "tsconfig.json" ]; then
  node -e '
    const fs=require("fs");
    const p="tsconfig.json";
    const j=JSON.parse(fs.readFileSync(p,"utf8"));
    j.compilerOptions = j.compilerOptions || {};
    j.compilerOptions.baseUrl = j.compilerOptions.baseUrl || ".";
    j.compilerOptions.paths = j.compilerOptions.paths || {};
    j.compilerOptions.paths["@/*"] = j.compilerOptions.paths["@/*"] || ["./*"];
    fs.writeFileSync(p, JSON.stringify(j,null,2));
    console.log("✓ tsconfig alias @/* og baseUrl .");
  '
else
  echo "ℹ️  tsconfig.json ikke funnet – hopper over alias-fix"
fi

# 3) Fiks import-stier i API-ruter
fix_import () {
  local file="$1"
  local target="$2"
  if [ ! -f "$file" ]; then
    echo "• skip (finnes ikke): $file"
    return 0
  fi
  # erstatt både alias- og feil relative imports til korrekt relativ sti
  perl -0777 -pe 's#from\s+[\'"]@/lib/env[\'"]#from "'"$target"'"#g;
                  s#from\s+[\'"][.]{1,5}/(?:[.]{1,5}/)*lib/env[\'"]#from "'"$target"'"#g' -i "$file"
  echo "✓ $file  →  import from '$target'"
}

# dybder fra hver fil til prosjektrot:
# app/api/products/update-attributes/route.ts  → ../../../../lib/env
# app/api/products/route.ts                    → ../../../lib/env
# app/api/products/merged/route.ts             → ../../../../lib/env
fix_import "app/api/products/update-attributes/route.ts" "../../../../lib/env"
fix_import "app/api/products/route.ts" "../../../lib/env"
fix_import "app/api/products/merged/route.ts" "../../../../lib/env"

# 4) Rydd dev-cache for å sikre at Next tar inn endringene
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
echo "�� Ryddet .next/.cache"

echo "✅ Ferdig. Start dev på nytt:  pnpm dev"
echo "Deretter test:"
echo "  curl -s http://localhost:3000/api/debug/env/magento | jq"
echo "  curl -i -X PATCH 'http://localhost:3000/api/products/update-attributes' -H 'Content-Type: application/json' -d '{\"sku\":\"TEST-RED\",\"attributes\":{\"ibu\":\"37\"}}'"
