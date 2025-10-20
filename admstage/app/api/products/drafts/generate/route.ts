import { NextResponse } from "next/server";

export async function POST(req: Request) {
  // Les hele body først
  const body = await req.json().catch(() => ({} as any));
  const prompt = body?.prompt?.toString?.() ?? "";
  const title = (prompt || "Nytt produkt").slice(0, 80);

  const draft = {
    id: "draft_" + Date.now(),
    title,
    subtitle: "Litebrygg AS",
    description: `Auto-generert forslag basert på: "${title}". Rediger før publisering.`,
    attributes: [
      { key: "brand", value: "Litebrygg" },
      { key: "origin", value: "NO" },
    ],
    images: [] as string[],
    status: "draft" as const,
  };

  // Valgfritt: kall lokal stock-endepunkt om client sendte med stock
  if (typeof body?.stock === "number") {
    try {
      await fetch("http://localhost:3000/api/ops/stock", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sku: body?.sku || body?.name || draft.id,
          qty: body.stock,
        }),
      });
    } catch {
      // ignorér best effort
    }
  }

  return NextResponse.json({ ok: true, draft }, { status: 200 });
}
