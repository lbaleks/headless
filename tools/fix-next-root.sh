#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "→ Prosjektrot: $ROOT"

# 1) Rett package.json scripts.dev til kun 'next dev'
if [ ! -f package.json ]; then
  echo "✗ Fant ikke package.json i $ROOT. Stå i prosjektroten og prøv igjen."
  exit 1
fi

echo "→ Oppdaterer package.json (dev/build/start scripts)"
# Bruk node for å redigere trygt uansett OS
node <<'NODE'
const fs = require('fs');
const p = JSON.parse(fs.readFileSync('package.json','utf8'));

p.scripts = p.scripts || {};
p.scripts.dev = 'next dev';
if (!p.scripts.build) p.scripts.build = 'next build';
if (!p.scripts.start) p.scripts.start = 'next start';

fs.writeFileSync('package.json', JSON.stringify(p, null, 2) + '\n');
console.log('✓ package.json oppdatert');
NODE

# 2) Sørg for at app/-mappa finnes med root layout og en enkel page
mkdir -p app

LAYOUT="app/layout.tsx"
if [ ! -f "$LAYOUT" ]; then
  echo "→ Lager $LAYOUT"
  cat > "$LAYOUT" <<'TSX'
export const metadata = {
  title: 'M2',
  description: 'Admin',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="no">
      <body>{children}</body>
    </html>
  );
}
TSX
else
  echo "✓ $LAYOUT finnes – hopper over"
fi

INDEXPAGE="app/page.tsx"
if [ ! -f "$INDEXPAGE" ]; then
  echo "→ Lager $INDEXPAGE"
  cat > "$INDEXPAGE" <<'TSX'
export default function Home() {
  return (
    <div style={{padding: 24}}>
      <h1>M2</h1>
      <p>Gå til <a href="/admin/dashboard">Admin</a></p>
    </div>
  );
}
TSX
else
  echo "✓ $INDEXPAGE finnes – hopper over"
fi

# 3) Rydd cache
echo "→ Rydder .next-cache"
rm -rf .next || true

echo "✓ Ferdig. Kjør: npm run dev"
