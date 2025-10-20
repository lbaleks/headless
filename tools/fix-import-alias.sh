#!/bin/bash
set -euo pipefail

echo "🔧 Fix: bruk relative imports for lib/env + sørg for at lib/env.ts finnes"

mkdir -p lib

# 1) Skriv/oppdater lib/env.ts (samme innhold som tidligere env-loader)
cat > lib/env.ts <<'TS'
// lib/env.ts
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'

export type MagentoConfig = {
  baseUrl: string
  rawBase: string
  token: string
}

function parseDotenvFile(p: string): Record<string,string> {
  try {
    if (!existsSync(p)) return {}
    const txt = readFileSync(p, 'utf8')
    const obj: Record<string,string> = {}
    for (const line of txt.split(/\r?\n/)) {
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/)
      if (!m) continue
      let [, key, val] = m
      val = val.replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1')
      obj[key] = val
    }
    return obj
  } catch {
    return {}
  }
}

function loadEnvFromFiles(): Record<string,string> {
  const root = process.cwd()
  const envLocal = parseDotenvFile(resolve(root, '.env.local'))
  const envBase  = parseDotenvFile(resolve(root, '.env'))
  return { ...envBase, ...envLocal, ...process.env as any }
}

function normalizeBase(input: string): { rawBase:string; baseV1:string } {
  let b = (input || '').trim().replace(/\/+$/, '')
  if (/\/rest(\/v1|\/V1)?$/i.test(b)) {
    if (/\/rest$/i.test(b)) return { rawBase: b, baseV1: b + '/V1' }
    return { rawBase: b, baseV1: b }
  }
  return { rawBase: b, baseV1: b + '/rest/V1' }
}

export function magentoUrl(baseV1: string, path: string): string {
  return baseV1.replace(/\/+$/, '') + '/' + String(path || '').replace(/^\/+/, '')
}

declare global {
  // eslint-disable-next-line no-var
  var __MAGENTO_TOKEN_CACHE: string | undefined
}

async function fetchAdminToken(baseV1: string, username: string, password: string): Promise<string> {
  const url = magentoUrl(baseV1, 'integration/admin/token')
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Token fetch failed ${res.status}: ${text}`)
  }
  const token = await res.json()
  if (typeof token !== 'string' || !token) throw new Error('Token response invalid')
  return token
}

export async function getMagentoConfig(): Promise<MagentoConfig> {
  const env = loadEnvFromFiles()
  const { rawBase, baseV1 } = normalizeBase(env.MAGENTO_URL || env.MAGENTO_BASE_URL || '')
  let token = env.MAGENTO_TOKEN || env.MAGENTO_ADMIN_TOKEN || ''

  if (!rawBase) throw new Error('MAGENTO_URL/MAGENTO_BASE_URL is missing (env)')

  if (!token && globalThis.__MAGENTO_TOKEN_CACHE) {
    token = globalThis.__MAGENTO_TOKEN_CACHE
  }

  if (!token) {
    const u = env.MAGENTO_ADMIN_USERNAME || ''
    const p = env.MAGENTO_ADMIN_PASSWORD || ''
    if (!u || !p) {
      throw new Error('Missing MAGENTO_TOKEN and admin credentials (MAGENTO_ADMIN_USERNAME/MAGENTO_ADMIN_PASSWORD)')
    }
    token = await fetchAdminToken(baseV1, u, p)
    globalThis.__MAGENTO_TOKEN_CACHE = token
  }

  return { baseUrl: baseV1, rawBase, token }
}
TS

# 2) Patch imports i API-ruter til relative sti ../../../lib/env
for f in \
  app/api/products/[sku]/route.ts \
  app/api/products/update-attributes/route.ts
do
  if [ -f "$f" ]; then
    echo "🛠  Retter import i $f"
    # bytt både '@/lib/env' og '@\\lib\\env' (Windows-komp) til '../../../lib/env'
    sed -i.bak "s|from '@/lib/env'|from '../../../lib/env'|g" "$f" || true
    sed -i.bak "s|from \"@/lib/env\"|from '../../../lib/env'|g" "$f" || true
    sed -i.bak 's|from "@/lib/env"|from "../../../lib/env"|g' "$f" || true
    sed -i.bak 's|from '\''@/lib/env'\''|from '\''../../../lib/env'\''|g' "$f" || true
    rm -f "${f}.bak"
  fi
done

# 3) Valgfritt: legg klar jsconfig (deaktivert alias)
if [ ! -f "jsconfig.json" ]; then
  cat > jsconfig.json <<'JSON'
{
  "compilerOptions": {
    "baseUrl": "."
    // Vil du bruke alias som i Next-eksemplene?
    // Fjern kommentar under og restart dev:
    // ,"paths": { "@/*": ["*"] }
  }
}
JSON
fi

echo "✅ Import-fix ferdig. Start dev på nytt: pnpm dev"
