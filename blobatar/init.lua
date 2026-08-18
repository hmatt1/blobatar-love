--- blobatar: deterministic geometric avatars from any string.
---
--- A port of https://github.com/Alain00/blobatar to pure Lua, with a LOVE
--- renderer on top. The same name renders the same blobatar here as it does
--- there: the hash, the trait ranges, the shape thresholds, the tone set and the
--- expression roster are all the same numbers, and `test/parity.lua` diffs the
--- rendered geometry against the original's output to keep it that way.
---
---   local blobatar = require("blobatar")
---
---   -- LOVE
---   local b = blobatar.new("alain@example.com")
---   function love.update(dt) b:update(dt) end
---   function love.draw() b:draw(20, 20, 96) end
---
---   -- anywhere
---   local svg = blobatar.svg("alain@example.com", { size = 96 })
---
--- `blobatar.love` is loaded on demand, so requiring this outside LOVE is fine.

local PREFIX = ...
local req = function(name) return require(PREFIX .. "." .. name) end

local blob = req("style.blob")
local render = req("render")
local svg = req("svg")

local M = {
  VERSION = "0.2.0",
  --- The version of the JavaScript library this port tracks. The determinism
  --- guarantee is per major, so a blobatar drawn here matches one drawn by any
  --- 0.2.x of the original.
  UPSTREAM = "0.2.0",

  color = req("color"),
  traits = req("traits"),
  hash = req("hash"),
  shape = req("shape"),
  path = req("path"),
  expression = req("expression"),
  animate = req("animate"),
  style = { blob = blob },
  render = render,
  svgmod = svg,
  util = req("util"),
  utf8 = req("utf8x"),
}

--- The default style. Everything below is bound to it; pass a different style
--- table to the `render` functions directly to use another.
M.defaultStyle = blob

--- The resolved scene for a name: palette, layout, geometry, pose.
function M.scene(name, opts)
  return render.scene(M.defaultStyle, name, opts)
end

--- SVG markup for a name.
function M.svg(name, opts)
  return svg.render(M.scene(name, opts))
end

--- The animated markup for a name, for a host with `motion.css`. The static
--- renderer is what a game wants; this is what a web page wants.
function M.animatedSvg(name, opts, mode)
  opts = opts or {}
  mode = mode or "hover"
  local base = {}
  for k, v in pairs(opts) do base[k] = v end
  base.animate = mode
  return svg.animated(M.scene(name, base), mode)
end

--- A `data:image/svg+xml` URI for a name.
function M.uri(name, opts)
  return svg.uri(M.svg(name, opts))
end

--- The numeric layout and resolved palette, before drawing. For tests and for
--- callers that need a seed's `shape` in bulk.
function M.layout(name, opts)
  return render._layout(M.defaultStyle, name, opts)
end

--- Applies NFC + trim + lowercase, the same way the seed hasher does.
M.normalizeSeed = M.hash.normalizeSeed

--- A drawable, animated blobatar. Requires LOVE.
---
---   local b = blobatar.new("alain@example.com", { animate = "hover" })
---   b:update(dt)
---   b:draw(x, y, size)
function M.new(name, opts)
  return M.love.new(M, name, opts)
end

--- The LOVE backend, loaded on the first `new` rather than at require time, so
--- that the rest of the library runs in plain Lua.
setmetatable(M, {
  __index = function(t, k)
    if k ~= "love" then return nil end
    local mod = req("love")
    rawset(t, "love", mod)
    return mod
  end,
})

return M
