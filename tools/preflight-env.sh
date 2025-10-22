#!/usr/bin/env bash
set -euo pipefail

missing=()
for v in MAGENTO_USER MAGENTO_PASS; do
  if [ -z "${!v:-}" ]; then missing+=("$v"); fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "❌ Mangler env variabler: ${missing[*]}"
  echo "   Sett dem i .env.local (Next.js laster automatisk)"
  exit 1
fi

# Enkel smoke av /api/health når serveren kjører lokalt
if command -v curl >/dev/null 2>&1; then
  BASE="${BASE:-http://localhost:${PORT:-3000}}"
  if curl -fsS "$BASE/api/health" >/dev/null 2>&1; then
    echo "🩺 Health OK ($BASE/api/health)"
  else
    echo "ℹ️ Health ikke tilgjengelig enda (det er greit hvis serveren ikke er startet)."
  fi
fi
