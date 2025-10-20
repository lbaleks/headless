#!/usr/bin/env bash
set -euo pipefail

GATEWAY_DIR="${GATEWAY_DIR:-$HOME/Documents/M2/m2-gateway}"
[ -d "$GATEWAY_DIR" ] || { echo "❌ Fant ikke gateway-dir: $GATEWAY_DIR"; exit 1; }

cd "$GATEWAY_DIR"

# a) Lag separat route-fil
cat > routes-products.js <<'JS'
const axios = require("axios");

module.exports = function attachProductsListRoute(app) {
  // Idempotent: unngå dobbel-registrering
  if (app._hasProductsListRoute) return;
  app._hasProductsListRoute = true;

  app.get("/ops/products/list", async (req, res) => {
    try {
      const base = (process.env.MAGENTO_BASE || "").replace(/\/+$/,"");
      const tok  = process.env.MAGENTO_TOKEN || "";
      if (!base || !tok) {
        return res.status(500).json({ ok:false, error:"Missing MAGENTO_BASE or MAGENTO_TOKEN" });
      }

      const page = Number(req.query.page || 1);
      const size = Number(req.query.size || 50);
      const q    = (req.query.q || "").toString().trim();

      // Feltene vi viser i tabellen
      const fields = "items[sku,name,price,status,visibility,extension_attributes[category_links[category_id]]]";

      const sp = new URLSearchParams();
      sp.set("searchCriteria[currentPage]", String(page));
      sp.set("searchCriteria[pageSize]", String(size));
      if (q) {
        // SKU like
        sp.set("searchCriteria[filter_groups][0][filters][0][field]", "sku");
        sp.set("searchCriteria[filter_groups][0][filters][0][value]", `%${q}%`);
        sp.set("searchCriteria[filter_groups][0][filters][0][condition_type]", "like");
        // Name like
        sp.set("searchCriteria[filter_groups][1][filters][0][field]", "name");
        sp.set("searchCriteria[filter_groups][1][filters][0][value]", `%${q}%`);
        sp.set("searchCriteria[filter_groups][1][filters][0][condition_type]", "like");
      }
      sp.set("fields", fields);

      const url = `${base}/rest/all/V1/products?${sp.toString()}`;
      const r = await axios.get(url, {
        headers: { Authorization: tok, "Content-Type": "application/json" },
        timeout: Number(process.env.MAGENTO_TIMEOUT_MS || 25000),
      });

      const items = Array.isArray(r.data?.items) ? r.data.items : [];
      res.json({ ok: true, count: items.length, page, size, items });
    } catch (err) {
      const code = err?.response?.status || 500;
      const msg  = err?.response?.data || { message: String(err) };
      res.status(code).json({ ok:false, error: msg });
    }
  });
};
JS
echo "✅ Skrev $GATEWAY_DIR/routes-products.js"

# b) Sørg for at server.js krever inn ruta før app.listen
[ -f server.js ] || { echo "❌ Fant ikke server.js i $GATEWAY_DIR"; exit 1; }

if ! grep -q "routes-products" server.js; then
  cp server.js server.js.bak.$(date +%s)
  awk '
    /app\.listen\(/ && !done {
      print "require(\"./routes-products\")(app); // AUTO: products list"
      done=1
    }
    { print }
  ' server.js > server.js.new
  mv server.js.new server.js
  echo "✅ Patcha server.js (require('./routes-products')(app) før app.listen)"
else
  echo "ℹ️  server.js har allerede routes-products."
fi

# c) Restart gateway
pkill -f "node server.js" 2>/dev/null || true
PORT="${PORT:-3044}" node server.js >/dev/null 2>&1 &

# d) Rask sanity
sleep 1
echo "🧪 Sanity:"
curl -sS "http://localhost:${PORT:-3044}/health/magento" || true
echo
curl -sS "http://localhost:${PORT:-3044}/ops/products/list" || true
echo
