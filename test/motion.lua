--- The motion layer, checked without a graphics context.
---
--- The visual half of this is `tools/motion_shot.mjs`, which freezes the
--- original stylesheet's clock in a browser and diffs the frame against what
--- LOVE draws at the same time. These are the parts that can be checked in
--- numbers: the timing model, the amplitude gate, and the one equivalence the
--- whole design rests on: that applying a pose as transforms puts the geometry
--- exactly where baking it into the coordinates does.
---
---   luajit test/motion.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("test.runner")
local describe, test = T.describe, T.test

local easing = require("blobatar.easing")
local motion = require("blobatar.motion")
local animate = require("blobatar.animate")
local expression = require("blobatar.expression")
local blob = require("blobatar.style.blob")
local traits = require("blobatar.traits").traits
local color = require("blobatar.color")

local abs, cos, sin, pi = math.abs, math.cos, math.sin, math.pi

local function newMotion(seed, mode)
  local t = traits(seed)
  return motion.new(animate.params(t), color.palette(210, true, 0.5), mode or "hover")
end

describe("timing functions", function()
  test("every curve passes through both ends", function()
    for _, f in ipairs({ easing.linear, easing.easeIn, easing.easeOut,
                         easing.easeInOut, easing.hover, easing.morph }) do
      T.near(f(0), 0, 1e-6)
      T.near(f(1), 1, 1e-6)
    end
  end)

  test("every curve is monotone", function()
    for _, f in ipairs({ easing.easeIn, easing.easeOut, easing.easeInOut,
                         easing.hover, easing.morph }) do
      local prev = -1
      for i = 0, 200 do
        local v = f(i / 200)
        T.gte(v, prev - 1e-9)
        prev = v
      end
    end
  end)

  test("ease-in-out is symmetric about its midpoint", function()
    for i = 0, 50 do
      local t = i / 50
      T.near(easing.easeInOut(t) + easing.easeInOut(1 - t), 1, 1e-6)
    end
  end)
end)

describe("keyframes", function()
  local stops = { { 0, 0 }, { 0.5, 10 }, { 1, 0 } }

  test("sampling hits the stated values at the stops", function()
    T.eq(easing.sample(stops, 0, easing.linear)[1], 0)
    T.eq(easing.sample(stops, 0.5, easing.linear)[1], 10)
    T.eq(easing.sample(stops, 1, easing.linear)[1], 0)
  end)

  test("sampling interpolates between them", function()
    T.near(easing.sample(stops, 0.25, easing.linear)[1], 5, 1e-9)
    T.near(easing.sample(stops, 0.75, easing.linear)[1], 5, 1e-9)
  end)

  test("a negative delay offsets the phase rather than postponing the start", function()
    -- The whole reason the stylesheet negates its delays. At t=0 with a phase of
    -- half a period, the animation is already halfway through.
    T.near(easing.progress(0, 2, 1, false), 0.5, 1e-12)
    T.near(easing.progress(0.5, 2, 1, false), 0.75, 1e-12)
  end)

  test("alternate runs odd iterations backwards", function()
    T.near(easing.progress(0.25, 1, 0, true), 0.25, 1e-12)  -- iteration 0
    T.near(easing.progress(1.25, 1, 0, true), 0.75, 1e-12)  -- iteration 1, reversed
    T.near(easing.progress(2.25, 1, 0, true), 0.25, 1e-12)  -- iteration 2
  end)
end)

describe("transitions", function()
  test("a transition lands exactly on its target", function()
    local tr = easing.transition({ 0 })
    tr:set({ 1 }, 0.4, easing.easeOut)
    for _ = 1, 30 do tr:update(1 / 60) end
    T.eq(tr.current[1], 1)
    T.eq(tr.running, false)
  end)

  test("reversing partway shortens the return", function()
    -- CSS's rule, and the reason a quick pass over a grid does not leave every
    -- blobatar drifting for a quarter second after the pointer has gone.
    local tr = easing.transition({ 0 })
    tr:set({ 1 }, 0.4, easing.linear)
    tr:update(0.1)
    tr:set({ 0 }, 0.4, easing.linear)
    T.near(tr.duration, 0.1, 1e-9)
  end)

  test("a full reversal after completion runs full length", function()
    local tr = easing.transition({ 0 })
    tr:set({ 1 }, 0.4, easing.linear)
    for _ = 1, 30 do tr:update(1 / 60) end
    tr:set({ 0 }, 0.4, easing.linear)
    T.near(tr.duration, 0.4, 1e-9)
  end)

  test("retargeting to where it already is cancels", function()
    local tr = easing.transition({ 0 })
    tr:set({ 0 }, 0.4, easing.linear)
    T.eq(tr.running, false)
  end)
end)

