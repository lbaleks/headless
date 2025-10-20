import fs from 'fs'
import path from 'path'

export function auditProductChange(sku:string, before:any, after:any){
  try{
    const dir = path.join(process.cwd(), 'var', 'audit')
    fs.mkdirSync(dir, { recursive:true })
    const line = JSON.stringify({ ts: new Date().toISOString(), sku, before, after }) + '\n'
    fs.appendFileSync(path.join(dir, `products.${sku}.jsonl`), line)
  }catch{/* best effort */}
}
