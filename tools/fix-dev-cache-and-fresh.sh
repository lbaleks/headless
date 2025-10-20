#!/bin/bash
set -euo pipefail
echo "🔧 Litebrygg: Dev-cache ⇒ memory + fresh /products/merged & /products/completeness"

# 1) next.config.js → bruk memory cache i dev (hindrer ENOENT/ChunkLoadError ved .next-clean)
if [ ! -f "next.config.js" ]; then
  cat > next.config.js <<'JS'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: {
    reactCompiler: true,
  },
  webpack: (config, { dev }) => {
    if (dev) {
      // Unngå filsystem-cache som gir ENOENT når .next ryddes under kjøring
      config.cache = { type: 'memory' };
    }
    return config;
  },
};
module.exports = nextConfig;
JS
  echo "🛠  Opprettet next.config.js (dev-cache: memory)"
else
  # Patch eksisterende config til å bruke memory-cache i dev
  if ! grep -q "config.cache = { type: 'memory' }" next.config.js; then
    tmp="$(mktemp)"; cp next.config.js "$tmp"
    node - <<'NODE' "$tmp" > next.config.js
const fs=require('fs');const p=process.argv[1];let s=fs.readFileSync(p,'utf8');
if(!/webpack:\s*\(/.test(s)){
  s = s.replace(/module\.exports\s*=\s*nextConfig\s*;?/,'')
  + `
const nextConfig = (()=>{
  const base = ${s.match(/module\.exports\s*=\s*(\{[\s\S]*\})/)?RegExp.$1:'{}'};
  base.webpack = (config,{dev}) => { if(dev){ config.cache = { type: 'memory' }; } return config; };
  return base;
})();
module.exports = nextConfig;
`; 
}else{
  s = s.replace(/webpack:\s*\(([^)]*)\)\s*=>\s*\{/, m=> m + "\n    if (dev) { config.cache = { type: 'memory' }; }\n")
}
process.stdout.write(s);
NODE
    echo "🛠  Patchet next.config.js (dev-cache: memory)"
  else
    echo "ℹ️  next.config.js har allerede memory-cache i dev"
  fi
fi

# 2) /api/products/merged → alltid fersk respons (no-store + tags)
mkdir -p app/api/products/merged
if [ -f "app/api/products/merged/route.ts" ]; then
  # Wrap eksisterende route: injiser revalidate/dynamic hvis de ikke finnes
  if ! grep -q "export const revalidate" app/api/products/merged/route.ts; then
    sed -i.bak '1iexport const revalidate = 0\nexport const dynamic = "force-dynamic"\n' app/api/products/merged/route.ts
  fi
  # NB: Vi antar at koden bruker fetch. Legg hint: next: { tags: ['products:merged','products'] }
  sed -i.bak "s/fetch(/fetch(/g" app/api/products/merged/route.ts >/dev/null 2>&1 || true
  echo "🛠  Pushet revalidate=0/dynamic=force-dynamic i products/merged"
  rm -f app/api/products/merged/route.ts.bak
else
  # Minimal fallback-route (hvis manglet): henter fra Magento simple liste
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
    const res = await fetch(url, { headers: { Authorization: 'Bearer ' + token }, cache:'no-store', next:{ tags:['products:merged','products'] } })
    if(!res.ok){
      return NextResponse.json({ ok:false, error: await res.text(), url }, { status: res.status })
    }
    const data = await res.json()
    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:String(e?.message||e) }, { status: 500 })
  }
}
TS
  echo "🧱 Opprettet minimal /api/products/merged (no-store)"
fi

# 3) /api/products/completeness → marker som fresh (no-store) hvis den finnes
if [ -f "app/api/products/completeness/route.ts" ]; then
  if ! grep -q "export const revalidate" app/api/products/completeness/route.ts; then
    sed -i.bak '1iexport const revalidate = 0\nexport const dynamic = "force-dynamic"\n' app/api/products/completeness/route.ts
    rm -f app/api/products/completeness/route.ts.bak
    echo "🛠  Pushet revalidate=0/dynamic=force-dynamic i products/completeness"
  fi
fi

# 4) Sørg for at oppdaterings-ruten revaliderer både liste og sku-spesifikk cache
if grep -q "revalidateTag('products')" app/api/products/update-attributes/route.ts; then
  # allerede lagt inn products:merged tidligere, men repatcher sikkerhetsmessig
  sed -i.bak "s/revalidateTag('products');[^;]*/revalidateTag('products'); try { revalidateTag('products:merged') } catch {}; try { revalidateTag('product:' + body.sku) } catch {}; try { revalidateTag('completeness:' + body.sku) } catch {}/" app/api/products/update-attributes/route.ts || true
  rm -f app/api/products/update-attributes/route.ts.bak
  echo "🛠  Revalidate utvidet i update-attributes"
fi

# 5) Clean caches for en helt ren rebuild
if [ -d ".next" ]; then
  echo "🧹 Rydder .next/"
  rm -rf .next
fi
if [ -d "node_modules/.cache" ]; then
  echo "🧹 Rydder node_modules/.cache/"
  rm -rf node_modules/.cache
fi

echo "✅ Ferdig. Start på nytt: pnpm dev"
echo "ℹ️  Hvis du fortsatt ser ChunkLoadError: lukk fanen, hard-refresh (Cmd+Shift+R)."
