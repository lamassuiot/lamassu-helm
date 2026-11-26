#!/usr/bin/env bash
set -euo pipefail

chart="$(cd "$(dirname "$0")/.." && pwd)/charts/lamassu"

for ttl in 0 0s 30m 1h30m 1.5h .5s 1.s +1h 1µs 1μs; do
  rendered=$(helm template lamassu "$chart" --show-only templates/dms-manager-configmap.yml \
    --set services.dmsManager.crlCache.maxSizeMB=42 \
    --set-string "services.dmsManager.crlCache.maxTTL=$ttl")
  [[ "$rendered" == *"max_size_mb: 42"* && "$rendered" == *"max_ttl: \"$ttl\""* ]]
done

for ttl in -1h 1d nonsense 1 1..5h; do
  if helm template lamassu "$chart" --set-string "services.dmsManager.crlCache.maxTTL=$ttl" >/dev/null 2>&1; then
    echo "Invalid CRL cache duration accepted: $ttl" >&2
    exit 1
  fi
done
