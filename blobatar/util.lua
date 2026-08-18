--- The arithmetic the port needs to agree with JavaScript on.
---
--- Lua and JavaScript both hold doubles, so most operations agree bit for bit
--- without anyone doing anything. These are the ones that do not, and each one
--- is here because it changed a rendered number when it was written the obvious
--- way.

local M = {}

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt
local format = string.format

--- `Math.round`. Rounds half toward +Infinity, so `round(-2.5)` is -2 and not -3.
---
--- `floor(x + 0.5)` is that, except for arguments just under 0.5 where adding
--- 0.5 rounds up to exactly 1 and the floor comes out one too high. That is the
--- correction the second branch makes.
function M.round(x)
  if x ~= x then return x end -- NaN
  local r = floor(x + 0.5)
  if r - x > 0.5 then return r - 1 end
  return r
end

--- Two decimal places, the precision every coordinate in the path data carries.
function M.r2(v)
  return M.round(v * 100) / 100
end

function M.r3(v)
  return M.round(v * 1000) / 1000
end

--- `Math.hypot`, which is not `sqrt(a*a + b*b)`.
---
--- V8 normalizes by the larger magnitude and sums the squares with Kahan
--- compensation, and the result differs from the naive form in the last bit for
--- around a third of all inputs. `layout` divides by it and then rounds to two
--- decimals, so this almost never shows, but "almost never" over a hash space
--- is a bug report from somebody whose avatar does not match the web one, and
--- the fix is nine lines.
---
--- V8 is the target because a browser is where the original renders. It is worth
--- knowing that this is a choice rather than a standard: `Math.hypot` is
--- approximated rather than specified, and V8 and JavaScriptCore disagree about
--- its last bit for about a third of all inputs, so bun and node do not agree
--- with each other about the twelfth decimal of a blobatar either. Nothing
--- survives the rounding to two decimals in the path data; `test/parity.lua`
--- checks the markup byte for byte against both and finds no difference.
function M.hypot(a, b)
  a = abs(a)
  b = abs(b)
  local max = a > b and a or b
  if max == 0 then return 0 end
  local sum, comp = 0, 0
  local n = a / max
  local summand = n * n - comp
  local prelim = sum + summand
  comp = (prelim - sum) - summand
  sum = prelim
  n = b / max
  summand = n * n - comp
  prelim = sum + summand
  comp = (prelim - sum) - summand
  sum = prelim
  return sqrt(sum) * max
end

--- Cube root.
---
--- `x^(1/3)` alone is off by an ulp on about 15% of inputs because 1/3 is not
--- representable; one Halley step on top brings that down without needing to
--- take the double apart bit by bit, which Lua cannot portably do. The residual
--- disagreement with `Math.cbrt` is at most one ulp, and every consumer of this
--- rounds to a byte long before that could matter. `test/parity.lua` is what
--- says so rather than this comment.
function M.cbrt(x)
  if x == 0 then return x end
  local neg = x < 0
  if neg then x = -x end
  local y = x ^ (1 / 3)
  local y3 = y * y * y
  y = y - y * (y3 - x) / (y3 + y3 + x)
  if neg then return -y end
  return y
end

--- `String(number)`: the shortest decimal string that reads back as the same
--- double, which is what JavaScript prints and what the path data is compared
--- against.
---
--- Only reachable from the SVG serializer. Everything else works in numbers.
function M.numstr(v)
  if v ~= v then return "NaN" end
  if v == floor(v) and abs(v) < 1e15 then
    if v == 0 then return "0" end -- also folds -0
    return format("%d", v)
  end
  for p = 1, 17 do
    local s = format("%." .. p .. "g", v)
    if tonumber(s) == v then return s end
  end
  return format("%.17g", v)
end

--- Shallow copy, for the places the original writes `{ ...obj }`.
function M.copy(t, extra)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  if extra then
    for k, v in pairs(extra) do out[k] = v end
  end
  return out
end

return M
