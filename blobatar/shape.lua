--- The single primitive. A port of `src/shape.ts`.
---
--- |x/a|^n + |y/b|^n = 1 covers the whole part vocabulary: n=2 is an ellipse
--- (eyes, pupils), n~4 a squircle (head, background), n->large a rectangle
--- (brows, mouth lines). One shape function, one continuous knob, so "head
--- shape" is a numeric trait rather than a set of hand-drawn alternatives.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local util = require(PREFIX == "" and "util" or (PREFIX .. ".util"))

local M = {}

local cos, sin, pi = math.cos, math.sin, math.pi
local min = math.min
local r2 = util.r2

--- Approximates each quadrant with one cubic Bezier.
---
--- The control offset is chosen so the curve passes exactly through the
--- superellipse's 45 degree point: B(0.5) = a(4+3k)/8 must equal a*2^(-1/n).
--- At n=2 this yields 0.5523, the standard circle constant, which is a good
--- sign the derivation is right. Four segments instead of a 24-point sampled
--- polyline keeps each shape at ~130 bytes of path data.
---
--- `s` is `{ cx, cy, rx, ry, n, rot }`. `n` defaults to 4 and `rot` to 0, both
--- in the same units the original uses: squareness, and degrees clockwise.
function M.superellipse(s)
  local cx, cy, rx, ry = s.cx, s.cy, s.rx, s.ry
  local n = s.n or 4
  local rot = s.rot or 0

  -- Above n~5.55 the control offset exceeds the radius, and the curve bulges
  -- outside the bounding box instead of squaring off, an inflated-looking
  -- corner rather than a sharper one. Clamping k trades exactness at the 45
  -- degree point for a shape that always stays within its stated bounds; past
  -- that point a superellipse is visually a rounded rect anyway.
  local k = min(1, (8 * 2 ^ (-1 / n) - 4) / 3)
  local a, b = rx, ry
  local ak, bk = a * k, b * k

  -- Anchor, control, control: walking the four quadrants.
  local pts = {
    a, 0,
    a, bk, ak, b, 0, b,
    -ak, b, -a, bk, -a, 0,
    -a, -bk, -ak, -b, 0, -b,
    ak, -b, a, -bk, a, 0,
  }

  local t = rot * pi / 180
  local c, sn = cos(t), sin(t)
  local function at(i)
    local x, y = pts[i * 2 + 1], pts[i * 2 + 2]
    return r2(cx + x * c - y * sn), r2(cy + x * sn + y * c)
  end

  local path = {}
  local x, y = at(0)
  path[1] = { "M", x, y }
  local w = 1
  for i = 1, 12, 3 do
    local x1, y1 = at(i)
    local x2, y2 = at(i + 1)
    local x3, y3 = at(i + 2)
    w = w + 1
    path[w] = { "C", x1, y1, x2, y2, x3, y3 }
  end
  path[w + 1] = { "Z" }
  return path
end

--- A quadratic arc, stroked. Used only for smiles and frowns, where a closed
--- superellipse would need a boolean subtraction to get the same read. The blob
--- style draws neither, so nothing in this port calls it; it is here because it
--- is part of the module being ported.
function M.arc(cx, cy, w, depth)
  return {
    { "M", r2(cx - w), r2(cy) },
    { "Q", r2(cx), r2(cy + depth), r2(cx + w), r2(cy) },
  }
end

--- An organic closed curve: radii sampled around a circle, joined by a closed
--- Catmull-Rom spline converted to cubic Beziers.
---
--- The superellipse handles everything symmetric; this handles everything that
--- needs to look hand-drawn. `radii` are multipliers of the base radius, one per
--- vertex, so a seed perturbing them by +/-15% produces the lopsided pebble
--- shapes without any noise function. The vertex count alone controls how lumpy
--- it is.
---
--- Catmull-Rom rather than a Bezier fit because it interpolates its points
--- exactly, so the radii mean what they say and containment stays predictable.
function M.blobPath(cx, cy, rx, ry, radii, rot)
  rot = rot or 0
  local n = #radii
  local t0 = rot * pi / 180
  local px, py = {}, {}
  for i = 1, n do
    local a = t0 + (2 * pi * (i - 1)) / n
    px[i] = cx + rx * radii[i] * cos(a)
    py[i] = cy + ry * radii[i] * sin(a)
  end

  -- The original indexes with a wrapping modulo over 0-based positions; this is
  -- the same wrap shifted to Lua's 1-based arrays.
  local function at(i)
    local k = ((i - 1) % n + n) % n + 1
    return px[k], py[k]
  end

  local path = {}
  local ax, ay = at(1)
  path[1] = { "M", r2(ax), r2(ay) }

  for i = 1, n do
    local x0, y0 = at(i - 1)
    local x1, y1 = at(i)
    local x2, y2 = at(i + 1)
    local x3, y3 = at(i + 2)
    path[i + 1] = {
      "C",
      r2(x1 + (x2 - x0) / 6), r2(y1 + (y2 - y0) / 6),
      r2(x2 - (x3 - x1) / 6), r2(y2 - (y3 - y1) / 6),
      r2(x2), r2(y2),
    }
  end

  path[n + 2] = { "Z" }
  return path
end

return M
