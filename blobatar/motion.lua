--- The motion layer. A port of `src/motion.css`.
---
--- The original animates a blobatar with a stylesheet: six idle loops, a hover
--- amplitude, and a transition across eleven registered custom properties that
--- *is* the expression morph. There are no per-expression keyframes over there
--- and there are none here. LOVE has no stylesheet, so this file is the browser's
--- half of that arrangement: a clock, a keyframe sampler, and the composition
--- order the CSS cascade was providing for free.
---
--- Nothing in this file touches LOVE. It reads a time and returns numbers, which
--- is what makes it testable in plain Lua and what keeps `love.lua` down to
--- drawing.
---
--- Layers, outermost first:
---
---   root      hover lift and scale, plus the tremor `shake` rides
---   breathe   a slow anisotropic scale about the frame centre
---   bob       a vertical drift, carrying the pose's whole-creature offset
---   eyes      the saccade, which moves both eyes as one because independent
---             movement reads as a lazy eye instantly
---   eye       the pose's per-eye scale, tilt and offset
---   shape     blink, and the eye-wrap that foreshortens a glance
---
--- The nesting is not decoration. An element has one transform, so hover-lift,
--- breathe and bob have to live on separate elements or they overwrite each
--- other, and the same is true of a graphics stack, one push at a time.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local req = function(name) return require(PREFIX == "" and name or (PREFIX .. "." .. name)) end

local easing = req("easing")
local expression = req("expression")
local color = req("color")

local M = {}

local floor = math.floor

----------------------------------------------------------------------
-- Durations and keyframes, straight off the stylesheet
----------------------------------------------------------------------

local D = {
  amp = 0.400,       -- --mo-amp, both directions
  hoverIn = 0.220,
  hoverOut = 0.160,
  morphIdle = 0.400, -- heading back to idle
  morphExpr = 0.300, -- heading to an expression
  shake = 0.112,
  breathe = 2.800,
  bob = 3.400,
}

M.DURATIONS = D

--- The hover reaction. A lift and a small scale, and nothing else. The idle
--- loops are what make it feel alive, and this is what makes them start.
local HOVER_LIFT = -1.5
local HOVER_SCALE = 1.04

--- `@keyframes mo-shake`. A held tremor rather than a fired one: it always runs,
--- and resolves to the identity at `shake: 0`, so a blobatar that is not
--- trembling pays a multiply by zero rather than a branch.
local SHAKE = {
  { 0.00, 0.62, -0.34 },
  { 0.25, -0.70, 0.22 },
  { 0.50, 0.38, 0.66 },
  { 0.75, -0.44, -0.60 },
  { 1.00, 0.62, -0.34 },
}

--- `@keyframes mo-breathe`, as a scale pair. The `from` is implicit in CSS: an
--- omitted `from` is the element's own value, which is the identity.
local BREATHE_X = 0.022
local BREATHE_Y = -0.018

--- `@keyframes mo-bob`.
local BOB_Y = -1.1

--- `@keyframes mo-blink`. Open for 97.2% of the cycle, shut over 1.4%, open again
--- over the last 1.4%. The closed scale carries `--mo-amp`, so at rest the whole
--- animation resolves to the identity and an unhovered blobatar does not blink.
local BLINK_CLOSE = 0.92
local BLINK = { 0.972, 0.986 }

--- `@keyframes mo-saccade`, in units of `lookX` and `lookY`.
---
--- One shared sequence visits the same fixations on every blobatar, which is why
--- the per-seed direction in `animate.lua` matters: without it the whole grid
--- would look left, then up, then right together.
local SACCADE = {
  { 0.000, 0.00, 0.00 },
  { 0.150, 0.00, 0.00 },
  { 0.165, -0.80, -0.90 },
  { 0.310, -0.80, -0.90 },
  { 0.325, 1.00, 0.10 },
  { 0.470, 1.00, 0.10 },
  { 0.485, -0.15, 0.85 },
  { 0.630, -0.15, 0.85 },
  { 0.645, 0.75, -0.80 },
  { 0.790, 0.75, -0.80 },
  { 0.805, -1.00, -0.15 },
  { 0.985, -1.00, -0.15 },
  { 1.000, 0.00, 0.00 },
}

