#!/usr/bin/env bash
# Runs every test in boundary. Exits non-zero if any fails. CI runs it.

here="$(cd "$(dirname "$0")" && pwd)"
failed=0

# Every script starts through env: NixOS has no /bin/bash. A hook that can't start lets the
# command it guards through.
for f in "$here"/*.sh "$here"/hooks/*.sh "$here"/scripts/*.sh; do
  if [ "$(head -n 1 "$f")" != "#!/usr/bin/env bash" ]; then
    echo "WRONG: $f doesn't start with #!/usr/bin/env bash"
    failed=1
  fi
done

for t in "$here/init.test.sh" "$here"/hooks/*.test.sh "$here"/scripts/*.test.sh; do
  "$t" || failed=1
done

# boundary's own design docs keep every requirement tied to its check.
for doc in "$here"/docs/*/README.md; do
  [ -f "$doc" ] || continue
  "$here/scripts/spec-checks.sh" "$doc" || failed=1
done
exit "$failed"
