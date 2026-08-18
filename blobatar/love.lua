--- The LOVE renderer.
---
--- Everything above this file is plain Lua and knows nothing about LOVE. This is
--- where the numbers become pixels: the Bezier paths get flattened to polygons,
--- the concave ones get triangulated, and the motion layer's transform stack gets
--- replayed as `love.graphics` calls.
---
--- The composition order is the stylesheet's, because it has to be. An element
--- has one transform, so hover-lift, breathe and bob live on separate elements
--- over there, and here they live in separate `push`/`pop` frames for exactly
--- the same reason.
---
---   local blobatar = require("blobatar")
---   local b = blobatar.new("alain@example.com", { animate = "hover" })
---
---   function love.update(dt)
---     b:setHover(b:hitTest(love.mouse.getPosition()))
---     b:update(dt)
---   end
---
---   function love.draw() b:draw(20, 20, 96) end
---
--- One thing to know before drawing with a non-opaque colour: the body is a core
--- shape plus up to nine decoration circles, and they overlap. In SVG they union
--- because they share one opaque fill. Draw them at 50% alpha and the overlaps
--- come out darker, because that is what alpha compositing does. `toImage` exists
--- for that case: it flattens the blobatar into one texture, which then fades as
--- a single object.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local req = function(name) return require(PREFIX == "" and name or (PREFIX .. "." .. name)) end

local path_mod = req("path")
local animate = req("animate")
local motion_mod = req("motion")
local expression = req("expression")

local M = {}

local lg = love.graphics
local floor, ceil, log, max, min = math.floor, math.ceil, math.log, math.max, math.min
local rad = math.rad

local Blobatar = {}
Blobatar.__index = Blobatar

M.Blobatar = Blobatar

----------------------------------------------------------------------
-- Mesh building
----------------------------------------------------------------------

