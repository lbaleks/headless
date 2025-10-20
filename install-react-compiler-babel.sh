#!/usr/bin/env bash
# install-react-compiler-babel.sh — LiteBrygg Admin (Next.js 15)
# Fixer feilen: "Failed to load the `babel-plugin-react-compiler`"
# - Installerer plugin
# - Oppretter/oppdaterer babel.config.js
# - Validerer installasjon
# - Starter dev-server

set -euo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;36m[react-compiler]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[error]\033[0m %s\n" "$*"; exit 1; }

# Prechecks
[ -f package.json ] || fail "Kjør fra prosjektroten (der package.json ligger)."
command -v node >/dev/null 2>&1 || fail "Node.js ikke funnet"
log "Node: $(node -v)"

# Velg pakkehåndterer
if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
  PKG="pnpm"
elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
  PKG="yarn"
else
  PKG="npm"
fi
log "Pakkehåndterer: $PKG"

# Installer plugin
log "Installerer babel-plugin-react-compiler"
case "$PKG" in
  pnpm) pnpm add -D babel-plugin-react-compiler >/dev/null ;;
  yarn) yarn add -D babel-plugin-react-compiler >/dev/null ;;
  npm)  npm i  -D babel-plugin-react-compiler >/dev/null ;;
esac

# Skriv babel.config.js (med backup hvis den finnes)
if [ -f babel.config.js ]; then
  TS=$(date +%Y%m%d-%H%M%S)
  cp babel.config.js "babel.config.js.bak.$TS"
  warn "Backup: babel.config.js -> babel.config.js.bak.$TS"
fi

# Vi bruker CJS for bred støtte i Next/Babel
cat > babel.config.js <<'JS'
/**
 * LiteBrygg Admin — Babel config for React Compiler
 * Next.js 15 bruker SWC by default, men React Compiler krever denne Babel-pluginen.
 */
module.exports = {
  presets: [],
  plugins: [
    // Viktig: må være strengen 'babel-plugin-react-compiler'
    'babel-plugin-react-compiler'
  ]
};
JS
log "Skrev babel.config.js"

# Sjekk at plugin kan resolves
node -e "require.resolve('babel-plugin-react-compiler'); console.log('Resolve OK: babel-plugin-react-compiler')" >/dev/null && log "Plugin resolve OK"

# Sørg for at experimental.reactCompiler er aktiv (oppretter next.config.ts hvis ingen finnes)
if [ ! -f next.config.ts ] && [ ! -f next.config.mjs ] && [ ! -f next.config.js ]; then
  cat > next.config.ts <<'TS'
import type { NextConfig } from 'next'
const nextConfig: NextConfig = {
  experimental: { reactCompiler: true }
}
export default nextConfig
TS
  log "Opprettet next.config.ts (experimental.reactCompiler = true)"
else
  log "Fant en next.config.* — sørg for at experimental.reactCompiler = true der."
fi

# Oppdater scripts i package.json dersom dev ikke finnes
node - <<'NODE'
const fs = require('fs');
const p = 'package.json';
const pkg = JSON.parse(fs.readFileSync(p,'utf8'));
pkg.scripts ||= {};
pkg.scripts.dev   ||= 'next dev -p 3000';
pkg.scripts.build ||= 'next build';
pkg.scripts.start ||= 'next start -p 3000';
fs.writeFileSync(p, JSON.stringify(pkg,null,2));
console.log('[react-compiler] Oppdatert package.json scripts (om nødvendig)');
NODE

# Start dev-server (blokkende; Ctrl+C for å stoppe)
log "Starter dev-server (npm run dev). Avslutt med Ctrl+C."
npm run dev