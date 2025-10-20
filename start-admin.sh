#!/usr/bin/env bash
set -e
cd "$HOME/Documents/M2/admstage"
lsof -ti tcp:3000 | xargs kill -9 2>/dev/null || true
pnpm dev || npm run dev || yarn dev
