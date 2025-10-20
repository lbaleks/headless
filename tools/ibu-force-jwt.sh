#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"

write() { mkdir -p "$(dirname "$1")"; cat > "$1"; echo "✓ Wrote $1"; }

# lib/env.ts — types + helpers + admin token helper
write "$ROOT/lib/env.ts" <<"TS"
export type MagentoConfig = {
  baseUrl: string;
  token: string | null;       // kept for completeness, but we won't use it
  adminUser: string | null;
  adminPass: string | null;
};

export function v1(baseUrl: string) {
  return `${baseUrl.replace(/\/$/, '')}/V1`;
}

export function getMagentoConfig(): MagentoConfig {
  const base = process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '';
  return {
    baseUrl: base,
    token: process.env.MAGENTO_TOKEN || null,
    adminUser: process.env.MAGENTO_ADMIN_USERNAME || null,
    adminPass: process.env.MAGENTO_ADMIN_PASSWORD || null,
  };
}

export async function getAdminToken(baseUrl: string, user: string, pass: string): Promise<string> {
  const res = await fetch(`${v1(baseUrl)}/integration/admin/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: user, password: pass }),
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`Admin token ${res.status}`);
  return res.text();
}
TS

# app/api/products/update-attributes/route.ts — write with admin JWT only
write "$ROOT/app/api/products/update-attributes/route.ts" <<"TS"
import { NextResponse } from 'next/server';
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env';

export const runtime = 'nodejs';
export const revalidate = 0;

type UpdatePayload = { sku: string; attributes: Record<string, string | number | null> };

export async function PATCH(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload;
    const sku = body?.sku;
    const attributes = body?.attributes;
    if (!sku || !attributes || typeof attributes !== 'object') {
      return NextResponse.json({ error: 'Bad payload' }, { status: 400 });
    }

    const cfg = getMagentoConfig();
    if (!cfg.baseUrl || !cfg.adminUser || !cfg.adminPass) {
      return NextResponse.json({ error: 'Missing admin creds in env' }, { status: 500 });
    }

    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass);
    const payload = {
      product: {
        sku,
        custom_attributes: Object.entries(attributes).map(([attribute_code, value]) => ({ attribute_code, value })),
      },
    };

    const res = await fetch(`${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify(payload),
      cache: 'no-store',
    });

    const bodyJson = await res.json().catch(() => ({}));
    if (!res.ok) {
      return NextResponse.json({ error: `Magento PUT ${res.status}`, magento: bodyJson }, { status: 500 });
    }
    return NextResponse.json({ success: true, magento: bodyJson });
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'unexpected' }, { status: 500 });
  }
}
TS

# app/api/products/[sku]/route.ts — read single with admin JWT, lift _attrs + ibu
write "$ROOT/app/api/products/[sku]/route.ts" <<"TS"
import { NextResponse } from 'next/server';
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env';

export const runtime = 'nodejs';
export const revalidate = 0;

export async function GET(_req: Request, ctx: { params: Promise<{ sku: string }> }) {
  try {
    const { sku } = await ctx.params;

    const cfg = getMagentoConfig();
    if (!cfg.baseUrl || !cfg.adminUser || !cfg.adminPass) {
      return NextResponse.json({ error: 'Missing admin creds in env' }, { status: 500 });
    }

    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass);
    const res = await fetch(`${v1(cfg.baseUrl)}/products/${encodeURIComponent(sku)}?storeId=0`, {
      headers: { Authorization: `Bearer ${jwt}` },
      cache: 'no-store',
    });
    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json({ error: `Magento GET ${res.status}`, magento: data }, { status: 500 });
    }

    const ca = Array.isArray((data as any).custom_attributes) ? (data as any).custom_attributes : [];
    const attrs = Object.fromEntries(ca.filter(Boolean).map((x: any) => [x.attribute_code, x.value]));
    const ibu = (attrs as any).ibu ?? null;

    return NextResponse.json({ ...(data as any), ibu, _attrs: attrs });
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'unexpected' }, { status: 500 });
  }
}
TS

# app/api/products/merged/route.ts — list page with admin JWT, lift _attrs + ibu
write "$ROOT/app/api/products/merged/route.ts" <<"TS"
import { NextResponse } from 'next/server';
import { getMagentoConfig, getAdminToken, v1 } from '@/lib/env';

export const runtime = 'nodejs';
export const revalidate = 0;

export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const page = Math.max(1, Number(url.searchParams.get('page') || '1'));
    const size = Math.max(1, Math.min(200, Number(url.searchParams.get('size') || '50')));

    const cfg = getMagentoConfig();
    if (!cfg.baseUrl || !cfg.adminUser || !cfg.adminPass) {
      return NextResponse.json({ error: 'Missing admin creds in env' }, { status: 500 });
    }

    const jwt = await getAdminToken(cfg.baseUrl, cfg.adminUser, cfg.adminPass);
    const listUrl =
      `${v1(cfg.baseUrl)}/products?storeId=0` +
      `&searchCriteria[currentPage]=${page}&searchCriteria[pageSize]=${size}`;

    const res = await fetch(listUrl, {
      headers: { Authorization: `Bearer ${jwt}` },
      cache: 'no-store',
    });
    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json({ error: `Magento GET ${res.status}`, magento: data }, { status: 500 });
    }

    const items = Array.isArray((data as any)?.items) ? (data as any).items : [];
    const lifted = items.map((p: any) => {
      const ca = Array.isArray(p.custom_attributes) ? p.custom_attributes : [];
      const attrs: Record<string, any> = Object.fromEntries(ca.filter(Boolean).map((x: any) => [x.attribute_code, x.value]));
      const ibu = attrs.ibu ?? null;
      return { ...p, ibu, _attrs: attrs };
    });

    return NextResponse.json({ items: lifted, page, size, total: (data as any)?.total_count ?? lifted.length });
  } catch (e: any) {
    return NextResponse.json({ error: e?.message || 'unexpected' }, { status: 500 });
  }
}
TS

echo "All done."
