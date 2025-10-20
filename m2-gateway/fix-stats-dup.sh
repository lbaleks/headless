set -euo pipefail
cd "$HOME/Documents/M2/m2-gateway"
cp server.js "server.js.bak.$(date +%s)"

# Dropp alt fra vår tidligere marker til EOF (om den finnes)
if grep -n "// --- live stats" server.js >/dev/null 2>&1; then
  awk 'BEGIN{p=1} /\/\/ --- live stats/{p=0} p{print}' server.js > server.tmp
else
  cp server.js server.tmp
fi

# Append en kollisjonssikker stats-blokk
cat >> server.tmp <<'JS'
// --- live stats ---
(() => {
  const cache = globalThis.__M2_STATS_CACHE || (globalThis.__M2_STATS_CACHE = { stats: null, ts: 0 });
  const STATS_TTL_MS = 30_000;

  async function mgGet2(path) {
    const url = `${process.env.MAGENTO_BASE}/rest/all/V1${path}`;
    const r = await fetch(url, {
      headers: {
        'Authorization': process.env.MAGENTO_TOKEN,
        'Content-Type': 'application/json'
      }
    });
    if (!r.ok) {
      const text = await r.text().catch(()=> '');
      throw new Error(`GET ${path} -> ${r.status} ${text}`);
    }
    return r.json();
  }

  async function computeStats2() {
    // Products: hent bare total_count (kjapt)
    const productsRes = await mgGet2('/products?searchCriteria[currentPage]=1&searchCriteria[pageSize]=1');
    const products = Number(productsRes.total_count ?? 0);

    // Categories: flatten id'er fra treet
    const catTree = await mgGet2('/categories');
    const ids = new Set();
    (function walk(n){
      if (n && typeof n === 'object') {
        if (n.id != null) ids.add(Number(n.id));
        if (Array.isArray(n.children_data)) n.children_data.forEach(walk);
        if (Array.isArray(n.children)) n.children.forEach(walk);
      }
    })(catTree);
    const categories = ids.size;

    // Variants: summer antall children for alle configurable
    let variants = 0;
    const pageSize = 50;
    const first = await mgGet2(`/products?searchCriteria[filter_groups][0][filters][0][field]=type_id&searchCriteria[filter_groups][0][filters][0][value]=configurable&searchCriteria[filter_groups][0][filters][0][condition_type]=eq&searchCriteria[currentPage]=1&searchCriteria[pageSize]=${pageSize}&fields=items[sku],total_count`);
    const totalConf = Number(first.total_count ?? 0);
    const pages = Math.max(1, Math.ceil(totalConf / pageSize));

    async function childrenCountFor(sku) {
      try {
        const kids = await mgGet2(`/configurable-products/${encodeURIComponent(sku)}/children`);
        return Array.isArray(kids) ? kids.length : 0;
      } catch { return 0; }
    }

    for (const it of (first.items ?? [])) variants += await childrenCountFor(it.sku);
    for (let p = 2; p <= pages; p++) {
      const page = await mgGet2(`/products?searchCriteria[filter_groups][0][filters][0][field]=type_id&searchCriteria[filter_groups][0][filters][0][value]=configurable&searchCriteria[filter_groups][0][filters][0][condition_type]=eq&searchCriteria[currentPage]=${p}&searchCriteria[pageSize]=${pageSize}&fields=items[sku]`);
      for (const it of (page.items ?? [])) variants += await childrenCountFor(it.sku);
    }

    return { ok: true, ts: new Date().toISOString(), totals: { products, categories, variants } };
  }

  app.get('/ops/stats/summary', async (req, res) => {
    try {
      const now = Date.now();
      const force = (req.query.refresh === '1');
      if (!force && cache.stats && (now - cache.ts) < STATS_TTL_MS) return res.json(cache.stats);
      const stats = await computeStats2();
      cache.stats = stats; cache.ts = now;
      res.json(stats);
    } catch (e) {
      res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  });

  app.post('/ops/stats/refresh', async (_req, res) => {
    try {
      const stats = await computeStats2();
      cache.stats = stats; cache.ts = Date.now();
      res.json(stats);
    } catch (e) {
      res.status(500).json({ ok: false, error: String(e?.message || e) });
    }
  });
})();
JS

mv server.tmp server.js
echo "✅ Ryddet dublett og lagt inn guarded stats-blokk."
