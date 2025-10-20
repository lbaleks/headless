#!/usr/bin/env bash
set -e

# Rekonstruer SEED-variablene uten rare tegn
ROOT="$(pwd)"
SEED_DIR="$ROOT/app/api/_debug/orders/seed"
SEED_ROUTE="$SEED_DIR/route.ts"

mkdir -p "$SEED_DIR"
echo "OK – variabler er rene:"
echo "  SEED_DIR   = $SEED_DIR"
echo "  SEED_ROUTE = $SEED_ROUTE"
