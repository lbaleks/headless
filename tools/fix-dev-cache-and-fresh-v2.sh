#!/bin/bash
set -euo pipefail
echo "🔧 Litebrygg: Dev-cache ⇒ memory + fresh /products/merged & /products/completeness (BSD-safe)"

# --- Helper: prepend lines til en fil uten BSD-sed ---
prepend_lines() {
  local file="$1"; shift
  local tmp="$(mktemp)"
  {
    printf "%s\n" "$@"
    cat "$file"
  } > "$tmp"
  mv "$tmp" "$file"
}

# 1) next.config.js → dev: memory-cache
if [ ! -f "next.config.js" ]; then
  cat > next.config.js <<'JS'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: { reactCompiler: true },
  webpack: (config, { dev }) => {
    if (dev) { config.cache = { type: 'memory' }; }
    return config;
  },
};
module.exports = nextConfig;
JS
  echo "🛠  Opprettet next.config.js (dev-cache: memory)"
else
  # Patch eksisterende fil med Node for å unngå sed-hodepine
  node - <<'NODE'
const fs = require('fs');
let s = fs.readFileSync('next.config.js','utf8');
if (!/webpack:\s*\(/.test(s)) {
  // enkel omskriving
  s = `
const base = ${s.match(/module\.exports\s*=\s*(\{[\s\S]*\})/)?.[1] || '{}'};
base.webpack = (config,{dev}) => { if(dev){ config.cache = { type: 'memory' }; } return config; };
module.exports = base;
`;
} else if (!/config\.cache\s*=\s*\{\s*type:\s*'memory'\s*\}/.test(s)) {
  s = s.replace(/webpack:\s*\(([^)]*)\)\s*=>\s*\{/, m => m + `\n    if (dev) { config.cache = { type: 'memory' }; }\n`);
}
fs.writeFileSync('next.config.js', s);
console.log('🛠  Patchet next.config.js (dev-cache: memory)');
NODE
fi

# 2) /api/products/merged → always fresh
mkdir -p app/api/products/merged
if [ -f "app/api/products/merged/route.ts" ]; then
  # sørg for revalidate/dynamic-exports øverst
  if ! grep -q "export const revalidate" app/api/products/merged/route.ts; then
    prepend_lines app/api/products/merged/route.ts "export const revalidate = 0" "export const dynamic = 'force-dynamic'"
    echo "🛠  La til revalidate=0 + dynamic=force-dynamic i products/merged"
  fi
  # legg på no-store header i svaret hvis ikke allerede
  if ! grep -q "Cache-Control" app/api/products/merged/route.ts; then
    # veldig enkel patch: pakk JSON-responsen i no-store hvis vi finner NextResponse.json(
    perl -0777 -pe "s|NextResponse\.json\(([^)]+)\)|NextResponse.json(\$1, { headers: { 'Cache-Control': 'no-store' } })|g" -i app/api/products/merged/route.ts
    echo "🛠  La til Cache-Control: no-store i products/merged"
  fi
else
  # fallback-minimal route
  cat > app/api/products/merged/route.ts <<'TS'
// app/api/products/merged/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const revalidate = 0
export const dynamic = 'force-dynamic'
export const runtime = 'nodejs'

export async function GET() {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    const url = magentoUrl(baseUrl, 'products?searchCriteria[pageSize]=10000')
    const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token }, cache: 'no-store', next: { tags: ['products:merged','products'] } })
    if (!res.ok) {
      return NextResponse.json({ ok:false, error: await res.text(), url }, { status: res.status })
    }
    const data = await res.json()
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:String(e?.message||e) }, { status: 500 })
  }
}
TS
  echo "🧱 Opprettet minimal /api/products/merged (always fresh)"
fi

# 3) /api/products/completeness → also fresh (hvis finnes)
if [ -f "app/api/products/completeness/route.ts" ]; then
  if ! grep -q "export const revalidate" app/api/products/completeness/route.ts; then
    prepend_lines app/api/products/completeness/route.ts "export const revalidate = 0" "export const dynamic = 'force-dynamic'"
    echo "🛠  La til revalidate=0 + dynamic=force-dynamic i products/completeness"
  fi
  if ! grep -q "Cache-Control" app/api/products/completeness/route.ts; then
    perl -0777 -pe "s|NextResponse\.json\(([^)]+)\)|NextResponse.json(\$1, { headers: { 'Cache-Control': 'no-store' } })|g" -i app/api/products/completeness/route.ts
    echo "🛠  La til Cache-Control: no-store i products/completeness"
  fi
fi

# 4) Utvid revalidate i update-attributes (liste + sku + completeness)
if [ -f "app/api/products/update-attributes/route.ts" ]; then
  node - <<'NODE'
const fs=require('fs');let f='app/api/products/update-attributes/route.ts';let s=fs.readFileSync(f,'utf8');
if(!/products:merged/.test(s)){
  s=s.replace(/revalidateTag\('products'\);?/,
    "revalidateTag('products'); try { revalidateTag('products:merged') } catch {}; try { revalidateTag('product:' + body.sku) } catch {}; try { revalidateTag('completeness:' + body.sku) } catch {}");
  fs.writeFileSync(f,s); console.log("🛠  Utvidet revalidateTag i update-attributes");
}else{
  console.log("ℹ️  update-attributes hadde allerede utvidet revalidate");
}
NODE
fi

# 5) Rens build caches for ren rebuild
if [ -d ".next" ]; then
  echo "🧹 Rydder .next/"
  rm -rf .next
fi
if [ -d "node_modules/.cache" ]; then
  echo "🧹 Rydder node_modules/.cache/"
  rm -rf node_modules/.cache
fi

echo "✅ Ferdig. Start på nytt: pnpm dev"
echo "   Tips: Hard refresh i nettleser (Cmd+Shift+R) om du så ChunkLoadError tidligere."
