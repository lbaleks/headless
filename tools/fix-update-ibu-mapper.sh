#!/bin/bash
set -euo pipefail
FILE="app/api/products/update-attributes/route.ts"
[ -f "$FILE" ] || { echo "Finner ikke $FILE"; exit 1; }

node - "$FILE" <<'NODE'
const fs=require('fs');
const path=process.argv[2];
let s=fs.readFileSync(path,'utf8');

// Finn plass å sette inn normaliserings-funksjoner (etter imports)
if(!/function\s+selectIbuKey\b/.test(s)){
  s=s.replace(
    /(import[^\n]*\n(?:import[^\n]*\n)*)/,
    `$1
// Velg korrekt IBU-attributt-kode basert på nåværende produkt
function selectIbuKey(current) {
  const arr = Array.isArray(current?.custom_attributes) ? current.custom_attributes : [];
  const have = new Set(arr.map(a => a?.attribute_code).filter(Boolean));
  const candidates = ['ibu','cfg_ibu','akeneo_ibu','IBU','ibu_value'];
  for (const c of candidates) if (have.has(c)) return c;
  // fallback hvis ingen finnes: bruk 'cfg_ibu'
  return 'cfg_ibu';
}

// Cast custom-verdier til string (Magento tåler best string for custom attrs)
function toMagentoValue(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}
`
  );
}

// Patch buildUpdatePayload slik at 'ibu' mappes til riktig kode og customs blir string
s = s.replace(
  /function\s+buildUpdatePayload\([\s\S]*?\)\s*\{[\s\S]*?\n\}/m,
`function buildUpdatePayload(current, partial) {
  const base = {
    sku: String(partial.sku || current?.sku || ''),
    attribute_set_id: current?.attribute_set_id,
    type_id: current?.type_id || 'simple',
    name: current?.name,
    price: current?.price,
    status: current?.status,
    visibility: current?.visibility,
    weight: current?.weight,
    custom_attributes: current?.custom_attributes || []
  };

  // existing custom map
  const customMap = new Map();
  for (const it of Array.isArray(base.custom_attributes) ? base.custom_attributes : []) {
    if (it && it.attribute_code) customMap.set(it.attribute_code, it.value);
  }

  // toppnivå felter vi lar være toppnivå
  const TOP_LEVEL = new Set(['sku','name','price','status','visibility','weight','attribute_set_id','type_id']);

  // Hvis UI sendte "ibu", map til korrekt nøkkel basert på produktet
  let resolvedPartial = { ...partial };
  if (Object.prototype.hasOwnProperty.call(partial, 'ibu')) {
    const key = selectIbuKey(current);
    resolvedPartial[key] = partial.ibu;
    delete resolvedPartial.ibu;
  }

  const top = {};
  for (const [k, vRaw] of Object.entries(resolvedPartial)) {
    if (k === 'sku') continue;
    if (TOP_LEVEL.has(k)) {
      top[k] = vRaw;
    } else {
      const v = toMagentoValue(vRaw);
      customMap.set(k, v);
    }
  }

  const customArr = Array.from(customMap.entries()).map(([attribute_code, value]) => ({ attribute_code, value }));
  const merged = { ...base, ...top, custom_attributes: customArr };

  // Fjern tomme felter
  const clean = {};
  for (const [k, v] of Object.entries(merged)) {
    if (v === undefined) continue;
    if (k === 'custom_attributes' && Array.isArray(v) && v.length === 0) continue;
    clean[k] = v;
  }
  return clean;
}`
);

// Sørg for at fil fortsatt eksporterer PATCH/POST (i tilfelle tidligere patcher var annerledes)
if(!/export\s+async\s+function\s+PATCH/.test(s)){
  s += `

export async function PATCH(req: Request) { return handleUpdate(req) }
export async function POST(req: Request)  { return handleUpdate(req) }
`;
}

fs.writeFileSync(path,s);
console.log('🛠  Patchet', path);
NODE

# Full clean for trygg rebuild
rm -rf .next .next-dev node_modules/.cache 2>/dev/null || true
echo "🧹 Ryddet build-caches. Start på nytt: pnpm dev"
