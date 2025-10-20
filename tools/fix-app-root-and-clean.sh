#!/bin/bash
set -euo pipefail
echo "🔧 Legger inn app/page.tsx (redirect til /admin/dashboard) + renser caches"

# 1) Opprett app/page.tsx hvis mangler
mkdir -p app
if [ ! -f "app/page.tsx" ]; then
  cat > app/page.tsx <<'TSX'
// app/page.tsx
import { redirect } from 'next/navigation'

export default function Page() {
  // Viderekoble root til admin-dashboard i dev
  redirect('/admin/dashboard')
}
TSX
  echo "🛠  Skrev app/page.tsx (redirect til /admin/dashboard)"
else
  echo "ℹ️  app/page.tsx finnes allerede"
fi

# (valgfritt) liten not-found for ryddigere fallback
if [ ! -f "app/not-found.tsx" ]; then
  cat > app/not-found.tsx <<'TSX'
// app/not-found.tsx
export default function NotFound() {
  return <div style={{padding:20}}>Not found</div>
}
TSX
  echo "🛠  Skrev app/not-found.tsx"
fi

# 2) Rens alle Next/Webpack-cacher
echo "🧹 Rydder .next og node_modules sine caches"
rm -rf .next || true
rm -rf node_modules/.cache || true
rm -rf node_modules/.vite || true
rm -rf .turbo || true

echo "✅ Ferdig. Start på nytt: pnpm dev"
