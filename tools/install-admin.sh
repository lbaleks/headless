#!/usr/bin/env bash
set -e
echo "🚀  Installing Admin v2 for Litebrygg (Next.js + API hooks)…"

ROOT=$(pwd)
APP_DIR="$ROOT/app/admin"
CMP_DIR="$ROOT/components/admin"
LIB_DIR="$ROOT/lib"

mkdir -p "$APP_DIR"/{products,orders,customers} "$CMP_DIR" "$LIB_DIR"

# ---- lib/api.ts --------------------------------------------------------------
cat >"$LIB_DIR/api.ts" <<'EOF'
export const BASE = process.env.NEXT_PUBLIC_BASE || '';
type Query = Record<string, string | number | boolean | undefined>;
export function qs(q: Query = {}) {
  const u = new URLSearchParams();
  Object.entries(q).forEach(([k, v]) => {
    if (v !== undefined && v !== '') u.set(k, String(v));
  });
  return u.toString();
}
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const url = `${BASE}${path}`;
  const r = await fetch(url, {
    cache: 'no-store',
    ...init,
    headers: { 'content-type': 'application/json', ...(init?.headers || {}) },
  });
  if (!r.ok) {
    let d:any=null; try{d=await r.json();}catch{}
    throw new Error(d?.error||d?.message||`HTTP ${r.status} @ ${path}`);
  }
  return r.json() as Promise<T>;
}
EOF

# ---- layout + page redirect --------------------------------------------------
cat >"$APP_DIR/layout.tsx" <<'EOF'
import Link from "next/link";
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-neutral-50 text-neutral-900">
      <header className="border-b bg-white">
        <div className="mx-auto max-w-6xl px-4 py-3 flex items-center gap-6">
          <h1 className="font-semibold tracking-tight">Admin</h1>
          <nav className="text-sm flex gap-4">
            <Link href="/admin/products" className="hover:underline">Products</Link>
            <Link href="/admin/orders" className="hover:underline">Orders</Link>
            <Link href="/admin/customers" className="hover:underline">Customers</Link>
          </nav>
          <div className="ml-auto text-xs text-neutral-500">
            API base: {process.env.NEXT_PUBLIC_BASE || "/"}
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}
EOF

cat >"$APP_DIR/page.tsx" <<'EOF'
import { redirect } from "next/navigation";
export default function AdminIndex(){ redirect("/admin/products"); }
EOF

# ---- shared components -------------------------------------------------------
cat >"$CMP_DIR/StatusPill.tsx" <<'EOF'
export default function StatusPill({ value }: { value?: string | number }) {
  const v = String(value ?? "").toLowerCase();
  const color =
    v==="complete"||v==="processing" ? "bg-green-100 text-green-700 border-green-200" :
    v==="pending" ? "bg-amber-100 text-amber-700 border-amber-200" :
    v==="canceled" ? "bg-rose-100 text-rose-700 border-rose-200" :
    "bg-neutral-100 text-neutral-700 border-neutral-200";
  return <span className={`inline-block border rounded-full px-2 py-[2px] text-xs ${color}`}>{value ?? "—"}</span>;
}
EOF

cat >"$CMP_DIR/SourceBadge.tsx" <<'EOF'
export function SourceBadge({ source }: { source?: string }) {
  const s = String(source || "").toLowerCase();
  const isLocal = s==="local-stub"||s==="local-override";
  const cls = isLocal ? "bg-sky-100 text-sky-700 border-sky-200" : "bg-neutral-100 text-neutral-700 border-neutral-200";
  return <span className={`inline-block border rounded px-2 py-[2px] text-xs ${cls}`}>{source || "magento"}</span>;
}
EOF

cat >"$CMP_DIR/InlineText.tsx" <<'EOF'
"use client";
import { useState } from "react";
export function InlineText({ value, onSave, placeholder="—", className="" }:{
  value?: string; onSave:(v:string)=>Promise<void>; placeholder?:string; className?:string;
}) {
  const [v,setV]=useState(value??""); const [saving,setSaving]=useState(false);
  async function commit(){ if(saving)return; setSaving(true); try{await onSave(v);}finally{setSaving(false);} }
  return (
    <div className={`inline-flex items-center gap-2 ${className}`}>
      <input className="border rounded px-2 py-1 text-sm bg-white" value={v}
        onChange={e=>setV(e.target.value)} placeholder={placeholder}
        onBlur={commit} onKeyDown={e=>{if(e.key==="Enter")(e.target as HTMLInputElement).blur();}}/>
      {saving && <span className="text-xs text-neutral-500">lagrer…</span>}
    </div>
  );
}
EOF

cat >"$CMP_DIR/InlineNumber.tsx" <<'EOF'
"use client";
import { useState } from "react";
export function InlineNumber({ value,onSave,step=1,min=0 }:{
  value?:number; onSave:(v:number)=>Promise<void>; step?:number; min?:number;
}) {
  const [v,setV]=useState<number>(Number(value??0)); const [saving,setSaving]=useState(false);
  async function commit(){ if(saving)return; setSaving(true); try{await onSave(Number(v));}finally{setSaving(false);} }
  return (
    <div className="inline-flex items-center gap-2">
      <input type="number" step={step} min={min} className="border rounded px-2 py-1 w-28 text-sm bg-white"
        value={v} onChange={e=>setV(Number(e.target.value))}
        onBlur={commit} onKeyDown={e=>{if(e.key==="Enter")(e.target as HTMLInputElement).blur();}}/>
      {saving && <span className="text-xs text-neutral-500">lagrer…</span>}
    </div>
  );
}
EOF

# ---- admin pages -------------------------------------------------------------
curl -fsSL https://raw.githubusercontent.com/litebrygg/m2-admin-snippets/main/products.page.tsx -o "$APP_DIR/products/page.tsx" 2>/dev/null || echo "⚠️  TODO: paste products.page.tsx manually (see spec)."
curl -fsSL https://raw.githubusercontent.com/litebrygg/m2-admin-snippets/main/orders.page.tsx   -o "$APP_DIR/orders/page.tsx"   2>/dev/null || echo "⚠️  TODO: paste orders.page.tsx manually (see spec)."
curl -fsSL https://raw.githubusercontent.com/litebrygg/m2-admin-snippets/main/customers.page.tsx -o "$APP_DIR/customers/page.tsx" 2>/dev/null || echo "⚠️  TODO: paste customers.page.tsx manually (see spec)."

# ---- deps --------------------------------------------------------------------
echo "📦  Installing dependencies…"
npm install next@latest react@latest react-dom@latest --save

# ---- env ---------------------------------------------------------------------
if ! grep -q "NEXT_PUBLIC_BASE" .env.local 2>/dev/null; then
  echo "NEXT_PUBLIC_BASE=http://localhost:3000" >> .env.local
fi

echo "✅  Admin v2 installed. Starting dev server..."
npm run dev