export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { writeFile, mkdir } from 'fs/promises'
import { join, basename } from 'path'


export async function POST(req: Request) {
  try {
    const filename = (req.headers.get('x-filename') || 'file.bin').replace(/[^\w.-]+/g,'_')
    const buf = Buffer.from(await req.arrayBuffer())
    const dir = join(process.cwd(), 'public', 'uploads')
    await mkdir(dir, { recursive: true })
    const stamped = `${Date.now()}-${basename(filename)}`
    const full = join(dir, stamped)
    await writeFile(full, buf)
    return NextResponse.json({ ok: true, url: `/uploads/${stamped}` })
  } catch (e:any) {
    console.error('Upload error', e)
    return NextResponse.json({ ok:false, error: String(e?.message||e) }, { status: 500 })
  }
}
