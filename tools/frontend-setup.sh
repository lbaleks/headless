#!/bin/bash
set -euo pipefail

echo "🛠  Frontend autoinstaller (store) – setter opp app/(store) + klient + komponenter"

# 0) Sjekk for pnpm
command -v pnpm >/dev/null 2>&1 || { echo "❌ pnpm mangler. Installer: corepack enable && corepack prepare pnpm@latest --activate"; exit 1; }

# 1) Dependencies (lette, battle-tested)
echo "→ Installerer avhengigheter (ky, swr, zod, clsx)"
pnpm add ky swr zod clsx

# 2) Folderstruktur
echo "→ Lager mapper"
mkdir -p app/\(store\)/product/[sku] app/\(store\)/cart app/\(store\)/account app/\(store\)/checkout
mkdir -p src/lib src/components src/context src/hooks
mkdir -p public/placeholder

# 3) Envs (legg til hvis ikke finnes)
touch .env.local
grep -q '^MAGENTO_BASE_URL=' .env.local || echo 'MAGENTO_BASE_URL="https://apistage.example.com/rest/V1"' >> .env.local
grep -q '^MAGENTO_TOKEN=' .env.local || echo 'MAGENTO_TOKEN=""' >> .env.local

# 4) Minimal Magento-klient (REST v1; bytt til GraphQL senere om ønskelig)
cat > src/lib/magento.ts <<'TS'
import ky from "ky";

const baseURL = process.env.MAGENTO_BASE_URL || "";
const token   = process.env.MAGENTO_TOKEN   || "";

export const mApi = ky.create({
  prefixUrl: baseURL.replace(/\/+$/,""),
  headers: token ? { Authorization: `Bearer ${token}` } : {},
  timeout: 20000,
  hooks: {
    beforeRequest: [
      req => {
        // JSON default
        req.headers.set("Content-Type","application/json");
      }
    ]
  }
});

// --- Typer (enkle) ---
export type MProduct = {
  id: number;
  sku: string;
  name: string;
  price?: number;
  custom_attributes?: { attribute_code: string; value: string }[];
  media_gallery_entries?: { file: string; label?: string }[];
  extension_attributes?: any;
};

export function imgFrom(product: MProduct): string | null {
  const file = product.media_gallery_entries?.[0]?.file;
  if (!file) return null;
  const clean = file.startsWith("/") ? file.slice(1) : file;
  // Typisk Magento: /media/catalog/product/...
  return `${(process.env.MAGENTO_BASE_URL||"")
    .replace(/\/rest\/V1$/,"")
    .replace(/\/+$/,"")}/media/${clean}`;
}

// --- REST-hjelpere ---
export async function searchProducts(opts: { q?: string; page?: number; pageSize?: number; categoryId?: number } = {}) {
  const page = Math.max(1, Number(opts.page||1));
  const pageSize = Math.min(60, Math.max(1, Number(opts.pageSize||24)));

  const searchCriteria = new URLSearchParams();
  let idx = 0;
  if (opts.q) {
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][field]`, "name");
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][value]`, `%${opts.q}%`);
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][condition_type]`, "like");
    idx++;
  }
  if (opts.categoryId) {
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][field]`, "category_id");
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][value]`, String(opts.categoryId));
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][condition_type]`, "eq");
    idx++;
  }
  searchCriteria.set("searchCriteria[currentPage]", String(page));
  searchCriteria.set("searchCriteria[pageSize]", String(pageSize));

  const u = `products?${searchCriteria.toString()}`;
  const res = await mApi.get(u).json<{ items: MProduct[], total_count: number }>();
  return res;
}

export async function getProductBySku(sku: string) {
  const res = await mApi.get(`products/${encodeURIComponent(sku)}`).json<MProduct>();
  return res;
}
TS

# 5) Cart-context (client component)
cat > src/context/cart.tsx <<'TSX'
"use client";
import React, { createContext, useContext, useEffect, useMemo, useState } from "react";

export type CartLine = { sku: string; name: string; qty: number; price?: number; image?: string; };
type CartState = { lines: CartLine[]; add: (l: CartLine)=>void; remove: (sku: string)=>void; clear: ()=>void; };

