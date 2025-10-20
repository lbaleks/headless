#!/usr/bin/env bash
set -Eeuo pipefail
. tools/_lib.sh
kill_ports 3000 3001
next dev -p 3000
