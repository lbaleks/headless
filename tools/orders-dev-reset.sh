#!/usr/bin/env bash
set -euo pipefail
mkdir -p var
echo "[]" > var/orders.dev.json
echo '{"ok":true,"reset":true}'