#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
FP_ADMIN_PAGE="src/components/AdminPage.tsx"
FP_PRODUCT="app/admin/products/[id]/page.tsx"

echo "==> 1) Sørger for AdminPage med både default og named export: $FP_ADMIN_PAGE"
mkdir -p "$(dirname "$FP_ADMIN_PAGE")"
cat > "$FP_ADMIN_PAGE" <<'TSX'
'use client';
import React from 'react';

type Props = { title: string; children: React.ReactNode };

export function AdminPage({ title, children }: Props) {
  return (
    <div className="admin-page">
      <div className="admin-header"><h1>{title}</h1></div>
      <div className="admin-body">{children}</div>
    </div>
  );
}
export default AdminPage;
TSX

echo "==> 2) Patcher product-siden: $FP_PRODUCT"
if [[ ! -f "$FP_PRODUCT" ]]; then
  echo "    ⚠ Fant ikke $FP_PRODUCT. Hopper over patch for den filen."
else
  cp "$FP_PRODUCT" "$FP_PRODUCT.bak.$(date +%s)"

  # a) Normaliser AdminPage-import (named -> default) og sti -> '@/src/components/AdminPage'
  #    variasjoner håndteres i to pass
  sed -i '' -E "s#import[[:space:]]*\{[[:space:]]*AdminPage[[:space:]]*\}[[:space:]]*from[[:space:]]*'@/[^']*AdminPage';#import AdminPage from '@/src/components/AdminPage';#g" "$FP_PRODUCT" || true
  sed -i '' -E "s#import[[:space:]]+AdminPage[[:space:]]+from[[:space:]]+'@/components/AdminPage';#import AdminPage from '@/src/components/AdminPage';#g" "$FP_PRODUCT" || true
  sed -i '' -E "s#import[[:space:]]+AdminPage[[:space:]]+from[[:space:]]+'@/src/components/AdminPage';#import AdminPage from '@/src/components/AdminPage';#g" "$FP_PRODUCT" || true

  # b) Normaliser komponent-stier for BulkVariantEdit og VariantImages til '@/src/components/...'
  sed -i '' -E "s#'@/components/BulkVariantEdit'#'@/src/components/BulkVariantEdit'#g" "$FP_PRODUCT" || true
  sed -i '' -E "s#'@/components/VariantImages'#'@/src/components/VariantImages'#g" "$FP_PRODUCT" || true

  # c) Next 15: params er Promise – oppdater type og unwrapping
  #    - type: { params: { id: string } }  -> { params: Promise<{ id: string }> }
  sed -i '' -E "s#(\{[[:space:]]*params[[:space:]]*\}:[[:space:]]*\{[[:space:]]*params:[[:space:]]*)\{[[:space:]]*id:[[:space:]]*string[[:space:]]*\}[[:space:]]*\}#\1Promise<{ id: string }>#g" "$FP_PRODUCT"

  #    - const { id } = params; -> const { id } = React.use(params);
  sed -i '' -E "s#const[[:space:]]*\{[[:space:]]*id[[:space:]]*\}[[:space:]]*=[[:space:]]*params;#const { id } = React.use(params);#g" "$FP_PRODUCT"

  echo "    ✓ Patching av product-siden fullført (backup laget som .bak)"
fi

echo "==> Ferdig!"
echo "Tips: restart dev-server om nødvendig. Kjør deretter /admin/products/[id] og /admin/dashboard."