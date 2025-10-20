import { NextResponse } from "next/server";
import fs from "fs";
import path from "path";

const storePath = path.join(process.cwd(), "tmp_drafts.json");

export async function GET() {
  try {
    const exists = fs.existsSync(storePath);
    const items = exists ? JSON.parse(fs.readFileSync(storePath, "utf8")) : [];
    return NextResponse.json({ ok: true, items });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "read_error" }, { status: 500 });
  }
}
