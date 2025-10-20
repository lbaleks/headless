/* eslint-disable '@typescript-eslint/no-unused-expressions' */
import { NextResponse } from "next/server"
import Papa from "papaparse"
import fs from "fs"
import path from "path"

export async function POST(req: Request) {
  try {
    const url = new URL(req.url)
    const dry = url.searchParams.get("dry") === "1"
    const text = await req.text()
    const parsed = Papa.parse(text.trim(), { header: true })
    const records = parsed.data.filter((x:any) => x.sku)

    const file = path.join(process.cwd(), "var/products.dev.json")
    const existing = fs.existsSync(file)
      ? JSON.parse(fs.readFileSync(file, "utf8"))
      : { items: [] }

    let updated = 0, created = 0, unchanged = 0
    for (const row of records) {
      const idx = existing.items.findIndex((x:any)=>x.sku===row.sku)
      if (idx>=0) {
        const diff = Object.entries(row).some(([k,v])=>existing.items[idx][k]!=v)
        diff ? updated++ : unchanged++
        if (!dry && diff) existing.items[idx] = { ...existing.items[idx], ...row }
      } else {
        created++
        if (!dry) existing.items.push(row)
      }
    }
    if (!dry) fs.writeFileSync(file, JSON.stringify(existing,null,2))
    return NextResponse.json({ ok:true, dry, created, updated, unchanged, total:records.length })
  } catch (err:any) {
    return NextResponse.json({ ok:false, error:String(err?.message||err) }, { status:500 })
  }
}
