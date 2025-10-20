const fs = require('fs');
const p = 'app/api/products/[id]/route.ts';
if(!fs.existsSync(p)){ console.log('ℹ️ Skipped, not found:', p); process.exit(0); }
let s = fs.readFileSync(p,'utf8');
if(!s.includes("@/src/utils/sku")){
  s = s.replace(/(^|\n)export async function PUT\(/, "\nimport { genSku, randomSku } from '@/src/utils/sku'\n$&");
}
if(!/if\s*\(\s*!\s*(body\.sku|next\.sku)/.test(s)){
  s = s.replace(/(const\s+body\s*=\s*await\s*_?req\.json\(\)[\s\S]+?{[\s\S]*?)(\n\s*\/\*|\n\s*const|\n\s*if|\n\s*let|\n\s*\/\/|$)/, (m, head, tail)=>{
    const add = `
  // Auto-assign SKU if missing
  if(!body.sku || !String(body.sku).trim()){
    const stem = (body.name||'').toString();
    body.sku = genSku(stem||undefined,'SKU');
  }`;
    return head + add + tail;
  });
}
fs.writeFileSync(p,s);
console.log('✅ Patched product route for auto-SKU:', p);
