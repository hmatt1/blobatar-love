#!/bin/sh
# Regenerates test/fixtures.txt from a checkout of the upstream library.
#
#   tools/gen_fixtures.sh /path/to/blobatar/packages/blobatar/src [seed count]
#
# Runs under node so the numbers come from V8, which is what a browser and most
# servers rasterize with. bun works too and is quicker, but its `Math.hypot`
# disagrees with V8's in the last bit: invisible in the markup, visible in the
# twelve-decimal layout rows.
set -e
SRC="${1:-../blobatar/packages/blobatar/src}"
COUNT="${2:-3000}"
if command -v node >/dev/null 2>&1; then
  node --experimental-strip-types --import ./tools/ts-resolve-register.mjs \
       tools/gen_fixtures.mjs "$SRC" "$COUNT"
else
  bun tools/gen_fixtures.mjs "$SRC" "$COUNT"
fi
