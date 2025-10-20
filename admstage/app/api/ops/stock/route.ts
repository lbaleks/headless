import { NextResponse } from "next/server";

function pickBase(){
  const c = (process.env.NEXT_PUBLIC_GATEWAY_BASE || process.env.MAGENTO_BASE || "").trim();
  if (c.startsWith("http")) return c.replace(/\/$/, "");
  return "https://m2-dev.litebrygg.no";
}
const GW_BASE = pickBase();
const UPSTREAM = GW_BASE + "/rest/V1/inventory/source-items";

function authHeaders(){
  const h: Record<string,string> = { "Content-Type":"application/json" };
  const token = process.env.M2_TOKEN || process.env.MAGENTO_TOKEN || "";
  const basic = process.env.M2_BASIC || "";
  if (token) h["Authorization"] = `Bearer ${token}`;
  else if (basic) h["Authorization"] = `Basic ${basic}`;
  return h;
}

type StockBody = { sku:string; qty:number; sourceCode?:string };

function buildPayload(b: StockBody){
  const source_code = b.sourceCode || "default";
  const status = b.qty > 0 ? 1 : 0; // MSI krever numerisk status
  return { sourceItems: [{ source_code, sku: b.sku, quantity: b.qty, status }] };
}

export async function GET(){
  const auth = authHeaders()["Authorization"] ? (authHeaders()["Authorization"]!.startsWith("Bearer") ? "bearer" : "basic") : "off";
  return NextResponse.json({ ok:true, base: GW_BASE, upstream: UPSTREAM, auth });
}

export async function POST(req: Request){
  try{
    const b = await req.json().catch(()=> ({}));
    const sku = b?.sku, qty = b?.qty, sourceCode = b?.sourceCode;
    if(!sku || typeof qty !== "number"){
      return NextResponse.json({ ok:false, error:"sku_and_qty_required" }, { status:400 });
    }
    const payload = buildPayload({ sku, qty, sourceCode });
    const r = await fetch(UPSTREAM, {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify(payload)
    });
    const text = await r.text();
    let json: any = null; try { json = JSON.parse(text); } catch {}
    if (!r.ok) {
      return NextResponse.json(
        { ok:false, status: r.status, upstream: UPSTREAM, payload, raw: (json ?? text) || null },
        { status: r.status || 502 }
      );
    }
    return NextResponse.json({ ok:true, upstream: UPSTREAM, payload, data: json ?? text });
  } catch(e:any){
    return NextResponse.json({ ok:false, error: e?.message || "stock_proxy_error" }, { status:500 });
  }
}
