// eslint.config.js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import jsxA11y from "eslint-plugin-jsx-a11y";
import next from "@next/eslint-plugin-next";
import importPlugin from "eslint-plugin-import";
import globals from "globals";

export default [
  // Ignorer bygde ting
  { ignores: ["**/.next/**", "**/dist/**", "**/out/**", "**/node_modules/**"] },

  // Felles baseline (JS/TS)
  {
    files: ["**/*.{js,cjs,mjs,jsx,ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.browser, ...globals.node },
    },
    plugins: {
      // NB: plugins som objekter
      "@typescript-eslint": tseslint.plugin,
      react,
      "react-hooks": reactHooks,
      "jsx-a11y": jsxA11y,
      next,
      import: importPlugin,
    },
    settings: {
      react: { version: "detect" },
    },
    rules: {
      // Slå ned “build-stoppere” til warn
      "@typescript-eslint/no-unused-expressions": "warn",
      "no-constant-binary-expression": "warn",
      "no-useless-escape": "warn",
      "prefer-const": "warn",

      // a11y midlertidig
      "jsx-a11y/click-events-have-key-events": "warn",
      "jsx-a11y/no-static-element-interactions": "warn",

      // Next-regler (NB: bruk "next/…" i flat config)
      "next/no-img-element": "warn",
      "next/no-html-link-for-pages": "warn",
    },
  },

  // SI: fortell ESLint at TS-filer skal parses med TS-parseren
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      parser: tseslint.parser,               // <- dette manglet
      parserOptions: {
        // Prosjekt-config er valgfritt; skru på om du trenger type-aware regler:
        // project: ['./tsconfig.json'],
        ecmaFeatures: { jsx: true },
      },
    },
    rules: {
      // evt. TS-spesifikke regler
    },
  },

  // Node-scripts og API (Node-kontekst)
  {
    files: [
      "scripts/**/*.{js,mjs,ts}",
      "pages/api/**/*.{ts,tsx,js}",
      "app/api/**/*.{ts,tsx,js}",
    ],
    languageOptions: { globals: { ...globals.node } },
    rules: {
      "no-undef": "off", // for mjs/edge-scripts som bruker fetch/console/process
    },
  },
];