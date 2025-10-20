"use client";
import React, { useState } from "react";
import { useState, useEffect } from "react";
import ProductCard from "./ProductCard";
import { usePaginatedProducts } from "@/hooks/usePaginatedProducts";

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
