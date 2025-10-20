import { NextResponse } from "next/server";
type Item = { sku:string; name?:string; price?:number; stock?:number; sales7d?:number; margin?:number };
function scoreItem(it: Item){
  const price   = typeof it.price  === "number" ? it.price  : 0;
  const stock   = typeof it.stock  === "number" ? it.stock  : 0;
  const sales7d = typeof it.sales7d=== "number" ? it.sales7d: 0;
  const margin  = typeof it.margin === "number" ? it.margin : 0;
  const score = sales7d*2 + margin*1.2 - Math.max(0, 5 - stock)*1.5;
  const action:string[] = [];
  if (sales7d > 5 && stock < 5) action.push("restock");
  if (margin > 30 && sales7d > 3) action.push("raise_price");
  if (sales7d <= 1 && stock > 10) action.push("promote");
  return { ...it, score: Math.round(score*10)/10, action };
}
export async function POST(req: Request){
  try{
    const b = await req.json().catch(()=>({} as any));
    const items: Item[] = Array.isArray((b as any)?.items) ? (b as any).items : [];
    const scored = items.map(scoreItem).sort((a,b)=> (b.score||0)-(a.score||0));
    return NextResponse.json({ ok:true, count: scored.length, items: scored });
  }catch(e:any){
    return NextResponse.json({ ok:false, error: e?.message||"reco_error" }, { status:500 });
  }
}
export async function GET(){
  return NextResponse.json({ ok:true, info:"POST { items:[{sku, price?, stock?, sales7d?, margin?}] } -> ranked recommendations" });
}
