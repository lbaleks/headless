export const runtime = 'nodejs';
import { NextResponse } from "next/server";
import { Variant, priceFromBase, maxUnitsPurchasable } from "../../../lib/units";

export async function GET() {
  // Demo-oppsett: lager i base-enheter: 100 g
  const base = { name: "grams", baseQty: 100, baseLabel: "100 g" };
  const basePrice = 9.9;         // pris per 100 g
  const availableBaseQty = 1200; // 1200 × 100g = 120 kg

  const variants: Variant[] = [
    { label: "100 g",       multiplier: 1 },
    { label: "1 kg",        multiplier: 10 },
    { label: "25 kg sekk",  multiplier: 250, priceFactor: 245 }, // rabatt vs 250
  ];

  const enriched = variants.map(v => ({
    label: v.label,
    multiplier: v.multiplier,
    price: Number(priceFromBase(basePrice, v.multiplier, v.priceFactor).toFixed(2)),
    maxUnits: maxUnitsPurchasable(availableBaseQty, v.multiplier),
  }));

  return NextResponse.json({ ok: true, base, basePrice, availableBaseQty, variants: enriched });
}
