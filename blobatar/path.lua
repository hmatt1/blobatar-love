--- Paths, as data rather than as markup.
---
--- The original builds SVG `d` strings directly, because a browser is the only
--- consumer it has. Here there are two: `svg.lua`, which has to produce those
--- same strings byte for byte, and `love.lua`, which needs real vertices. So the
--- shape functions return this structure and each consumer reads it.
---
--- A path is a flat list of ops:
---
---   { "M", x, y }
---   { "L", x, y }
---   { "H", x }
---   { "V", y }
---   { "C", x1, y1, x2, y2, x, y }
---   { "Q", x1, y1, x, y }
---   { "Z" }
---
--- Coordinates are already rounded to two decimals when they arrive, at exactly
--- the point the original rounds them. That is deliberate: it keeps the drawn
--- geometry and the serialized geometry identical, so what LOVE fills is what a
--- browser would have filled rather than a more precise shape that only agrees
--- to within a rounding step.

local M = {}

local sqrt = math.sqrt
local max = math.max

----------------------------------------------------------------------
-- Flattening
----------------------------------------------------------------------

--- Distance from the chord, squared, for both control points. The standard
--- flatness test: when both controls sit on the line between the endpoints, the
--- curve is that line.
local function flat_enough(x0, y0, x1, y1, x2, y2, x3, y3, tol2)
  local ux = 3 * x1 - 2 * x0 - x3
  local uy = 3 * y1 - 2 * y0 - y3
  local vx = 3 * x2 - 2 * x3 - x0
  local vy = 3 * y2 - 2 * y3 - y0
  ux = ux * ux
  uy = uy * uy
  vx = vx * vx
  vy = vy * vy
  if vx > ux then ux = vx end
  if vy > uy then uy = vy end
  return ux + uy <= 16 * tol2
end

local function subdivide(out, x0, y0, x1, y1, x2, y2, x3, y3, tol2, depth)
  if depth > 16 or flat_enough(x0, y0, x1, y1, x2, y2, x3, y3, tol2) then
    out[#out + 1] = x3
    out[#out + 1] = y3
    return
  end
  local x01, y01 = (x0 + x1) / 2, (y0 + y1) / 2
  local x12, y12 = (x1 + x2) / 2, (y1 + y2) / 2
  local x23, y23 = (x2 + x3) / 2, (y2 + y3) / 2
  local xa, ya = (x01 + x12) / 2, (y01 + y12) / 2
  local xb, yb = (x12 + x23) / 2, (y12 + y23) / 2
  local xm, ym = (xa + xb) / 2, (ya + yb) / 2
  subdivide(out, x0, y0, x01, y01, xa, ya, xm, ym, tol2, depth + 1)
  subdivide(out, xm, ym, xb, yb, x23, y23, x3, y3, tol2, depth + 1)
end

--- Flattens a path to one closed polygon, as a flat `{x1, y1, x2, y2, ...}` list.
---
--- `tolerance` is the largest distance a straight segment may sit from the true
--- curve, in viewBox units. Every path this library makes is a single closed
--- contour, so one polygon out is the whole answer; a subpath would need a list
--- and nothing here produces one.
function M.flatten(path, tolerance)
  local tol = tolerance or 0.08
  local tol2 = tol * tol
  local out = {}
  local cx, cy = 0, 0
  local sx, sy = 0, 0

  for i = 1, #path do
    local op = path[i]
    local kind = op[1]
    if kind == "M" then
      cx, cy = op[2], op[3]
      sx, sy = cx, cy
      out[#out + 1] = cx
      out[#out + 1] = cy
    elseif kind == "L" then
      cx, cy = op[2], op[3]
      out[#out + 1] = cx
      out[#out + 1] = cy
    elseif kind == "H" then
      cx = op[2]
      out[#out + 1] = cx
      out[#out + 1] = cy
    elseif kind == "V" then
      cy = op[2]
      out[#out + 1] = cx
      out[#out + 1] = cy
    elseif kind == "C" then
      subdivide(out, cx, cy, op[2], op[3], op[4], op[5], op[6], op[7], tol2, 0)
      cx, cy = op[6], op[7]
    elseif kind == "Q" then
      -- Raised to a cubic; there is one quadratic in the library and this keeps
      -- the subdivision code single.
      local c1x = cx + 2 / 3 * (op[2] - cx)
      local c1y = cy + 2 / 3 * (op[3] - cy)
      local c2x = op[4] + 2 / 3 * (op[2] - op[4])
      local c2y = op[5] + 2 / 3 * (op[3] - op[5])
      subdivide(out, cx, cy, c1x, c1y, c2x, c2y, op[4], op[5], tol2, 0)
      cx, cy = op[4], op[5]
    elseif kind == "Z" then
      cx, cy = sx, sy
    end
  end

  -- A closed contour ends where it started; the duplicate point is a degenerate
  -- triangle to every triangulator that sees it.
  local n = #out
  if n >= 4 and out[n - 1] == out[1] and out[n] == out[2] then
    out[n] = nil
    out[n - 1] = nil
  end
  return out
end

--- Axis-aligned bounds of a flattened polygon.
function M.bounds(poly)
  local x0, y0 = math.huge, math.huge
  local x1, y1 = -math.huge, -math.huge
  for i = 1, #poly, 2 do
    local x, y = poly[i], poly[i + 1]
    if x < x0 then x0 = x end
    if x > x1 then x1 = x end
    if y < y0 then y0 = y end
    if y > y1 then y1 = y end
  end
  return x0, y0, x1, y1
end

--- Signed area, doubled. Positive is counter-clockwise in a y-up space and
--- clockwise in the y-down space an SVG viewBox uses.
function M.area2(poly)
  local a = 0
  local n = #poly
  local jx, jy = poly[n - 1], poly[n]
  for i = 1, n, 2 do
    local ix, iy = poly[i], poly[i + 1]
    a = a + (jx * iy - ix * jy)
    jx, jy = ix, iy
  end
  return a
end

return M
