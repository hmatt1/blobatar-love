--- Timing functions, and the two pieces of CSS timing that are not obvious.
---
--- The motion layer is a port of a stylesheet, so every duration in it is paired
--- with a `cubic-bezier` the browser solves for free. This is that solver, plus
--- the keyframe and transition machinery that reads it.

local M = {}

local abs = math.abs

----------------------------------------------------------------------
-- cubic-bezier
----------------------------------------------------------------------

--- Solves the CSS `cubic-bezier(x1, y1, x2, y2)` curve for y at a given x.
---
--- The curve is parametric, so the x the animation hands in is not the
--- parameter. It has to be inverted first. Newton converges in a handful of
--- steps almost everywhere; the bisection is for the flat regions where the
--- derivative is near zero and Newton wanders.
---
--- Returns a function, so the inversion constants are computed once per curve
--- rather than once per frame.
function M.bezier(x1, y1, x2, y2)
  if x1 == y1 and x2 == y2 then
    return function(t) return t end
  end

  local cx = 3 * x1
  local bx = 3 * (x2 - x1) - cx
  local ax = 1 - cx - bx
  local cy = 3 * y1
  local by = 3 * (y2 - y1) - cy
  local ay = 1 - cy - by

  local function sampleX(t) return ((ax * t + bx) * t + cx) * t end
  local function sampleY(t) return ((ay * t + by) * t + cy) * t end
  local function slopeX(t) return (3 * ax * t + 2 * bx) * t + cx end

  return function(x)
    if x <= 0 then return 0 end
    if x >= 1 then return 1 end

    local t = x
    for _ = 1, 8 do
      local err = sampleX(t) - x
      if abs(err) < 1e-7 then return sampleY(t) end
      local d = slopeX(t)
      if abs(d) < 1e-7 then break end
      t = t - err / d
    end

    local lo, hi = 0, 1
    t = x
    while lo < hi do
      local v = sampleX(t)
      if abs(v - x) < 1e-7 then return sampleY(t) end
      if x > v then lo = t else hi = t end
      local next_t = (hi + lo) / 2
      if next_t == t then break end
      t = next_t
    end
    return sampleY(t)
  end
end

M.linear = function(t) return t end
M.ease = M.bezier(0.25, 0.1, 0.25, 1)
M.easeIn = M.bezier(0.42, 0, 1, 1)
M.easeOut = M.bezier(0, 0, 0.58, 1)
M.easeInOut = M.bezier(0.42, 0, 0.58, 1)

--- The two curves the stylesheet names outright.
---
--- `hover` is the lift, and it overshoots nothing. It is a hard decelerate, so
--- the blobatar arrives at the raised position almost immediately and settles.
--- `morph` is the expression transition, which is symmetric and slower off the
--- mark so that two poses passing through each other do not read as a snap.
M.hover = M.bezier(0.23, 1, 0.32, 1)
M.morph = M.bezier(0.45, 0.05, 0.5, 1)

----------------------------------------------------------------------
-- Keyframes
----------------------------------------------------------------------

--- Evaluates a keyframe list at iteration progress `p` in [0, 1].
---
--- `stops` is `{ { offset, v1, v2, ... }, ... }` in ascending offset order, and
--- every stop must carry the same number of values. `ease` is the timing
--- function for the segment *starting* at each stop, which is how CSS scopes
--- `animation-timing-function` inside `@keyframes`: the function declared on a
--- keyframe governs the interval that begins there, not the one that ends there.
--- Pass a single function to use it for every segment.
function M.sample(stops, p, ease, out)
  out = out or {}
  local n = #stops
  if p <= stops[1][1] then
    for i = 2, #stops[1] do out[i - 1] = stops[1][i] end
    return out
  end
  if p >= stops[n][1] then
    for i = 2, #stops[n] do out[i - 1] = stops[n][i] end
    return out
  end

  local k = 1
  for i = 1, n - 1 do
    if p >= stops[i][1] and p <= stops[i + 1][1] then
      k = i
      break
    end
  end

  local a, b = stops[k], stops[k + 1]
  local span = b[1] - a[1]
  local local_t = span > 0 and (p - a[1]) / span or 0
  local f = type(ease) == "table" and ease[k] or ease
  if f then local_t = f(local_t) end

  for i = 2, #a do
    out[i - 1] = a[i] + (b[i] - a[i]) * local_t
  end
  return out
