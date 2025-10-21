export const runtime = 'nodejs';
// app/api/catalog/product/[sku]/lots/route.ts
import { NextResponse } from "next/server";
import { getLots, setLots } from "../../../../../data/catalog";

export async function GET(_req: Request, ctx: { params: { sku: string } }) {
  try {
    const sku = ctx.params?.sku || "";
    return NextResponse.json({ ok:true, sku, lots: getLots(sku) });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "server_error" }, { status:500 });
  }
}

export async function POST(req: Request, ctx: { params: { sku: string } }) {
  try {
    const sku = ctx.params?.sku || "";
    const body = await req.json().catch(() => ({}));
    const lots = Array.isArray(body?.lots) ? body.lots : [];
    setLots(sku, lots);
    return NextResponse.json({ ok:true });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "server_error" }, { status:500 });
  }
}
