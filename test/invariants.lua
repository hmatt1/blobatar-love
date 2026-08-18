--- The invariant suite, ported from the original's tests.
---
--- These are the checks that replace eyeballing the grid one cell at a time.
--- Staring at 400 blobatars tells you whether the ranges are tasteful; these tell
--- you whether any seed in the space is outright broken: an eye off the cheek,
--- a body clipped by the frame, two capsules fused into one.
---
---   luajit test/invariants.lua
---   lua5.4 test/invariants.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("test.runner")
local describe, test = T.describe, T.test

local blobatar = require("blobatar")
local blob = require("blobatar.style.blob")
local traits = require("blobatar.traits").traits
local color = require("blobatar.color")
local shape = require("blobatar.shape")
local svgmod = require("blobatar.svg")
local hash = require("blobatar.hash")
local expression = require("blobatar.expression")
local util = require("blobatar.util")

local SEED_COUNT = tonumber(os.getenv("BLOB_SEEDS") or "6000")
local SEEDS = {}
for i = 0, SEED_COUNT - 1 do SEEDS[i + 1] = "seed-" .. i end

local abs, min, max, cos, sin, pi = math.abs, math.min, math.max, math.cos, math.sin, math.pi

--- Signed containment: <= 1 is inside the superellipse.
local function inside(px, py, s)
  return abs((px - s.cx) / s.rx) ^ s.n + abs((py - s.cy) / s.ry) ^ s.n
end

--- The four corners of a rotated box: a conservative hull for a capsule.
local function corners(e)
  local t = e.rot * pi / 180
  local c, s = cos(t), sin(t)
  local out = {}
  local signs = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
  for i = 1, 4 do
    local sx, sy = signs[i][1], signs[i][2]
    out[i] = {
      e.cx + sx * e.rx * c - sy * e.ry * s,
      e.cy + sx * e.rx * s + sy * e.ry * c,
    }
  end
  return out
end

local function minRadius(radii)
  local m = math.huge
  for i = 1, #radii do m = min(m, radii[i]) end
  return m
end

--- Every number in every path in the markup.
local function pathNumbers(svg, fn)
  for d in svg:gmatch(' d="([^"]+)"') do
    for v in d:gmatch("%-?%d+%.?%d*") do fn(tonumber(v), d) end
  end
end

local function checkContainment(layouts, label)
  for i = 1, #layouts do
    local l = layouts[i]
    -- For the spline shapes the core dips to its smallest sampled radius
    -- between vertices, so containment is measured against that, not the mean.
    local shrink = 1
    if l.shape == "organic" or l.shape == "cloud" then
      shrink = minRadius(l.body.radii) * 0.95
    end
    local core = {
      cx = l.body.cx,
      cy = l.body.cy,
      rx = l.body.rx * shrink,
      ry = l.body.ry * shrink,
      -- Understate squareness: a boxy body is roomier than the ellipse we test.
      n = 2,
    }
    for k = 1, #l.eyes do
      local pts = corners(l.eyes[k])
      for j = 1, 4 do
        T.lt(inside(pts[j][1], pts[j][2], core), 1,
             label .. ": eye corner outside the body core (" .. l.shape .. ")")
      end
    end
  end
end

local function checkFusion(layouts, label)
  for i = 1, #layouts do
    local a, b = layouts[i].eyes[1], layouts[i].eyes[2]
    -- Separating axis on x is conservative: clearing it proves no overlap.
    local function reach(e)
      local t = e.rot * pi / 180
      return abs(e.rx * cos(t)) + abs(e.ry * sin(t))
    end
    T.gt(abs(b.cx - a.cx), reach(a) + reach(b), label .. ": eyes fused")
  end
end

local function checkDecoration(layouts, label)
  for i = 1, #layouts do
    local l = layouts[i]
    for k = 1, #l.petals do
      local p = l.petals[k]
      local d = util.hypot(p.cx - l.body.cx, p.cy - l.body.cy)
      -- Overlapping the core is what makes the union read as one creature.
      T.lt(d, l.body.rx * 0.95 + p.r, label .. ": decoration detached from the body")
    end
  end
end

----------------------------------------------------------------------

