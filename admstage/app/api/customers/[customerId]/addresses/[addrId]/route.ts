import { NextResponse } from "next/server";
import { readJson, writeJson } from "@/lib/fsdb";

type Addr = {
  id: string; label?: string; name: string; phone?: string;
  line1: string; line2?: string; zip: string; city: string; country: string;
  isDefault?: boolean;
};

export async function PUT(req: Request, { params }: { params: { customerId: string; addrId: string } }) {
  const key = "addr_" + params.customerId;
  const list = readJson<Addr[]>(key, []);
  const i = list.findIndex(a => a.id === params.addrId);
  if (i < 0) return NextResponse.json({ ok: false, error: "not_found" }, { status: 404 });
  const body = await req.json();
  if (body.isDefault) list.forEach(a => a.isDefault = false);
  list[i] = { ...list[i], ...body, id: params.addrId };
  writeJson(key, list);
  return NextResponse.json({ ok: true, item: list[i] });
}

export async function DELETE(_: Request, { params }: { params: { customerId: string; addrId: string } }) {
  const key = "addr_" + params.customerId;
  const list = readJson<Addr[]>(key, []);
  const next = list.filter(a => a.id !== params.addrId);
  writeJson(key, next);
  return NextResponse.json({ ok: true });
}