--- `@keyframes mo-wrap`. The eye foreshortens and tilts as the pair travels, so
--- a glance reads as a head turning rather than as two capsules sliding.
---
--- Per stop: the scale-x term that follows the travel distance, the scale-x term
--- that follows the direction and the eye's own side, the scale-y term, and the
--- rotation coefficient. The eye leading into a turn foreshortens harder, which
--- is what the side-dependent term buys and why one keyframe list serves both
--- eyes.
local WRAP = {
  { 0.000, 0.0000, 0.0000, 0.0000, 0.000 },
  { 0.150, 0.0000, 0.0000, 0.0000, 0.000 },
  { 0.165, -0.0176, 0.0080, -0.0270, 0.648 },
  { 0.310, -0.0176, 0.0080, -0.0270, 0.648 },
  { 0.325, -0.0220, -0.0100, -0.0030, 0.090 },
  { 0.470, -0.0220, -0.0100, -0.0030, 0.090 },
  { 0.485, -0.0033, 0.0015, -0.0255, -0.115 },
  { 0.630, -0.0033, 0.0015, -0.0255, -0.115 },
  { 0.645, -0.0165, -0.0075, -0.0240, -0.540 },
  { 0.790, -0.0165, -0.0075, -0.0240, -0.540 },
  { 0.805, -0.0220, 0.0100, -0.0045, 0.135 },
  { 0.985, -0.0220, 0.0100, -0.0045, 0.135 },
  { 1.000, 0.0000, 0.0000, 0.0000, 0.000 },
}

----------------------------------------------------------------------
-- Instance
----------------------------------------------------------------------

local Motion = {}
Motion.__index = Motion

