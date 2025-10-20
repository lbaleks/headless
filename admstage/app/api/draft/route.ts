import { NextResponse } from "next/server";
import fs from "fs"; import path from "path";
const storePath = path.join(process.cwd(), "tmp_drafts.json");
function readAll(){ return fs.existsSync(storePath) ? JSON.parse(fs.readFileSync(storePath,"utf8")) : []; }
function writeAll(all:any[]){ fs.writeFileSync(storePath, JSON.stringify(all,null,2)); }

export async function GET() {
  try { return NextResponse.json({ ok:true, drafts: readAll() }); }
  catch(e:any){ return NextResponse.json({ ok:false, error:e?.message||"read_failed" }, { status:500 }); }
}

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const all = [ { ...body, created: new Date().toISOString(), synced:false }, ...readAll() ].slice(0,25);
    writeAll(all);
    return NextResponse.json({ ok:true, saved: body });
  } catch (e:any) {
    return NextResponse.json({ ok:false, error: e?.message || "invalid_json" }, { status:400 });
  }
}
