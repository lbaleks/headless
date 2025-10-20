#!/usr/bin/env bash
set -euo pipefail
f=routes-variants.js
cp "$f" "$f.bak.$(date +%s)"

node - <<'JS'
const fs=require('fs');const f='routes-variants.js';
let s=fs.readFileSync(f,'utf8');

// gjør oppførsel eksplisitt: hvis VARIANT_ALLOW_STOCK_FORBIDDEN=1 og vi får 401/403 på MSI ELLER legacy,
// så hopper vi over stock i stedet for å kaste.
s=s.replace(
/async function upsertStock\([\s\S]*?\}\n\s*\};/m,
m=>{
  if(m.includes('VARIANT_ALLOW_STOCK_FORBIDDEN_PATCH')) return m; // allerede patchet
  return m.replace(
    /{\s*\/\/ start upsertStock/,
    `{
  // VARIANT_ALLOW_STOCK_FORBIDDEN_PATCH
  // start upsertStock`
  ).replace(
    /const r = await mfetch\([^]+?\);\s*if \(r\.ok\) return true;/m,
    `$&
  if (String(process.env.VARIANT_ALLOW_STOCK_FORBIDDEN)==='1' && (r.status===401||r.status===403)) {
    // hopp over stock helt – token har ikke ACL ennå
    return false;
  }`
  ).replace(
    /const r2 = await mfetch\([^]+?\);\s*if \(r2\.ok\) return true;/m,
    `$&
  if (String(process.env.VARIANT_ALLOW_STOCK_FORBIDDEN)==='1' && (r2.status===401||r2.status===403)) {
    return false;
  }`
  ).replace(
    /const legacy = await mfetch\([^]+?\);\s*if \(legacy\.ok\) return true;/m,
    `$&
  if (String(process.env.VARIANT_ALLOW_STOCK_FORBIDDEN)==='1' && (legacy.status===401||legacy.status===403)) {
    return false;
  }`
  );
});

fs.writeFileSync(f,s);
console.log('✅ Patchet: hoppe over stock på 401/403 (MSI og legacy).');
JS

chmod +x skip-stock-on-401.sh
./skip-stock-on-401.sh

# sørg for flagget er slått på
grep -q '^VARIANT_ALLOW_STOCK_FORBIDDEN=' .env || echo 'VARIANT_ALLOW_STOCK_FORBIDDEN=1' >> .env

# restart
pkill -f "/Users/litebrygg/Documents/M2/m2-gateway/server.js" 2>/dev/null || true
node /Users/litebrygg/Documents/M2/m2-gateway/server.js
