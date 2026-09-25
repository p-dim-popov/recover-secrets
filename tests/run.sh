#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
status=0
for f in test_*.sh; do
  echo "== $f"
  bash "$f" || status=1
done
exit $status
