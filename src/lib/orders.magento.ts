// src/lib/orders.magento.ts
import { magentoGet } from './magento';

type MagentoOrder = {
  entity_id: number;
  increment_id?: string;
  customer_email?: string;
  customer_firstname?: string;
  customer_lastname?: string;
  grand_total?: number;
  created_at?: string;
  status?: string;
  items?: Array<{ sku: string; name: string; qty_ordered: number }>;
};

type MagentoSearchResult<T> = {
  items: T[];
  total_count: number;
};

export async function listOrders(page = 1, size = 50, q?: string) {
  const qs: Record<string, string | number> = {
    'searchCriteria[currentPage]': page,
    'searchCriteria[pageSize]': size,
    'searchCriteria[sortOrders][0][field]': 'created_at',
    'searchCriteria[sortOrders][0][direction]': 'DESC',
  };

  if (q && q.trim()) {
    qs['searchCriteria[filterGroups][0][filters][0][field]'] = 'increment_id';
    qs['searchCriteria[filterGroups][0][filters][0][value]'] = `%${q}%`;
    qs['searchCriteria[filterGroups][0][filters][0][conditionType]'] = 'like';

    qs['searchCriteria[filterGroups][1][filters][0][field]'] = 'customer_email';
    qs['searchCriteria[filterGroups][1][filters][0][value]'] = `%${q}%`;
    qs['searchCriteria[filterGroups][1][filters][0][conditionType]'] = 'like';
  }

  const data = await magentoGet<MagentoSearchResult<MagentoOrder>>('/orders', qs);

  const rows = data.items.map(o => ({
    id: o.entity_id,
    orderNo: o.increment_id ?? String(o.entity_id),
    customer: [o.customer_firstname, o.customer_lastname].filter(Boolean).join(' ') || o.customer_email || 'N/A',
    email: o.customer_email ?? null,
    total: o.grand_total ?? null,
    status: o.status ?? null,
    createdAt: o.created_at ?? null,
    lines: (o.items || []).map(i => ({
      sku: i.sku,
      name: i.name,
      qty: i.qty_ordered,
    })),
  }));

  return { rows, total: data.total_count };
}
