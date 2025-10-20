
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { dirname } from 'node:path'
const FILE = process.cwd() + '/data/db.json'
type Db = { products?: any[]; pricingRules?: any[]; customers?: any[] }
export async function readDb(): Promise<Db>{
  try{ const raw=await readFile(FILE,'utf8'); return JSON.parse(raw||'{}') }catch{ return { products:[], pricingRules:[], customers:[] } }
}
export async function writeDb(obj:any){ await mkdir(dirname(FILE),{recursive:true}); await writeFile(FILE, JSON.stringify(obj,null,2)) }