const CartCtx = createContext<CartState|null>(null);

export function CartProvider({ children }: { children: React.ReactNode }) {
  const [lines, setLines] = useState<CartLine[]>([]);

  // hydrate from localStorage
  useEffect(()=> {
    try { const raw = localStorage.getItem("m2_cart"); if (raw) setLines(JSON.parse(raw)); } catch {}
  }, []);
  useEffect(()=> { try { localStorage.setItem("m2_cart", JSON.stringify(lines)); } catch {} }, [lines]);

  const api = useMemo<CartState>(()=>({
    lines,
    add: (l) => setLines(prev => {
      const ix = prev.findIndex(p => p.sku === l.sku);
      if (ix >= 0) { const copy=[...prev]; copy[ix] = { ...copy[ix], qty: copy[ix].qty + l.qty }; return copy; }
      return [...prev, l];
    }),
    remove: (sku) => setLines(prev => prev.filter(p => p.sku !== sku)),
    clear: () => setLines([])
  }), [lines]);

  return <CartCtx.Provider value={api}>{children}</CartCtx.Provider>;
}

export const useCart = () => {
  const ctx = useContext(CartCtx);
  if (!ctx) throw new Error("useCart must be used within CartProvider");
  return ctx;
};
TSX

# 6) Hooks
cat > src/hooks/usePaginatedProducts.ts <<'TS'
import useSWR from "swr";
import { searchProducts } from "@/src/lib/magento";

export function usePaginatedProducts(params: { q?: string; page?: number; pageSize?: number }) {
  const key = ["products", params.q||"", params.page||1, params.pageSize||24] as const;
  return useSWR(key, () => searchProducts(params));
}
TS

# 7) Komponenter
cat > src/components/StockBadge.tsx <<'TSX'
"use client";
import React from "react";
import clsx from "clsx";

export default function StockBadge({ qty }: { qty?: number }) {
  const tone = qty == null ? "bg-neutral-300" : qty > 10 ? "bg-green-500" : qty > 0 ? "bg-yellow-400" : "bg-red-500";
  const label = qty == null ? "Ukjent" : qty > 10 ? "På lager" : qty > 0 ? "Lavt lager" : "Utsolgt";
  return (
    <span className={clsx("inline-flex items-center gap-2 text-xs px-2 py-1 rounded-full", "bg-black/5 dark:bg-white/10")}>
      <span className={`inline-block w-2.5 h-2.5 rounded-full ${tone}`} />
      {label}
    </span>
  );
}
TSX

cat > src/components/ProductCard.tsx <<'TSX'
import Image from "next/image";
import Link from "next/link";
import StockBadge from "./StockBadge";
import { MProduct, imgFrom } from "@/src/lib/magento";

export default function ProductCard({ p }: { p: MProduct }) {
  const img = imgFrom(p);
  return (
    <Link href={`/product/${encodeURIComponent(p.sku)}`} className="block rounded-2xl border p-3 hover:shadow-sm transition">
      <div className="aspect-square relative rounded-xl overflow-hidden bg-white dark:bg-neutral-900">
        {img ? (
          <Image src={img} alt={p.name} fill sizes="(min-width: 768px) 25vw, 50vw" className="object-contain" />
        ) : (
          <div className="w-full h-full grid place-items-center text-xs opacity-60">Ingen bilde</div>
        )}
      </div>
      <div className="mt-3 flex flex-col gap-1">
        <div className="text-sm font-medium line-clamp-2">{p.name}</div>
        <div className="text-xs opacity-70">{p.sku}</div>
        <div className="flex items-center justify-between mt-1">
          <span className="font-semibold">{p.price != null ? `${p.price.toFixed(2)} kr` : "Pris ukjent"}</span>
          <StockBadge qty={p.extension_attributes?.stock_item?.qty} />
        </div>
      </div>
    </Link>
  );
}
TSX

cat > src/components/ProductGrid.tsx <<'TSX'
"use client";
import React, { useState } from "react";
import ProductCard from "./ProductCard";
import { usePaginatedProducts } from "@/src/hooks/usePaginatedProducts";

