export const runtime = 'nodejs';
import { NextResponse } from 'next/server'
import { readFile } from 'node:fs/promises'
const F=process.cwd()+'/data/pricing.json'
export async function GET(){ try{ const j=JSON.parse(await readFile(F,'utf8')); return NextResponse.json({priceLists:j.priceLists||[]}) }catch{ return NextResponse.json({priceLists:[]}) } }
