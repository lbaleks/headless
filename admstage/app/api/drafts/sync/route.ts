import { NextResponse } from "next/server";

type Draft = {
  sku?: string;
  name?: string;
  price?: number;
  stock?: number;
  sourceCode?: string;
  [k: string]: any;
};

export async function GET() {
  return NextResponse.json({ ok: true, info: "POST { items: Draft[] } to sync" });
}

export async function POST(req: Request) {
  try {
    const body = (await req.json().catch(() => null)) as { items?: Draft[] } | null;
    const items = Array.isArray(body?.items) ? body!.items! : [];
    const results: any[] = [];

    for (let i = 0; i < items.length; i++) {
      const r = items[i] || {};
      const sku = r.sku || r.name;
      const out: any = { ok: true, index: i, item: r };

      // Valgfritt lager-kall via lokal proxy (gir robust JSON-svar)
      if (sku && typeof r.stock === "number") {
        try {
          const stockPayload = { sku, qty: r.stock, sourceCode: r.sourceCode || "default" };
          const s = await fetch("http://localhost:3000/api/ops/stock", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(stockPayload),
          });
          const text = await s.text();
          let j: any = null; try { j = JSON.parse(text); } catch { j = { raw: (text || "").slice(0, 400) }; }
          out.stock = { http: s.status, ...j };
        } catch (e: any) {
          out.stock = { ok: false, error: e?.message || "stock_call_failed" };
        }
      }

      // TODO: her kan vi legge inn price/product mot gateway senere.

      results.push(out);
    }

    return NextResponse.json({ ok: true, count: results.length, results });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "sync_route_error" }, { status: 500 });
  }
}
