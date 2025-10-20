// src/lib/fsdb.ts
import { promises as fs } from 'fs'
import path from 'path'
const dbPath = path.join(process.cwd(), 'data', 'pricing-rules.json')
export type PricingRule = {
  id: string; name: string; type: 'margin'|'discount'|'bogo'|string;
  value: number; enabled: boolean; scope?: 'global'|'category'|'sku'|string
}
export async function readDb() {
  try { const raw = await fs.readFile(dbPath,'utf8'); return JSON.parse(raw) as { rules: PricingRule[] } }
  catch (e:any) { if (e.code==='ENOENT') return { rules: [] as PricingRule[] }; throw e }
}
export async function writeDb(data:{ rules: PricingRule[] }) {
  await fs.mkdir(path.dirname(dbPath), { recursive: true })
  await fs.writeFile(dbPath, JSON.stringify(data, null, 2), 'utf8')
}
