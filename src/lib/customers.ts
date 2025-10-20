// src/lib/customers.ts
import { magentoGet } from './magento';

type MagentoCustomer = {
  id: number;
  email?: string;
  firstname?: string;
  lastname?: string;
  created_at?: string;
};

type MagentoSearchResult<T> = {
  items: T[];
  total_count: number;
};

export async function listCustomers(page = 1, size = 50, q?: string) {
  const qs: Record<string, string | number> = {
    'searchCriteria[currentPage]': page,
    'searchCriteria[pageSize]': size,
  };

  if (q && q.trim()) {
    qs['searchCriteria[filterGroups][0][filters][0][field]'] = 'email';
    qs['searchCriteria[filterGroups][0][filters][0][value]'] = `%${q}%`;
    qs['searchCriteria[filterGroups][0][filters][0][conditionType]'] = 'like';

    qs['searchCriteria[filterGroups][1][filters][0][field]'] = 'firstname';
    qs['searchCriteria[filterGroups][1][filters][0][value]'] = `%${q}%`;
    qs['searchCriteria[filterGroups][1][filters][0][conditionType]'] = 'like';

    qs['searchCriteria[filterGroups][2][filters][0][field]'] = 'lastname';
    qs['searchCriteria[filterGroups][2][filters][0][value]'] = `%${q}%`;
    qs['searchCriteria[filterGroups][2][filters][0][conditionType]'] = 'like';
  }

  // Viktig: Magento customers list lives under /customers/search
  const data = await magentoGet<MagentoSearchResult<MagentoCustomer>>('/customers/search', qs);

  const rows = data.items.map(c => ({
    id: c.id,
    email: c.email ?? '',
    name: [c.firstname, c.lastname].filter(Boolean).join(' ') || c.email || `#${c.id}`,
    createdAt: c.created_at ?? null,
  }));

  return { rows, total: data.total_count };
}
