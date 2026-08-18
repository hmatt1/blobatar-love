--- A soft body and two capsule eyes. A port of `src/styles/blob.ts`.
---
--- The silhouette carries the identity here, so it comes from a vocabulary of
--- six: a plain round, a tilted box, a lopsided organic pebble, a lumpy cloud, a
--- petalled sun, and a round body with a nub growing off it. Everything is drawn
--- in one fill color, which means overlapping parts union visually with no
--- boolean geometry and no clip paths. That works in LOVE for the same reason it
--- works in SVG, and for the same reason it stops working if you draw with a
--- non-opaque colour. See `love.lua`.
---
--- Every eye dimension is expressed as a fraction of the body radius rather than
--- in absolute units. Bodies here range from 22 to 38 units depending on how much
--- room the decoration needs, and absolute eye sizes would drift off a small sun
--- while looking lost on a large round.

-- Two levels up: this file is `<pkg>.style.blob` and its siblings are `<pkg>.*`.
local PREFIX = ((...):match("^(.*)%.[^.]*%.[^.]*$")) or ""
local req = function(name) return require(PREFIX == "" and name or (PREFIX .. "." .. name)) end

local shape_mod = req("shape")
local util = req("util")

local M = {}

local min, max, abs, asin, pi = math.min, math.max, math.abs, math.asin, math.pi
local floor = math.floor
local hypot = util.hypot

--- Weighted rather than uniform: rounds and pebbles are the everyday shapes, and
--- suns and clouds are the ones you want to be pleased to see. Thresholds are
--- frozen per major, exactly like a `pick` array.
local function shapeOf(v)
  if v < 0.28 then return "round" end
  if v < 0.58 then return "organic" end
  if v < 0.72 then return "boxy" end
  if v < 0.84 then return "nub" end
  if v < 0.93 then return "cloud" end
  return "sun"
end

M.shapeOf = shapeOf

--- How much of the frame the core body takes, leaving room for decoration.
local CORE = {
  round = 1,
  boxy = 0.86,
  organic = 0.98,
  cloud = 0.78,
  sun = 0.7,
  nub = 0.88,
}

