#!/usr/bin/env bash
set -euo pipefail
: "${BASE_APP:=http://localhost:3000}"
source "$HOME/Documents/M2/tools/beer-qol.sh"
mageget "${1:?usage: mageget-cli.sh <SKU>}"
