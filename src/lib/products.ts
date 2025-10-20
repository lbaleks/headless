// src/lib/products.ts
import { magentoGet } from './magento';

type MagentoProduct = {
  id: number;
  sku: string;
  name: string;
  price?: number;
  type_id?: string;
  extension_attributes?: {
    stock_item?: { qty?: number; is_in_stock?: boolean };
  };
};

type MagentoSearchResult<T> = {
  items: T[];
  total_count: number;
};

export async function listProducts(page = 1, size = 50, query?: string) {
  const qs: Record<string, string | number> = {
    'searchCriteria[currentPage]': page,
    'searchCriteria[pageSize]': size,
  };

  if (query && query.trim()) {
    qs['searchCriteria[filterGroups][0][filters][0][field]'] = 'name';
    qs['searchCriteria[filterGroups][0][filters][0][value]'] = `%${query}%`;
    qs['searchCriteria[filterGroups][0][filters][0][conditionType]'] = 'like';

    qs['searchCriteria[filterGroups][1][filters][0][field]'] = 'sku';
    qs['searchCriteria[filterGroups][1][filters][0][value]'] = `%${query}%`;
    qs['searchCriteria[filterGroups][1][filters][0][conditionType]'] = 'like';
  }

  const data = await magentoGet<MagentoSearchResult<MagentoProduct>>('/products', qs);

  const rows = data.items.map(p => ({
    id: p.id,
    sku: p.sku,
    name: p.name,
    price: p.price ?? null,
    stock: p.extension_attributes?.stock_item?.qty ?? null,
    inStock: p.extension_attributes?.stock_item?.is_in_stock ?? null,
  }));

  return { rows, total: data.total_count };
}
