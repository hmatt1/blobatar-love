--- A trait reader. A port of `src/traits.ts`.
---
--- Every value is addressed by a string key rather than drawn from a sequential
--- stream, so trait keys are an append-only namespace: introducing
--- `t.num("freckles.size", ...)` in a later version leaves every other trait,
--- and therefore every existing blobatar, exactly where it was.
---
--- The one thing that is NOT free to change is the contents of a `pick` array,
--- since option index is part of the mapping. Those are frozen per major.
---
--- The reader is a table with a `__call` metamethod rather than a function with
--- properties hung off it, because Lua functions carry no fields. Call sites read
--- the same either way: `t("shape")`, `t.num("body.r", 31, 38)`.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local hash = require(PREFIX == "" and "hash" or (PREFIX .. ".hash"))

local M = {}

local floor = math.floor

--- Builds a trait reader for `seed`.
---
--- `overrides` is a sparse map from trait key to the 0-1 position the hash would
--- otherwise have produced, so `{ shape = 0.95 }` means "always a sun, everything
--- else per seed".
---
--- Overrides are clamped rather than trusted. `pick` and `int` index and floor,
--- so a value of exactly 1 selects one past the end of an options list and one
--- past `max`. Anything that is not a number above 0 falls to 0 through the same
--- comparison, so a bad parse renders a blobatar instead of a path full of NaN.
function M.traits(seed, normalize, overrides)
  if normalize == nil then normalize = true end
  local state = hash.seedState(seed, normalize)

  local t = {}

  local function read(key)
    local o = overrides and overrides[key]
    if o == nil then return hash.stream(state, key) end
    if type(o) ~= "number" then return 0 end
    -- Written as the original writes it, comparison first, so that NaN, which
    -- fails every comparison, lands on 0 rather than propagating.
    if o > 0 then
      if o < 1 then return o end
      return 0.999999
    end
    return 0
  end

  setmetatable(t, { __call = function(_, key) return read(key) end })

  --- Uniform float in [min, max).
  function t.num(key, min, max)
    return min + read(key) * (max - min)
  end

  --- Uniform integer in [min, max].
  function t.int(key, min, max)
    return min + floor(read(key) * (max - min + 1))
  end

  --- Uniform choice. Appending to `options` remaps existing seeds.
  function t.pick(key, options)
    return options[floor(read(key) * #options) + 1]
  end

  --- True with probability `p`.
  function t.bool(key, p)
    return read(key) < (p or 0.5)
  end

  --- Symmetric jitter in [-amount, amount).
  function t.jitter(key, amount)
    return (read(key) * 2 - 1) * amount
  end

  return t
end

return M
