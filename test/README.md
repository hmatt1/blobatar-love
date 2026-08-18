# Tests

Three layers, in increasing order of what they need to run.

## `invariants.lua` and `motion.lua`

Plain Lua, no fixtures, no graphics. Run them with either runtime:

```
luajit test/invariants.lua
luajit test/motion.lua
lua5.4 test/all.lua
```

`invariants.lua` is a port of the original's own suite: containment across 6000
seeds and across the corners of the trait-override space, the contrast floors at
every hue and tone, the tint guarantee at every heat and target, and the
normalization rules that make two spellings of a name the same blobatar.

`motion.lua` covers the timing model: the cubic-bezier solver, keyframe
sampling, negative delays, alternating direction, and CSS's rule for shortening
an interrupted transition, plus the equivalence the animated renderer depends
on: that applying a pose as transforms lands the geometry exactly where baking
it into the coordinates does.

## `parity.lua`

Diffs the port against the original, row by row. Needs `fixtures.txt`, which is
what the TypeScript library produced for a wide slice of its input space:

```
bun tools/gen_fixtures.mjs /path/to/blobatar/packages/blobatar/src 20000
luajit test/parity.lua
```

The committed fixture is a smaller sample so the repository stays a reasonable
size. Regenerate it at any width you like; the checked-in one is 3000 seeds.

The SVG rows are the load-bearing ones. A blobatar's whole pipeline (hash,
traits, palette, layout, containment fit, pose baking, path construction and
rounding) ends up in that string, so a byte comparison covers all of it at once.

## The motion comparison

A stylesheet can only be checked against a browser. `tools/dump_animated.lua`
writes the port's animated markup, `tools/motion_shot.mjs` loads it alongside the
original's `motion.css`, freezes every animation at a stated time and
screenshots it. Rendering the same seeds in LOVE with the clock set to the same
time gives two images that should differ only where a rasterizer's edges differ.

```
mkdir -p /tmp/motion && cp /path/to/blobatar/packages/blobatar/src/motion.css /tmp/motion/
luajit tools/dump_animated.lua mad > /tmp/motion/index.html
node tools/motion_shot.mjs 4.1 mad
```

`docs/parity.png` is what that comparison looks like.
