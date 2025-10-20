import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { dirname } from 'node:path'
const PATH = process.cwd() + '/data/pricing.json'

export type Rule = { type:string; label:string; price:number; currency?:string }

export async function readPricing(): Promise<Rule[]> {
  try{
    const raw = await readFile(PATH,'utf8')
    const j = raw? JSON.parse(raw): {}
    return Array.isArray(j.rules) ? j.rules : []
  }catch{ return [] }
}

export async function writePricing(rules: Rule[]) {
  await mkdir(dirname(PATH),{recursive:true})
  const clean = (Array.isArray(rules)?rules:[]).map(r=>({
    type: String(r?.type||'base'),
    label: String(r?.label||''),
    price: Number(r?.price||0),
    currency: String(r?.currency||'NOK')
  }))
  await writeFile(PATH, JSON.stringify({ rules: clean, updatedAt: new Date().toISOString() }, null, 2), 'utf8')
}
