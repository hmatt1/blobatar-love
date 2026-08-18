--- SVG serialization, byte-identical to the original.
---
--- The LOVE renderer is what this port is for, so this file could reasonably not
--- exist. It exists for two reasons.
---
--- The first is verification. `test/parity.lua` renders thousands of seeds
--- through here and diffs the strings against what the TypeScript library emits
--- for the same seeds. Every coordinate in the geometry, every rounding decision
--- and every colour in the palette is in that string, so one comparison covers
--- the whole pipeline, and a difference points at a line rather than at a
--- vague "the avatars look different".
---
--- The second is that a game is not the only place a Lua program runs. Emitting
--- an `<img src>` payload from a Lua web service is the original library's job
--- description, and this is that job.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local req = function(name) return require(PREFIX == "" and name or (PREFIX .. "." .. name)) end

local util = req("util")
local expression = req("expression")

local M = {}

local numstr = util.numstr
local r2 = util.r2
local concat = table.concat

--- Path ops back to a `d` attribute, in the original's spelling: no separator
--- between an op letter and its first number, a single space between numbers.
function M.pathdata(path)
  local out = {}
  for i = 1, #path do
    local op = path[i]
    local kind = op[1]
    if kind == "M" then
      out[#out + 1] = "M" .. numstr(op[2]) .. " " .. numstr(op[3])
    elseif kind == "L" then
      out[#out + 1] = "L" .. numstr(op[2]) .. " " .. numstr(op[3])
    elseif kind == "H" then
      out[#out + 1] = "H" .. numstr(op[2])
    elseif kind == "V" then
      out[#out + 1] = "V" .. numstr(op[2])
    elseif kind == "C" then
      out[#out + 1] = "C" .. numstr(op[2]) .. " " .. numstr(op[3])
        .. " " .. numstr(op[4]) .. " " .. numstr(op[5])
        .. " " .. numstr(op[6]) .. " " .. numstr(op[7])
    elseif kind == "Q" then
      out[#out + 1] = "Q" .. numstr(op[2]) .. " " .. numstr(op[3])
        .. " " .. numstr(op[4]) .. " " .. numstr(op[5])
    elseif kind == "Z" then
      out[#out + 1] = "Z"
    end
  end
  return concat(out)
end

local function escape(s)
  return (s:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

--- The figure: decoration, core, then eyes.
---
--- Decoration first so the core sits on top and the eyes always land on it.
--- Petals are true circles, so `<circle>` costs about a quarter of what the
--- equivalent four-segment path would, and a sun carries up to nine of them
local function figure(scene, mo)
  local g = scene.geometry
  local out = { '<g fill="' .. scene.palette.head .. '">' }

  for i = 1, #g.petals do
    local d = g.petals[i]
    out[#out + 1] = '<circle cx="' .. numstr(r2(d.cx))
      .. '" cy="' .. numstr(r2(d.cy))
      .. '" r="' .. numstr(r2(d.r)) .. '"/>'
  end

  out[#out + 1] = '<path d="' .. M.pathdata(g.core) .. '"/>'
  out[#out + 1] = "</g>"

  -- The eye group already existed to share a fill, and it is exactly the element
  -- the saccade layer needs: both eyes must move as one, because independent
  -- movement reads as a lazy eye instantly.
  out[#out + 1] = '<g fill="' .. scene.palette.eye .. '"'
    .. (mo and ' class="mo-eyes"' or "") .. ">"

  for i = 1, #g.eyes do
    local path = '<path d="' .. M.pathdata(g.eyes[i]) .. '"/>'
    if mo then
      local e = scene.layout.eyes[i]
      out[#out + 1] = '<g class="mo-eye" style="--mo-wrap:' .. (i == 2 and 1 or -1)
        .. ";--mo-lean:" .. numstr(r2(e.rot))
        .. ";transform-origin:" .. numstr(r2(e.cx)) .. "px " .. numstr(r2(e.cy))
        .. 'px">' .. path .. "</g>"
    else
      out[#out + 1] = path
    end
  end

  out[#out + 1] = "</g>"

  local body = concat(out)
  if mo then
    return '<g class="mo-breathe"><g class="mo-bob">' .. body .. "</g></g>"
  end
  return body
end

M.figure = figure

--- The complete `<svg>` element for a scene.
function M.render(scene)
  local dim = scene.size and (' width="' .. numstr(scene.size)
    .. '" height="' .. numstr(scene.size) .. '"') or ""

  local out = {}
  if scene.title then out[#out + 1] = "<title>" .. escape(scene.title) .. "</title>" end
  if scene.backdrop then
    out[#out + 1] = '<path d="' .. M.pathdata(scene.backdrop.path)
      .. '" fill="' .. scene.backdrop.fill .. '"/>'
  end

  -- The pose wraps the figure but not the backdrop, for the same reason the
  -- motion groups sit inside the figure: a plate that scales and leans with the
  -- creature stops being a plate.
  local body = figure(scene, false)
  if scene.bdy ~= 0 then
    body = '<g transform="translate(0 ' .. numstr(util.r3(scene.bdy)) .. ')">'
      .. body .. "</g>"
  end
  out[#out + 1] = body

  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"' .. dim
    .. ">" .. concat(out) .. "</svg>"
end

--- The animated markup, as the React adapter assembles it.
---
--- The motion layer is a stylesheet over there, so an animated blobatar is this
--- markup plus `motion.css`: a root `<g>` carrying the mode class, and the seeded
--- timing and the pose as custom properties on the `<svg>`.
---
--- It exists here for the same reason `render` does. `test/motion_parity.lua`
--- loads this into a browser alongside the original's stylesheet, freezes the
--- clock at a known time, and compares the result against what `motion.lua`
--- computes for that same time, which is the only way to check a port of a
--- stylesheet against the stylesheet.
---
---   mode  "hover" or "always"
function M.animated(scene, mode, traits)
  local animate = req("animate")
  local vars, order = animate.motionVars(traits or scene.traits)

  -- The fills go out as custom properties on every animated blobatar, tinted
  -- when the pose tints, and identical to the markup's own attributes when it
  -- does not. Emitted unconditionally, because the stylesheet's `fill` rules
  -- have to resolve to something correct on a blobatar wearing no expression,
  -- and a `var()` that falls back to nothing makes `fill` inherit black.
  vars["--mo-head"] = scene.palette.head
  vars["--mo-eye"] = scene.palette.eye
  order[#order + 1] = "--mo-head"
  order[#order + 1] = "--mo-eye"

  local pv, po = expression.poseVars(scene.pose)
  for i = 1, #po do
    vars[po[i]] = pv[po[i]]
    order[#order + 1] = po[i]
  end

  local expressive = #po > 0 or (scene.expression and scene.expression.tint ~= nil)
  local cls = animate.rootClass(mode or "hover", expressive)

  local dim = scene.size and (' width="' .. numstr(scene.size)
    .. '" height="' .. numstr(scene.size) .. '"') or ""

  local out = {}
  if scene.title then out[#out + 1] = "<title>" .. escape(scene.title) .. "</title>" end
  if scene.backdrop then
    out[#out + 1] = '<path d="' .. M.pathdata(scene.backdrop.path)
      .. '" fill="' .. scene.backdrop.fill .. '"/>'
  end
  out[#out + 1] = '<g class="' .. cls .. '">' .. figure(scene, true) .. "</g>"

  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"' .. dim
    .. ' style="' .. animate.serializeVars(vars, order) .. '">'
    .. concat(out) .. "</svg>"
end

--- A `data:` URI suitable for an `<img src>`.
---
--- Percent-encoded rather than base64: base64 inflates payloads ~33%, while SVG
--- markup is mostly characters that survive percent-encoding untouched. Only the
--- characters that actually break inside an attribute are escaped.
function M.uri(svg)
  local s = svg:gsub('"', "'")
  s = s:gsub("[%%#<>{}|\\%^%[%]`]", function(c)
    return string.format("%%%02X", c:byte())
  end)
  s = s:gsub("%s+", " ")
  return "data:image/svg+xml," .. s
end

--- The `<svg>` contents and its motion custom properties, separately: the
--- original's `_parts`, for a host that owns the outer element.
---
--- The split is load-bearing over there: nothing that varies with the expression
--- may appear in `inner`, because React hands that to `dangerouslySetInnerHTML`
--- and a single byte of drift replaces the subtree, which kills the transition.
--- Nothing in Lua cares, but the shape is kept so the two libraries emit the same
--- markup.
function M.parts(scene, animate)
  local mo = nil
  if animate then
    local vars, order = expression.poseVars(scene.pose)
    mo = { vars = vars, order = order }
  end
  return {
    bg = scene.backdrop,
    inner = figure(scene, animate ~= nil and animate ~= false),
    vars = mo and mo.vars or nil,
    order = mo and mo.order or nil,
  }
end

return M
