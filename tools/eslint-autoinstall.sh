#!/usr/bin/env bash
set -euo pipefail

echo "→ ESLint autoinstaller 📦"

# 1) Finn pakkebehandler
PKG=""
if command -v pnpm >/dev/null 2>&1; then PKG="pnpm"
elif command -v yarn >/dev/null 2>&1; then PKG="yarn"
elif command -v bun >/dev/null 2>&1; then PKG="bun"
else PKG="npm"; fi
echo "→ Bruker package manager: $PKG"

# 2) Sjekk at vi står i prosjektrot (package.json finnes)
if [ ! -f package.json ]; then
  echo "✗ Fant ikke package.json i denne mappen. Kjør scriptet fra prosjektroten."
  exit 1
fi

# 3) Installer/oppdater dev-deps
DEPS=(
  "eslint@^9"
  "@eslint/js@^9"
  "typescript-eslint@^8"
  "eslint-plugin-react@^7"
  "eslint-plugin-react-hooks@^5"
  "eslint-plugin-jsx-a11y@^6"
  "@next/eslint-plugin-next@^14"
  "globals@^15"
)

echo "→ Installerer devDependencies: ${DEPS[*]}"
case "$PKG" in
  pnpm) pnpm add -D "${DEPS[@]}" ;;
  yarn) yarn add -D "${DEPS[@]}" ;;
  bun)  bun add -d "${DEPS[@]}" ;;
  npm)  npm install -D "${DEPS[@]}" ;;
esac

# 4) Legg til "type": "module" i package.json (hvis ikke satt)
echo "→ Sikrer \"type\": \"module\" i package.json"
if command -v jq >/dev/null 2>&1; then
  TMP_PKG="$(mktemp)"
  jq 'if has("type") then . else . + {"type":"module"} end' package.json > "$TMP_PKG" && mv "$TMP_PKG" package.json
else
  # enkel sed-basert fallback: legg inn "type": "module" etter første {
  if ! grep -q '"type"[[:space:]]*:[[:space:]]*"module"' package.json; then
    cp package.json package.json.bak-eslinstall
    awk 'NR==1{print; print "  \"type\": \"module\","; next}1' package.json.bak-eslinstall > package.json
  fi
fi

# 5) Skriv eslint.config.js (backup hvis finnes)
ESLINT_CFG="eslint.config.js"
if [ -f "$ESLINT_CFG" ]; then
  cp "$ESLINT_CFG" "${ESLINT_CFG}.bak.$(date +%s)"
  echo "→ Tok backup av eksisterende $ESLINT_CFG"
fi

cat > "$ESLINT_CFG" <<'EOF'
// eslint.config.js (Flat config)
import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import react from 'eslint-plugin-react'
import hooks from 'eslint-plugin-react-hooks'
import jsxA11y from 'eslint-plugin-jsx-a11y'
import next from '@next/eslint-plugin-next'
import globals from 'globals'

export default [
  // 0) Ignorer ting vi ikke vil lint’e nå
  {
    ignores: [
      'node_modules/**',
      '.next/**',
      'dist/**',
      'var/**',
      // midlertidig: skrur av admstage til det får egen konfig
      'admstage/**',
      // bygg/output
      '**/*.min.*',
    ],
  },

  // 1) Base + presets (disse SKAL komme FØR overrides)
  ...tseslint.configs.recommended,
  js.configs.recommended,
  react.configs.recommended,
  hooks.configs.recommended,
  jsxA11y.configs.recommended,
  (next.configs?.recommended ?? {}),

  // 2) Våre prosjekt-overrides (kommer SIST, vinner over alt over)
  {
    files: ['**/*.{ts,tsx,js,jsx}'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { ecmaVersion: 'latest', sourceType: 'module', ecmaFeatures: { jsx: true } },
      globals: { ...globals.browser, ...globals.node, React: 'readonly' },
    },
    plugins: { react, 'react-hooks': hooks, 'jsx-a11y': jsxA11y, '@next/next': next },
    settings: { react: { version: 'detect' } },
    rules: {
      // typer & støy
      'no-undef': 'off',
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unsafe-function-type': 'warn',
      '@typescript-eslint/triple-slash-reference': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', {
        argsIgnorePattern: '^_',
        varsIgnorePattern: '^_',
      }],

      // slå av eksperimentelle hook-regler som ga støy
      'react-hooks/purity': 'off',
      'react-hooks/set-state-in-effect': 'off',

      // a11y/next foreløpig som advarsler
      'jsx-a11y/label-has-associated-control': 'warn',
      '@next/next/no-html-link-for-pages': 'warn',

      // kosmetikk / WIP
      'no-empty': 'warn',
      'no-unused-expressions': 'warn',
      'react/react-in-jsx-scope': 'off',

      // tillat ts-ignore med begrunnelse
      '@typescript-eslint/ban-ts-comment': ['warn', { 'ts-ignore': 'allow-with-description' }],
    },
  },

  // 3) Node/CJS-scripts og gateway: tillat require()
  {
    files: [
      'apps/**/src/**/*.{js,cjs,mjs}',
      'apps/**/*.js',
      'm2-gateway/**/*.js',
      'tools/**/*.js',
      'scripts/**/*.js',
      'next.config.js',
      'postcss.config.js',
      'tailwind.config.ts',
    ],
    languageOptions: {
      sourceType: 'commonjs',
      globals: { ...globals.node, require: 'readonly', module: 'readonly', __dirname: 'readonly', __filename: 'readonly' },
    },
    rules: {
      '@typescript-eslint/no-require-imports': 'off',
    },
  },
]
EOF
echo "→ Skrev $ESLINT_CFG"

# 6) Legg til npm-scripts (lint/lint:fix)
echo "→ Legger til scripts i package.json (lint, lint:fix)"
if command -v jq >/dev/null 2>&1; then
  TMP_PKG="$(mktemp)"
  jq '
    .scripts = (.scripts // {}) |
    .scripts.lint = (.scripts.lint // "eslint .") |
    .scripts["lint:fix"] = (.scripts["lint:fix"] // "eslint . --fix")
  ' package.json > "$TMP_PKG" && mv "$TMP_PKG" package.json
else
  # naive sed/awk fallback – bare legg inn hvis ikke finnes
  if ! grep -q '"lint"' package.json; then
    cp package.json package.json.bak-eslinstall-scripts
    awk 'BEGIN{added=0}
      /"scripts"[[:space:]]*:[[:space:]]*{/ && added==0 {
        print;
        print "    \"lint\": \"eslint .\",";
        print "    \"lint:fix\": \"eslint . --fix\",";
        added=1; next
      }1' package.json.bak-eslinstall-scripts > package.json
  fi
fi

# 7) Kjør lint for å bekrefte
echo "→ Kjører lint (første pass)"
case "$PKG" in
  pnpm) pnpm run -s lint || true ;;
  yarn) yarn -s lint || true ;;
  bun)  bun run lint || true ;;
  npm)  npm run -s lint || true ;;
esac

echo "✓ ESLint autoinstaller ferdig"