#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "→ Installerer Magento bridge i $ROOT"

# --- Hjelper ---
ensure_dir() {
  mkdir -p "$1"
  echo "  ✔ mappe: $1"
}

write_file() {
  local path="$1"
  local tmp="$(mktemp)"
  cat > "$tmp"
  mkdir -p "$(dirname "$path")"
  mv "$tmp" "$path"
  echo "  ✔ skrev: $path"
}

# --- Mapper ---
ensure_dir "src/lib"
ensure_dir "app/api/products"
ensure_dir "app/api/customers"
ensure_dir "app/api/orders"
ensure_dir "app/api/_debug/env"

# --- src/lib/magento.ts ---
write_file "src/lib/magento.ts" <<'EOF_TS'
// src/lib/magento.ts
const RAW_BASE =
  process.env.MAGENTO_BASE_URL ||
  process.env.M2_BASE_URL ||
  process.env.NEXT_PUBLIC_GATEWAY_BASE ||
  '';

const TOKEN =
  process.env.MAGENTO_ADMIN_TOKEN ||
  process.env.M2_ADMIN_TOKEN ||
  process.env.M2_TOKEN ||
  '';

if (!RAW_BASE || !TOKEN) {
  throw new Error('Missing MAGENTO_BASE_URL or MAGENTO_ADMIN_TOKEN in environment');
}

const BASE = RAW_BASE.replace(/\/+$/, '');
const REST = BASE.endsWith('/rest') ? BASE : `${BASE}/rest`;
const V1 = `${REST}/V1`;

function authHeaders() {
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${TOKEN}`,
  };
}

async function handle<T>(res: Response, verb: string, url: string): Promise<T> {
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Magento ${verb} ${url} failed: ${res.status} ${text || res.statusText}`);
  }
  if (res.status === 204) return undefined as unknown as T;
  return res.json() as Promise<T>;
}

export async function magentoGet<T>(path: string, qs: Record<string, string | number | boolean | undefined> = {}) {
  const url = new URL(`${V1}${path}`);
  Object.entries(qs).forEach(([k, v]) => {
    if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
  });
  const res = await fetch(url.toString(), { headers: authHeaders(), cache: 'no-store' });
  return handle<T>(res, 'GET', url.toString());
}

export async function magentoPost<T>(path: string, body: any) {
  const url = `${V1}${path}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(body ?? {}),
  });
  return handle<T>(res, 'POST', url);
}

export async function magentoPut<T>(path: string, body: any) {
  const url = `${V1}${path}`;
  const res = await fetch(url, {
    method: 'PUT',
    headers: authHeaders(),
    body: JSON.stringify(body ?? {}),
  });
  return handle<T>(res, 'PUT', url);
}
EOF_TS

# --- src/lib/products.ts ---
write_file "src/lib/products.ts" <<'EOF_TS'
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
EOF_TS

# --- src/lib/customers.ts ---
write_file "src/lib/customers.ts" <<'EOF_TS'
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
EOF_TS

# --- src/lib/orders.magento.ts ---
write_file "src/lib/orders.magento.ts" <<'EOF_TS'
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
EOF_TS

# --- app/api/products/route.ts ---
write_file "app/api/products/route.ts" <<'EOF_TS'
// app/api/products/route.ts
import { NextResponse } from 'next/server';
import { listProducts } from '@/src/lib/products';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const page = Number(searchParams.get('page') ?? '1') || 1;
  const size = Number(searchParams.get('size') ?? '50') || 50;
  const q = searchParams.get('q') ?? undefined;

  try {
    const { rows, total } = await listProducts(page, size, q);
    return NextResponse.json({ rows, total, page, size });
  } catch (err: any) {
    return NextResponse.json({ error: err?.message || 'Failed to load products' }, { status: 400 });
  }
}
EOF_TS

# --- app/api/customers/route.ts ---
write_file "app/api/customers/route.ts" <<'EOF_TS'
// app/api/customers/route.ts
import { NextResponse } from 'next/server';
import { listCustomers } from '@/src/lib/customers';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const page = Number(searchParams.get('page') ?? '1') || 1;
  const size = Number(searchParams.get('size') ?? '50') || 50;
  const q = searchParams.get('q') ?? undefined;

  try {
    const { rows, total } = await listCustomers(page, size, q);
    return NextResponse.json({ rows, total, page, size });
  } catch (err: any) {
    return NextResponse.json({ error: err?.message || 'Failed to load customers' }, { status: 400 });
  }
}
EOF_TS

# --- app/api/orders/route.ts ---
write_file "app/api/orders/route.ts" <<'EOF_TS'
// app/api/orders/route.ts
import { NextResponse } from 'next/server';
import { listOrders } from '@/src/lib/orders.magento';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const page = Number(searchParams.get('page') ?? '1') || 1;
  const size = Number(searchParams.get('size') ?? '50') || 50;
  const q = searchParams.get('q') ?? undefined;

  try {
    const { rows, total } = await listOrders(page, size, q);
    return NextResponse.json({ rows, total, page, size });
  } catch (err: any) {
    return NextResponse.json({ error: err?.message || 'Failed to load orders' }, { status: 400 });
  }
}
// NB: POST (ordreopprettelse) mot Magento krever quote/checkout-flow.
// Vi lar lokal create leve separat inntil videre.
EOF_TS

# --- app/api/_debug/env/route.ts (valgfritt, nyttig for feilsøking) ---
write_file "app/api/_debug/env/route.ts" <<'EOF_TS'
// app/api/_debug/env/route.ts
import { NextResponse } from 'next/server';

export async function GET() {
  const rawBase =
    process.env.MAGENTO_BASE_URL ||
    process.env.M2_BASE_URL ||
    process.env.NEXT_PUBLIC_GATEWAY_BASE ||
    '';

  const token =
    process.env.MAGENTO_ADMIN_TOKEN ||
    process.env.M2_ADMIN_TOKEN ||
    process.env.M2_TOKEN ||
    '';

  return NextResponse.json({
    hasBase: Boolean(rawBase),
    hasToken: Boolean(token),
    // Maskert preview
    base: rawBase || null,
    tokenPrefix: token ? token.slice(0, 8) + '…' : null,
  });
}
EOF_TS

echo "→ Rydder cache (.next)"
rm -rf .next 2>/dev/null || true
rm -rf .next-cache 2>/dev/null || true

echo "✓ Ferdig!"
echo
echo "Miljøvariabler (.env.local) – bruk én av disse variantene (du har M2_* allerede, det funker):"
echo "  MAGENTO_BASE_URL=https://m2-dev.litebrygg.no/rest"
echo "  MAGENTO_ADMIN_TOKEN=<integration_token>"
echo "eller"
echo "  M2_BASE_URL=https://m2-dev.litebrygg.no/rest"
echo "  M2_ADMIN_TOKEN=<integration_token>"
echo
echo "Start på nytt: npm run dev"
echo "Test:          curl -s http://localhost:3000/api/_debug/env | jq ."