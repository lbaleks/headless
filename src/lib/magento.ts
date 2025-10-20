import ky from "ky";

const baseURL = process.env.MAGENTO_BASE_URL || "";
const token   = process.env.MAGENTO_TOKEN   || "";

export const mApi = ky.create({
  prefixUrl: baseURL.replace(/\/+$/,""),
  headers: token ? { Authorization: `Bearer ${token}` } : {},
  timeout: 20000,
  hooks: {
    beforeRequest: [
      req => {
        // JSON default
        req.headers.set("Content-Type","application/json");
      }
    ]
  }
});

// --- Typer (enkle) ---
export type MProduct = {
  id: number;
  sku: string;
  name: string;
  price?: number;
  custom_attributes?: { attribute_code: string; value: string }[];
  media_gallery_entries?: { file: string; label?: string }[];
  extension_attributes?: any;
};

export function imgFrom(product: MProduct): string | null {
  const file = product.media_gallery_entries?.[0]?.file;
  if (!file) return null;
  const clean = file.startsWith("/") ? file.slice(1) : file;
  // Typisk Magento: /media/catalog/product/...
  return `${(process.env.MAGENTO_BASE_URL||"")
    .replace(/\/rest\/V1$/,"")
    .replace(/\/+$/,"")}/media/${clean}`;
}

// --- REST-hjelpere ---
export async function searchProducts(opts: { q?: string; page?: number; pageSize?: number; categoryId?: number } = {}) {
  const page = Math.max(1, Number(opts.page||1));
  const pageSize = Math.min(60, Math.max(1, Number(opts.pageSize||24)));

  const searchCriteria = new URLSearchParams();
  let idx = 0;
  if (opts.q) {
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][field]`, "name");
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][value]`, `%${opts.q}%`);
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][condition_type]`, "like");
    idx++;
  }
  if (opts.categoryId) {
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][field]`, "category_id");
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][value]`, String(opts.categoryId));
    searchCriteria.set(`searchCriteria[filter_groups][${idx}][filters][0][condition_type]`, "eq");
    idx++;
  }
  searchCriteria.set("searchCriteria[currentPage]", String(page));
  searchCriteria.set("searchCriteria[pageSize]", String(pageSize));

  const u = `products?${searchCriteria.toString()}`;
  const res = await mApi.get(u).json<{ items: MProduct[], total_count: number }>();
  return res;
}

export async function getProductBySku(sku: string) {
  const res = await mApi.get(`products/${encodeURIComponent(sku)}`).json<MProduct>();
  return res;
}
