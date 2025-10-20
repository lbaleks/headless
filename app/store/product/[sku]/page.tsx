"use client";
import React from "react";

type VariantInfo = { label:string; multiplier:number; price:number; maxUnits:number };
type Lot = { lotId:string; qty:number; expiry?:string };

async function fetchVariants(sku: string) {
  const r = await fetch(`/api/catalog/product/${encodeURIComponent(sku)}/variants`, { cache: "no-store" });
  return r.json();
}

export default function ProductPage(props: { params: Promise<{ sku: string }> }) {
  const { sku } = React.use(props.params); // <- Next 15: unwrap params
  const [loading, setLoading] = React.useState(true);
  const [data, setData] = React.useState<any>(null);
  const [variant, setVariant] = React.useState<number>(0);
  const [qty, setQty] = React.useState<number>(1);

  React.useEffect(() => {
    let alive = true;
    (async () => {
      const j = await fetchVariants(sku);
      if (!alive) return;
      setData(j); setLoading(false);
    })();
    return () => { alive = false; };
  }, [sku]);

  const variants: VariantInfo[] = data?.variants ?? [];
  const v = variants[variant];

  return (
    <main className="p-6 space-y-6">
      <h2 className="text-base font-medium">Produkt: {sku}</h2>
      {loading && <div className="sub">Laster…</div>}
      {!loading && (
        <section className="card space-y-3">
          <div className="text-sm">Base: {data?.base?.baseLabel} • På lager (base): {data?.availableBaseQty}</div>
          <div className="flex gap-3 items-end">
            <label className="block">
              <div className="text-xs opacity-60 mb-1">Variant</div>
              <select className="border rounded-lg px-3 py-1.5 text-sm" value={variant} onChange={e=>setVariant(Number(e.target.value)||0)}>
                {variants.map((x,i)=><option key={x.label} value={i}>{x.label} — {x.price}</option>)}
              </select>
            </label>
            <label className="block">
              <div className="text-xs opacity-60 mb-1">Antall</div>
              <input type="number" className="border rounded-lg px-3 py-1.5 text-sm w-24" value={qty} onChange={e=>setQty(Number(e.target.value)||0)} />
            </label>
            {v && <div className="text-xs opacity-60">Maks {v.maxUnits} enheter</div>}
          </div>
          {v && <div className="text-sm">Forespurt base-kvantum: <b>{qty} × {v.multiplier} = {qty*v.multiplier}</b></div>}
        </section>
      )}
    </main>
  );
}
