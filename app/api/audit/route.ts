import { NextResponse } from 'next/server'
const logs=[{id:1,ts:new Date().toISOString(),msg:'Server started'}]
export async function GET(){ return NextResponse.json({logs}) }
export async function POST(req:Request){ const body=await req.json(); logs.unshift({id:Date.now(),ts:new Date().toISOString(),msg:body.msg}); if(logs.length>100) logs.pop(); return NextResponse.json({ok:true}) }
