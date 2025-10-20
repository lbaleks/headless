# tools/patch-customers-search.sh
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"

echo "→ Patcher /app/api/customers/route.ts til riktig søk på email/firstname/lastname…"
cat > "$ROOT/app/api/customers/route.ts" <<'TS'
import { NextResponse } from 'next/server'
import { m2Get, mapCustomer } from '@/src/lib/m2fetch'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const page = Math.max(1, Number(url.searchParams.get('page') || '1'))
  const size = Math.max(1, Math.min(200, Number(url.searchParams.get('size') || '25')))
  const q    = (url.searchParams.get('q') || '').trim()
  const sort = (url.searchParams.get('sort') || 'created_at:desc').trim()

  const params = new URLSearchParams()
  params.set('searchCriteria[currentPage]', String(page))
  params.set('searchCriteria[pageSize]', String(size))

  // Sortering (Magento customers har feltet 'created_at')
  if (sort) {
    const [fieldRaw, dirRaw] = sort.split(':')
    const field = fieldRaw || 'created_at'
    const direction = (dirRaw || 'desc').toUpperCase() === 'ASC' ? 'ASC' : 'DESC'
    params.set('searchCriteria[sortOrders][0][field]', field)
    params.set('searchCriteria[sortOrders][0][direction]', direction)
  }

  // Fritekstsøk
  if (q) {
    if (q.includes('@')) {
      // Typisk e-post: målrett mot email
      params.set('searchCriteria[filter_groups][0][filters][0][field]', 'email')
      params.set('searchCriteria[filter_groups][0][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'like')
    } else {
      // OR: firstname like OR lastname like OR email like
      params.set('searchCriteria[filter_groups][0][filters][0][field]', 'firstname')
      params.set('searchCriteria[filter_groups][0][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][0][filters][0][condition_type]', 'like')

      params.set('searchCriteria[filter_groups][1][filters][0][field]', 'lastname')
      params.set('searchCriteria[filter_groups][1][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][1][filters][0][condition_type]', 'like')

      params.set('searchCriteria[filter_groups][2][filters][0][field]', 'email')
      params.set('searchCriteria[filter_groups][2][filters][0][value]', `%${q}%`)
      params.set('searchCriteria[filter_groups][2][filters][0][condition_type]', 'like')
    }
  }

  const data = await m2Get<any>(`V1/customers/search?${params.toString()}`)
  const items = (data.items || []).map(mapCustomer)
  const total = Number(data.total_count || data.totalCount || items.length)

  return NextResponse.json({ page, size, total, items })
}
TS

echo "→ Rydder .next/.next-cache…"
rm -rf "$ROOT/.next" "$ROOT/.next-cache" 2>/dev/null || true

echo "✓ Ferdig. Start dev på nytt (npm run dev)."
echo "  Test:"
echo "    curl -s 'http://localhost:3000/api/customers?page=1&size=5&q=a' | jq '.total,(.items[0]//{})'"