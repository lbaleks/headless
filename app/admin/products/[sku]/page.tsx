import React from "react";
import ProductDetail from "./ProductDetail.client";

export default function Page({ params }: { params: Promise<{ sku: string }> }) {
  const { sku } = React.use(params); // Next 15: params er en Promise i server components
  return <ProductDetail sku={decodeURIComponent(sku)} />;
}
