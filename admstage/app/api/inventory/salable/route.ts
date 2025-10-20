import { NextResponse } from "next/server";

function pickBase(){
  const c = (process.env.NEXT_PUBLIC_GATEWAY_BASE || process.env.MAGENTO_BASE || "").trim();
  if (c.startsWith("http")) return c.replace(/\/$/, "");
  return "https://m2-dev.litebrygg.no";
}
const BASE = pickBase();

function authHeaders(){
  const h: Record<string,string> = {};
  const token = process.env.M2_TOKEN || process.env.MAGENTO_TOKEN || "";
  const basic = process.env.M2_BASIC || "";
  if (token) h["Authorization"] = `Bearer ${token}`;
  else if (basic) h["Authorization"] = `Basic ${basic}`;
  return h;
}

/** GET /api/inventory/salable?sku=AAA[,BBB] 
 *  Returnerer salgbart lager per sku via MSI-endepunktet.
 */
export async function GET(req: Request){
  try{
    const u = new URL(req.url);
    const skuParam = (u.searchParams.get("sku")||"").trim();
    if (!skuParam) return NextResponse.json({ ok:false, error:"missing_sku" }, { status:400 });

    const skus = Array.from(new Set(skuParam.split(",").map(s => s.trim()).filter(Boolean)));
    // 1 = default stock id i Magento MSI
    const stockId = 1;

    const out: Record<string, number | null> = {};
    for (const sku of skus){
      const url = `${BASE}/rest/V1/inventory/get-product-salable-quantity/${encodeURIComponent(sku)}/${stockId}`;
      const r   = await fetch(url, { headers: authHeaders() });
      const txt = await r.text();
      if (!r.ok) {
        // returner feilmelding per sku, men ikke feile hele kall
        out[sku] = null;
        continue;
      }
      // dette endepunktet returnerer tall som tekst (ex: 13)
      const n = Number(txt);
      out[sku] = Number.isFinite(n) ? n : null;
    }
    const auth = authHeaders()["Authorization"] ? (authHeaders()["Authorization"]!.startsWith("Bearer") ? "bearer" : "basic") : "off";
    return NextResponse.json({ ok:true, base:BASE, auth, salable: out });
  } catch(e:any){
    return NextResponse.json({ ok:false, error: e?.message || "salable_error" }, { status:500 });
  }
}