export default function ProductGrid() {
  const [page, setPage] = useState(1);
  const { data, isLoading } = usePaginatedProducts({ page, pageSize: 24 });

  if (isLoading) return <div className="p-6">Laster…</div>;
  const items = data?.items ?? [];
  const total = data?.total_count ?? 0;
  const maxPage = Math.max(1, Math.ceil(total / 24));

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {items.map(p => (<ProductCard key={p.sku} p={p} />))}
      </div>
      <div className="flex items-center justify-center gap-3 py-4">
        <button className="px-3 py-1.5 border rounded" disabled={page<=1} onClick={()=>setPage(p=>Math.max(1,p-1))}>Forrige</button>
        <span className="text-sm opacity-70">{page} / {maxPage}</span>
        <button className="px-3 py-1.5 border rounded" disabled={page>=maxPage} onClick={()=>setPage(p=>Math.min(maxPage,p+1))}>Neste</button>
      </div>
    </div>
  );
}
TSX

cat > src/components/VariantSelector.tsx <<'TSX'
"use client";
import React, { useState } from "react";
import { useCart } from "@/src/context/cart";

export default function VariantSelector({ sku, name, price, image }: { sku: string; name: string; price?: number; image?: string }) {
  const { add } = useCart();
  const [qty, setQty] = useState(1);
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <input type="number" className="w-20 border rounded px-2 py-1" min={1} value={qty} onChange={e=>setQty(Math.max(1, Number(e.target.value||1)))} />
        <button className="px-3 py-2 rounded border hover:bg-black/5" onClick={()=>add({ sku, name, qty, price, image })}>
          Legg i kurv
        </button>
      </div>
      <div className="text-xs opacity-70">Pris: {price != null ? `${price.toFixed(2)} kr` : "ukjent"}</div>
    </div>
  );
}
TSX

# 8) Layout + sider (App Router)
cat > app/\(store\)/layout.tsx <<'TSX'
import React from "react";
import Link from "next/link";
import { CartProvider } from "@/src/context/cart";

export const metadata = { title: "Litebrygg – Nettbutikk", description: "Frontend (store)" };

export default function StoreLayout({ children }: { children: React.ReactNode }) {
  return (
    <CartProvider>
      <div className="min-h-dvh flex flex-col">
        <header className="sticky top-0 z-20 bg-white/80 dark:bg-black/40 backdrop-blur border-b">
          <nav className="mx-auto max-w-6xl px-4 h-14 flex items-center gap-4">
            <Link href="/" className="font-semibold">Litebrygg</Link>
            <Link href="/cart" className="ml-auto">Kurv</Link>
            <Link href="/account">Min side</Link>
          </nav>
        </header>
        <main className="mx-auto max-w-6xl w-full px-4 py-6">{children}</main>
        <footer className="border-t py-6 text-center text-sm opacity-70">© Litebrygg</footer>
      </div>
    </CartProvider>
  );
}
TSX

cat > app/\(store\)/page.tsx <<'TSX'
import ProductGrid from "@/src/components/ProductGrid";

export default function Home() {
  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">Produkter</h1>
      <ProductGrid />
    </div>
  );
}
TSX

cat > app/\(store\)/product/[sku]/page.tsx <<'TSX'
import Image from "next/image";
import { getProductBySku, imgFrom } from "@/src/lib/magento";
import VariantSelector from "@/src/components/VariantSelector";

export default async function ProductPage({ params }: { params: { sku: string }}) {
  const p = await getProductBySku(params.sku);
  const img = imgFrom(p);

  return (
    <div className="grid md:grid-cols-2 gap-8">
      <div className="relative aspect-square rounded-2xl overflow-hidden bg-white dark:bg-neutral-900">
        {img ? <Image src={img} alt={p.name} fill sizes="50vw" className="object-contain" /> : <div className="grid place-items-center opacity-60">Ingen bilde</div>}
      </div>
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold">{p.name}</h1>
        <div className="text-lg font-medium">{p.price != null ? `${p.price.toFixed(2)} kr` : "Pris ukjent"}</div>
        <VariantSelector sku={p.sku} name={p.name} price={p.price} image={img || undefined} />
        <div className="prose dark:prose-invert max-w-none">
          {/* Enkel beskrivelse fra custom_attributes dersom finnes */}
          <p>{p.custom_attributes?.find(a=>a.attribute_code==="description")?.value || "Produktbeskrivelse kommer."}</p>
        </div>
      </div>
    </div>
  );
}
TSX

