"use client";
import React from "react";
import Image from "next/image";
import Link from "next/link";
import { useCart } from "@/context/cart";

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
