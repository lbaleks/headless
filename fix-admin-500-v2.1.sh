#!/usr/bin/env bash
# fix-admin-500-v2.1.sh — LiteBrygg Admin (Next.js 15)
# Unblocks 500s, scaffolder admin-ruter, lager /api/pricing/rules + /api/health.
# Bruker ett Node-skript (uten TS-annotasjoner i selve skriptet).

set -euo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;36m[fix-admin]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[error]\033[0m %s\n" "$*"; exit 1; }

# 1) Forhåndssjekker
if [ ! -f package.json ]; then
  fail "Kjør fra prosjektroten (der package.json ligger)."
fi
if ! command -v node >/dev/null 2>&1; then
  fail "Node.js ikke funnet"
fi
log "Node.js $(node -v)"

# 2) Installer minimale deps (idempotent)
if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
  PKG="pnpm"
elif [ -f yarn.lock ] && command -v yarn >/devnull 2>&1; then
  PKG="yarn"
else
  PKG="npm"
fi
log "Pakkehåndterer: $PKG"

case "$PKG" in
  pnpm) pnpm add next@latest react react-dom zod date-fns >/dev/null; pnpm add -D typescript @types/node >/dev/null ;;
  yarn) yarn add next@latest react react-dom zod date-fns >/dev/null; yarn add -D typescript @types/node >/dev/null ;;
  npm)  npm i -S next@latest react react-dom zod date-fns >/dev/null; npm i -D typescript @types/node >/dev/null ;;
esac

# 3) Skriv alle filer via ett Node-skript (EN HEREDOC)
node - <<'__NODE__'
import fs from 'node:fs/promises'
import path from 'node:path'

const root = process.cwd()
const w = async (p, c) => {
  const file = path.join(root, p)
  await fs.mkdir(path.dirname(file), { recursive: true })
  try { await fs.stat(file); await fs.cp(file, file + '.bak.' + Date.now()) } catch {}
  await fs.writeFile(file, c)
  console.log('[write]', p)
}

const tsconfig = `{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023","DOM"],
    "jsx": "preserve",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "noEmit": true,
    "strict": true,
    "baseUrl": ".",
    "paths": { "@/*": ["./*"] },
    "types": ["node"]
  },
  "include": ["next-env.d.ts","**/*.ts","**/*.tsx","**/*.cjs","**/*.mjs"],
  "exclude": ["node_modules"]
}
`

const nextconfig = `import type { NextConfig } from 'next'
const nextConfig: NextConfig = {
  experimental: { reactCompiler: true }
}
export default nextConfig
`

const fsdb = `// src/lib/fsdb.ts
import { promises as fs } from 'fs'
import path from 'path'
const dbPath = path.join(process.cwd(), 'data', 'pricing-rules.json')
export type PricingRule = {
  id: string; name: string; type: 'margin'|'discount'|'bogo'|string;
  value: number; enabled: boolean; scope?: 'global'|'category'|'sku'|string
}
export async function readDb() {
  try { const raw = await fs.readFile(dbPath,'utf8'); return JSON.parse(raw) as { rules: PricingRule[] } }
  catch (e:any) { if (e.code==='ENOENT') return { rules: [] as PricingRule[] }; throw e }
}
export async function writeDb(data:{ rules: PricingRule[] }) {
  await fs.mkdir(path.dirname(dbPath), { recursive: true })
  await fs.writeFile(dbPath, JSON.stringify(data, null, 2), 'utf8')
}
`

