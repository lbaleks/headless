#!/bin/bash
set -euo pipefail
echo "🔧 Retter relative imports til '../../../../lib/env' og lager loader-basert env-check"

# 1) Sørg for at lib/env.ts finnes (ingen overwrite hvis den allerede finnes)
if [ ! -f "lib/env.ts" ]; then
  echo "⚠️  lib/env.ts mangler – avbryter ikke, men patcher imports uansett."
fi

# 2) Patch imports i begge produkt-ruter
for f in \
  app/api/products/\[sku]/route.ts \
  app/api/products/update-attributes/route.ts
do
  if [ -f "$f" ]; then
    echo "🛠  Patcher import i $f"
    # erstatt enhver variant av '@/lib/env' eller '../../../lib/env' til '../../../../lib/env'
    sed -i.bak "s|from '@/lib/env'|from '../../../../lib/env'|g" "$f" || true
    sed -i.bak 's|from "@/lib/env"|from "../../../../lib/env"|g' "$f" || true
    sed -i.bak "s|from '../../../lib/env'|from '../../../../lib/env'|g" "$f" || true
    sed -i.bak 's|from "../../../lib/env"|from "../../../../lib/env"|g' "$f" || true
    rm -f "$f.bak"
  else
    echo "ℹ️  Hopper over: $f finnes ikke"
  fi
done

# 3) Lag et env-check endepunkt som bruker loaderen, ikke process.env direkte
mkdir -p app/api/env/check-loader
cat > app/api/env/check-loader/route.ts <<'TS'
// app/api/env/check-loader/route.ts
import { NextResponse } from 'next/server'
import { getMagentoConfig } from '../../../../lib/env'

export const runtime = 'nodejs'

export async function GET() {
  try {
    const cfg = await getMagentoConfig()
    const masked = cfg.token ? (cfg.token.length>6 ? cfg.token.slice(0,3)+'...'+cfg.token.slice(-3) : '***') : '<empty>'
    return NextResponse.json({
      ok: true,
      source: 'loader',
      baseUrl: cfg.baseUrl,
      rawBase: cfg.rawBase,
      tokenMasked: masked
    })
  } catch (e: any) {
    return NextResponse.json({ ok:false, error: String(e?.message || e) }, { status: 500 })
  }
}
TS

echo "✅ Import-stier fikset. Start Next.js på nytt: pnpm dev"
echo "🔎 Test loader-env:  http://localhost:3000/api/env/check-loader"
