--- Palette construction. A port of `src/color.ts`.
---
--- Hue is the only value the seed controls. Lightness and chroma are authored
--- constants, which is what makes every blobatar look like it came from the same
--- designer rather than from a random number generator.
---
--- Colors resolve to hex strings rather than staying in OKLCh. In the original
--- that was because server-side SVG rasterizers do not implement `oklch()`; here
--- it is because hex is what the contrast guarantee is enforced against. Doing
--- the conversion up front means the ratio is measured on real sRGB luminance
--- instead of assumed from OKLab lightness, which drifts by up to ~1.4:1 between
--- hues at equal L.
---
--- An Oklch is a plain table `{ l = , c = , h = }`. A palette is
--- `{ bg = "#rrggbb", head = ..., eye = ... }`.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local util = require(PREFIX == "" and "util" or (PREFIX .. ".util"))

local M = {}

local cos, sin, atan = math.cos, math.sin, math.atan
local min, max, abs = math.min, math.max, math.abs
local floor = math.floor
local cbrt, hypot, round = util.cbrt, util.hypot, util.round

local PI = math.pi
local DEG = 180 / PI

--- `math.atan(y, x)` is the two-argument form on 5.3+; 5.1 spells it `atan2`.
local atan2 = math.atan2 or function(y, x) return atan(y, x) end

--- The slots a blobatar has, in the order the ramp fills them. Iterating a Lua
--- table is unordered, and `palette()` has to produce the same three entries
--- every time for the tests to compare it.
M.KEYS = { "bg", "head", "eye" }

----------------------------------------------------------------------
-- OKLCh <-> sRGB
----------------------------------------------------------------------

--- OKLCh -> linear-light sRGB. Components may fall outside [0,1] (out of gamut).
local function toLinear(color)
  local r = color.h / DEG
  local a = color.c * cos(r)
  local b = color.c * sin(r)
  local l = color.l

  local l_ = l + 0.3963377774 * a + 0.2158037573 * b
  local m_ = l - 0.1055613458 * a - 0.0638541728 * b
  local s_ = l - 0.0894841775 * a - 1.291485548 * b

  local L = l_ * l_ * l_
  local Mm = m_ * m_ * m_
  local S = s_ * s_ * s_

  return 4.0767416621 * L - 3.3077115913 * Mm + 0.2309699292 * S,
         -1.2684380046 * L + 2.6097574011 * Mm - 0.3413193965 * S,
         -0.0041960863 * L - 0.7034186147 * Mm + 1.707614701 * S
end

local function inGamut(r, g, b)
  return r >= -1e-4 and r <= 1 + 1e-4
     and g >= -1e-4 and g <= 1 + 1e-4
     and b >= -1e-4 and b <= 1 + 1e-4
end

--- Resolves to in-gamut linear sRGB, reducing chroma if needed.
---
--- Chroma is the right axis to give up: lowering it desaturates, while clipping
--- channels shifts hue: a clipped vivid blue turns purple.
local function toRGB(color)
  local r, g, b = toLinear(color)
  if not inGamut(r, g, b) then
    local lo, hi = 0, color.c
    local probe = { l = color.l, c = 0, h = color.h }
    for _ = 1, 12 do
      local mid = (lo + hi) / 2
      probe.c = mid
      if inGamut(toLinear(probe)) then lo = mid else hi = mid end
    end
    probe.c = lo
    r, g, b = toLinear(probe)
  end
  return min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b))
end

--- WCAG relative luminance. The values coming out of `toRGB` are already
--- linear-light sRGB, which is exactly what WCAG's piecewise transfer function
--- produces, so this needs no further linearization.
local function luminance(color)
  local r, g, b = toRGB(color)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

function M.contrast(a, b)
  local x = luminance(a)
  local y = luminance(b)
  return (max(x, y) + 0.05) / (min(x, y) + 0.05)
end

--- Pushes `fg`'s lightness away from `bg` until the pair clears `min`.
---
--- Walks in the direction it is already leaning first, so a dark ink on a light
--- head gets darker rather than flipping to light. If that direction runs out of
--- range, it tries the other way before giving up at pure black or white.
function M.ensureContrast(fg, bg, minRatio)
  if M.contrast(fg, bg) >= minRatio then return fg end

  local lean = fg.l >= bg.l and 1 or -1
  for _, dir in ipairs({ lean, -lean }) do
    local probe = { l = fg.l, c = fg.c, h = fg.h }
    for _ = 1, 60 do
      probe.l = min(1, max(0, probe.l + dir * 0.02))
      if M.contrast(probe, bg) >= minRatio then return probe end
      if probe.l == 0 or probe.l == 1 then break end
    end
  end

  -- Unreachable for the authored ramps, but a palette override could get here.
  local black = { l = 0, c = 0, h = fg.h }
  local white = { l = 1, c = 0, h = fg.h }
  if M.contrast(black, bg) >= M.contrast(white, bg) then return black end
  return white
