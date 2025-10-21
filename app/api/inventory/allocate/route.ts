export const runtime = 'nodejs';
import { NextResponse } from "next/server";

export type Strategy = "FIFO" | "FEFO";
export type Lot = { lotId: string; qty: number; expiry?: string };

function toBaseQty(units: number, multiplier: number) {
  return Math.max(0, Math.round(units * multiplier));
}

function sortLots(strategy: Strategy, lots: Lot[]) {
  const copy = lots.slice();
  if (strategy === "FEFO") {
    copy.sort((a, b) => {
      const ax = a.expiry ?? "9999-12-31";
      const bx = b.expiry ?? "9999-12-31";
      return ax > bx ? 1 : ax < bx ? -1 : 0;
    });
  }
  return copy; // FIFO keeps incoming order
}

type Body = {
  strategy?: Strategy;
  lots?: Lot[];
  baseQty?: number;
  qty?: number;
  multiplier?: number;
};

export async function POST(req: Request) {
  try {
    const b = (await req.json()) as Body;
    const strategy: Strategy = b.strategy ?? "FEFO";
    const lots = Array.isArray(b.lots) ? b.lots.filter(l => l && l.lotId) : [];
    const baseQty = typeof b.baseQty === "number"
      ? Math.max(0, Math.round(b.baseQty))
      : toBaseQty(b.qty ?? 0, b.multiplier ?? 1);

    let need = baseQty;
    const allocations: { lotId: string; take: number }[] = [];
    for (const lot of sortLots(strategy, lots)) {
      if (need <= 0) break;
      const take = Math.min(lot.qty, need);
      if (take > 0) {
        allocations.push({ lotId: lot.lotId, take });
        need -= take;
      }
    }
    const fulfilled = baseQty - need;
    return NextResponse.json({ ok: true, strategy, requested: baseQty, fulfilled, remaining: need, allocations });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "bad_request" }, { status: 400 });
  }
}

export async function GET() {
  return NextResponse.json({
    ok: true,
    info: "POST { strategy?:'FIFO'|'FEFO', lots:[{lotId,qty,expiry?}], baseQty?:number, qty?:number, multiplier?:number }",
  });
}