cat > app/\(store\)/cart/page.tsx <<'TSX'
"use client";
import React from "react";
import Image from "next/image";
import Link from "next/link";
import { useCart } from "@/src/context/cart";

export default function CartPage() {
  const { lines, remove, clear } = useCart();
  const sum = lines.reduce((s,l)=> s + (l.price || 0)*l.qty, 0);

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">Handlekurv</h1>
      {lines.length === 0 ? (
        <div className="text-sm opacity-70">Kurven er tom. <Link href="/" className="underline">Fortsett å handle</Link></div>
      ) : (
        <>
          <ul className="space-y-3">
            {lines.map(l => (
              <li key={l.sku} className="flex items-center gap-4 border rounded-xl p-3">
                <div className="relative w-16 h-16 rounded bg-white dark:bg-neutral-900 overflow-hidden">
                  {l.image ? <Image src={l.image} alt={l.name} fill className="object-contain" /> : null}
                </div>
                <div className="flex-1">
                  <div className="font-medium">{l.name}</div>
                  <div className="text-xs opacity-70">{l.sku}</div>
                </div>
                <div className="w-20 text-right">{l.qty} stk</div>
                <div className="w-28 text-right">{l.price != null ? (l.price * l.qty).toFixed(2) : "-"} kr</div>
                <button className="ml-2 px-2 py-1 border rounded" onClick={()=>remove(l.sku)}>Fjern</button>
              </li>
            ))}
          </ul>
          <div className="flex items-center justify-between border-t pt-4">
            <button className="px-3 py-2 border rounded" onClick={clear}>Tøm kurv</button>
            <div className="text-lg font-semibold">Sum: {sum.toFixed(2)} kr</div>
          </div>
          <div className="text-right">
            <Link href="/checkout" className="inline-block px-4 py-2 rounded border hover:bg-black/5">Til kassen</Link>
          </div>
        </>
      )}
    </div>
  );
}
TSX

cat > app/\(store\)/checkout/page.tsx <<'TSX'
export default function CheckoutPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-xl font-semibold">Kasse</h1>
      <p>Denne siden kobles til faktisk betaling/frakt i neste steg (Klarna/Stripe + Bring/PostNord).</p>
    </div>
  );
}
TSX

cat > app/\(store\)/account/page.tsx <<'TSX'
export default function AccountPage() {
  return (
    <div className="space-y-3">
      <h1 className="text-xl font-semibold">Min side</h1>
      <p>Ordrehistorikk og gjenbestilling kommer her.</p>
    </div>
  );
}
TSX

# 9) Skript i package.json (legg til dev-store alias hvis ønskelig)
if [ -f package.json ]; then
  node - <<'JS'
const fs=require('fs');const pj=JSON.parse(fs.readFileSync('package.json','utf8'));
pj.scripts = pj.scripts || {};
pj.scripts["dev"] = pj.scripts["dev"] || "next dev";
pj.scripts["lint"] = pj.scripts["lint"] || "eslint .";
pj.scripts["dev:store"] = "next dev";
fs.writeFileSync('package.json', JSON.stringify(pj,null,2));
console.log("✓ package.json oppdatert");
JS
fi

# 10) Lint en gang
echo "→ Kjører eslint --fix"
pnpm run lint --fix || true

echo
echo "✅ Frontend (store) klar! "
echo "   • Sett korrekte miljøvariabler i .env.local:"
echo "       MAGENTO_BASE_URL=\"https://apistage.dittdomene.no/rest/V1\""
echo "       MAGENTO_TOKEN=\"<integration token>\""
echo "   • Start: pnpm dev  (åpne / for produktliste, /product/<sku> for produktside)"
