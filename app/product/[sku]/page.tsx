"use client";
import React, { useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Image from "next/image";
import StockBadge from "@/src/components/StockBadge";

type Product = {
  id?: string;
  sku?: string;
  name?: string;
  title?: string; // fallback hvis API bruker title
  description?: string;
  price?: number;
  images?: string[];                // array av urls
  image?: string;                   // fallback: enkeltbilde
  qty?: number;                     // lager
  attributes?: { key: string; value: string }[];
};

function normalize(p: any): Product {
  if (!p) return {};
  return {
    id: p.id ?? p._id,
    sku: p.sku ?? p.SKU ?? p.code ?? p.id,
    name: p.name ?? p.title ?? p.productName ?? p.sku,
    title: p.title ?? p.name,
    description: p.description ?? p.subtitle ?? "",
    price: typeof p.price === "number" ? p.price : Number(p.price ?? 0),
    images: Array.isArray(p.images) ? p.images : (p.image ? [p.image] : []),
    image: p.image,
    qty: p.qty ?? p.stock ?? p.inventory ?? 0,
    attributes: Array.isArray(p.attributes) ? p.attributes : [],
  };
}

function useProductBySku(sku: string | undefined) {
  const [data, setData] = useState<Product | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    let mounted = true;
    if (!sku) return;
    (async () => {
      setLoading(true); setError(null);
      try {
        // 1) Prøv query mot /api/products?sku=
        const r1 = await fetch(`/api/products?sku=${encodeURIComponent(String(sku))}`, { cache: "no-store" });
        if (r1.ok) {
          const j = await r1.json();
          const arr = Array.isArray(j) ? j : (Array.isArray(j?.items) ? j.items : []);
          const found = arr.find((x: any) => String(x?.sku ?? x?.SKU ?? x?.code ?? x?.id) === String(sku));
          if (found) { mounted && setData(normalize(found)); mounted && setLoading(false); return; }
        }
        // 2) Fallback: hent alle og filtrer
        const r2 = await fetch(`/api/products`, { cache: "no-store" });
        if (!r2.ok) throw new Error(`API ${r2.status}`);
        const j2 = await r2.json();
        const arr2 = Array.isArray(j2) ? j2 : (Array.isArray(j2?.items) ? j2.items : []);
        const found2 = arr2.find((x: any) => String(x?.sku ?? x?.SKU ?? x?.code ?? x?.id) === String(sku));
        mounted && setData(found2 ? normalize(found2) : null);
      } catch (e: any) {
        mounted && setError(e?.message ?? "Ukjent feil");
      } finally {
        mounted && setLoading(false);
      }
    })();
    return () => { mounted = false; };
  }, [sku]);

  return { data, error, loading };
}

function addToCart(item: { sku: string; name?: string; price?: number; qty: number }) {
  if (!item?.sku) return;
  try {
    const key = "cart";
    const raw = typeof window !== "undefined" ? localStorage.getItem(key) : "[]";
    const cart = raw ? JSON.parse(raw) as any[] : [];
    const i = cart.findIndex(x => x.sku === item.sku);
    if (i >= 0) cart[i].qty = Number(cart[i].qty || 0) + item.qty;
    else cart.push({ ...item });
    localStorage.setItem(key, JSON.stringify(cart));
  } catch { /* ignore */ }
}

export default function ProductDetailPage() {
  const { sku } = useParams<{ sku: string }>();
  const router = useRouter();
  const { data: p, error, loading } = useProductBySku(sku);

  // Kvantum-multiplikator (eks: 1, 6, 12)
  const [step, setStep] = useState<number>(1);
  const [qty, setQty] = useState<number>(1);

  useEffect(() => {
    setQty(step); // når man bytter multiplikator, sett qty = step
  }, [step]);

  const priceTotal = useMemo(() => {
    const unit = Number(p?.price || 0);
    return Math.max(0, unit * qty);
  }, [p?.price, qty]);

  if (loading) return <div className="p-6">Laster produkt…</div>;
  if (error) return <div className="p-6 text-red-600">Feil: {error}</div>;
  if (!p) return <div className="p-6">Fant ikke produktet.</div>;

  const img = p.images?.[0] || p.image || "/placeholder.svg";
  const name = p.name || p.title || p.sku || "Produkt";

  return (
    <main className="max-w-5xl mx-auto p-6">
      <button
        type="button"
        className="text-sm text-neutral-600 hover:underline"
        onClick={() => router.back()}
      >
        ← Tilbake
      </button>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 mt-4">
        {/* Bilde */}
        <div className="border rounded-lg p-2 bg-white">
          <Image
            src={img}
            alt={name}
            width={800}
            height={600}
            className="w-full h-auto object-contain rounded"
          />
          {p.images && p.images.length > 1 && (
            <div className="grid grid-cols-4 gap-2 mt-2">
              {p.images.slice(0, 8).map((u, i) => (
                <Image key={u + i} src={u} alt={`${name}-${i}`} width={200} height={150}
                  className="w-full h-24 object-cover rounded border" />
              ))}
            </div>
          )}
        </div>

        {/* Info */}
        <div>
          <h1 className="text-2xl font-semibold">{name}</h1>
          <div className="mt-2 flex items-center gap-3">
            <StockBadge qty={p.qty} />
            {typeof p.price === "number" && (
              <div className="text-xl font-medium tabular-nums">{p.price.toFixed(2)} kr</div>
            )}
          </div>

          {p.description && (
            <p className="mt-4 text-neutral-700 whitespace-pre-wrap">{p.description}</p>
          )}

          {/* Kvantum + multiplikator */}
          <div className="mt-6 border rounded-lg p-4 space-y-3">
            <div className="text-sm font-medium">Kvantum</div>
            <div className="flex gap-2">
              {[1, 6, 12, 24].map(v => (
                <button
                  key={v}
                  type="button"
                  onClick={() => setStep(v)}
                  className={`px-3 py-1 rounded border ${step === v ? "bg-black text-white" : "bg-white hover:bg-neutral-50"}`}
                >
                  x{v}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-2">
              <input
                type="number"
                min={step}
                step={step}
                value={qty}
                onChange={(e) => setQty(Math.max(step, Number(e.target.value || step)))}
                className="border rounded px-3 py-2 w-32"
              />
              <div className="text-sm text-neutral-600">Total: <b>{priceTotal.toFixed(2)} kr</b></div>
            </div>
            <button
              type="button"
              onClick={() => addToCart({ sku: p.sku || "", name, price: p.price, qty })}
              className="px-4 py-2 rounded bg-black text-white hover:bg-black/85"
              disabled={!p.sku}
            >
              Legg i handlekurv
            </button>
          </div>

          {/* Attributter */}
          {p.attributes && p.attributes.length > 0 && (
            <div className="mt-6">
              <div className="font-medium mb-2">Egenskaper</div>
              <table className="text-sm">
                <tbody>
                  {p.attributes.map((a, i) => (
                    <tr key={(a.key || "k") + i}>
                      <td className="pr-4 text-neutral-500">{a.key}</td>
                      <td className="font-medium">{a.value}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

        </div>
      </div>
    </main>
  );
}
