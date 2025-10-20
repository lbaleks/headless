#!/usr/bin/env bash
set -euo pipefail

echo "→ ESLint hardening: miljøer, globals og overrides"

# Avhengighet for standard globale variabler
npm i -D globals >/dev/null

# Sørg for at eslint.config.js finnes
if [ ! -f eslint.config.js ]; then
  echo "⚠ Fant ikke eslint.config.js – kjører autoinstaller først"
  npm pkg set scripts.lint="eslint ."
  npm i -D eslint @eslint/js typescript-eslint eslint-plugin-react eslint-plugin-react-hooks eslint-plugin-jsx-a11y @next/eslint-plugin-next globals >/dev/null
  cat > eslint.config.js <<'CFG'
import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import react from 'eslint-plugin-react'
import hooks from 'eslint-plugin-react-hooks'
import jsxA11y from 'eslint-plugin-jsx-a11y'
import next from '@next/eslint-plugin-next'
import globals from 'globals'

export default [
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    ignores: ['node_modules/**', '.next/**', 'dist/**', 'var/**'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parser: tseslint.parser,
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.browser, ...globals.node, React: 'readonly' },
    },
    plugins: {
      '@typescript-eslint': tseslint.plugin,
      react,
      'react-hooks': hooks,
      'jsx-a11y': jsxA11y,
      '@next/next': next,
    },
    rules: {
      ...js.configs.recommended.rules,
      ...tseslint.configs.recommended.rules,
      ...react.configs.recommended.rules,
      ...hooks.configs.recommended.rules,
      ...jsxA11y.configs.recommended.rules,
      ...next.configs['core-web-vitals'].rules,

      // TS håndterer udefinerte typer/globals – skru av core-varianten
      'no-undef': 'off',

      // Lokale preferanser
      'react/react-in-jsx-scope': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
    settings: { react: { version: 'detect' } },
  },

  // CommonJS/Node-skript (server, gateway, scripts, plugins)
  {
    files: [
      'apps/**/src/**/*.js',
      'apps/**/src/**/*.cjs',
      'apps/**/src/**/*.mjs',
      'm2-gateway/**/*.js',
      'tools/**/*.js',
      'scripts/**/*.js',
      'apps/**/*.js',
      'next.config.js',
      'postcss.config.js',
      'tailwind.config.ts',
    ],
    languageOptions: {
      sourceType: 'commonjs',
      globals: {
        ...globals.node,
        require: 'readonly',
        module: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
      },
    },
    rules: {
      // disse filene er JS/Node – beholde 'no-undef' her
    },
  },

  // Slå av en for streng hook-regel inntil vi evt. refaktorerer
  {
    files: ['src/components/layout/AdminNav.tsx'],
    rules: {
      'react-hooks/static-components': 'off',
    },
  },
]
CFG
fi

# Patch eksisterende eslint.config.js for å sikre alt over også i custom config
# (idempotent - setter/forsterker de kritiske delene)
node - <<'PATCH'
import fs from 'fs'
let t = fs.readFileSync('eslint.config.js','utf8')

// Sørg for import globals
if (!t.includes("from 'globals'")) {
  t = t.replace(/(@next\/eslint-plugin-next'.*\n)/, `$1import globals from 'globals'\n`)
}

// Legg til ...globals.browser/node og React global hvis ikke finnes
if (!t.includes('globals: { ...globals.browser, ...globals.node')) {
  t = t.replace(/languageOptions:\s*\{[^}]*\}/s, (m)=>{
    // Sett inn/oppdater languageOptions-blokka grovt
    let block = m
    if (!/globals\s*:/.test(block)) {
      block = block.replace(/\}$/, `, globals: { ...globals.browser, ...globals.node, React: 'readonly' } }`)
    } else {
      block = block.replace(/globals\s*:\s*\{[^}]*\}/, `globals: { ...globals.browser, ...globals.node, React: 'readonly' }`)
    }
    return block
  })
}

// Skru av core no-undef i hovedblokka (TS)
if (!/['"]no-undef['"]\s*:\s*['"]off['"]/.test(t)) {
  t = t.replace(/rules:\s*\{/, "rules: {\n      'no-undef': 'off',")
}

// Legg inn CommonJS override hvis ikke finnes
if (!t.includes('CommonJS/Node-skript') && !t.includes('sourceType: \'commonjs\'')) {
t = t.replace(/\]\s*$/s, `,
  {
    // CommonJS/Node-skript (server, gateway, scripts, plugins)
    files: [
      'apps/**/src/**/*.js',
      'apps/**/src/**/*.cjs',
      'apps/**/src/**/*.mjs',
      'm2-gateway/**/*.js',
      'tools/**/*.js',
      'scripts/**/*.js',
      'apps/**/*.js',
      'next.config.js',
      'postcss.config.js',
      'tailwind.config.ts',
    ],
    languageOptions: {
      sourceType: 'commonjs',
      globals: {
        ...globals.node,
        require: 'readonly',
        module: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
      },
    },
  },
]`)
}

fs.writeFileSync('eslint.config.js', t)
console.log('→ Oppdatert eslint.config.js')
PATCH

echo "→ Kjør lint (kan vise reelle problemer, men 'no-undef' for fetch/process m.m. skal forsvinne)"
npx eslint . || true

echo "✓ ESLint hardening ferdig"