local function toVertices(poly)
  local out = {}
  for i = 1, #poly, 2 do
    out[#out + 1] = { poly[i], poly[i + 1] }
  end
  return out
end

--- A filled polygon as a Mesh.
---
--- Convex shapes go out as a triangle fan, which is what `love.graphics.polygon`
--- would have done and costs no triangulation. The organic silhouettes are the
--- ones that need `love.math.triangulate`: their radii vary by up to 16%, and a
--- dip between two bulges is a concavity a fan renders as a fold.
local function meshFor(poly, convex)
  if #poly < 6 then return nil end
  if convex then
    return lg.newMesh(toVertices(poly), "fan", "static")
  end
  local ok, tris = pcall(love.math.triangulate, poly)
  if not ok or not tris or #tris == 0 then
    -- A degenerate contour. A fan is wrong for a concave shape but it is a
    -- shape, which beats an error thrown from inside a draw call.
    return lg.newMesh(toVertices(poly), "fan", "static")
  end
  local verts = {}
  for i = 1, #tris do
    local t = tris[i]
    verts[#verts + 1] = { t[1], t[2] }
    verts[#verts + 1] = { t[3], t[4] }
    verts[#verts + 1] = { t[5], t[6] }
  end
  return lg.newMesh(verts, "triangles", "static")
end

--- Flattening tolerance for a draw size, in viewBox units.
---
--- Quarter of a pixel at the size asked for. Quantized to powers of two so that
--- an animating size (a grid that scales on hover, a zoom) rebuilds a handful
--- of times rather than every frame.
local function bucketFor(size)
  local b = 2 ^ ceil(log(max(size, 8)) / log(2))
  return b
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

--- Options are the library's, plus:
---
---   animate   "hover" (default), "always", or false for no idle motion
---   reduced   holds every pose and runs no loop or morph, for a
---             reduced-motion setting
---
--- `expression` is honoured on the way in and can be changed at any time with
--- `setExpression`.
function M.new(lib, name, opts)
  opts = opts or {}

  local mode = opts.animate
  local frozen = false
  if mode == false or mode == nil then
    -- The loops still exist; `amp` simply never leaves zero, which is the same
    -- thing the stylesheet does to an unhovered blobatar.
    frozen = mode == false
    mode = "hover"
  end

  -- The expression is driven by the motion layer rather than baked into the
  -- geometry, which is what lets it morph and what lets one set of meshes serve
  -- every pose. Passing `animate` through is what tells the scene builder to
  -- leave it unbaked.
  local base = {}
  for k, v in pairs(opts) do base[k] = v end
  base.animate = mode

  local scene = lib.render.scene(lib.defaultStyle, name, base)

  local self = setmetatable({}, Blobatar)
  self.name = name
  self.scene = scene
  self.layout = scene.layout
  -- The untinted palette. Every tint is derived from it per frame, so handing
  -- the motion layer an already-tinted one would tint a tint.
  self.palette = scene.basePalette
  self.alpha = 1
  self.frozen = frozen
  self._cache = {}

  self.motion = motion_mod.new(
    animate.params(scene.traits), scene.basePalette, mode, opts.reduced)

  local e = expression.resolve(opts.expression)
  if e and e ~= expression.idle then
    self.motion:setExpression(e)
    -- Mounting into a pose is not a morph. A browser runs no transition on first
    -- style resolution either, for want of a previous computed value.
    self.motion.channels:snap(self.motion.channels.target)
    self.motion.fill:snap(self.motion.fill.target)
  end

  return self
end

--- The meshes for a draw size, built once per size bucket.
function Blobatar:_meshes(size)
  local b = bucketFor(size)
  local c = self._cache[b]
  if c then return c end

  local tol = min(0.5, max(0.004, 25 / b))
  local g = self.scene.geometry
  c = { eyes = {} }

  c.core = meshFor(path_mod.flatten(g.core, tol),
                   self.layout.shape ~= "organic" and self.layout.shape ~= "cloud")
  for i = 1, #g.eyes do
    -- A superellipse with n >= 1 is convex, and every eye here is drawn at
    -- n between 3.5 and 6.
    c.eyes[i] = meshFor(path_mod.flatten(g.eyes[i], tol), true)
  end
  if self.scene.backdrop then
    c.backdrop = meshFor(path_mod.flatten(self.scene.backdrop.path, tol), true)
  end

  -- Petals are true circles, so they go through `love.graphics.circle` rather
  -- than a mesh. The segment count is the only thing that has to scale.
  c.petalSegments = max(12, min(72, ceil(b / 8)))

  self._cache[b] = c
  return c
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

function Blobatar:update(dt)
  self.motion:update(dt)
end

--- Which pose the blobatar holds, as a value from `blobatar.expression` or its
--- name. Held until you change it; nothing here returns to idle on its own.
function Blobatar:setExpression(e)
  self.motion:setExpression(e)
end

function Blobatar:getExpression()
  return self.motion.expr
end

--- Whether the pointer is over this blobatar. Ignored in `"always"` mode.
function Blobatar:setHover(on)
  if self.frozen then return end
  self.motion:setHover(on)
end

--- Whether a point in screen space is over the blobatar's body.
---
--- Tested against the silhouette rather than a bounding box, which is what a
--- browser does with an inline SVG: hover follows the filled geometry, so the
--- transparent corners of a round blobatar are not part of it.
---
--- Tested against the *resting* silhouette, which is where a browser and this
--- part company. Over there the hit area is the animated geometry, so a blobatar
--- that grows 4% on hover grows its own hit area and a pointer resting on the
--- edge chatters between the two states. Holding the rest pose costs nothing and
--- removes that.
function Blobatar:hitTest(mx, my, x, y, size)
  x = x or self.lastX
  y = y or self.lastY
  size = size or self.lastSize
  if not x or not size then return false end

  local k = 100 / size
  local px = (mx - x) * k
  local py = (my - y) * k

  if self.scene.backdrop then
    -- With a plate, the plate is the target: it is the part of the frame a
    -- pointer can actually land on.
    if px < 0 or py < 0 or px > 100 or py > 100 then return false end
    if self.scene.backdrop.kind == "square" then return true end
  end

  local l = self.layout
  for i = 1, #l.petals do
    local p = l.petals[i]
    local dx, dy = px - p.cx, py - p.cy
    if dx * dx + dy * dy <= p.r * p.r then return true end
  end

  local poly = self._hitPoly
  if not poly then
    poly = path_mod.flatten(self.scene.geometry.core, 0.4)
    self._hitPoly = poly
  end

  local inside = false
  local n = #poly
  local jx, jy = poly[n - 1], poly[n]
  for i = 1, n, 2 do
    local ix, iy = poly[i], poly[i + 1]
    if (iy > py) ~= (jy > py) and px < (jx - ix) * (py - iy) / (jy - iy) + ix then
      inside = not inside
    end
    jx, jy = ix, iy
  end
  return inside
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function setColor(c, a)
  lg.setColor(c[1], c[2], c[3], a)
end

--- Draws the blobatar into a `size` by `size` box with its top-left at `x, y`.
---
--- The blobatar does not fill that box: the body is a silhouette inside a 100
--- unit frame, and how much of the frame it takes depends on the shape it drew.
--- A sun with nine petals reaches further than a round.
function Blobatar:draw(x, y, size)
  size = size or 64
  self.lastX, self.lastY, self.lastSize = x, y, size

  local c = self:_meshes(size)
  local s = self.motion:sample()
  local k = size / 100
  local a = self.alpha

  lg.push()
  lg.translate(x, y)
  lg.scale(k, k)

  -- The backdrop sits outside the motion root, because a plate that lifts and
  -- breathes with the creature stops being a plate.
  if c.backdrop then
    local bg = self.scene.backdrop.fill
    local r = tonumber(bg:sub(2, 3), 16) / 255
    local g = tonumber(bg:sub(4, 5), 16) / 255
    local b = tonumber(bg:sub(6, 7), 16) / 255
    lg.setColor(r, g, b, a)
    lg.draw(c.backdrop)
  end

  -- Root: the tremor and the hover lift, about the frame centre.
  lg.push()
  lg.translate(50, 50)
  lg.translate(s.root.tx, s.root.ty)
  lg.scale(s.root.s, s.root.s)
  lg.translate(-50, -50)

  -- Breathe, also about the frame centre.
  lg.push()
  lg.translate(50, 50)
  lg.scale(s.breathe.sx, s.breathe.sy)
  lg.translate(-50, -50)

  -- Bob, which carries the pose's whole-creature offset.
  lg.push()
  lg.translate(0, s.bob.ty)

  -- Decoration first so the core sits on top and the eyes always land on it.
  setColor(s.head, a)
  local petals = self.layout.petals
  for i = 1, #petals do
    local p = petals[i]
    lg.circle("fill", p.cx, p.cy, p.r, c.petalSegments)
  end
  if c.core then lg.draw(c.core) end

  -- Both eyes move as one under the saccade, because independent movement reads
  -- as a lazy eye instantly. Blink and the wrap stay on the individual shapes.
  setColor(s.eyeColor, a)
  lg.push()
  lg.translate(s.eyes.tx, s.eyes.ty)

  for i = 1, #c.eyes do
    local mesh = c.eyes[i]
    if mesh then
      local e = s.eye[i]
      local le = self.layout.eyes[i]
      local lean = le.rot

      lg.push()
      lg.translate(le.cx, le.cy)
      lg.translate(e.tx, e.ty)
      -- The pose's tilt, less as much of the seeded lean as `lock` cancels. The
      -- lean is already in the mesh's coordinates, so it comes off here.
      lg.rotate(rad(e.tilt - lean * e.lock))
      -- Scale about the eye's own axes rather than the screen's. A leaned capsule
      -- arrives already tilted, so a plain scaleY would shear it instead of
      -- squashing it.
      lg.rotate(rad(lean))
      lg.scale(e.sx, e.sy)
      lg.rotate(-rad(lean))
      -- The glance layer: foreshortening and a small counter-tilt.
      lg.rotate(rad(e.wrapRot))
      lg.scale(e.wsx, e.wsy)
      -- Blink, in the eye's own axes for the same reason the pose scale is.
      lg.rotate(rad(lean))
      lg.scale(1, e.blink)
      lg.rotate(-rad(lean))
      lg.translate(-le.cx, -le.cy)
      lg.draw(mesh)
      lg.pop()
    end
  end

  lg.pop() -- eyes
  lg.pop() -- bob
  lg.pop() -- breathe
  lg.pop() -- root
  lg.pop() -- frame

  lg.setColor(1, 1, 1, 1)
end

--- Flattens the blobatar into a texture at its current state.
---
--- Two uses. A grid of hundreds of static blobatars costs one draw call each this
--- way rather than a transform stack each. And a blobatar drawn at less than full
--- alpha has to go through here, because the body is several overlapping shapes
--- sharing one fill: at 50% alpha the overlaps double up, where a texture fades
--- as one object.
---
--- The canvas is yours to release. Nothing here caches it, because the state it
--- captured is a moment rather than a property.
function Blobatar:toImage(size, samples)
  size = size or 128
  local canvas = lg.newCanvas(size, size, { msaa = samples or 4 })
  local prev = lg.getCanvas()
  local r, g, b, a = lg.getColor()
  local blend, alphamode = lg.getBlendMode()

  lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 0)
  lg.setBlendMode("alpha", "alphamultiply")
  local keepAlpha = self.alpha
  self.alpha = 1
  self:draw(0, 0, size)
  self.alpha = keepAlpha
  lg.setCanvas(prev)

  lg.setBlendMode(blend, alphamode)
  lg.setColor(r, g, b, a)
  return canvas
end

--- Frees the GPU objects this blobatar holds. Meshes are released when they are
--- collected anyway; this is for a grid that churns.
function Blobatar:release()
  for _, c in pairs(self._cache) do
    if c.core then c.core:release() end
    if c.backdrop then c.backdrop:release() end
    for i = 1, #c.eyes do
      if c.eyes[i] then c.eyes[i]:release() end
    end
  end
  self._cache = {}
end

return M