end

local function encode(v)
  local s = v <= 0.0031308 and 12.92 * v or 1.055 * v ^ (1 / 2.4) - 0.055
  return round(s * 255)
end

function M.toHex(color)
  local r, g, b = toRGB(color)
  return string.format("#%02x%02x%02x", encode(r), encode(g), encode(b))
end

--- sRGB hex -> OKLCh. The inverse of `toLinear` plus the encode above, and the
--- only way back into the color space from a palette that has already been
--- serialized.
---
--- It exists because a tint has to start from the colors that are actually on
--- screen, not from the ramp that produced them: a caller can override `head` or
--- `eye` outright, and a hot pair derived from the ramp instead would tint
--- toward a color the blobatar never wore.
function M.fromHex(hex)
  local n = tonumber(hex:sub(2), 16)
  local function decode(v)
    local s = v / 255
    if s <= 0.04045 then return s / 12.92 end
    return ((s + 0.055) / 1.055) ^ 2.4
  end
  local r = decode(floor(n / 65536) % 256)
  local g = decode(floor(n / 256) % 256)
  local b = decode(n % 256)

  local l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  local m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  local s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

  local A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
  local B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s

  return {
    l = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    c = hypot(A, B),
    h = atan2(B, A) * DEG,
  }
end

--- Blend two colors in OKLab: `color-mix(in oklab, a, b t)`, done here.
---
--- Interpolating in OKLab means lerping cartesian `a`/`b`, not the polar `c`/`h`
--- this module otherwise speaks. A hue lerp would swing a desaturated color
--- around the wheel and pick up chroma that is in neither endpoint.
function M.mix(a, b, t)
  local ax = a.c * cos(a.h / DEG)
  local ay = a.c * sin(a.h / DEG)
  local bx = b.c * cos(b.h / DEG)
  local by = b.c * sin(b.h / DEG)
  local x = ax + (bx - ax) * t
  local y = ay + (by - ay) * t
  return {
    l = a.l + (b.l - a.l) * t,
    c = hypot(x, y),
    h = atan2(y, x) * DEG,
  }
end

--- `mix` between two serialized colors, serialized.
function M.mixHex(a, b, t)
  return M.toHex(M.mix(M.fromHex(a), M.fromHex(b), t))
end

----------------------------------------------------------------------
-- Tints
----------------------------------------------------------------------

--- Where a tinting pose is heading: `{ h, l, pull, c }`.
---
--- Four numbers rather than an authored colour, because the endpoint has to be
--- derived per seed. A tint says *which way*, and the blobatar's own palette says
--- where that lands.
---
--- `h` is the hue the body arrives at, `l` the lightness it heads toward, `pull`
--- how far of the way to `l` it actually travels, and `c` a chroma floor so the
--- body never desaturates on the way.

--- Red, because every reference for anger is, and only 60% of the way there in
--- lightness so the tone set survives the trip.
M.HOT = { h = 27, l = 0.58, pull = 0.6, c = 0.18 }
M.ROSE = { h = 358, l = 0.72, pull = 0.55, c = 0.16 }
M.BLUSH = { h = 12, l = 0.84, pull = 0.4, c = 0.1 }
M.BILE = { h = 142, l = 0.66, pull = 0.6, c = 0.13 }

--- Every target the suite has to hold the contrast guarantee across.
M.TINTS = {
  { "hot", M.HOT },
  { "rose", M.ROSE },
  { "blush", M.BLUSH },
  { "bile", M.BILE },
}

--- A hair over the 4.5:1 the suite asserts. The margin is for 8-bit
--- quantization and nothing else.
local TINT_FLOOR = 4.55

--- The darkest host surface a backdrop-less blob is expected to land on, and the
--- ratio it must clear against it.
---
--- `FLOORS` can only relate colors that are in the palette, and the surface never
--- is: the style ships with its backdrop off, so the body sits directly on
--- whatever the page provides. Guaranteeing contrast against the palette's own
--- light `bg` says nothing about that case, which is how the ink tone came to
--- render as a near-invisible silhouette on a dark page.
local DARK_SURFACE = { l = 0.145, c = 0, h = 0 } -- about #0a0a0b
local SURFACE_FLOOR = 1.5

