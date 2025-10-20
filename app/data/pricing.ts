// app/data/pricing.ts
export type Rule =
  | { type:"bulk"; sku:string; minUnits:number; factor:number }
  | { type:"roleDiscount"; role:string; factor:number }
  | { type:"overrideVariant"; sku:string; multiplier:number; price:number };

export const basePrices: Record<string, number> = {
  "FLOUR-001": 9.9,
  "COFFEE-250": 24.0,
};

export const rules: Rule[] = [
  { type:"bulk", sku:"FLOUR-001", minUnits: 10,  factor: 0.97 },
  { type:"bulk", sku:"FLOUR-001", minUnits: 250, factor: 0.95 },
  { type:"roleDiscount", role:"ops", factor: 0.98 },
  { type:"overrideVariant", sku:"FLOUR-001", multiplier: 250, price: 9.9*245 },
];

export function applyPricing(params:{
  sku: string; baseQty: number; variantMultiplier?: number; role?: string;
}){
  const base = basePrices[params.sku] ?? 0;
  if (base<=0) return { unitPrice:0, total:0, notes:["no_base_price"] };

  const notes: string[] = [];
  let unitFactor = 1.0;

  const bulk = rules
    .filter((r:any) => r.type==="bulk" && r.sku===params.sku)
    .sort((a:any,b:any)=>b.minUnits-a.minUnits)
    .find((r:any)=> params.baseQty>=r.minUnits);
  if (bulk){ unitFactor *= (bulk as any).factor; notes.push(); }

  const roleRule = rules.find((r:any)=> r.type==="roleDiscount" && r.role===params.role) as any;
  if (roleRule){ unitFactor *= roleRule.factor; notes.push(); }

  const ov = rules.find((r:any)=> r.type==="overrideVariant" && r.sku===params.sku && r.multiplier===params.variantMultiplier) as any;
  if (ov){
    const total = ov.price;
    const unitPrice = total / (params.variantMultiplier||1);
    notes.push("override_variant");
    return { unitPrice: +unitPrice.toFixed(4), total: +total.toFixed(2), notes };
  }

  const unitPrice = base * unitFactor;
  const total = unitPrice * params.baseQty;
  return { unitPrice: +unitPrice.toFixed(4), total: +total.toFixed(2), notes };
}