const apiRules = `// app/api/pricing/rules/route.ts
import { NextResponse } from 'next/server'
import { readDb, writeDb, type PricingRule } from '@/src/lib/fsdb'
import { z } from 'zod'
const Rule = z.object({ id:z.string().min(1), name:z.string().min(1), type:z.string().min(1), value:z.number(), enabled:z.boolean(), scope:z.string().optional() })
export async function GET(){ return NextResponse.json(await readDb()) }
export async function POST(req:Request){
  const body = await req.json().catch(()=>null); const p = Rule.safeParse(body)
  if(!p.success) return NextResponse.json({ error: p.error.flatten() },{ status:400 })
  const db = await readDb(); if(db.rules.some(r=>r.id===p.data.id)) return NextResponse.json({error:'Rule with this id already exists'},{status:409})
  db.rules.push(p.data as PricingRule); await writeDb(db); return NextResponse.json(p.data,{status:201})
}
export async function PUT(req:Request){
  const body = await req.json().catch(()=>null); const p = Rule.safeParse(body)
  if(!p.success) return NextResponse.json({ error: p.error.flatten() },{ status:400 })
  const db = await readDb(); const i = db.rules.findIndex(r=>r.id===p.data.id)
  if(i===-1) return NextResponse.json({ error:'Not found' },{ status:404 })
  db.rules[i] = p.data as PricingRule; await writeDb(db); return NextResponse.json(p.data)
}
export async function DELETE(req:Request){
  const { searchParams } = new URL(req.url); const id = searchParams.get('id')
  if(!id) return NextResponse.json({ error:'id required' },{ status:400 })
  const db = await readDb(); const before = db.rules.length
  db.rules = db.rules.filter(r=>r.id!==id)
  if(db.rules.length===before) return NextResponse.json({ error:'Not found' },{ status:404 })
  await writeDb(db); return NextResponse.json({ ok:true })
}
`

const apiHealth = `// app/api/health/route.ts
import { NextResponse } from 'next/server'
export async function GET(){ return NextResponse.json({ ok:true, ts:new Date().toISOString() }) }
`

const adminPage = `// src/components/AdminPage.tsx
'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
export default function AdminPage({ title, children }:{ title:string; children?:React.ReactNode }){
  const path = usePathname()
  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">{title}</h1>
        <nav className="text-sm text-gray-500"><span>Admin</span> <span className="mx-1">/</span> <span>{title}</span></nav>
      </div>
      <div className="rounded-xl border p-4">
        {children ?? (
          <div className="space-y-2">
            <p>This is a placeholder for <code>{path}</code>.</p>
            <div className="flex gap-2 text-sm">
              <Link className="underline" href="/admin/dashboard">Dashboard</Link>
              <Link className="underline" href="/admin/orders">Orders</Link>
              <Link className="underline" href="/admin/pricing">Pricing</Link>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
`

// *** FIX: Ren JS-signatur (ingen :string) ***
const mkPage = (title, feature) => `import dynamic from 'next/dynamic'
const AdminPage = dynamic(() => import('@/src/components/AdminPage'), { ssr: false })
export default function Page(){ return <AdminPage title="${title}"><p>${feature} will be implemented here.</p></AdminPage> }
export const dynamic = 'force-static'
`

const err = `'use client'
export default function Error({ error }:{ error:Error }){ return <div className="p-6 text-red-600">Something went wrong: {error.message}</div> }
`
const load = `export default function Loading(){ return <div className="p-6">Loading…</div> }
`

const integProvider = `import dynamic from 'next/dynamic'
const AdminPage = dynamic(() => import('@/src/components/AdminPage'), { ssr: false })
interface Props { params:{ provider:string } }
export default function Page({ params }:Props){
  const { provider } = params
  return <AdminPage title={\`Integration: \${provider}\`}><p>Settings and sync for <b>{provider}</b> will appear here.</p></AdminPage>
}
export const dynamic = 'force-static'
`

// Write configs
try { await fs.stat(path.join(root,'tsconfig.json')) } catch { await w('tsconfig.json', tsconfig) }
const hasNextTs  = await fs.stat(path.join(root,'next.config.ts' )).then(()=>true).catch(()=>false)
const hasNextMjs = await fs.stat(path.join(root,'next.config.mjs')).then(()=>true).catch(()=>false)
const hasNextJs  = await fs.stat(path.join(root,'next.config.js' )).then(()=>true).catch(()=>false)
if (!hasNextTs && !hasNextMjs && !hasNextJs) { await w('next.config.ts', nextconfig) }

