export const runtime = 'nodejs';
import { NextResponse } from "next/server";

type Item = { sku:string; price:number; stock:number; sales7d:number; margin?:number };
type Body = { items: Item[] };

export async function POST(req: Request) {
  try {
    const b = (await req.json()) as Body;
    const items = Array.isArray(b?.items) ? b.items : [];
    const scored = items.map((it) => {
      const margin = typeof it.margin === "number" ? it.margin : 20;
      const score  = (it.sales7d * 3) + (margin * 1.5) - Math.max(0, it.stock - 5);
      return { ...it, score: Math.round(score * 10) / 10 };
    }).sort((a,b)=>b.score-a.score);
    return NextResponse.json({ ok: true, count: scored.length, items: scored.slice(0,10) });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "bad_request" }, { status:400 });
  }
}

export async function GET() {
  return NextResponse.json({ ok:true, info:"POST { items:[{sku,price,stock,sales7d,margin?}] }" });
}
