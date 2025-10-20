import { NextResponse } from "next/server";
import fs from "fs";
import path from "path";

export async function POST(req: Request) {
  try {
    const form = await req.formData();
    const f = form.get("file") as File | null;
    if (!f) return NextResponse.json({ ok:false, error:"file_required" }, { status:400 });
    const buf = Buffer.from(await f.arrayBuffer());
    const dir = path.join(process.cwd(), "public/brand");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "logo.png"), buf);
    return NextResponse.json({ ok:true, url:"/brand/logo.png" });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error:e?.message || "unknown_error" }, { status:500 });
  }
}
