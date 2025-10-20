#!/bin/bash
set -euo pipefail
echo "🔧 Litebrygg: gjør /admin/products alltid fresh + løfter alle custom_attributes på API"

# 1) Patch app/admin/products/page.tsx til å være 100% dynamisk (ingen cache)
if [ -f "app/admin/products/page.tsx" ]; then
  # legg til revalidate/dynamic på topp hvis mangler
  if ! grep -q "export const revalidate" app/admin/products/page.tsx; then
    tmp=$(mktemp)
    printf "export const revalidate = 0\nexport const dynamic = 'force-dynamic'\n" > "$tmp"
    cat app/admin/products/page.tsx >> "$tmp"
    mv "$tmp" app/admin/products/page.tsx
    echo "🛠  La til revalidate=0 og dynamic=force-dynamic i admin/products/page.tsx"
  fi
  # gjør fetch-kall no-store (best effort)
  perl -0777 -pe "s/fetch\(([^)]+)\)/fetch(\$1, { cache: 'no-store' })/g" -i app/admin/products/page.tsx 2>/dev/null || true
  # hvis fetch allerede hadde init-objekt, injiser cache: 'no-store'
  perl -0777 -pe "s/fetch\(\s*([^,]+),\s*\{([^}]*)\}\s*\)/fetch(\$1, {\$2, cache: 'no-store'})/g" -i app/admin/products/page.tsx 2>/dev/null || true
else
  echo "ℹ️  Fant ikke app/admin/products/page.tsx – hopper over side-patch."
fi

# 2) Patch API: løft ALLE custom_attributes → toppnivå i /api/products og /api/products/merged
patch_api() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ℹ️  Hopper over (mangler): $file"
    return
  fi
  node - "$file" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
let s = fs.readFileSync(path,'utf8');

function upsertHelper(src){
  if (/function\s+flattenCustomAttributes\s*\(/.test(src)) {
    // Erstatt med variant som løfter alle attrs + setter .ibu fallback
    return src.replace(/function\s+flattenCustomAttributes\s*\([^)]*\)\s*\{[\s\S]*?\}\s*\n/m, `
function flattenCustomAttributes(item){
  const arr = Array.isArray(item && item.custom_attributes) ? item.custom_attributes : [];
  const map = {};
  for (const ca of arr) {
    if (!ca || !ca.attribute_code) continue;
    map[ca.attribute_code] = ca.value;
  }
  // Løft alle custom attrs til toppnivå (ikke overskriv eksisterende toppnivå)
  for (const k of Object.keys(map)) {
    if (item[k] === undefined) item[k] = map[k];
  }
  // Sett .ibu med fallback
  const ibuCand = map.ibu ?? map.cfg_ibu ?? map.akeneo_ibu ?? map.IBU ?? map.ibu_value;
  if (ibuCand !== undefined) item.ibu = ibuCand;
  item._attrs = map;
  return item;
}
`);
  } else {
    // Injiser helper rett etter imports
    return src.replace(/(import[^\n]*\n(?:import[^\n]*\n)*)/m, `$1
function flattenCustomAttributes(item){
  const arr = Array.isArray(item && item.custom_attributes) ? item.custom_attributes : [];
  const map = {};
  for (const ca of arr) {
    if (!ca || !ca.attribute_code) continue;
    map[ca.attribute_code] = ca.value;
  }
  for (const k of Object.keys(map)) {
    if (item[k] === undefined) item[k] = map[k];
  }
  const ibuCand = map.ibu ?? map.cfg_ibu ?? map.akeneo_ibu ?? map.IBU ?? map.ibu_value;
  if (ibuCand !== undefined) item.ibu = ibuCand;
  item._attrs = map;
  return item;
}
`);
  }
}

function ensureMapUse(src){
  // Sørg for at data.items mappes før retur
  if (/data\.items\s*=\s*data\.items\.map\(flattenCustomAttributes\)/.test(src)) return src;
  if (/Array\.isArray\(data\?\.\items\)/.test(src)) {
    return src.replace(/if\s*\(\s*Array\.isArray\(data\?\.\items\)\s*\)\s*\{\s*([\s\S]*?)\}/m,
`if (Array.isArray(data?.items)) {
  data.items = data.items.map(flattenCustomAttributes);
  $1
}`);
  }
  // Fallback: sett mapping før NextResponse.json(data)
  return src.replace(/return\s+NextResponse\.json\(\s*data(\s*,\s*\{[\s\S]*?\})?\s*\)/m,
`if (Array.isArray(data?.items)) data.items = data.items.map(flattenCustomAttributes);
return NextResponse.json(data$1)`);
}

function ensureFreshExports(src){
  if (!/export const revalidate = 0/.test(src)) src = `export const revalidate = 0\n` + src;
  if (!/export const dynamic = 'force-dynamic'/.test(src)) src = `export const dynamic = 'force-dynamic'\n` + src;
  return src;
}
function ensureNoStoreHeader(src){
  if (!/Cache-Control'\s*:\s*'no-store'/.test(src)) {
    src = src.replace(/NextResponse\.json\(([^)]+)\)/g, `NextResponse.json($1, { headers: { 'Cache-Control': 'no-store' } })`);
  }
  return src;
}

s = upsertHelper(s);
s = ensureMapUse(s);
s = ensureFreshExports(s);
s = ensureNoStoreHeader(s);

fs.writeFileSync(path, s);
console.log('🛠  Patchet', path);
NODE
}

patch_api "app/api/products/route.ts"
patch_api "app/api/products/merged/route.ts"

# 3) Clean build caches (vi bruker .next-dev som distDir nå, men rydd begge for sikkerhets skyld)
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
echo "🧹 Ryddet build-caches"

echo "✅ Ferdig. Start på nytt: pnpm dev (og hard refresh i nettleser)"
