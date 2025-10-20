import useSWR from "swr";
import { searchProducts } from "@/lib/magento";

export function usePaginatedProducts(params: { q?: string; page?: number; pageSize?: number }) {
  const key = ["products", params.q||"", params.page||1, params.pageSize||24] as const;
  return useSWR(key, () => searchProducts(params));
}
