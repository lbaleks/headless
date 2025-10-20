// app/data/catalog.ts
export type Strategy = "FIFO" | "FEFO";
export type BaseUom = { name: string; baseQty: number; baseLabel: string };
export type Lot = { lotId: string; qty: number; expiry?: string };
export type Product = {
  sku: string;
  name: string;
  strategy: Strategy;
  baseUom: BaseUom;
  basePrice: number;        // pris pr. "baseUom.baseQty"
  availableBaseQty: number; // tilgjengelig i base-enheter
  lots: Lot[];
};

const DB: Record<string, Product> = {
  "FLOUR-001": {
    sku: "FLOUR-001",
    name: "Hvetemel",
    strategy: "FEFO",
    baseUom: { name: "grams", baseQty: 100, baseLabel: "100 g" },
    basePrice: 9.9,
    availableBaseQty: 1200, // 1200 × 100 g = 120 kg
    lots: [
      { lotId: "F1", qty: 300, expiry: "2026-01-01" },
      { lotId: "F2", qty: 900, expiry: "2025-12-01" },
    ],
  },
  "COFFEE-250": {
    sku: "COFFEE-250",
    name: "Kaffe",
    strategy: "FIFO",
    baseUom: { name: "grams", baseQty: 250, baseLabel: "250 g" },
    basePrice: 49.0,
    availableBaseQty: 500, // 500 × 250 g = 125 kg
    lots: [
      { lotId: "C1", qty: 300 },
      { lotId: "C2", qty: 200 },
    ],
  },
};

export function getProduct(sku: string): Product | undefined {
  return DB[sku];
}
export function setStrategy(sku: string, strategy: Strategy): void {
  const p = DB[sku];
  if (p) p.strategy = strategy;
}
export function getLots(sku: string): Lot[] {
  const p = DB[sku];
  return p ? (p.lots || []) : [];
}
export function setLots(sku: string, lots: Lot[]): void {
  const p = DB[sku];
  if (p) p.lots = Array.isArray(lots) ? lots.filter(x => x && x.lotId) : [];
}
