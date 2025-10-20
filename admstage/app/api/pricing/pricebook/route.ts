import { NextResponse } from "next/server";
import fs from "fs";
import path from "path";

const DATA_FILE = path.join(process.cwd(), "data", "pricebooks.json");

function load(){
  try{ return JSON.parse(fs.readFileSync(DATA_FILE,"utf8")); }
  catch{ return { default: {} }; }
}
function save(db: any){
  fs.writeFileSync(DATA_FILE, JSON.stringify(db, null, 2));
}

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

/** GET:  /api/pricing/pricebook?book=default
 *  POST: { book?:string, sku:string, price:number, name?, description?, status?, visibility? }
 *        - Lagrer i pricebook og forsøker å PUTe produktet i Magento.
 */
export async function GET(req: Request){
  const u = new URL(req.url);
  const book = (u.searchParams.get("book") || "default").trim();
  const db = load();
  const cur = db[book] || {};
  const auth = authHeaders()["Authorization"] ? (authHeaders()["Authorization"]!.startsWith("Bearer") ? "bearer" : "basic") : "off";
  return NextResponse.json({ ok:true, book, count: Object.keys(cur).length, base: BASE, auth, entries: cur });
}

export async function POST(req: Request){
  try{
    const b = await req.json().catch(()=> ({}));
    const book = (b?.book || "default").trim();
    const sku  = b?.sku as string;
    const price= b?.price;

    if (!sku || typeof price !== "number"){
      return NextResponse.json({ ok:false, error:"missing_sku_or_price" }, { status:400 });
    }

    const db = load();
    db[book] = db[book] || {};
    db[book][sku] = { price, ts: Date.now() };
    save(db);

    // Proxy til Magento (samme som /api/ops/product)
    const productPayload: any = { product: { sku, price } };
    if (typeof b.name === "string")       productPayload.product.name = b.name;
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
      // Pris ble lagret lokalt, men Magento feilet -> returner 207-like info
      return NextResponse.json(
        { ok:false, saved:true, status:r.status, upstream:url, pricebook: { book, sku, price }, raw: (json ?? txt) || null },
        { status: 207 }
      );
    }
    return NextResponse.json({ ok:true, saved:true, upstream:url, pricebook: { book, sku, price }, data: json ?? txt });
  } catch(e:any){
    return NextResponse.json({ ok:false, error: e?.message || "pricebook_error" }, { status:500 });
  }
}
