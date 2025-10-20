#!/bin/bash
set -euo pipefail

FILE="app/api/products/update-attributes/route.ts"
[ -f "$FILE" ] || { echo "Finner ikke $FILE"; exit 1; }

node - "$FILE" <<'NODE'
const fs = require('fs');
const path = process.argv[1];
let s = fs.readFileSync(path, 'utf8');

// Finn funksjonen som håndterer PATCH (handleUpdate eller PATCH handler)
if (!/async function handleUpdate|export async function PATCH/.test(s)) {
  console.log("⚠️  Fant ikke handleUpdate/PATCH i filen – jeg patcher likevel med en ny handleUpdate og lar PATCH bruke den.");
}

// Sett inn en helper som bygger payload og prøver flere attribute_codes
const helper = `
type UpdatePayload = { sku: string; attributes: Record<string, any> };

async function putWithCodes(baseUrl: string, token: string, sku: string, top: Record<string, any>, codes: string[]) {
  // Split ut standardfelter vs. IBU-verdi
  const { ibu, cfg_ibu, akeneo_ibu, ...restTop } = top || {};
  const candidates = [];
  if (ibu != null) candidates.push({ code: 'ibu', value: ibu });
  if (cfg_ibu != null) candidates.push({ code: 'cfg_ibu', value: cfg_ibu });
  if (akeneo_ibu != null) candidates.push({ code: 'akeneo_ibu', value: akeneo_ibu });
  // Hvis ingen eksplisitt IBU i top-level, men vi har generiske "attributes" map, don't care – PATCH skal uansett støtte custom_attributes nedenfor
  // Bygg baseprodukt
  const baseProduct: any = { ...restTop };
  // Hvis klienten allerede har sendt custom_attributes, behold dem og evt. overskriv/append for koder vi prøver
  const given = Array.isArray(top?.custom_attributes) ? [...top.custom_attributes] : [];

  // Prøv i prioritert rekkefølge
  const tryCodes = candidates.length ? candidates.map(c => c.code) : codes;
  const tryValue = candidates.length ? candidates[0].value : (top?.ibu ?? top?.cfg_ibu ?? top?.akeneo_ibu);

  for (const code of tryCodes) {
    const cas = [...given.filter(x => x?.attribute_code !== code)];
    if (tryValue != null) cas.push({ attribute_code: code, value: String(tryValue) });
    const payload = { product: { ...baseProduct, custom_attributes: cas } };

    const res = await fetch(\`\${baseUrl}/rest/V1/products/\${sku}\`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: \`Bearer \${token}\`,
      },
      body: JSON.stringify(payload),
    });
    if (res.ok) return { ok: true, code };
    // 400 med “attribute not exist” => prøv neste kode
    const txt = await res.text();
    // hvis 401/403 – break, ikke vits å prøve neste
    if (res.status === 401 || res.status === 403) {
      return { ok: false, lastStatus: res.status, lastText: txt };
    }
    // ellers fortsett loop
  }
  return { ok: false, lastStatus: 400, lastText: 'All candidate codes failed' };
}
`;

// Injiser helperen én gang
if (!/function putWithCodes\(/.test(s)) {
  s = s.replace(/(import[^\n]*\n(?:.*\n)*?)/, `$1\n${helper}\n`);
}

// Patch handleUpdate til å bruke putWithCodes
s = s.replace(
  /async function handleUpdate\s*\([^)]*\)\s*\{[\s\S]*?\}\s*/m,
  `
async function handleUpdate(req: Request) {
  try {
    const body = (await req.json()) as UpdatePayload;
    if (!body || !body.sku || !body.attributes) {
      return NextResponse.json({ error: 'Missing "sku" or "attributes" in body' }, { status: 400 });
    }

    const base = (process.env.MAGENTO_URL || process.env.MAGENTO_BASE_URL || '').replace(/\\/$/, '');
    if (!base) return NextResponse.json({ error: 'Missing MAGENTO_URL/MAGENTO_BASE_URL' }, { status: 500 });

    const token = process.env.MAGENTO_TOKEN || '';
    if (!token) return NextResponse.json({ error: 'Missing MAGENTO_TOKEN' }, { status: 500 });

    // Prøv i rekkefølge: ibu → cfg_ibu → akeneo_ibu
    const tried = await putWithCodes(base, token, body.sku, body.attributes, ['ibu','cfg_ibu','akeneo_ibu']);
    if (!tried.ok) {
      const detail = tried.lastText || 'Magento update failed';
      return NextResponse.json({ error: 'Magento update failed', detail }, { status: tried.lastStatus || 500 });
    }

    // Tving cache/oversikter å oppdatere
    try { revalidateTag && revalidateTag('products'); } catch {}
    return NextResponse.json({ success: true, codeUsed: tried.code });
  } catch (e: any) {
    console.error('Update attributes failed', e);
    return NextResponse.json({ error: e?.message || 'Unknown error' }, { status: 500 });
  }
}
`
);

// Hvis handleUpdate ikke fantes, bygg PATCH rundt den
if (!/export\s+async\s+function\s+PATCH/.test(s)) {
  s = s.replace(/export\s+async\s+function\s+GET[\s\S]*/m, (m)=>m) + `
export async function PATCH(req: Request) {
  return handleUpdate(req);
}
`;
}

fs.writeFileSync(path, s);
console.log('🛠  Patchet', path);
NODE

echo "✅ Ferdig. Start serveren på nytt og test en lagring med IBU."
