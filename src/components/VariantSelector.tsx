"use client";
import React, { useState } from "react";
import { useState, useEffect } from "react";
import { useCart } from "@/context/cart";

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
