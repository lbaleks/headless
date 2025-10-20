import { NextResponse } from "next/server";

export async function GET() {
  // TODO: Knytt mot faktisk PIM/ERP. Nå: demo-data.
  const items = [
    { sku: "TEST-BLUE-EXTRA", name: "Test produkt", price: 222, stock: 13, sales7d: 5 },
    { sku: "A", name: "Alpha",  price: 249, stock: 2,  sales7d: 8 },
    { sku: "B", name: "Beta",   price: 199, stock: 12, sales7d: 1 },
    { sku: "C", name: "Gamma",  price: 159, stock: 4,  sales7d: 5 },
  ];
  return NextResponse.json({ ok:true, items, total: items.length });
}
