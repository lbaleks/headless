#!/bin/bash
set -euo pipefail
echo "🔧 ESM next.config + fresh merged with custom_attributes flatten + clean caches"

# 1) Skriv Next config som ESM (next.config.mjs)
cat > next.config.mjs <<'MJS'
/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  experimental: { reactCompiler: true },
  webpack: (cfg, { dev }) => {
    // I dev: bruk memory-cache for å unngå fil-cache ENOENT ved rydding av .next
    if (dev) cfg.cache = { type: 'memory' };
    return cfg;
  },
};
export default config;
MJS
echo "🛠  Skrev next.config.mjs (ESM)."

# Rydd bort ev. gammel CJS-config for å unngå konflikt
if [ -f "next.config.js" ]; then
  mv next.config.js next.config.js.bak 2>/dev/null || true
  echo "🧹 Flyttet next.config.js -> next.config.js.bak"
fi

# 2) /api/products/merged → always fresh + flatten custom_attributes til toppnivå
mkdir -p app/api/products/merged
cat > app/api/products/merged/route.ts <<'TS'
// app/api/products/merged/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig, magentoUrl } from '../../_lib/env'

export const revalidate = 0
export const dynamic = 'force-dynamic'
export const runtime = 'nodejs'

function flattenCustomAttributes(item: any) {
  const src = Array.isArray(item?.custom_attributes) ? item.custom_attributes : []
  const map: Record<string, any> = {}
  for (const ca of src) {
    if (!ca || !ca.attribute_code) continue
    map[ca.attribute_code] = ca.value
  }
  // Speil ut relevante custom attributes på toppnivå (inkluderer IBU)
  // Du kan legge til flere koder her ved behov.
  const liftKeys = [
    'ibu', 'cfg_ibu', 'akeneo_ibu',
    'tax_class_id','url_key','options_container','msrp_display_actual_price_type',
    'category_ids','required_options','has_options','cfg_color'
  ]
  for (const k of liftKeys) {
    if (map[k] !== undefined && item[k] === undefined) item[k] = map[k]
  }
  // Ha med hele map’en også (nyttig i UI)
  item._attrs = map
  return item
}

export async function GET() {
  try {
    const { baseUrl, token } = await getMagentoConfig()
    const url = magentoUrl(baseUrl, 'products?searchCriteria[pageSize]=10000')
    const res = await fetch(url, {
      headers: { Authorization: 'Bearer ' + token },
      cache: 'no-store',
      next: { tags: ['products:merged','products'] }
    })
    if (!res.ok) {
      return NextResponse.json({ ok:false, error: await res.text(), url }, { status: res.status })
    }
    const data = await res.json()

    // Magento svarer ofte { items: [...], search_criteria: {...}, total_count: N }
    if (Array.isArray(data?.items)) {
      data.items = data.items.map(flattenCustomAttributes)
    } else if (Array.isArray(data)) {
      // fallback om APIet returnerer rå liste
      data.forEach(flattenCustomAttributes)
    }

    return NextResponse.json(data, { headers: { 'Cache-Control': 'no-store' } })
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:String(e?.message||e) }, { status: 500 })
  }
}
TS
echo "🛠  Opprettet/oppdatert /api/products/merged (fresh + flatten)."

# 3) Sørg for at update-attributes revaliderer liste + sku + completeness
if [ -f "app/api/products/update-attributes/route.ts" ]; then
  node - <<'NODE'
const fs=require('fs');const f='app/api/products/update-attributes/route.ts';
let s=fs.readFileSync(f,'utf8');
if(!/products:merged/.test(s)){
  s=s.replace(/revalidateTag\('products'\);?/,
    "revalidateTag('products'); try { revalidateTag('products:merged') } catch {}; try { revalidateTag('product:' + body.sku) } catch {}; try { revalidateTag('completeness:' + body.sku) } catch {}");
  fs.writeFileSync(f,s); console.log("🛠  Utvidet revalidateTag i update-attributes");
} else {
  console.log("ℹ️  update-attributes hadde allerede utvidet revalidate");
}
NODE
fi

# 4) Clean caches for ren rebuild
if [ -d ".next" ]; then
  echo "🧹 Rydder .next/"
  rm -rf .next
fi
if [ -d "node_modules/.cache" ]; then
  echo "🧹 Rydder node_modules/.cache/"
  rm -rf node_modules/.cache
fi

echo "✅ Ferdig. Start på nytt: pnpm dev"
echo "   Tips: Hard refresh i nettleser (Cmd+Shift+R) hvis du så ChunkLoadError tidligere."
