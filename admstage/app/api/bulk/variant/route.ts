import { NextResponse } from "next/server";

function gw() {
  return process.env.NEXT_PUBLIC_GATEWAY_BASE || process.env.NEXT_PUBLIC_GATEWAY || "http://localhost:3044";
}

async function jpost(url: string, body: any) {
  const r = await fetch(url, { method: "POST", headers: { "Content-Type":"application/json" }, body: JSON.stringify(body) });
  let j:any=null; try { j = await r.json(); } catch { j = { ok:false, error:"non_json_response" }; }
  return { status: r.status, json: j };
}

export async function POST(req: Request) {
  try {
    const data = await req.json();
    // forventede felter
    const parentSku = String(data.parentSku||"").trim();
    const childSku  = String(data.childSku||"").trim();
    const attrCode  = String(data.attrCode||"cfg_color").trim();
    const valueIndex = Number(data.valueIndex ?? 0);
    const price = data.price!=null ? Number(data.price) : undefined;
    const stockQty = data.stock!=null ? Number(data.stock) : undefined;
    const label = data.label!=null ? String(data.label) : undefined;
    const websiteId = Number(data.websiteId ?? 1);

    if(!parentSku || !childSku) {
      return NextResponse.json({ ok:false, error:"parentSku/childSku required" }, { status:400 });
    }

    const base = gw();
    const steps: any[] = [];

    // (a) heal (inkl. lager hvis satt)
    if (stockQty!=null) {
      const healBody:any = {
        parentSku, sku: childSku,
        cfgAttr: attrCode, cfgValue: valueIndex,
        label: label ?? String(valueIndex),
        websiteId,
        stock: { source_code:"default", quantity: stockQty, status: 1 }
      };
      steps.push({ step:"heal", ...(await jpost(`${base}/ops/variant/heal`, healBody)) });
    } else {
      // heal uten lager
      const healBody:any = {
        parentSku, sku: childSku,
        cfgAttr: attrCode, cfgValue: valueIndex,
        label: label ?? String(valueIndex), websiteId
      };
      steps.push({ step:"heal", ...(await jpost(`${base}/ops/variant/heal`, healBody)) });
    }

    // (b) link configurable
    const linkBody = { parentSku, childSku, attrCode, valueIndex };
    steps.push({ step:"link", ...(await jpost(`${base}/ops/configurable/link`, linkBody)) });

    // (c) price (valgfritt)
    if (price!=null && !Number.isNaN(price)) {
      steps.push({ step:"price", ...(await jpost(`${base}/ops/price/upsert`, { sku: childSku, price })) });
    }

    const ok = steps.every(s => (s.json?.ok ?? true));
    return NextResponse.json({ ok, steps });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "unknown_error" }, { status:500 });
  }
}
