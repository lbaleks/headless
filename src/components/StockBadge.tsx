"use client";
import React from "react";

export default function StockBadge({ qty }: { qty?: number }) {
  const q = typeof qty === "number" ? qty : 0;
  let color = "bg-neutral-300 text-neutral-800";
  let label = "Ukjent";
  if (q > 10) { color = "bg-green-100 text-green-800"; label = "På lager"; }
  else if (q > 0) { color = "bg-yellow-100 text-yellow-800"; label = "Lavt lager"; }
  else { color = "bg-red-100 text-red-800"; label = "Tomt"; }
  return <span className={`inline-flex items-center px-2 py-1 text-xs font-medium rounded ${color}`}>{label}</span>;
}