end

--- Where one CSS animation is in its cycle at time `t`.
---
--- `phase` is subtracted rather than added because the stylesheet states it as a
--- negative `animation-delay`: a positive delay postpones the start, which would
--- leave a whole grid opening in unison after an awkward pause, where a negative
--- one offsets the phase and is what makes the grid a crowd.
---
--- Returns the iteration progress, already reversed on odd iterations when
--- `alternate` is set. Reversing the progress rather than the eased output is
--- what the Web Animations model does, and it is not the same thing: an
--- `ease-in-out` played backwards is still `ease-in-out`, but an `ease-in` played
--- backwards is `ease-out`.
function M.progress(t, duration, phase, alternate)
  if duration <= 0 then return 0 end
  local elapsed = t + (phase or 0)
  local iter = math.floor(elapsed / duration)
  local p = (elapsed - iter * duration) / duration
  if alternate and iter % 2 ~= 0 then return 1 - p end
  return p
end

----------------------------------------------------------------------
-- Transitions
----------------------------------------------------------------------

--- A CSS transition over a vector of numbers.
---
--- All of this library's transitions move several numbers on one clock (eleven
--- pose channels, or two colours), so the unit is a vector rather than a scalar.
---
--- The reversing behaviour is the part worth having. Interrupt a hover-in
--- halfway and CSS does not restart a full-length hover-out; it shortens the new
--- transition by how far the old one got, so the blobatar comes back down in
--- 110ms rather than taking 220ms to travel half the distance. Without it, quick
--- passes over a grid leave every blobatar drifting for a quarter second after
--- the pointer has gone.
local Transition = {}
Transition.__index = Transition

function M.transition(values)
  local self = setmetatable({}, Transition)
  self.current = {}
  self.from = {}
  self.target = {}
  self.reversingStart = {}
  self.n = #values
  for i = 1, self.n do
    self.current[i] = values[i]
    self.from[i] = values[i]
    self.target[i] = values[i]
    self.reversingStart[i] = values[i]
  end
  self.elapsed = 0
  self.duration = 0
  self.factor = 1
  self.ease = M.linear
  self.running = false
  return self
end

local function same(a, b, n)
  for i = 1, n do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- Points the transition at a new vector. `duration` is in seconds.
function Transition:set(values, duration, ease)
  local n = self.n
  if same(values, self.target, n) then return end

  if same(values, self.current, n) then
    -- Already there. CSS cancels rather than running a zero-distance transition.
    for i = 1, n do
      self.target[i] = values[i]
      self.from[i] = values[i]
      self.reversingStart[i] = values[i]
    end
    self.running = false
    return
  end

  local factor = 1
  if self.running and same(values, self.reversingStart, n) then
    -- Reversing an in-flight transition. The new duration is scaled by how far
    -- the old one had actually travelled, measured through its timing function
    -- rather than on the clock.
    local progress = self.duration > 0 and self.ease(self.elapsed / self.duration) or 1
    factor = progress * self.factor + (1 - self.factor)
    if factor < 0 then factor = -factor end
    if factor > 1 then factor = 1 end
  end

  for i = 1, n do
    self.from[i] = self.current[i]
    self.reversingStart[i] = self.current[i]
    self.target[i] = values[i]
  end
  self.factor = factor
  self.duration = duration * factor
  self.ease = ease or M.linear
  self.elapsed = 0
  self.running = self.duration > 0
  if not self.running then
    for i = 1, n do self.current[i] = values[i] end
  end
end

--- Jumps to the target with no transition, for reduced-motion and for the first
--- frame after an expression is set before anything has been drawn.
function Transition:snap(values)
  for i = 1, self.n do
    self.current[i] = values[i]
    self.from[i] = values[i]
    self.target[i] = values[i]
    self.reversingStart[i] = values[i]
  end
  self.running = false
end

function Transition:update(dt)
  if not self.running then return end
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.duration then
    for i = 1, self.n do self.current[i] = self.target[i] end
    self.running = false
    return
  end
  local p = self.ease(self.elapsed / self.duration)
  for i = 1, self.n do
    self.current[i] = self.from[i] + (self.target[i] - self.from[i]) * p
  end
end

return M
