#!/usr/bin/env bash
set -euo pipefail

echo "→ Installerer ESLint (flat) + plugins"
# Bevar eksisterende, men sørg for at disse finnes
npm pkg set scripts.lint="eslint ."
npm pkg set scripts.fix="eslint . --fix"

# Installer dev-avhengigheter (idempotent)
npm i -D eslint @eslint/js typescript-eslint eslint-plugin-react eslint-plugin-react-hooks eslint-plugin-jsx-a11y @next/eslint-plugin-next >/dev/null

echo "→ Skriver eslint.config.js"
cat > eslint.config.js <<'CFG'
// Flat ESLint config for Next.js + TS
import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import react from 'eslint-plugin-react'
import hooks from 'eslint-plugin-react-hooks'
import jsxA11y from 'eslint-plugin-jsx-a11y'
import next from '@next/eslint-plugin-next'

export default [
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    ignores: ['node_modules/**', '.next/**', 'dist/**', 'var/**'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      parser: tseslint.parser,
      parserOptions: {
        ecmaFeatures: { jsx: true }
        // NB: bevisst uten "project" for raskere lint uten typechecking
      },
      globals: {
        window: 'readonly',
        document: 'readonly',
        navigator: 'readonly',
      },
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

      // Prosjekt-tilpasninger
      'react/react-in-jsx-scope': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
    settings: { react: { version: 'detect' } },
  },
]
CFG

echo "→ Linter…"
npx eslint . >/dev/null || true
echo "✓ ESLint flat config på plass"
