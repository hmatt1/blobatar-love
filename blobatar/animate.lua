--- Per-blobatar motion parameters. A port of `src/animate.ts`.
---
--- This file decides *how* one blobatar's idle loops differ from another's. What
--- those loops actually do lives in `motion.lua`, which is a port of the
--- stylesheet the original ships alongside this.
---
--- A grid where every blobatar breathes in unison does not read as a crowd of
--- creatures; it reads as a heartbeat. Seeded offsets are what make it a crowd,
--- and they are the single most load-bearing 40 bytes in the motion layer.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local util = require(PREFIX == "" and "util" or (PREFIX .. ".util"))

local M = {}

local round = util.round

--- `"hover"` animates one blobatar at a time, which is both the aesthetic answer
--- (ambient motion seen constantly is motion worth removing) and the performance
--- one. `"always"` is the escape hatch for the single-blobatar case (a profile
--- header, an onboarding screen) where that frequency argument does not apply.
M.MODES = { hover = true, always = true }

--- The seeded timing for one blobatar, in the units `motion.lua` reads.
---
--- Phases are stored positive here and subtracted by the clock, where the
--- original negates them into `animation-delay`. Same offset, and the sign lives
--- next to the thing that applies it rather than a file away.
---
--- Breathe and bob get independent offsets. Sharing one preserves the drift
--- between their two periods but locks every blobatar into the same drift, which
--- is the unison problem again, one level up.
---
--- These keys cost nothing in compatibility: traits are string-addressed, so
--- adding `motion.*` cannot perturb any existing blobatar.
function M.params(t)
  local blink = round(t.num("motion.blink", 3500, 6500))
  local saccade = round(t.num("motion.saccade", 4200, 7600))
  local lookX = t.num("motion.lookX", 1, 2.2)
  local lookY = t.num("motion.lookY", 0.8, 1.7)

  return {
    -- Seconds, because that is what LOVE hands `love.update`.
    phase = round(t.num("motion.phase", 0, 2800)) / 1000,
    bobPhase = round(t.num("motion.bob", 0, 3400)) / 1000,
    blink = blink / 1000,
    blinkPhase = round(t.num("motion.blinkPhase", 0, blink)) / 1000,

    -- Where this blobatar looks when it glances. One shared keyframe sequence
    -- visits the same fixations on every blobatar, so without a per-seed
    -- direction the whole grid would look left, then up, then right together,
    -- the unison problem again, and more legible than the original because a
    -- sequence is easier to spot than a phase.
    --
    -- Magnitude and sign are drawn separately so the value cannot land near
    -- zero: a seed that draws 0.02 would simply never appear to look anywhere.
    -- The magnitude is kept alongside the signed value because the eye-wrap
    -- layer foreshortens by *how far* the eyes travel, which is sign-independent.
    lookX = lookX * (t.bool("motion.lookXFlip") and -1 or 1),
    lookMX = lookX,
    -- Still short of horizontal (eyes rove side to side more than up and down)
    -- but not by much, because the fixations are real compass directions rather
    -- than scaled copies of one vector, and a squashed vertical range would
    -- collapse "up" and "up-left" into the same look.
    lookY = lookY * (t.bool("motion.lookYFlip") and -1 or 1),
    lookMY = lookY,
    saccade = saccade / 1000,
    saccadePhase = round(t.num("motion.saccadePhase", 0, saccade)) / 1000,
  }
end

--- The same values as the original's CSS custom properties, for `svg.lua`.
---
--- Milliseconds, and delays negated, exactly as the stylesheet expects them: a
--- positive `animation-delay` postpones the start rather than offsetting the
--- phase, so the whole grid would still open in unison, after an awkward pause
--- Same keystroke, opposite behavior, and it only shows on first paint.
function M.motionVars(t)
  local p = M.params(t)
  local ms = function(v) return string.format("%dms", -round(v * 1000)) end
  local r2 = function(v) return util.numstr(util.r2(v)) end

  local vars = {
    ["--mo-phase"] = ms(p.phase),
    ["--mo-bob-phase"] = ms(p.bobPhase),
    ["--mo-blink"] = string.format("%dms", round(p.blink * 1000)),
    ["--mo-blink-phase"] = ms(p.blinkPhase),
    ["--mo-look-x"] = r2(p.lookX),
    ["--mo-look-mx"] = r2(p.lookMX),
    ["--mo-look-y"] = r2(p.lookY),
    ["--mo-look-my"] = r2(p.lookMY),
    ["--mo-saccade"] = string.format("%dms", round(p.saccade * 1000)),
    ["--mo-saccade-phase"] = ms(p.saccadePhase),
  }

  local order = {
    "--mo-phase", "--mo-bob-phase", "--mo-blink", "--mo-blink-phase",
    "--mo-look-x", "--mo-look-mx", "--mo-look-y", "--mo-look-my",
    "--mo-saccade", "--mo-saccade-phase",
  }

  return vars, order
end

--- Root class. Amplitude, and therefore everything else, hangs off this.
---
--- `mo-expr` marks "wearing a non-idle expression" and exists for exactly one
--- reason: a transition takes its duration from the state it is heading *to*, so
--- the class is what lets adopting an expression and returning to idle run on
--- different clocks.
function M.rootClass(mode, expressive)
  return "mo-root"
    .. (mode == "always" and " mo-always" or "")
    .. (expressive and " mo-expr" or "")
end

--- `--a:1;--b:2`: for the string API, which has no style object to hand.
function M.serializeVars(vars, order)
  local out = {}
  for i = 1, #order do
    out[i] = order[i] .. ":" .. vars[order[i]]
  end
  return table.concat(out, ";")
end

return M
