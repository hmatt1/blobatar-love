--- Seed to palette to geometry. A port of the parts of `src/render.ts` that are
--- not about serializing markup.
---
--- The original binds a style into a function that returns a string. Here it
--- binds a style into a function that returns a *scene*: the same numbers, in a
--- structure both `svg.lua` and `love.lua` can consume. Everything above this
--- line in the original (traits, palette, pose, backdrop) is identical.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local req = function(name) return require(PREFIX == "" and name or (PREFIX .. "." .. name)) end

local traits = req("traits")
local color = req("color")
local shape = req("shape")
local expression = req("expression")
local util = req("util")

local M = {}

--- Options, all optional:
---
---   size        emits width/height on the SVG; ignored when drawing in LOVE,
---               where the draw call states the size
---   background  false, true, "square", "circle" or "squircle". Overrides the
---               style's default, which for the blob style is off
---   palette     overrides specific palette entries. Overridden colors bypass
---               the contrast guarantee, by definition
---   hue         locks the hue in degrees, so the name drives shape only
---   tone        locks the tone as a 0-1 position in the swatch set
---   traits      pins individual traits, each as the 0-1 position the hash would
---               have produced for that key
---   normalize   applies NFC + trim + lowercase to the name. Default true
---   contrast    enforces the minimum contrast ratios. Default true
---   title       adds a <title> for screen readers, in the SVG output
---   expression  which pose the blobatar holds, as a value or a name

--- Traits and palette for a seed, before any geometry.
function M.resolve(seed, opts)
  opts = opts or {}
  local normalize = opts.normalize
  if normalize == nil then normalize = true end
  local enforce = opts.contrast
  if enforce == nil then enforce = true end

  local t = traits.traits(seed, normalize, opts.traits)

  local hue = opts.hue
  if hue == nil then hue = t.num("hue", 0, 360) end
  local tone = opts.tone
  if tone == nil then tone = t("tone") end

  local pal = color.palette(hue, enforce, tone)
  if opts.palette then
    for k, v in pairs(opts.palette) do pal[k] = v end
  end

  return t, pal
end

--- The plate behind the figure, as geometry rather than as markup.
function M.backdrop(style, opts, pal)
  local bg = opts.background
  if bg == nil then bg = style.background end
  if bg == false then return nil end

  local path
  if bg == "square" then
    path = { { "M", 0, 0 }, { "H", 100 }, { "V", 100 }, { "H", 0 }, { "Z" } }
  else
    path = shape.superellipse({
      cx = 50, cy = 50, rx = 50, ry = 50,
      n = bg == "circle" and 2 or 6,
    })
  end

  -- A palette is partial because each style fills only the slots it needs, but
  -- every ramp fills `bg`, and a backdrop with no colour is not a thing this
  -- can be asked to draw.
  return { path = path, fill = pal.bg, kind = bg == true and "squircle" or bg }
end

--- Everything a renderer needs, resolved.
---
--- `pose` is the expression's channel table, always present and equal to the
--- identity when there is none. `bdy` is the whole-creature offset the pose asks
--- for, kept out of the baked geometry because the backdrop must not move with
--- it. A plate that scales and leans with the creature stops being a plate.
---
--- **A pose is baked into the geometry only when nothing is going to animate
--- it.** With `animate` set, the geometry stays unposed and the pose is applied
--- as transforms (by the stylesheet in the original, by `motion.lua` here) so
--- baking it as well would apply it twice. The two are exactly equivalent:
--- `bakePose` scales by `esx`/`esy` and then rotates, which is the same order the
--- transform stack composes in, and the offsets commute with both because the
--- rotation and scale are about each eye's own centre.
---
--- It is also what keeps one set of meshes serving every expression, since
--- nothing about the geometry varies with the pose.
function M.scene(style, name, opts)
  opts = opts or {}
  local t, pal = M.resolve(name, opts)
  local e = expression.resolve(opts.expression)
  local animated = opts.animate ~= nil and opts.animate ~= false

  local tinted = expression.tint(e, pal)
  local l = style.layout(t)
  local posed, bdy = l, 0
  if e and not animated then posed, bdy = expression.bakePose(l, e.p) end

  return {
    traits = t,
    palette = tinted,
    basePalette = pal,
    animated = animated,
    expression = e,
    pose = e and e.p or expression.IDENT,
    layout = posed,
    baseLayout = l,
    bdy = bdy,
    backdrop = M.backdrop(style, opts, tinted),
    geometry = style.geometry(posed),
    title = opts.title,
    size = opts.size,
  }
end

--- The numeric layout and resolved palette, before serialization.
---
--- Kept separate from rendering so geometric invariants (features staying inside
--- the body, the body staying inside the frame) can be asserted directly rather
--- than by parsing path data back out of the markup. The original underscores
--- this to say the shape of the object is not public API; the same applies here.
function M._layout(style, name, opts)
  opts = opts or {}
  local t, pal = M.resolve(name, opts)
  local e = expression.resolve(opts.expression)
  local l = style.layout(t)
  local posed = l
  if e then posed = expression.bakePose(l, e.p) end
  local out = util.copy(posed)
  out.palette = expression.tint(e, pal)
  return out
end

return M
