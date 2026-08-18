--- 32-bit integer arithmetic, portable across Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT.
---
--- The hash in `hash.lua` is a bit-exact port of a JavaScript one, and JavaScript
--- does all of its bitwise work on 32-bit integers regardless of the double it
--- stores them in. Lua has no such rule: 5.1 and LuaJIT have only doubles, 5.3
--- and later have real 64-bit integers, and neither of those is 32 bits. So the
--- width is enforced here rather than assumed anywhere else.
---
--- Three implementations of xor are tried, best first: LuaJIT's `bit` library,
--- native `~` compiled at runtime on 5.3+, and a nibble table. The syntax for the
--- second one is a parse error on 5.1, which is why it goes through `load` on a
--- string rather than being written inline.
---
--- Every function here takes and returns an *unsigned* 32-bit number in [0, 2^32).
--- JavaScript's `Math.imul` and `<<` produce signed results, but the bit patterns
--- are identical and only the pattern feeds the next round, so working unsigned
--- throughout costs a `% 2^32` and saves a sign correction on every operation.

local M = {}

local floor = math.floor

local TWO32 = 4294967296

--- xor, resolved once at load.
local bxor

do
  local ok, bitlib = pcall(require, "bit") -- LuaJIT
  if ok and type(bitlib) == "table" and bitlib.bxor then
    local raw = bitlib.bxor
    -- LuaJIT returns a signed 32-bit result. Normalize it.
    bxor = function(a, b) return raw(a, b) % TWO32 end
  end
end

if not bxor then
  -- Lua 5.3+ native operators. Compiled from a string because `~` is a parse
  -- error on 5.1, and a parse error is not something pcall can catch at the
  -- call site of a file that contains it.
  local loader = load or loadstring
  local chunk = loader("return function(a, b) return (a ~ b) & 0xFFFFFFFF end")
  if chunk then
    local ok, fn = pcall(chunk)
    if ok and fn then
      local ok2 = pcall(fn, 1, 2)
      if ok2 then bxor = fn end
    end
  end
end

if not bxor then
  -- Pure Lua. One 16x16 nibble table, eight lookups per xor.
  local NIB = {}
  for i = 0, 15 do
    local row = {}
    for j = 0, 15 do
      local v, bitv = 0, 1
      for k = 0, 3 do
        local a = floor(i / bitv) % 2
        local b = floor(j / bitv) % 2
        if a ~= b then v = v + bitv end
        bitv = bitv * 2
      end
      row[j] = v
    end
    NIB[i] = row
  end

  bxor = function(a, b)
    a = a % TWO32
    b = b % TWO32
    local out, scale = 0, 1
    for _ = 1, 8 do
      out = out + NIB[a % 16][b % 16] * scale
      a = floor(a / 16)
      b = floor(b / 16)
      scale = scale * 16
    end
    return out
  end
end

M.bxor = bxor

--- `Math.imul`: a 32-bit multiply, truncated rather than rounded.
---
--- Split into 16-bit halves so no intermediate exceeds 2^48. That is the whole
--- trick: a plain `a * b` reaches 2^64 and loses its low bits to double rounding
--- on 5.1, which is exactly the half that survives the truncation.
function M.imul(a, b)
  a = a % TWO32
  b = b % TWO32
  local ah = floor(a / 65536)
  local al = a % 65536
  return ((ah * b) % 65536 * 65536 + al * b) % TWO32
end

--- `(h << n) | (h >>> (32 - n))` for unsigned h. The two halves share no bits,
--- so addition is the same as the OR the original spells it with.
function M.rotl(h, n)
  h = h % TWO32
  local lo = 2 ^ n
  return floor((h * lo) % TWO32 + floor(h / (TWO32 / lo)))
end

--- `h >>> n`.
function M.rshift(h, n)
  return floor((h % TWO32) / 2 ^ n)
end

return M
