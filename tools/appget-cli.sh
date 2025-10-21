#!/usr/bin/env bash
set -euo pipefail
: "${BASE_APP:=http://localhost:3000}"
source "$HOME/Documents/M2/tools/beer-qol.sh"
appget "${1:?usage: appget-cli.sh <SKU>}"
