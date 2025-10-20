// app/api/catalog/product/[sku]/config/route.ts
import { NextResponse } from "next/server";
import { getProduct, setStrategy, type Strategy } from "../../../../../data/catalog";

export async function GET(_req: Request, ctx: { params: { sku: string } }) {
  try {
    const sku = ctx.params?.sku || "";
    const p = getProduct(sku);
    if (!p) return NextResponse.json({ ok:false, error:"not_found" }, { status:404 });
    return NextResponse.json({
      ok: true,
      sku: p.sku,
      name: p.name,
      strategy: p.strategy,
      baseUom: p.baseUom,
      basePrice: p.basePrice,
    });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "server_error" }, { status:500 });
  }
}

export async function POST(req: Request, ctx: { params: { sku: string } }) {
  try {
    const sku = ctx.params?.sku || "";
    const body = await req.json().catch(() => ({}));
    const strategy = body?.strategy as Strategy | undefined;
    if (strategy !== "FIFO" && strategy !== "FEFO") {
      return NextResponse.json({ ok:false, error:"invalid_strategy" }, { status:400 });
    }
    setStrategy(sku, strategy);
    return NextResponse.json({ ok:true });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "server_error" }, { status:500 });
  }
}