--- The numeric layout for a set of traits, before any palette or drawing.
function M.layout(t)
  local shape = shapeOf(t("shape"))
  local r = t.num("body.r", 31, 38) * CORE[shape]
  local rx = r
  local ry = r * t.num("body.ratio", 0.92, 1.08)

  local radii = {}
  local pts = t.int("body.pts", 6, 8)
  for i = 0, pts - 1 do
    -- Lopsided by +/-16%, which is enough to read as hand-drawn and not so much
    -- that the eyes can end up on a bulge instead of the face. The key is
    -- 0-based because the original's array index is.
    radii[i + 1] = 1 + t.jitter("body.r" .. i, 0.16)
  end

  local body = {
    cx = 50 + t.jitter("body.x", 1.5),
    cy = 50 + t.jitter("body.y", 1.5),
    rx = rx,
    ry = ry,
    n = shape == "boxy" and t.num("body.n", 3.4, 6) or t.num("body.n", 1.9, 2.5),
    rot = shape == "boxy" and t.num("body.rot", -20, 20) or 0,
    radii = radii,
  }

  -- Where the eye pair sits as a unit. Gaze is deliberately a small effect: at
  -- blobatar sizes it reads as jitter rather than as direction, and the budget it
  -- used to spend is worth more in the gap below.
  local gx = t.jitter("gaze.x", 0.09) * rx
  local gy = t.num("gaze.y", -0.2, 0.08) * ry

  local er0 = t.num("eye.rx", 0.075, 0.105) * rx
  local ratio = t.num("eye.ratio", 1.9, 3.2)
  -- The second eye differs from the first in both overall size and in how tall
  -- it is for that size, drawn separately so a pair can read as big-and-round
  -- next to small-and-narrow rather than as one capsule scaled twice.
  local scale = t.num("eye.scale", 0.78, 1.24)
  local stretch = t.num("eye.stretch", 0.85, 1.18)

  -- The gap is measured from the eye's own edge outward, not from the body
  -- center. Drawn independently, a large eye and a small gap co-occur and
  -- produce two capsules crammed together with no room left to tilt, and
  -- because the lean bound below is derived from that clearance, those same
  -- seeds also came out untilted. Deriving the gap fixes both at once.
  local clearance = t.num("eye.gap", 0.1, 0.24) * rx
  -- Every bound below is taken over the larger of the two eyes, since either one
  -- can be the larger now.
  local wide = er0 * max(1, scale)
  local tall = er0 * ratio * max(1, scale * stretch)
  local gap0 = wide + rx * 0.03 + clearance

  -- Containment by construction rather than by hope. Each range is safe on its
  -- own, but their simultaneous extremes are not, and a 2000-seed test only
  -- samples that corner; it does not rule it out. Measuring the cluster against
  -- the tightest radius the body actually reaches and scaling it as a unit makes
  -- the guarantee hold across the whole space.
  local tight = 1
  if shape == "organic" or shape == "cloud" then
    local m = math.huge
    for i = 1, #radii do m = min(m, radii[i]) end
    tight = m * 0.95
  end
  local need = (abs(gx) + gap0 + hypot(wide, tall)) / rx
  local fit = need > tight * 0.9 and (tight * 0.9) / need or 1

  local er = er0 * fit
  local gap = gap0 * fit
  local eyeRy = er * ratio

  -- Lean is bounded by that clearance rather than drawn freely. A tall capsule
  -- tilted hard sweeps sideways by ry*sin(lean), and two of them meeting in the
  -- middle of the face is the one failure this style cannot survive. The 12
  -- degree ceiling is a taste bound on top of that geometric one: past roughly
  -- that much, the pair stops reading as a tilt and starts reading as a mistake.
  local MAX_LEAN = 12
  local room = max(0, min(1, (clearance * fit) / (tall * fit)))
  local bound = min(MAX_LEAN, asin(room) * 180 / pi)
  local lean = t.num("eye.lean", -1, 1) * bound
  -- The second eye's own tilt is clamped to the same ceiling so the difference
  -- between the two never pushes either past it.
  local lean2 = max(-MAX_LEAN, min(MAX_LEAN, lean + t.jitter("eye.lean2", 3.5)))

  -- Petals and lumps ride on a ring just outside the core, so they read as part
  -- of the same creature rather than as satellites.
  local petals = {}

  if shape == "sun" then
    local count = t.int("sun.n", 6, 9)
    local dist = r * t.num("sun.dist", 1.0, 1.08)
    local pr = r * t.num("sun.r", 0.2, 0.26)
    local off = t.num("sun.rot", 0, 2 * pi)
    for i = 0, count - 1 do
      local a = off + (2 * pi * i) / count
      petals[i + 1] = {
        cx = body.cx + math.cos(a) * dist,
        cy = body.cy + math.sin(a) * dist,
        r = pr,
      }
    end
  elseif shape == "cloud" then
    -- Lobes ride the upper half only, so the silhouette stays a cloud rather
    -- than a flower.
    local count = t.int("cloud.n", 4, 6)
    for i = 0, count - 1 do
      local a = pi + (pi * (i + 0.5)) / count
      petals[i + 1] = {
        cx = body.cx + math.cos(a) * r * 0.8,
        cy = body.cy + math.sin(a) * r * 0.5,
        r = r * t.num("cloud.r" .. i, 0.44, 0.62),
      }
    end
  elseif shape == "nub" then
    local count = t.int("nub.n", 1, 2)
    for i = 0, count - 1 do
      local a = t.num("nub.a" .. i, 0, 2 * pi)
      petals[i + 1] = {
        cx = body.cx + math.cos(a) * r * 0.88,
        cy = body.cy + math.sin(a) * r * 0.88,
        r = r * t.num("nub.r" .. i, 0.24, 0.4),
      }
    end
  end

  return {
    shape = shape,
    body = body,
    petals = petals,
    eyes = {
      {
        cx = body.cx + gx - gap,
        cy = body.cy + gy,
        rx = er,
        ry = eyeRy,
        n = t.num("eye.n", 3.5, 6),
        rot = lean,
      },
      {
        cx = body.cx + gx + gap,
        cy = body.cy + gy + t.jitter("eye.dy", 0.04) * ry,
        -- The far eye is slightly larger here, not smaller. It reads as
        -- personality rather than as a perspective mistake.
        rx = er * scale,
        ry = eyeRy * scale * stretch,
        n = t.num("eye.n", 3.5, 6),
        rot = lean2,
      },
    },
  }
end

--- The layout as drawable geometry: one core path, a list of petal circles, and
--- one path per eye.
---
--- This is the half of the original's `render` that decides *what* the shapes
--- are. The half that decides how they are written down lives in `svg.lua` and
--- `love.lua`, because those two disagree about everything except this.
function M.geometry(l)
  local b = l.body
  local core
  if l.shape == "organic" or l.shape == "cloud" then
    core = shape_mod.blobPath(b.cx, b.cy, b.rx, b.ry, b.radii,
                              l.shape == "cloud" and 0 or b.rot)
  else
    core = shape_mod.superellipse(b)
  end

  local eyes = {}
  for i = 1, #l.eyes do
    eyes[i] = shape_mod.superellipse(l.eyes[i])
  end

  return { core = core, petals = l.petals, eyes = eyes }
end

--- No backdrop by default. The body *is* the blobatar here, and a plate behind a
--- near-full-bleed shape just adds a rim of color that fights the silhouette.
M.background = false

return M