--- The palette a tinting pose heads toward, given the one it is tinting from.
---
--- Derived per seed rather than being a single authored colour, and the reason is
--- polarity: the style flips its eye between near-black and near-white depending
--- on the body's lightness, and no fixed red clears 4.5:1 against both.
---
--- So the tinted body meets its target partway. Holding the body's own lightness
--- is too quiet. A pastel goes pink rather than angry. Travelling the whole way
--- is the opposite failure: every blobatar converges on one red and the tone set,
--- which is most of what makes a grid look like a crowd, disappears at the exact
--- moment the grid is loudest.
---
--- The eye endpoint is then pushed until every point along the mix clears the
--- floor, not merely both ends. A straight line in OKLab between two passing
--- pairs is not itself a passing pair: the body travels further than the eye, so
--- the two lightnesses can close on each other in the middle of a transition
--- that is legible at both stops.
function M.tinted(head, eye, t)
  local base = M.fromHex(head)
  local baseEye = M.fromHex(eye)

  -- Chroma is floored rather than replaced: a body that is already vivid should
  -- not lose saturation on the way, and the pale neutral swatch has almost none
  -- to keep.
  local hotHead = {
    l = base.l + (t.l - base.l) * t.pull,
    c = max(base.c, t.c),
    h = t.h,
  }
  hotHead = M.ensureContrast(hotHead, DARK_SURFACE, SURFACE_FLOOR)

  local hotEye = M.ensureContrast(baseEye, hotHead, TINT_FLOOR)

  local dir = hotEye.l >= hotHead.l and 1 or -1
  local headHex = M.toHex(hotHead)
  for _ = 1, 40 do
    local eyeHex = M.toHex(hotEye)
    local worst = math.huge
    for i = 0, 10 do
      local k = i / 10
      worst = min(worst, M.contrast(
        M.fromHex(M.mixHex(eye, eyeHex, k)),
        M.fromHex(M.mixHex(head, headHex, k))
      ))
    end
    if worst >= TINT_FLOOR then return headHex, eyeHex end
    local l = min(1, max(0, hotEye.l + dir * 0.02))
    if l == hotEye.l then return headHex, eyeHex end
    hotEye = { l = l, c = hotEye.c, h = hotEye.h }
  end

  return headHex, M.toHex(hotEye)
end

----------------------------------------------------------------------
-- The ramp
----------------------------------------------------------------------

--- The tone set.
---
--- The one place the seed is allowed to move lightness and chroma, not just hue.
--- A body vocabulary this varied looks monotonous in a single tone. Letting
--- the seed roam freely over L and C is what makes generated palettes look
--- generated, so instead it picks from six authored swatches.
---
--- Thresholds are cumulative, so pale and mid tones dominate and the near-black
--- body stays a rare find.
local TONES = {
  { 0.2, { l = 0.86, c = 0.085 } },  -- pastel
  { 0.36, { l = 0.9, c = 0.028 } },  -- pale neutral
  { 0.62, { l = 0.73, c = 0.135 } }, -- mid
  { 0.8, { l = 0.62, c = 0.165 } },  -- deep
  { 0.93, { l = 0.87, c = 0.16 } },  -- bright
  -- Dark, but not darker than a dark host surface. At l 0.17 this swatch scored
  -- 1.03:1 against a near-black page and the body simply vanished, leaving two
  -- floating eyes. l 0.34 still reads as the ink tone and clears both ends.
  { 1.0, { l = 0.34, c = 0.035 } },  -- ink
}

local function toneAt(v)
  for i = 1, #TONES do
    if v < TONES[i][1] then return TONES[i][2] end
  end
  return TONES[1][2]
end

--- Minimum contrast ratios as {foreground, background, ratio}, applied in order.
--- Later pairs resolve against already-final earlier colors, so the chain
--- converges. 4.5 on the eyes is the WCAG text floor: they are small marks that
--- have to read at 24px.
---
--- The body/backdrop floor is deliberately weak. The backdrop is off by default,
--- and the pale swatches are meant to sit quietly on a light surface, forcing
--- 1.6:1 there would darken exactly the tones the style exists for.
M.FLOORS = {
  { "head", "bg", 1.25 },
  { "eye", "head", 4.5 },
}

--- The palette in OKLCh, before hex encoding.
function M.ramp(hue, enforce, tone)
  if enforce == nil then enforce = true end
  tone = tone or 0

  local t = toneAt(tone)
  local head = M.ensureContrast({ l = t.l, c = t.c, h = hue }, DARK_SURFACE, SURFACE_FLOOR)

  local r = {
    bg = { l = 0.965, c = 0.01, h = hue },
    head = head,
    -- Polarity follows the body: dark eyes on a light body, light eyes on a
    -- dark one. Without this the ink tone would render an invisible face.
    eye = head.l >= 0.5 and { l = 0.17, c = 0.02, h = hue }
                        or { l = 0.97, c = 0.012, h = hue },
  }

  if enforce then
    for i = 1, #M.FLOORS do
      local fg, bg, ratio = M.FLOORS[i][1], M.FLOORS[i][2], M.FLOORS[i][3]
      r[fg] = M.ensureContrast(r[fg], r[bg], ratio)
    end
  end

  return r
end

function M.palette(hue, enforce, tone)
  local r = M.ramp(hue, enforce, tone)
  local out = {}
  for i = 1, #M.KEYS do
    local k = M.KEYS[i]
    out[k] = M.toHex(r[k])
  end
  return out
end

return M
