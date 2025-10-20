#!/usr/bin/env bash
set -euo pipefail

# --- Installer Next.js Admin Skeleton ---
echo "→ Oppretter admstage (Next.js-admin)…"

# 1) Opprett mappe og init prosjekt
rm -rf admstage
npx create-next-app@14 admstage --typescript --eslint --tailwind --no-src-dir --app --import-alias "@/*" <<'EOT'
Y
EOT

cd admstage

# 2) Installer axios (for API-kall)
npm install axios

# 3) Sett opp .env.local
cat > .env.local <<'EOF'
NEXT_PUBLIC_GATEWAY=http://localhost:3000
EOF

# 4) Legg til en enkel API-klient
cat > lib/api.ts <<'EOF'
import axios from 'axios';

const baseURL = process.env.NEXT_PUBLIC_GATEWAY || 'http://localhost:3000';

export const api = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json' },
});
EOF

# 5) Legg til en enkel dashboard-side (app/page.tsx)
cat > app/page.tsx <<'EOF'
"use client";
import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function HomePage() {
  const [health, setHealth] = useState<any>(null);

  useEffect(() => {
    api.get('/health/magento').then(res => setHealth(res.data));
  }, []);

  return (
    <main className="p-8">
      <h1 className="text-3xl font-bold mb-4">Litebrygg Admin Dashboard</h1>
      <pre className="bg-gray-100 p-4 rounded">{JSON.stringify(health, null, 2)}</pre>
    </main>
  );
}
EOF

# 6) Produktside (app/products/page.tsx)
mkdir -p app/products
cat > app/products/page.tsx <<'EOF'
"use client";
import { useEffect, useState } from 'react';
import { api } from '../../lib/api';

export default function ProductsPage() {
  const [products, setProducts] = useState<any[]>([]);

  useEffect(() => {
    api.get('/ops/product/list').then(res => setProducts(res.data.items || []));
  }, []);

  return (
    <main className="p-8">
      <h1 className="text-2xl font-bold mb-4">Produkter</h1>
      <table className="table-auto border-collapse border border-gray-300 w-full">
        <thead>
          <tr>
            <th className="border p-2">SKU</th>
            <th className="border p-2">Navn</th>
          </tr>
        </thead>
        <tbody>
          {products.map((p) => (
            <tr key={p.sku}>
              <td className="border p-2">{p.sku}</td>
              <td className="border p-2">{p.name}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
EOF

# 7) Kategoriside (app/categories/page.tsx)
mkdir -p app/categories
cat > app/categories/page.tsx <<'EOF'
"use client";
import { useEffect, useState } from 'react';
import { api } from '../../lib/api';

export default function CategoriesPage() {
  const [cats, setCats] = useState<any[]>([]);

  useEffect(() => {
    api.get('/ops/category/tree').then(res => setCats(res.data.items || []));
  }, []);

  return (
    <main className="p-8">
      <h1 className="text-2xl font-bold mb-4">Kategorier</h1>
      <ul className="list-disc ml-8">
        {cats.map(c => (
          <li key={c.id}>{c.name} (id={c.id})</li>
        ))}
      </ul>
    </main>
  );
}
EOF

echo "✅ admstage opprettet. Kjør:  cd admstage && npm run dev  (åpner på http://localhost:3000)"