describe("amplitude", function()
  test("an unhovered blobatar holds every idle layer at the identity", function()
    local m = newMotion("alain", "hover")
    for i = 1, 400 do
      m:update(1 / 60)
      local s = m:sample()
      T.eq(s.amp, 0)
      T.eq(s.breathe.sx, 1)
      T.eq(s.breathe.sy, 1)
      T.eq(s.bob.ty, 0)
      T.eq(s.eyes.tx, 0)
      T.eq(s.eyes.ty, 0)
      T.eq(s.eye[1].blink, 1)
      T.eq(s.eye[1].wsx, 1)
      T.eq(s.eye[2].wrapRot, 0)
      if i > 200 then break end
    end
  end)

  test("always mode starts at full amplitude", function()
    local m = newMotion("alain", "always")
    m:update(1 / 60)
    T.eq(m:sample().amp, 1)
  end)

  test("hovering raises amplitude over the stated 400ms", function()
    local m = newMotion("alain", "hover")
    m:setHover(true)
    for _ = 1, 12 do m:update(1 / 60) end  -- 200ms
    local mid = m:sample().amp
    T.gt(mid, 0)
    T.lt(mid, 1)
    for _ = 1, 20 do m:update(1 / 60) end
    T.eq(m:sample().amp, 1)
  end)

  test("breathing stays inside the amplitude the stylesheet states", function()
    local m = newMotion("alain", "always")
    local lo, hi = 2, 0
    for _ = 1, 600 do
      m:update(1 / 60)
      local s = m:sample()
      lo = math.min(lo, s.breathe.sx)
      hi = math.max(hi, s.breathe.sx)
    end
    T.gte(lo, 1 - 1e-9)
    T.lte(hi, 1.022 + 1e-9)
    T.gt(hi, 1.02) -- it does actually get there
  end)

  test("a blobatar blinks, and only briefly", function()
    local m = newMotion("alain", "always")
    local closed, frames = 0, 3600
    for _ = 1, frames do
      m:update(1 / 60)
      if m:sample().eye[1].blink < 0.5 then closed = closed + 1 end
    end
    T.gt(closed, 0, "never blinked in a minute")
    T.lt(closed / frames, 0.05, "blinks too much of the time")
  end)
end)

describe("the tremor", function()
  test("resolves to nothing when a pose does not ask for it", function()
    local m = newMotion("alain", "always")
    for _ = 1, 60 do
      m:update(1 / 60)
      local s = m:sample()
      T.eq(s.root.tx, 0)
    end
  end)

  test("runs on the poses that spend it, and at their own strengths", function()
    local function amplitude(name)
      local m = newMotion("alain", "always")
      m:setExpression(name)
      for _ = 1, 60 do m:update(1 / 60) end
      local peak = 0
      for _ = 1, 60 do
        m:update(1 / 240)
        peak = math.max(peak, abs(m:sample().root.tx))
      end
      return peak
    end
    local mad, scared, sick = amplitude("mad"), amplitude("scared"), amplitude("sick")
    T.gt(mad, scared)
    T.gt(scared, sick)
    T.gt(sick, 0)
  end)
end)

