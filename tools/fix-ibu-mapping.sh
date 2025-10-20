#!/bin/bash
set -euo pipefail
echo "🔧 Setter alltid item.ibu på toppnivå i /api/products og /api/products/merged"

apply_patch() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ℹ️  Hopper over (mangler): $file"
    return 0
  fi

  # Legg inn en robust flatten-funksjon som også setter item.ibu
  node - "$file" <<'NODE'
const fs = require('fs');
const path = process.argv[1];
let s = fs.readFileSync(path, 'utf8');

function ensureHelper(src) {
  if (/function\s+flattenCustomAttributes\s*\(/.test(src)) {
    // Patch eksisterende helper: sørg for at den setter item.ibu fra flere nøkkelnavn
    src = src.replace(
      /function\s+flattenCustomAttributes\s*\([^)]*\)\s*\{[\s\S]*?\}/m,
`function flattenCustomAttributes(item) {
  const src = Array.isArray(item?.custom_attributes) ? item.custom_attributes : [];
  const map = {};
  for (const ca of src) {
    if (!ca || !ca.attribute_code) continue;
    map[ca.attribute_code] = ca.value;
  }
  // Løft vanlige felter
  const liftKeys = [
    'ibu','cfg_ibu','akeneo_ibu','IBU','ibu_value',
    'tax_class_id','url_key','options_container','msrp_display_actual_price_type',
    'category_ids','required_options','has_options','cfg_color'
  ];
  for (const k of liftKeys) if (map[k] !== undefined && item[k] === undefined) item[k] = map[k];

  // Sett item.ibu med fallback
  const ibuCand = map['ibu'] ?? map['cfg_ibu'] ?? map['akeneo_ibu'] ?? map['IBU'] ?? map['ibu_value'];
  if (ibuCand !== undefined) item.ibu = ibuCand;

  // Eksponer hele kartet
  item._attrs = map;
  return item;
}`
    );
    return src;
  } else {
    // Ikke funnet helper → injiser en rett etter imports
    return src.replace(
      /(import[^\n]*\n(?:import[^\n]*\n)*)/m,
      `$1
function flattenCustomAttributes(item) {
  const src = Array.isArray(item?.custom_attributes) ? item.custom_attributes : [];
  const map = {};
  for (const ca of src) {
    if (!ca || !ca.attribute_code) continue;
    map[ca.attribute_code] = ca.value;
  }
  const liftKeys = [
    'ibu','cfg_ibu','akeneo_ibu','IBU','ibu_value',
    'tax_class_id','url_key','options_container','msrp_display_actual_price_type',
    'category_ids','required_options','has_options','cfg_color'
  ];
  for (const k of liftKeys) if (map[k] !== undefined && item[k] === undefined) item[k] = map[k];
  const ibuCand = map['ibu'] ?? map['cfg_ibu'] ?? map['akeneo_ibu'] ?? map['IBU'] ?? map['ibu_value'];
  if (ibuCand !== undefined) item.ibu = ibuCand;
  item._attrs = map;
  return item;
}
`
    );
  }
}

function ensureUsed(src) {
  // Bruk helperen på items når vi bygger svaret
  if (/data\.items\s*=\s*data\.items\.map\(flattenCustomAttributes\)/.test(src)) return src;
  if (/Array\.isArray\(data\?\.\items\)\)/.test(src)) {
    return src.replace(
      /if\s*\(\s*Array\.isArray\(data\?\.\items\)\s*\)\s*\{\s*([\s\S]*?)\}/m,
      `if (Array.isArray(data?.items)) {
  data.items = data.items.map(flattenCustomAttributes);
  $1
}`
    );
  }
  // Fallback: hvis vi finner return av data uten mapping, prøv en enkel map før retur
  if (/return\s+NextResponse\.json\(data/.test(src)) {
    src = src.replace(
      /return\s+NextResponse\.json\(data([^)]*)\)/,
      `if (Array.isArray(data?.items)) data.items = data.items.map(flattenCustomAttributes);
return NextResponse.json(data$1)`
    );
  }
  return src;
}

s = ensureHelper(s);
s = ensureUsed(s);

// Sørg for no-store header (hvis ikke finnes)
if (!/Cache-Control'\s*:\s*'no-store'/.test(s)) {
  s = s.replace(
    /NextResponse\.json\(([^)]+)\)/g,
    `NextResponse.json($1, { headers: { 'Cache-Control': 'no-store' } })`
  );
}

// Sørg for revalidate=0 + dynamic=force-dynamic øverst
if (!/export const revalidate = 0/.test(s)) s = `export const revalidate = 0\n` + s;
if (!/export const dynamic = 'force-dynamic'/.test(s)) s = `export const dynamic = 'force-dynamic'\n` + s;

fs.writeFileSync(path, s);
console.log('🛠  Patchet', path);
NODE
}

apply_patch "app/api/products/route.ts"
apply_patch "app/api/products/merged/route.ts"

# Rydd bygg-cacher for ren rebuild
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
echo "🧹 Ryddet build-caches"

echo "✅ Ferdig. Start på nytt: pnpm dev"
