#!/usr/bin/env bash
# Lists the requirements in design docs that name no check. Exits non-zero if there are any.
# A requirement is a list item under a "## Requirements" heading; it counts once it says
# "Check:" followed by something (a command, a test's name, "manual: ..." or "none ...").
#   scripts/spec-checks.sh docs/<topic>/README.md [more docs...]

missing=0
for doc in "$@"; do
  if [ ! -f "$doc" ]; then
    echo "$doc: no such file"
    missing=1
    continue
  fi
  # A design doc with no requirements has nothing linked to the code, so it doesn't pass.
  if ! grep -q '^## Requirements' "$doc"; then
    echo "$doc: no ## Requirements section"
    missing=1
    continue
  fi
  in_reqs=0
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      '## Requirements'*) in_reqs=1; continue ;;
      '## '*|'# '*) in_reqs=0; continue ;;
    esac
    [ "$in_reqs" -eq 1 ] || continue
    case "$line" in
      '- '*|'* '*)
        if ! printf '%s' "$line" | grep -Eq 'Check:[[:space:]]*[^[:space:]]'; then
          echo "$doc:$n: no check: ${line#??}"
          missing=1
        fi
        ;;
    esac
  done <"$doc"
done
exit "$missing"
