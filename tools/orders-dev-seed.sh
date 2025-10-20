#!/usr/bin/env bash
set -euo pipefail
N="${1:-5}"                             # hvor mange ordre du vil legge til
FILE="var/orders.dev.json"
mkdir -p var

# Les eksisterende (array ELLER {items:[...]})
RAW="$(cat "$FILE" 2>/dev/null || echo '[]')"
NODE_SCRIPT=$(cat <<'JS'
const fs=require('fs');
const file=process.argv[1];
const raw=process.argv[2];
let arr;
try{
  const j=JSON.parse(raw);
  arr = Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : []);
}catch{ arr=[]; }

const now=()=>new Date().toISOString();
const mk=(i)=>({
  id:`ORD-${Date.now()}-${i}`,
  increment_id:`ORD-${Date.now()}-${i}`,
  status:'new',
  created_at:now(),
  customer:{ email:`dev+${i}@example.com` },
  lines:[{ sku:'TEST', productId:null, name:'TEST', qty:(i%3)+1, price:199, rowTotal:((i%3)+1)*199, i:0 }],
  notes:'seed',
  total:((i%3)+1)*199,
  source:'local-stub',
});

const n=parseInt(process.argv[3]||'5',10);
for(let i=1;i<=n;i++) arr.unshift(mk(i));
fs.writeFileSync(file, JSON.stringify(arr, null, 2));
console.log(JSON.stringify({ok:true, total:arr.length}));
JS
)
node -e "$NODE_SCRIPT" "$FILE" "$RAW" "$N"