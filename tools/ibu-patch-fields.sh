#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
SKU_RT="$ROOT/app/api/products/[sku]/route.ts"
MRG_RT="$ROOT/app/api/products/merged/route.ts"

# Patch single product route: add storeId=0 and fields for custom_attributes
if [[ -f "$SKU_RT" ]]; then
  node - "$SKU_RT" <<'JS'
const fs = require('fs');
const file = process.argv[2];
let s = fs.readFileSync(file, 'utf8');

// Replace ".../products/${encodeURIComponent(sku)}?..." with canonical query
s = s.replace(
  /(\${v1\(cfg\.baseUrl\)}\/products\/\$\{encodeURIComponent\(sku\)\})(\?[^'"]*)?/,
  (_m, base, qs='') => {
    const u = new URL('http://x'); // dummy origin
    const q = qs.startsWith('?') ? qs.slice(1) : '';
    q.split('&').filter(Boolean).forEach(kv => {
      const [k, ...r] = kv.split('=');
      u.searchParams.set(k, r.join('='));
    });
    u.searchParams.set('storeId', '0');
    u.searchParams.set('fields', 'attribute_set_id,sku,custom_attributes[attribute_code,value]');
    return `${base}?${u.searchParams.toString()}`;
  }
);

fs.writeFileSync(file, s);
console.log('patched [sku]');
JS
fi

# Patch merged route: request custom_attributes in list response and set storeId=0
if [[ -f "$MRG_RT" ]]; then
  node - "$MRG_RT" <<'JS'
const fs = require('fs');
const file = process.argv[2];
let s = fs.readFileSync(file, 'utf8');

s = s.replace(
  /(\${v1\(cfg\.baseUrl\)}\/products\?)([^'"]*)/,
  (_m, prefix, rest) => {
    const u = new URL('http://x');
    rest.split('&').filter(Boolean).forEach(kv => {
      const [k, ...r] = kv.split('=');
      u.searchParams.set(k, r.join('='));
    });
    u.searchParams.set('storeId', '0');
    u.searchParams.set('fields', 'items[sku,custom_attributes[attribute_code,value]],total_count');
    return `${prefix}${u.searchParams.toString()}`;
  }
);

fs.writeFileSync(file, s);
console.log('patched merged');
JS
fi

echo "OK"
