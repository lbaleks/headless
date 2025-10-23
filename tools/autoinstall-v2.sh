#!/usr/bin/env bash
set -euo pipefail

# --- Konfig ---
NODE_VER="v20.19.5"                 # eksakt Node 20 vi har brukt
NODE_DIR="$HOME/.nvm/versions/node/$NODE_VER"
BIN="$NODE_DIR/bin"

echo "▶ Autoinstaller v2 – sikrer Node 20 + pnpm 10, wrappere, scripts og PM2-oppsett"

# --- Sjekk Node 20 ---
if [[ ! -x "$BIN/node" ]]; then
  echo "❌ Fant ikke Node 20 på $BIN"
  echo "   Kjør:  nvm install 20 && nvm use 20"
  exit 1
fi

mkdir -p tools logs

# --- pn20 wrapper: kjør pnpm 10 *alltid* via Node 20 (CJS entry) ---
cat > tools/pn20 <<'SH'
#!/usr/bin/env bash
set -euo pipefail
NODE_DIR="$HOME/.nvm/versions/node/v20.19.5"
BIN="$NODE_DIR/bin"

if [[ ! -x "$BIN/node" ]]; then
  echo "❌ Fant ikke Node 20 i $BIN. Kjør: nvm install 20 && nvm use 20" >&2
  exit 1
fi

# Bruk pnpm.cjs fra dette Node 20-prefixet (uavhengig av systemets PATH)
PNPM_JS="$("$BIN/npm" root -g --prefix "$NODE_DIR")/pnpm/bin/pnpm.cjs"
if [[ ! -f "$PNPM_JS" ]]; then
  echo "ℹ️ Installerer pnpm@10.19.0 globalt i $NODE_DIR ..."
  "$BIN/npm" i -g pnpm@10.19.0 --prefix "$NODE_DIR" --force >/dev/null
fi

exec "$BIN/node" "$PNPM_JS" "$@"
SH
chmod +x tools/pn20

# --- next20 wrapper: start/build Next via Node 20 uansett PATH ---
cat > tools/next20 <<'SH'
#!/usr/bin/env bash
set -euo pipefail
NODE="$HOME/.nvm/versions/node/v20.19.5/bin/node"

# Foretrekk prosjektets Next-bin
NEXT_JS="./node_modules/next/dist/bin/next"
if [[ ! -f "$NEXT_JS" ]]; then
  # fallback: global next hvis installert under samme Node 20
  ALT="$HOME/.nvm/versions/node/v20.19.5/lib/node_modules/next/dist/bin/next"
  [[ -f "$ALT" ]] && NEXT_JS="$ALT"
fi

if [[ ! -f "$NEXT_JS" ]]; then
  echo "❌ Finner ikke next-bin. Kjør 'tools/pn20 install' først." >&2
  exit 1
fi

exec "$NODE" "$NEXT_JS" "$@"
SH
chmod +x tools/next20

# --- Sikre .nvmrc (for dev/CI-konsistens) ---
if [[ ! -f .nvmrc ]] || ! grep -q "20" .nvmrc; then
  echo "20.19.5" > .nvmrc
  echo "✅ .nvmrc satt til 20.19.5"
fi

# --- package.json: lås packageManager, engines og scripts til wrapperne ---
node -e '
const fs=require("fs");
const p=JSON.parse(fs.readFileSync("package.json","utf8"));
p.packageManager = "pnpm@10.19.0";
p.engines = { node: ">=20 <21" };

p.scripts ||= {};
p.scripts.build = "tools/next20 build";
p.scripts.start = "tools/next20 start -p ${PORT:-3100}";
p.scripts["deploy:prod"] = "tools/pn20 install && tools/pn20 run build && pm2 reload m2-web --update-env && pm2 save";

fs.writeFileSync("package.json", JSON.stringify(p,null,2));
console.log("✅ package.json oppdatert (packageManager, engines, scripts)");
'

# --- Patch PM2-ecosystem til å bruke tools/next20 start ---
node - <<'NODE'
const fs = require('fs');
for (const fn of ['ecosystem.config.cjs','ecosystem.config.js']) {
  if (!fs.existsSync(fn)) continue;
  let s = fs.readFileSync(fn,'utf8');
  const before = s;
  s = s.replace(/(?<![\w/.-])next start\b/g, 'tools/next20 start');
  if (s !== before) {
    fs.writeFileSync(fn, s);
    console.log('✅ Patchet', fn, '-> tools/next20 start');
  } else {
    console.log('ℹ️ Ingen endring i', fn, '(allerede korrekt eller annen oppstartsmåte)');
  }
}
NODE

# --- Installer deps med pnpm 10 via Node 20 ---
echo "▶ pnpm install (Node 20)…"
tools/pn20 install

# --- Build med Next via Node 20 ---
echo "▶ Build…"
tools/pn20 run build

# --- PM2 reload + save ---
if pm2 describe m2-web >/dev/null 2>&1; then
  echo "▶ PM2 reload m2-web"
  pm2 reload m2-web --update-env
else
  if [[ -f ecosystem.config.cjs ]]; then
    echo "▶ PM2 start via ecosystem.config.cjs"
    pm2 start ecosystem.config.cjs
  elif [[ -f ecosystem.config.js ]]; then
    echo "▶ PM2 start via ecosystem.config.js"
    pm2 start ecosystem.config.js
  else
    echo "ℹ️ Fant ikke ecosystem.config.* – hopper over PM2 start"
  fi
fi
pm2 save || true

# --- Smoke test ---
echo "▶ Smoke:"
set +e
curl -fsS "http://127.0.0.1:3100/api/health" | jq . 2>/dev/null || curl -fsS "http://127.0.0.1:3100/api/health"
curl -fsS "http://127.0.0.1:3100/api/magento/health" | jq . 2>/dev/null || curl -fsS "http://127.0.0.1:3100/api/magento/health"
set -e

echo "✅ Autoinstaller v2 ferdig."