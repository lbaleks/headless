
import { NextResponse } from 'next/server'
export async function GET(req:Request){
  const { searchParams } = new URL(req.url)
  const provider = searchParams.get('provider') || 'unknown'
  // Mocks: Tripletex er disabled til vi har demo-konto
  const ok = provider==='tripletex' ? false : true
  return NextResponse.json({ provider, ok, ts: new Date().toISOString(), latencyMs: Math.floor(Math.random()*120)+30 })
}
