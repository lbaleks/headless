import { NextResponse } from "next/server";

function pickBase(){
  const c = (process.env.NEXT_PUBLIC_GATEWAY_BASE || process.env.MAGENTO_BASE || "").trim();
  if (c.startsWith("http")) return c.replace(/\/$/, "");
  return "https://m2-dev.litebrygg.no";
}
const BASE = pickBase();

function authHeaders(){
  const h: Record<string,string> = { "Content-Type":"application/json" };
  const token = process.env.M2_TOKEN || process.env.MAGENTO_TOKEN || "";
  const basic = process.env.M2_BASIC || "";
  if (token) h["Authorization"] = `Bearer ${token}`;
  else if (basic) h["Authorization"] = `Basic ${basic}`;
  return h;
}

// Accepts: { sku, name?, price?, description?, status?, visibility? }
export async function GET(){
  return NextResponse.json({ ok:true, info: "POST { sku, name?, price?, description?, status?, visibility? }" });
}

export async function POST(req: Request){
  try{
    const b = await req.json().catch(()=> ({}));
    const sku = b?.sku as string;
    if(!sku) return NextResponse.json({ ok:false, error:"missing_sku" }, { status:400 });

    const productPayload: any = { product: { sku } };
    if (typeof b.name === "string")       productPayload.product.name = b.name;
    if (typeof b.price === "number")      productPayload.product.price = b.price;
    if (typeof b.status === "number")     productPayload.product.status = b.status;
    if (typeof b.visibility === "number") productPayload.product.visibility = b.visibility;
    if (typeof b.description === "string"){
      productPayload.product.custom_attributes = [
        { attribute_code: "description", value: b.description }
      ];
    }

    const url = `${BASE}/rest/V1/products/${encodeURIComponent(sku)}`;
    const r   = await fetch(url, { method:"PUT", headers: authHeaders(), body: JSON.stringify(productPayload) });
    const txt = await r.text();
    let json: any = null; try { json = JSON.parse(txt); } catch {}
    if (!r.ok){
      return NextResponse.json(
        { ok:false, status:r.status, upstream:url, payload:productPayload, raw: (json ?? txt) || null },
        { status: r.status || 502 }
      );
    }
    return NextResponse.json({ ok:true, upstream:url, payload:productPayload, data: json ?? txt });
  } catch(e:any){
    return NextResponse.json({ ok:false, error: e?.message || "product_proxy_error" }, { status:500 });
  }
}
