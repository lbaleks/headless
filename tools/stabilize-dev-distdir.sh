#!/bin/bash
set -euo pipefail
echo "🔧 Stabiliserer Next dev: distDir=.next-dev + dev-cache=off + full clean"

# next.config.mjs (ESM)
cat > next.config.mjs <<'MJS'
/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  experimental: { reactCompiler: true },
  // Tving nytt build-katalognavn for å slippe gamle .next-manifester
  distDir: '.next-dev',
  webpack: (cfg, { dev }) => {
    if (dev) cfg.cache = false; // slå AV cache i dev
    return cfg;
  },
};
export default config;
MJS
echo "🛠  Skrev next.config.mjs med distDir=.next-dev og cache=false"

# Flytt vekk ev. CommonJS-config så Next ikke plukker den
[ -f next.config.js ] && mv -f next.config.js next.config.js.bak || true

# Sørg for at vi har en root-side (redirect) så '/' ikke trigger rart
mkdir -p app
if [ ! -f app/page.tsx ]; then
  cat > app/page.tsx <<'TSX'
import { redirect } from 'next/navigation'
export default function Page(){ redirect('/admin/dashboard') }
TSX
  echo "🛠  Opprettet app/page.tsx (redirect til /admin/dashboard)"
fi

# Full clean av gamle bygg-/cache-mapper
rm -rf .next .next-dev node_modules/.cache node_modules/.vite .turbo || true
echo "🧹 Ryddet .next, .next-dev og caches"

echo "✅ Klar. Start på nytt: pnpm dev"
