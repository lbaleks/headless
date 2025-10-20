'use client';
import * as React from 'react';
import type { ProductLike, VariantLike } from '@/types/product';
import { effectiveVariantPrice, applyOptionsPriceDelta } from '@/utils/inventory';

export default function PricePreview({
  product,
  variant,
  selectedOptions
}: {
  product: ProductLike;
  variant?: VariantLike | null;
  selectedOptions?: Record<string, any>;
}) {
  const base = variant ? effectiveVariantPrice(product, variant) : Number(product.price||0);
  const withOpts = applyOptionsPriceDelta(base, selectedOptions||{}, product.options||[]);
  return (
    <div className="text-sm text-neutral-700">
      <div>Base price: {base.toFixed(2)} {product.currency||'NOK'}</div>
      <div>With options: <b>{withOpts.toFixed(2)} {product.currency||'NOK'}</b></div>
    </div>
  );
}