--- The channel vector, in the order `expression.CHANNELS` states, minus `heat`.
---
--- `heat` is not a transitioned channel over there either. Colour is resolved to
--- a finished pair and carried by a `transition: fill`, because a hot endpoint
--- held in a custom property vanishes the instant an expression is cleared and
--- snaps the fill while the rest of the pose is still easing. The same argument
--- applies here for a different reason: the tint walk is not something to run
--- per frame.
local CHANNELS = {}
for i = 1, #expression.CHANNELS do
  local k = expression.CHANNELS[i]
  if k ~= "heat" then CHANNELS[#CHANNELS + 1] = k end
end

M.CHANNELS = CHANNELS

local function poseVector(p, out)
  for i = 1, #CHANNELS do out[i] = p[CHANNELS[i]] end
  return out
end

local function hexToRGB(hex)
  local n = tonumber(hex:sub(2), 16)
  return floor(n / 65536) % 256 / 255, floor(n / 256) % 256 / 255, n % 256 / 255
end

--- Builds the motion state for one blobatar.
---
---   params    from `animate.params(traits)`
---   palette   the untinted palette, which every tint is derived from
---   mode      "hover" or "always"
---   reduced   skips every loop and every transition, holding the pose
function M.new(params, palette, mode, reduced)
  local self = setmetatable({}, Motion)
  self.p = params
  self.palette = palette
  self.mode = mode or "hover"
  self.reduced = reduced or false
  self.t = 0
  self.hovered = false

  self.expr = nil
  self.pose = expression.pose({})

  self.amp = easing.transition({ self.mode == "always" and 1 or 0 })
  self.lift = easing.transition({ 0 })
  self.channels = easing.transition(poseVector(self.pose, {}))

  local hr, hg, hb = hexToRGB(palette.head)
  local er, eg, eb = hexToRGB(palette.eye)
  self.fill = easing.transition({ hr, hg, hb, er, eg, eb })

  -- Reused every frame. A blobatar grid redraws sixty times a second and this is
  -- the only per-frame allocation there would otherwise be.
  self.state = {
    amp = 0,
    root = { tx = 0, ty = 0, s = 1 },
    breathe = { sx = 1, sy = 1 },
    bob = { ty = 0 },
    eyes = { tx = 0, ty = 0 },
    -- Per eye: the pose offset, its scale about the eye's own centre, the tilt
    -- and how much of the seeded lean it cancels, then the glance layer's
    -- foreshortening and the blink. `love.lua` supplies the lean itself, which
    -- is a constant of the layout rather than of the clock.
    eye = {
      { tx = 0, ty = 0, sx = 1, sy = 1, tilt = 0, lock = 0, wrapRot = 0, wsx = 1, wsy = 1, blink = 1 },
      { tx = 0, ty = 0, sx = 1, sy = 1, tilt = 0, lock = 0, wrapRot = 0, wsx = 1, wsy = 1, blink = 1 },
    },
    head = { 0, 0, 0 },
    eyeColor = { 0, 0, 0 },
    pose = self.pose,
    channels = poseVector(self.pose, {}),
  }
  -- Reused every frame, for the same reason `state` is.
  self._scratch = { 0, 0, 0, 0 }
  self._vec = {}
  self._ch = {}

  return self
end

--- Which expression the blobatar holds. Set by you and held until you change it.
--- Nothing here returns to idle on its own, and there are no timers. A burst is
--- `setExpression(happy)` and your own countdown, which is four lines in your
--- code and none in this file.
---
--- Accepts a value from `blobatar.expression` or its name.
function Motion:setExpression(e)
  e = expression.resolve(e)
  if e == expression.idle then e = nil end
  if e == self.expr then return end
  self.expr = e

  local p = e and e.p or expression.IDENT
  self.pose = p
  self.state.pose = p

  -- A transition takes its duration from the state it is heading to, which is
  -- what lets adopting an expression and returning to idle run on different
  -- clocks. Over there it is a class swapping `--mo-morph`; here it is this
  -- branch.
  local expressive = e ~= nil
  local duration = expressive and D.morphExpr or D.morphIdle
  local ease = expressive and easing.morph or easing.easeInOut

  local target = poseVector(p, self._vec)
  local tinted = expression.tint(e, self.palette)
  local hr, hg, hb = hexToRGB(tinted.head)
  local er, eg, eb = hexToRGB(tinted.eye)

  if self.reduced then
    -- Reduced motion removes the morph, not the pose. A pose is meaning; the
    -- morph is decoration.
    self.channels:snap(target)
    self.fill:snap({ hr, hg, hb, er, eg, eb })
  else
    self.channels:set(target, duration, ease)
    self.fill:set({ hr, hg, hb, er, eg, eb }, duration, ease)
  end
end

--- Whether the pointer is over this blobatar. Ignored in `"always"` mode, which
--- is the escape hatch for the single-blobatar case (a profile header, an
--- onboarding screen) where "ambient motion seen constantly is motion worth
--- removing" does not apply.
function Motion:setHover(on)
  on = on and true or false
  if on == self.hovered then return end
  self.hovered = on
  if self.mode == "always" or self.reduced then return end
  self.amp:set({ on and 1 or 0 }, D.amp, easing.easeOut)
  self.lift:set({ on and 1 or 0 }, on and D.hoverIn or D.hoverOut, easing.hover)
end

function Motion:update(dt)
  self.t = self.t + dt
  if self.reduced then return end
  self.amp:update(dt)
  self.lift:update(dt)
  self.channels:update(dt)
  self.fill:update(dt)
end

--- The composed state for this frame.
---
--- Every layer's numbers are here, in the space the layout lives in: a 100 unit
--- viewBox. Scaling to a draw size is `love.lua`'s business, which keeps this
--- file's numbers comparable with the stylesheet's.
function Motion:sample()
  local s = self.state
  local p = self.p
  local t = self.t
  local reduced = self.reduced

  local amp = reduced and 0 or self.amp.current[1]
  s.amp = amp

  local c = self.channels.current
  local ch = self._ch
  for i = 1, #CHANNELS do ch[CHANNELS[i]] = c[i] end
  s.channels = ch

  -- Root: the tremor, then the hover lift.
  local shake = ch.shake
  if reduced or shake == 0 then
    s.root.tx, s.root.ty = 0, 0
  else
    local k = easing.sample(SHAKE, easing.progress(t, D.shake, 0, false),
                            easing.linear, self._scratch)
    s.root.tx = k[1] * shake
    s.root.ty = k[2] * shake
  end

  local lift = reduced and 0 or self.lift.current[1]
  s.root.ty = s.root.ty + HOVER_LIFT * lift
  s.root.s = 1 + (HOVER_SCALE - 1) * lift

  -- Breathe and bob, both `alternate` so they never jump back to the start.
  if reduced then
    s.breathe.sx, s.breathe.sy = 1, 1
    s.bob.ty = ch.bdy
  else
    local bp = easing.easeInOut(easing.progress(t, D.breathe, p.phase, true))
    s.breathe.sx = 1 + BREATHE_X * amp * bp
    s.breathe.sy = 1 + BREATHE_Y * amp * bp

    local op = easing.easeInOut(easing.progress(t, D.bob, p.bobPhase, true))
    s.bob.ty = ch.bdy + BOB_Y * amp * op
  end

  -- Saccade, on the pair.
  if reduced or amp == 0 then
    s.eyes.tx, s.eyes.ty = 0, 0
  else
    local k = easing.sample(SACCADE, easing.progress(t, p.saccade, p.saccadePhase, false),
                            easing.linear, self._scratch)
    s.eyes.tx = k[1] * p.lookX * amp
    s.eyes.ty = k[2] * p.lookY * amp
  end

  -- Blink, shared by both eyes: they close together, which is the one place two
  -- eyes moving as one is not a stylistic choice.
  local blink = 1
  if not reduced and amp > 0 then
    local bp = easing.progress(t, p.blink, p.blinkPhase, false)
    if bp > BLINK[1] then
      local closed = 1 - BLINK_CLOSE * amp
      if bp < BLINK[2] then
        local u = easing.easeIn((bp - BLINK[1]) / (BLINK[2] - BLINK[1]))
        blink = 1 + (closed - 1) * u
      else
        local u = easing.easeOut((bp - BLINK[2]) / (1 - BLINK[2]))
        blink = closed + (1 - closed) * u
      end
    end
  end

  -- The eye-wrap, which is per side.
  local wrap
  if not reduced and amp > 0 then
    wrap = easing.sample(WRAP, easing.progress(t, p.saccade, p.saccadePhase, false),
                         easing.linear, self._scratch)
  end

  for i = 1, 2 do
    local e = s.eye[i]
    -- The original's `--mo-wrap`: -1 on the left eye, +1 on the right. A sign per
    -- eye is what lets one keyframe list serve both.
    local side = i == 2 and 1 or -1
    local sel = i == 2 and 1 or 0

    e.tx = ch.edx * side
    e.ty = ch.edy
    e.sx = ch.esx + ch.esx2 * sel
    e.sy = ch.esy + ch.esy2 * sel
    -- The pose's tilt, minus as much of the seeded lean as `lock` cancels. The
    -- lean itself is already baked into the path's coordinates, so it is
    -- subtracted here rather than removed there.
    e.tilt = (ch.tilt + ch.tilt2 * sel) * side
    e.lock = ch.lock
    e.blink = blink

    if wrap then
      e.wsx = 1 + wrap[1] * p.lookMX * amp + wrap[2] * p.lookX * side * amp
      e.wsy = 1 + wrap[3] * p.lookMY * amp
      e.wrapRot = wrap[4] * p.lookX * p.lookY * side * amp
    else
      e.wsx, e.wsy, e.wrapRot = 1, 1, 0
    end
  end

  local f = self.fill.current
  s.head[1], s.head[2], s.head[3] = f[1], f[2], f[3]
  s.eyeColor[1], s.eyeColor[2], s.eyeColor[3] = f[4], f[5], f[6]

  return s
end

return M
