// app/api/catalog/product/[sku]/variants/route.ts
import { NextResponse } from "next/server";
import { getProduct } from "../../../../../data/catalog";

function variantPrice(basePrice: number, multiplier: number, priceFactor?: number) {
  const factor = typeof priceFactor === "number" ? priceFactor : multiplier;
  return Number((basePrice * factor).toFixed(2));
}
function maxUnits(availableBaseQty: number, multiplier: number) {
  const m = multiplier || 1;
  return Math.floor((availableBaseQty || 0) / m);
}

export async function GET(_req: Request, ctx: { params: { sku: string } }) {
  try {
    const sku = ctx.params?.sku || "";
    const p = getProduct(sku);
    if (!p) return NextResponse.json({ ok:false, error:"not_found" }, { status:404 });

    const baseLabel = p.baseUom?.baseLabel || "base";
    const vts = [
      { label: baseLabel,            multiplier: 1   },
      { label: "10 × " + baseLabel,  multiplier: 10  },
      { label: "25 × " + baseLabel,  multiplier: 25,  priceFactor: 24  },
      { label: "250 × " + baseLabel, multiplier: 250, priceFactor: 245 },
    ];

    const variants = vts.map(v => ({
      label: v.label,
      multiplier: v.multiplier,
      price: variantPrice(p.basePrice, v.multiplier, v.priceFactor),
      maxUnits: maxUnits(p.availableBaseQty, v.multiplier),
    }));

    return NextResponse.json({
      ok: true,
      sku: p.sku,
      baseUom: p.baseUom,
      basePrice: p.basePrice,
      availableBaseQty: p.availableBaseQty,
      variants,
    });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "server_error" }, { status:500 });
  }
}