describe("the frame", function()
  test("all geometry stays inside the viewBox", function()
    for i = 1, #SEEDS do
      pathNumbers(blobatar.svg(SEEDS[i], { background = false }), function(n)
        T.gte(n, 0)
        T.lte(n, 100)
      end)
    end
  end)

  test("every expression keeps the figure in the frame", function()
    for _, name in ipairs(expression.names) do
      for i = 1, min(400, #SEEDS) do
        local svg = blobatar.svg(SEEDS[i], { expression = name })
        T.ok(not svg:find("nan"), "NaN in path data")
        -- A pose translates the whole creature, so the check is against the
        -- frame plus that offset rather than against the frame.
        local bdy = abs(expression.byName[name].p.bdy)
        pathNumbers(svg, function(n)
          T.gte(n, -bdy - 0.01)
          T.lte(n, 100 + bdy + 0.01)
        end)
      end
    end
  end)
end)

describe("blob", function()
  local layouts = {}
  for i = 1, #SEEDS do layouts[i] = blob.layout(traits(SEEDS[i])) end

  test("eyes sit inside the body core", function()
    checkContainment(layouts, "seeded")
  end)

  test("eyes never fuse into each other", function()
    checkFusion(layouts, "seeded")
  end)

  test("decoration stays attached to the body", function()
    checkDecoration(layouts, "seeded")
  end)

  test("every shape in the vocabulary is reachable", function()
    local seen = {}
    for i = 1, #layouts do seen[layouts[i].shape] = true end
    for _, s in ipairs({ "round", "organic", "boxy", "nub", "cloud", "sun" }) do
      T.ok(seen[s], "shape never drawn: " .. s)
    end
  end)

  test("common shapes stay common", function()
    local round, sun = 0, 0
    for i = 1, #layouts do
      if layouts[i].shape == "round" then round = round + 1 end
      if layouts[i].shape == "sun" then sun = sun + 1 end
    end
    T.gt(round / #layouts, 0.2)
    T.lt(sun / #layouts, 0.12)
  end)
end)

--- The same invariants, under configuration rather than under seeds.
---
--- This is the test that makes trait overrides safe to expose. Hashing spreads
--- values out, so thousands of seeds sample the interior of the space densely
--- and its corners barely at all, but a caller writing an override map goes
--- straight to the corners, because "biggest eyes, widest gap, roundest body" is
--- the first thing anyone tries.
describe("blob under trait overrides", function()
  --- Every trait key the style reads, including the indexed families it only
  --- reaches for some shapes. A list rather than something derived, because a
  --- list scraped from the implementation would agree with the implementation by
  --- construction, including where the implementation is wrong.
  local KEYS = {
    "shape", "hue", "tone",
    "body.r", "body.ratio", "body.x", "body.y", "body.n", "body.rot", "body.pts",
    "gaze.x", "gaze.y",
    "eye.rx", "eye.ratio", "eye.scale", "eye.stretch", "eye.gap", "eye.n",
    "eye.lean", "eye.lean2", "eye.dy",
    "sun.n", "sun.dist", "sun.r", "sun.rot",
    "cloud.n",
    "nub.n", "nub.a0", "nub.a1", "nub.r0", "nub.r1",
  }
  for i = 0, 7 do KEYS[#KEYS + 1] = "body.r" .. i end
  for i = 0, 5 do KEYS[#KEYS + 1] = "cloud.r" .. i end

  local MAPS = {}
  for _, v in ipairs({ 0, 0.5, 0.999999 }) do
    local all = {}
    for _, k in ipairs(KEYS) do all[k] = v end
    MAPS[#MAPS + 1] = all
    -- One key pushed to each end while the rest sit together: the pairwise
    -- corners that `fit` and the lean bound exist to survive.
    for _, k in ipairs(KEYS) do
      local lo, hi = {}, {}
      for a, b in pairs(all) do lo[a] = b; hi[a] = b end
      lo[k] = 0
      hi[k] = 0.999999
      MAPS[#MAPS + 1] = lo
      MAPS[#MAPS + 1] = hi
    end
  end
  -- And a deterministic scatter, for corners no single-key sweep reaches.
  local s = 1
  local bit32 = require("blobatar.bit32")
  for _ = 1, 400 do
    local m = {}
    for _, k in ipairs(KEYS) do
      s = (bit32.imul(s, 1664525) + 1013904223) % 4294967296
      m[k] = s / 4294967296
    end
    MAPS[#MAPS + 1] = m
  end

  local layouts = {}
  for i = 1, #MAPS do layouts[i] = blob.layout(traits("cfg", true, MAPS[i])) end

  test("eyes sit inside the body core", function()
    checkContainment(layouts, "override")
  end)

  test("eyes never fuse into each other", function()
    checkFusion(layouts, "override")
  end)

  test("decoration stays attached to the body", function()
    checkDecoration(layouts, "override")
  end)

  test("all geometry stays inside the viewBox", function()
    for i = 1, #MAPS do
      local svg = blobatar.svg("cfg", { traits = MAPS[i], background = false })
      T.ok(not svg:lower():find("nan"), "NaN in path data")
      pathNumbers(svg, function(n)
        T.gte(n, 0)
        T.lte(n, 100)
      end)
    end
  end)
end)

describe("path emission", function()
  local function numbers(path)
    local out = {}
    for _, op in ipairs(path) do
      for i = 2, #op do out[#out + 1] = op[i] end
    end
    return out
  end

  test("superellipse coordinates stay finite for the whole n range", function()
    local n = 1.6
    while n <= 8 do
      for _, v in ipairs(numbers(shape.superellipse({ cx = 50, cy = 50, rx = 30, ry = 30, n = n }))) do
        T.ok(v == v and v ~= math.huge and v ~= -math.huge, "non-finite coordinate at n=" .. n)
      end
      n = n + 0.1
    end
  end)

  test("the 45-degree control constant matches the circle case exactly", function()
    -- n=2 must reproduce the standard 0.5523 kappa, or the derivation is wrong.
    local d = svgmod.pathdata(shape.superellipse({ cx = 0, cy = 0, rx = 100, ry = 100, n = 2 }))
    T.ok(d:find("55.23", 1, true), "kappa is not 0.5523 at n=2")
  end)

  test("control points never overshoot the bounding box", function()
    local n = 1.6
    while n <= 8 do
      for _, v in ipairs(numbers(shape.superellipse({ cx = 50, cy = 50, rx = 40, ry = 40, n = n }))) do
        T.gte(v, 9.9)
        T.lte(v, 90.1)
      end
      n = n + 0.1
    end
  end)

  test("blobPath interpolates its vertices exactly", function()
    -- Catmull-Rom passes through its points, which is what makes the radii mean
    -- what they say and containment predictable.
    local d = svgmod.pathdata(shape.blobPath(50, 50, 20, 20, { 1, 1, 1, 1 }, 0))
    T.ok(d:sub(1, 8) == "M70 50C7" or d:sub(1, 6) == "M70 50", "does not start at the first vertex")
    T.ok(d:find("50 70", 1, true), "misses the vertex at 50 70")
    T.ok(d:find("30 50", 1, true), "misses the vertex at 30 50")
  end)

  test("blobPath closes and stays within its radii", function()
    local radii = { 1.1, 0.9, 1.05, 0.95, 1.12, 0.88 }
    local d = svgmod.pathdata(shape.blobPath(50, 50, 20, 20, radii, 0))
    T.eq(d:sub(-1), "Z")
    for v in d:gmatch("%-?%d+%.?%d*") do
      T.gt(tonumber(v), 50 - 20 * 1.5)
      T.lt(tonumber(v), 50 + 20 * 1.5)
    end
  end)
end)

describe("palette", function()
  test("every hue and tone clears the contrast floors", function()
    for h = 0, 359 do
      for _, tone in ipairs({ 0, 0.1, 0.25, 0.3, 0.45, 0.5, 0.7, 0.75, 0.85, 0.9, 0.95, 0.99 }) do
        local r = color.ramp(h, true, tone)
        for _, floor in ipairs(color.FLOORS) do
          T.gte(color.contrast(r[floor[1]], r[floor[2]]), floor[3] - 1e-9,
                string.format("hue %d tone %g: %s on %s", h, tone, floor[1], floor[2]))
        end
      end
    end
  end)

  test("every hue resolves to a valid 6-digit hex", function()
    for h = 0, 359, 3 do
      local p = color.palette(h)
      for _, k in ipairs(color.KEYS) do
        T.matches(p[k], "^#%x%x%x%x%x%x$")
      end
    end
  end)

  test("eye polarity follows the body across every tone", function()
    for h = 0, 359, 7 do
      for _, tone in ipairs({ 0.1, 0.3, 0.5, 0.7, 0.9, 0.97 }) do
        local r = color.ramp(h, true, tone)
        T.eq(r.eye.l < 0.5, r.head.l >= 0.5, "eye polarity does not follow the body")
        T.gte(color.contrast(r.eye, r.head), 4.5 - 1e-9)
      end
    end
  end)

  test("the tone set spans pale to dark", function()
    local seen, lo, hi = {}, 1, 0
    for _, tone in ipairs({ 0.1, 0.3, 0.5, 0.7, 0.9, 0.97 }) do
      local l = color.ramp(0, false, tone).head.l
      seen[string.format("%.4f", l)] = true
      lo = min(lo, l)
      hi = max(hi, l)
    end
    T.lt(lo, 0.4)
    T.gt(hi, 0.85)
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    T.eq(n, 6, "the six tones are not six distinct lightnesses")
  end)

  test("pale tones survive enforcement rather than being darkened away", function()
    for h = 0, 359, 5 do
      T.gt(color.ramp(h, true, 0.3).head.l, 0.85)
    end
  end)
end)

describe("tints", function()
  local HEATS = { 0, 0.25, 0.5, 0.75, 1 }

  test("the eye clears the body at 4.5:1 at every heat, hue, tone and target", function()
    for _, entry in ipairs(color.TINTS) do
      local name, tint = entry[1], entry[2]
      for h = 0, 359, 11 do
        for _, tone in ipairs({ 0.1, 0.3, 0.5, 0.7, 0.9, 0.97 }) do
          local p = color.palette(h, true, tone)
          local head, eye = color.tinted(p.head, p.eye, tint)
          for _, heat in ipairs(HEATS) do
            local a = color.fromHex(color.mixHex(p.eye, eye, heat))
            local b = color.fromHex(color.mixHex(p.head, head, heat))
            T.gte(color.contrast(a, b), 4.5,
                  string.format("%s at hue %d tone %g heat %g", name, h, tone, heat))
          end
        end
      end
    end
  end)

  test("heat 0 is the palette untouched", function()
    for _, entry in ipairs(color.TINTS) do
      local p = color.palette(210, true, 0.5)
      local head, eye = color.tinted(p.head, p.eye, entry[2])
      T.eq(color.mixHex(p.head, head, 0), p.head)
      T.eq(color.mixHex(p.eye, eye, 0), p.eye)
    end
  end)

  test("a tinted body arrives at its target hue", function()
    for _, entry in ipairs(color.TINTS) do
      local name, tint = entry[1], entry[2]
      for h = 0, 359, 23 do
        for _, tone in ipairs({ 0.1, 0.5, 0.9 }) do
          local p = color.palette(h, true, tone)
          local head = color.tinted(p.head, p.eye, tint)
          local c = color.fromHex(head)
          local off = abs(((c.h - tint.h + 180) % 360) - 180)
          T.lt(off, 6, name .. " hue " .. h .. " tone " .. tone)
          T.gt(c.c, 0.06, name .. " hue " .. h .. " tone " .. tone)
        end
      end
    end
  end)

  test("the tone set survives the trip rather than collapsing onto one colour", function()
    for _, entry in ipairs(color.TINTS) do
      local heads, seen, lo, hi = {}, {}, 1, 0
      for _, tone in ipairs({ 0.1, 0.3, 0.5, 0.7, 0.9, 0.97 }) do
        local p = color.palette(200, true, tone)
        local head = color.tinted(p.head, p.eye, entry[2])
        local l = color.fromHex(head).l
        seen[string.format("%.3f", l)] = true
        lo = min(lo, l)
        hi = max(hi, l)
      end
      local n = 0
      for _ in pairs(seen) do n = n + 1 end
      T.eq(n, 6, entry[1] .. ": tones collapsed")
      T.gt(hi - lo, 0.2, entry[1] .. ": tone spread lost")
    end
  end)
end)

describe("ensureContrast", function()
  test("rescues a pair that starts far too close", function()
    local bg = { l = 0.6, c = 0.1, h = 240 }
    local fg = { l = 0.62, c = 0.1, h = 240 }
    T.lt(color.contrast(fg, bg), 1.2)
    T.gte(color.contrast(color.ensureContrast(fg, bg, 4.5), bg), 4.5)
  end)

  test("keeps the direction it is already leaning", function()
    local bg = { l = 0.9, c = 0.05, h = 30 }
    local fg = { l = 0.85, c = 0.05, h = 30 }
    T.lt(color.ensureContrast(fg, bg, 4.5).l, fg.l) -- darker, not flipped
  end)

  test("flips direction when the lean runs out of range", function()
    local bg = { l = 0.05, c = 0.02, h = 30 }
    local fg = { l = 0.04, c = 0.02, h = 30 }
    T.gte(color.contrast(color.ensureContrast(fg, bg, 7), bg), 7)
  end)

  test("leaves an already-passing pair untouched", function()
    local bg = { l = 0.95, c = 0.02, h = 30 }
    local fg = { l = 0.1, c = 0.02, h = 30 }
    -- The same table back, not a copy: nothing to do is nothing done.
    T.eq(color.ensureContrast(fg, bg, 4.5), fg)
  end)
end)

describe("determinism", function()
  test("the same name renders the same blobatar", function()
    for i = 1, min(500, #SEEDS) do
      T.eq(blobatar.svg(SEEDS[i]), blobatar.svg(SEEDS[i]))
    end
  end)

  test("names a human considers equal hash equally", function()
    local pairs_ = {
      { "Alain@Example.COM", "alain@example.com" },
      { "  alain  ", "alain" },
      { "caf\195\169", "cafe\204\129" },      -- precomposed vs decomposed
      { "\195\137COLE", "\195\169cole" },     -- ECOLE vs ecole
    }
    for _, p in ipairs(pairs_) do
      T.eq(blobatar.svg(p[1]), blobatar.svg(p[2]),
           "normalization did not fold " .. p[1] .. " onto " .. p[2])
    end
  end)

  test("normalize false leaves the seed alone", function()
    T.ok(blobatar.svg("Alain", { normalize = false }) ~= blobatar.svg("alain", { normalize = false }))
  end)

  test("neighbouring names produce unrelated blobatars", function()
    -- Avalanche. Plain FNV-1a does not give you this; the murmur3 finalizer does.
    local a = hash.seedState("alain")
    local b = hash.seedState("alaim")
    local differing = 0
    for bit = 0, 31 do
      local pa = math.floor(a / 2 ^ bit) % 2
      local pb = math.floor(b / 2 ^ bit) % 2
      if pa ~= pb then differing = differing + 1 end
    end
    T.gt(differing, 8, "one-character change moved only " .. differing .. " bits")
  end)
end)

describe("traits", function()
  test("overrides are clamped rather than trusted", function()
    local t = traits("x", true, { a = 2, b = -1, c = 0, d = 0 / 0 })
    T.near(t("a"), 0.999999, 1e-12)
    T.eq(t("b"), 0)
    T.eq(t("c"), 0)
    T.eq(t("d"), 0, "NaN did not fall to 0")
  end)

  test("an override of 1 does not index past the end of a pick list", function()
    local t = traits("x", true, { k = 1 })
    T.eq(t.pick("k", { "a", "b", "c" }), "c")
    T.eq(t.int("k", 6, 8), 8)
  end)

  test("adding a trait key leaves the others alone", function()
    local t = traits("alain")
    local before = t("shape")
    local _ = t("something.new")
    T.eq(t("shape"), before)
  end)

  test("values land in the range they are declared over", function()
    for i = 1, min(2000, #SEEDS) do
      local t = traits(SEEDS[i])
      local v = t.num("body.r", 31, 38)
      T.gte(v, 31)
      T.lt(v, 38)
      local n = t.int("body.pts", 6, 8)
      T.ok(n == 6 or n == 7 or n == 8, "int outside its range: " .. n)
    end
  end)
end)

describe("options", function()
  test("size emits width and height", function()
    T.ok(blobatar.svg("a", { size = 48 }):find('width="48" height="48"', 1, true))
    T.ok(not blobatar.svg("a"):find("width=", 1, true))
  end)

  test("hue locks colour without touching shape", function()
    local a = blobatar.layout("alain", { hue = 200 })
    local b = blobatar.layout("alain", { hue = 20 })
    T.eq(a.body.rx, b.body.rx)
    T.ok(a.palette.head ~= b.palette.head)
  end)

  test("a palette override bypasses the ramp", function()
    local svg = blobatar.svg("alain", { palette = { head = "#123456" } })
    T.ok(svg:find('fill="#123456"', 1, true))
  end)

  test("the backdrop is off by default and drawable on request", function()
    T.ok(not blobatar.svg("alain"):find('d="M0 0H100V100H0Z"', 1, true))
    T.ok(blobatar.svg("alain", { background = "square" }):find('d="M0 0H100V100H0Z"', 1, true))
    T.ok(blobatar.svg("alain", { background = true }):find("<path", 1, true))
  end)

  test("a title is escaped", function()
    T.ok(blobatar.svg("a", { title = "A & B <c>" }):find("<title>A &amp; B &lt;c&gt;</title>", 1, true))
  end)

  test("idle renders byte-identical markup to no expression at all", function()
    for i = 1, 50 do
      T.eq(blobatar.svg(SEEDS[i], { expression = "idle" }), blobatar.svg(SEEDS[i]))
    end
  end)
end)

describe("the uri form", function()
  test("percent-encodes only what breaks inside an attribute", function()
    local u = blobatar.uri("alain")
    T.ok(u:sub(1, 19) == "data:image/svg+xml,", "wrong prefix")
    T.ok(not u:find('"', 1, true), "double quotes survived")
    T.ok(not u:find("<", 1, true), "angle brackets survived")
    T.ok(not u:find("#", 1, true), "a hash survived, which would truncate the URI")
  end)
end)

os.exit(T.run() == 0 and 0 or 1)
