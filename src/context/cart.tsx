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
