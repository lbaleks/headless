#!/usr/bin/env bash
set -euo pipefail
: "${BASE_APP:=http://localhost:3000}"
source "$HOME/Documents/M2/tools/beer-qol.sh"
beer-smoke "${1:?usage: beer-smoke-cli.sh <SKU>}"