describe("the morph", function()
  test("heading to an expression is quicker than heading back", function()
    local m = newMotion("alain", "always")
    m:setExpression("happy")
    local toExpr = m.channels.duration
    for _ = 1, 40 do m:update(1 / 60) end
    m:setExpression(nil)
    T.near(toExpr, 0.3, 1e-9)
    T.near(m.channels.duration, 0.4, 1e-9)
  end)

  test("it arrives at the pose it was given", function()
    local m = newMotion("alain", "always")
    m:setExpression("mad")
    for _ = 1, 40 do m:update(1 / 60) end
    local s = m:sample()
    local p = expression.mad.p
    T.near(s.channels.esx, p.esx, 1e-9)
    T.near(s.channels.tilt, p.tilt, 1e-9)
    T.near(s.channels.lock, p.lock, 1e-9)
  end)

  test("the fill travels with it", function()
    local pal = color.palette(210, true, 0.5)
    local m = motion.new(animate.params(traits("alain")), pal, "always")
    m:setExpression("mad")
    for _ = 1, 40 do m:update(1 / 60) end
    local s = m:sample()
    local target = expression.tint(expression.mad, pal)
    local n = tonumber(target.head:sub(2), 16)
    T.near(s.head[1], math.floor(n / 65536) % 256 / 255, 1 / 255)
  end)

  test("reduced motion holds the pose and skips the morph", function()
    local m = motion.new(animate.params(traits("alain")),
                         color.palette(210, true, 0.5), "always", true)
    m:setExpression("happy")
    local s = m:sample()
    T.eq(s.channels.esx, expression.happy.p.esx)
    T.eq(s.amp, 0)
    T.eq(s.breathe.sx, 1)
  end)
end)

--- The equivalence the whole design rests on.
---
--- The static renderer bakes a pose into the eye coordinates; the animated one
--- leaves the coordinates alone and applies the pose as transforms. If those two
--- disagree, the blobatar jumps the moment you turn animation on, and the
--- disagreement would be silent, because both look plausible on their own.
describe("baking a pose and transforming one agree", function()
  --- A point on the superellipse boundary, in the same parametrization for both
  --- sides so the comparison is of the geometry rather than of the sampling.
  local function boundary(e, theta)
    local ct, st = cos(theta), sin(theta)
    local ux = (ct >= 0 and 1 or -1) * abs(ct) ^ (2 / e.n)
    local uy = (st >= 0 and 1 or -1) * abs(st) ^ (2 / e.n)
    local x, y = e.rx * ux, e.ry * uy
    local a = (e.rot or 0) * pi / 180
    return e.cx + x * cos(a) - y * sin(a), e.cy + x * sin(a) + y * cos(a)
  end

  --- The transform stack `love.lua` replays, as arithmetic.
  local function transformed(e, ch, side, sel, theta)
    local x, y = boundary(e, theta)
    x, y = x - e.cx, y - e.cy

    local function rot(px, py, deg)
      local a = deg * pi / 180
      return px * cos(a) - py * sin(a), px * sin(a) + py * cos(a)
    end

    local lean = e.rot
    -- Innermost first, matching the order the graphics stack composes in.
    x, y = rot(x, y, -lean)
    x, y = x * (ch.esx + ch.esx2 * sel), y * (ch.esy + ch.esy2 * sel)
    x, y = rot(x, y, lean)
    x, y = rot(x, y, (ch.tilt + ch.tilt2 * sel) * side - lean * ch.lock)

    return e.cx + x + ch.edx * side, e.cy + y + ch.edy
  end

  test("every pose, every seed, every point on the outline", function()
    for _, name in ipairs(expression.names) do
      local e = expression.byName[name]
      for i = 0, 200 do
        local l = blob.layout(traits("seed-" .. i))
        local baked = expression.bakePose(l, e.p)
        for k = 1, 2 do
          local side = k == 2 and 1 or -1
          local sel = k == 2 and 1 or 0
          for j = 0, 15 do
            local theta = j * pi / 8
            local ax, ay = boundary(baked.eyes[k], theta)
            local bx, by = transformed(l.eyes[k], e.p, side, sel, theta)
            T.near(ax, bx, 1e-9, name .. " seed-" .. i .. " eye " .. k .. " x")
            T.near(ay, by, 1e-9, name .. " seed-" .. i .. " eye " .. k .. " y")
          end
        end
      end
    end
  end)
end)

os.exit(T.run() == 0 and 0 or 1)
