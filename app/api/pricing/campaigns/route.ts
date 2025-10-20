
import { NextResponse } from 'next/server'
import { readFile, writeFile } from 'node:fs/promises'
const F=process.cwd()+'/data/pricing.json'
async function load(){ try{ return JSON.parse(await readFile(F,'utf8')) }catch{ return {campaigns:[],priceLists:[]} } }
export async function GET(){ const j=await load(); return NextResponse.json({campaigns:j.campaigns||[]}) }
export async function POST(req:Request){ const b=await req.json().catch(()=>null); const j=await load(); j.campaigns=j.campaigns||[]; j.campaigns.push({...b,id:'camp'+Date.now()}); await writeFile(F,JSON.stringify(j,null,2)); return NextResponse.json({ok:true}) }
