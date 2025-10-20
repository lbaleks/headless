#!/usr/bin/env bash
set -euo pipefail

f="server.js"
[ -f "$f" ] || { echo "❌ Fant ikke $f (kjør i m2-gateway-mappa)"; exit 1; }

# Sjekk om endepunkt allerede finnes
if grep -q "/ops/stats/summary" "$f"; then
  echo "✅ /ops/stats/summary finnes allerede."
  exit 0
fi

echo "→ Legger til /ops/stats/summary i $f …"

# Sett inn like før siste linje i server.js
perl -0777 -pe '
  s|(app\.listen.*)|app.get("/ops/stats/summary", async (req, res) => {
  try {
    const token = process.env.MAGENTO_TOKEN;
    const base = process.env.MAGENTO_BASE;
    const headers = { Authorization: token, "Content-Type": "application/json" };

    const [p, o, c] = await Promise.all([
      fetch(`${base}/rest/V1/products?searchCriteria[pageSize]=1`, { headers }),
      fetch(`${base}/rest/V1/orders?searchCriteria[pageSize]=1`, { headers }),
      fetch(`${base}/rest/V1/customers/search?searchCriteria[pageSize]=1`, { headers }),
    ]);

    const pj = await p.json();
    const oj = await o.json();
    const cj = await c.json();

    res.json({
      ok: true,
      products: pj.total_count || 0,
      orders: oj.total_count || 0,
      customers: cj.total_count || 0,
    });
  } catch (err) {
    console.error("❌ stats error", err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

$1|s' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

echo "✅ Ferdig. Restart gatewayen:"
echo "   node server.js"