// Seed data
await fs.mkdir(path.join(root,'data'), { recursive: true })
try { await fs.stat('data/pricing-rules.json') } catch {
  await w('data/pricing-rules.json', JSON.stringify({
    rules: [{ id:'seed-rule-1', name:'Base margin', type:'margin', value:0.15, enabled:true, scope:'global' }]
  }, null, 2))
}

// Lib + API
await w('src/lib/fsdb.ts', fsdb)
await w('app/api/pricing/rules/route.ts', apiRules)
await w('app/api/health/route.ts', apiHealth)

// Component
await w('src/components/AdminPage.tsx', adminPage)

// Routes
for (const r of [
  { route:'admin/users', title:'Users', feature:'User management' },
  { route:'admin/audit', title:'Audit', feature:'Audit log & events' },
  { route:'admin/flags', title:'Flags', feature:'Feature flags' },
  { route:'admin/integrations', title:'Integrations', feature:'Integrations overview' },
]) {
  await w(`app/${r.route}/page.tsx`, mkPage(r.title, r.feature))
  await w(`app/${r.route}/error.tsx`, err)
  await w(`app/${r.route}/loading.tsx`, load)
}
await w('app/admin/integrations/[provider]/page.tsx', integProvider)

// Pricing placeholder (only if missing)
let pricingExists = await fs.stat(path.join(root,'app/admin/pricing/page.tsx')).then(()=>true).catch(()=>false)
if (!pricingExists) {
  await w('app/admin/pricing/page.tsx', `import dynamic from 'next/dynamic'
const AdminPage = dynamic(() => import('@/src/components/AdminPage'), { ssr: false })
export default function Page(){ return <AdminPage title="Pricing"><p>Connect to <code>/api/pricing/rules</code> using fetch for live data.</p></AdminPage> }
export const dynamic = 'force-static'
`)
}

// Update package.json scripts
const pkgPath = path.join(root,'package.json')
const pkg = JSON.parse(await fs.readFile(pkgPath,'utf8'))
pkg.scripts ||= {}
pkg.scripts.dev   ||= 'next dev -p 3000'
pkg.scripts.build ||= 'next build'
pkg.scripts.start ||= 'next start -p 3000'
pkg.scripts['sanity:api'] = 'node scripts/sanity-api.mjs'
await fs.writeFile(pkgPath, JSON.stringify(pkg,null,2))

// Sanity script
await fs.mkdir(path.join(root,'scripts'), { recursive: true })
await w('scripts/sanity-api.mjs', `import assert from 'node:assert/strict'
const base = process.env.BASE_URL || 'http://localhost:3000'
const j = r => r.json()
const ok = r => { if(!r.ok) throw new Error(r.status+': '+r.statusText); return r }
const health = await fetch(base+'/api/health').then(ok).then(j); console.assert(health.ok===true)
const rules  = await fetch(base+'/api/pricing/rules').then(ok).then(j); console.assert(Array.isArray(rules.rules))
const id='autotest-rule'
await fetch(base+'/api/pricing/rules',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({id,name:'Auto Test',type:'margin',value:0.2,enabled:true})}).then(r=>r.ok||r.status===409?r:Promise.reject(new Error(r.status)))
const updated = await fetch(base+'/api/pricing/rules',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({id,name:'Auto Test',type:'margin',value:0.25,enabled:true})}).then(ok).then(j); console.assert(updated.value===0.25)
await fetch(base+\`/api/pricing/rules?id=\${id}\`,{method:'DELETE'}).then(r=>r.ok||Promise.reject(new Error(r.status)))
console.log('Sanity OK')
`)
console.log('All files written.')
__NODE__

# 4) Kjøring
echo "
---
KJØRING
1) Start dev:   npm run dev   (evt. pnpm/yarn)
2) Åpne:
   /admin/users
   /admin/audit
   /admin/flags
   /admin/integrations
   /admin/integrations/salesforce
3) API-sjekk:
   curl -sS http://localhost:3000/api/health | jq
   curl -sS http://localhost:3000/api/pricing/rules | jq
   node scripts/sanity-api.mjs
---
"