import { NextResponse } from "next/server";

function pickBase(){
  const a = (process.env.MAGENTO_BASE || process.env.NEXT_PUBLIC_GATEWAY_BASE || "").trim();
  if (a.startsWith("http")) return a.replace(/\/$/, "");
  return "http://127.0.0.1:3044";
}

function buildAuth(headers: Headers){
  const bearer = (process.env.M2_TOKEN || process.env.MAGENTO_TOKEN || "").trim();
  const basic  = (process.env.M2_BASIC || "").trim();
  if (bearer) { headers.set("Authorization", `Bearer ${bearer}`); return "bearer"; }
  if (basic)  { headers.set("Authorization", `Basic ${basic}`);   return "basic";  }
  return "none";
}

const BASE = pickBase();
const UPSTREAM = `${BASE}/rest/V1/products/base-prices`;

export async function GET(){
  const headers = new Headers({ "Content-Type": "application/json" });
  const auth = buildAuth(headers);
  return NextResponse.json({ ok: true, base: BASE, upstream: UPSTREAM, auth });
}

type PriceItem = { sku: string; price: number; store_id?: number };
type Payload = { prices: PriceItem[] };

export async function POST(req: Request){
  try{
    const body = await req.json().catch(() => ({} as any)) as Payload;
    const prices = Array.isArray(body?.prices) ? body.prices : [];
    if (!prices.length) return NextResponse.json({ ok:false, error:"prices_required" }, { status:400 });

    // enkel validering
    for (const it of prices){
      if (!it?.sku || typeof it?.price !== "number") {
        return NextResponse.json({ ok:false, error:"sku_and_price_required" }, { status:400 });
      }
    }

    const headers = new Headers({ "Content-Type": "application/json" });
    const auth = buildAuth(headers);

    const r = await fetch(UPSTREAM, { method:"POST", headers, body: JSON.stringify({ prices }) });
    const text = await r.text();
    let json: any = null; try { json = JSON.parse(text); } catch {}

    if (!r.ok) {
      return NextResponse.json(
        { ok:false, status: r.status, upstream: UPSTREAM, payload: { prices }, raw: (json ?? text) || null },
        { status: r.status || 502 }
      );
    }
    return NextResponse.json({ ok:true, upstream: UPSTREAM, payload: { prices }, data: json ?? text });
  }catch(e:any){
    return NextResponse.json({ ok:false, error: e?.message || "price_proxy_error" }, { status:500 });
  }
}
