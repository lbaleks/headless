// app/lib/units.ts
export type BaseUom = { name: string; baseQty: number; baseLabel: string };
export type Variant = { label: string; multiplier: number; priceFactor?: number };

export function toBaseQty(units: number, multiplier: number) {
  return Math.max(0, Math.round((units || 0) * (multiplier || 0)));
}
export function priceFromBase(basePricePerBaseUnit: number, multiplier: number, priceFactor?: number) {
  const factor = typeof priceFactor === "number" ? priceFactor : multiplier;
  return basePricePerBaseUnit * factor;
}
export function maxUnitsPurchasable(availableBaseQty: number, multiplier: number) {
  return Math.floor((availableBaseQty || 0) / (multiplier || 1));
}
