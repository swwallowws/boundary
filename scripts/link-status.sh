#!/usr/bin/env bash
# HTTP status for each URL given, following redirects (what a link checker would see).
# Usage: bash scripts/link-status.sh <url> [url ...]
for u in "$@"; do
  code=$(curl -s -o /dev/null -L --max-time 20 -w "%{http_code}" "$u")
  echo "$code  $u"
done
