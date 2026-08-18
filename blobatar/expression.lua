--- Expressions. A port of `src/expression.ts`.
---
--- An expression is a named pose the consumer sets and the library holds. It is
--- a separate axis from the idle loop in `animate.lua`: idle motion is ambient
--- and gated on hover, an expression is triggered and gated on nothing. A
--- blobatar can be sad and still breathing.
---
--- Pose-only, by definition. Every channel below moves a part the blobatar
--- already has. Nothing here adds a mark, so a blob grows no mouth when it is
--- happy. That ceiling is what the roster has to live inside: two capsule eyes
--- and a soft body, with no brows to carry anger the easy way.
---
--- The original passes each expression in as a value rather than naming it as a
--- string, so that a bundler can drop the ones a consumer never imports. Lua has
--- no tree shaking and the whole file is 6 KB, so they are all here, but the
--- interface is unchanged, and `blobatar.expression.happy` is still a value you
--- hand to the renderer rather than a name it looks up.

local PREFIX = (...):match("^(.*)%.[^.]*$") or ""
local color = require(PREFIX == "" and "color" or (PREFIX .. ".color"))

local M = {}

local util = require(PREFIX == "" and "util" or (PREFIX .. ".util"))

--- The original's `r3` returns a string, not a number, and that matters: Lua 5.4
--- prints an integral float as "4.0" where 5.1 prints "4", so a pose emitted as
--- numbers would serialize differently on different runtimes.
local r3 = function(v) return util.numstr(util.r3(v)) end

----------------------------------------------------------------------
-- The pose
----------------------------------------------------------------------

--- The channels a pose may touch, and nothing else.
---
--- Petals are excluded on purpose: a sun's nine petals are silhouette, and
--- moving them independently reads as wind or as the creature coming apart. Path
--- data is excluded because interpolating it puts geometry on the main thread
--- every frame.
---
--- The body deforms for nothing, so it no longer deforms. `bdy` survives because
--- it is a rigid translate. It moves the creature without distorting it, which is
--- what happy's lift and sad's sink actually needed.
---
--- Units: scales are factors, `tilt` is degrees, offsets are viewBox units, and
--- `heat` and `shake` are 0-1 amounts. `tilt` and `edx` are mirrored per side.
---
--- The `*2` channels are the second eye's differential, not its value: they add
--- to the shared channel on the right eye only, so an identity of 0 is a
--- symmetric face.
---
--- Fields:
---   esx    eye width, about each eye's own center
---   esy    eye height, about each eye's own center
---   tilt   eye tilt, mirrored per side: left rotates by -tilt, right by +tilt
---   edy    eye pair offset, positive = down
---   edx    eye convergence, positive = apart
---   esx2   extra width on the right eye only
---   esy2   extra height on the right eye only
---   tilt2  extra tilt on the right eye only, before the per-side mirroring
---   lock   how much of the seeded eye lean the pose overrides, 0-1
---   heat   how far the palette shifts toward its hot pair, 0-1
---   shake  tremor amplitude, 0-1
---   bdy    whole-creature offset, positive = down
---
--- On `tilt`, which is the trap in this file: what a tilt reads as depends on
--- the eye's orientation, and the sign flips when it changes. On a portrait
--- capsule (the natural shape here, median aspect 2.55:1) a positive tilt leans
--- both tops outward and brings the inner edges down, which is the angry
--- direction. Flatten the capsule past square with `esy` and the same rotation
--- raises the inner ends instead: on a landscape bar, negative tilt is the angry
--- `\ /` and positive is the sad `/ \`. No test in the suite can see the
--- difference. Look at the render.
---
--- On `lock`: `tilt` is a brow, and a brow is an absolute direction. The layout
--- leans each eye by up to 12 degrees in a single seeded direction. That is
--- identity, and good identity, on an idle face. Added to a pose it is noise on
--- the one channel that carries the meaning. So the loud poses take their tilt
--- absolute, and the seeded lean returns intact the moment the expression
--- clears.

--- The identity pose, and the channel order. Every channel's custom property is
--- its own name prefixed, so no lookup table is needed, and iterating this in a
--- fixed order is what lets `poseVars` skip channels a pose leaves alone.
M.CHANNELS = {
  "esx", "esy", "tilt", "edy", "edx", "esx2", "esy2", "tilt2",
  "lock", "heat", "shake", "bdy",
}

M.IDENT = {
  esx = 1,
  esy = 1,
  tilt = 0,
  edy = 0,
  edx = 0,
  esx2 = 0,
  esy2 = 0,
  tilt2 = 0,
  lock = 0,
  heat = 0,
  shake = 0,
  bdy = 0,
}

--- Fills in every channel a pose leaves out, so the rest of the library can read
--- a pose without checking for nil on each field.
local function pose(p)
  local out = {}
  for i = 1, #M.CHANNELS do
    local k = M.CHANNELS[i]
    local v = p[k]
    out[k] = v == nil and M.IDENT[k] or v
  end
  return out
end

M.pose = pose

----------------------------------------------------------------------
-- Applying a pose
----------------------------------------------------------------------

--- The animated path in the original: the pose as registered CSS custom
--- properties, with the identity omitted.
---
--- Kept because `svg.lua` reproduces the original's animated markup, and because
--- it is the clearest statement of which channels a pose actually moves. The
--- LOVE renderer reads the pose numbers directly.
function M.poseVars(p)
  local out, order = {}, {}
  for i = 1, #M.CHANNELS do
    local k = M.CHANNELS[i]
    -- `heat` is the one channel the stylesheet never sees. Colour is not
    -- composed in CSS. It is resolved here and emitted as a finished pair, so a
    -- `--mo-heat` declaration would be a variable that looks live and is read by
    -- nothing.
    if k ~= "heat" and p[k] ~= M.IDENT[k] then
      out["--mo-" .. k] = r3(p[k])
      order[#order + 1] = "--mo-" .. k
    end
  end
  return out, order
end

--- The palette a tinting pose wears: the resolved one, mixed `heat` of the way
--- toward the pair `tinted` derives for its target.
---
--- The mix happens here rather than in the stylesheet, and in the original that
--- was the load-bearing choice: a hot endpoint held in a custom property vanishes
--- the instant an expression is cleared and snaps the fill while the rest of the
--- pose is still easing. Here it matters for a simpler reason: LOVE has no
--- custom properties, and this is where the colour has to be decided anyway.
function M.tintWith(pal, p, t)
  local head, eye = color.tinted(pal.head, pal.eye, t)
  local out = {}
  for k, v in pairs(pal) do out[k] = v end
  out.head = color.mixHex(pal.head, head, p.heat)
  out.eye = color.mixHex(pal.eye, eye, p.heat)
  return out
end

--- The static path: eye channels baked into geometry, body channels handed back
--- as a translate for the caller to apply.
---
--- Baking is exact rather than approximate, because the animated composition runs
--- in the same order the geometry does. `superellipse` scales by `rx`/`ry` and
--- then rotates, and the animated path applies the pose scale innermost and the
--- tilt outside it. The offsets commute with both, since the rotation and scale
--- are about each eye's own center.
function M.bakePose(l, p)
  local eyes = {}
  for i = 1, #l.eyes do
    local e = l.eyes[i]
    -- The original's `i ? 1 : -1`: -1 on the left eye, +1 on the right, so a
    -- positive tilt leans both tops outward and brings the inner edges down.
    -- That asymmetry is the entire brow vocabulary available here.
    local side = i == 2 and 1 or -1
    local second = i == 2
    eyes[i] = {
      cx = e.cx + p.edx * side,
      cy = e.cy + p.edy,
      -- The `*2` differential lands on the right eye only, and is added before
      -- the mirroring on `tilt`. Adding it after would flip its sign on the
      -- left eye and turn a one-sided brow into a symmetric one.
      rx = e.rx * (p.esx + (second and p.esx2 or 0)),
      ry = e.ry * (p.esy + (second and p.esy2 or 0)),
      n = e.n,
      -- `lock` fades the seeded lean out rather than switching it off, which is
      -- what lets it interpolate. At 0 this is the plain sum it always was.
      rot = e.rot * (1 - p.lock) + (p.tilt + (second and p.tilt2 or 0)) * side,
    }
  end

  local out = {}
  for k, v in pairs(l) do out[k] = v end
  out.eyes = eyes

  return out, p.bdy
end

----------------------------------------------------------------------
-- The roster
----------------------------------------------------------------------

--- Frozen per major, exactly like the shape thresholds and the tone set. A
--- fifth expression added later is additive and safe; renaming one is not.
---
--- The numbers come off measurement rather than taste alone. Across 4000 seeds
--- the capsule's natural aspect is 2.03 / 2.55 / 3.12 (p10 / median / p90,
--- ry:rx), which is a portrait capsule, so a landscape bar needs `esx/esy`
--- near 10, not near 2. Containment was never the binding guard; fusion is,
--- and a widened pair buys its clearance back through `edx` at about 1:2.
---
--- The rule that picked the second and third rosters: a pose has to differ from
--- its nearest neighbour on three channels at once, and a tint is never the only
--- thing separating two poses. `sick` is not a green `sleepy`, it is `sleepy`
--- with the bars tilted and the body trembling, and it would still be a
--- different pose in greyscale.

local function expr(p, tint)
  return { p = pose(p), tint = tint }
end

M.idle = expr({})

--- Wide flat arcs riding high: the universal smiling squint, at full volume.
M.happy = expr({
  esx = 1.72, esy = 0.3, tilt = 8, edy = -1.5, edx = 1.5,
  -- A touch of asymmetry, well short of a wink. The pair reads as drawn rather
  -- than as stamped twice, which is the whole reason the channel exists.
  esx2 = 0.08, esy2 = 0.05, tilt2 = -16,
  lock = 1, bdy = -2.2,
})

--- Small eyes, low and drifted apart, over a body that sinks.
M.sad = expr({
  esx = 0.6, esy = 0.56, tilt = 26, edy = 3.6, edx = 1.9,
  esx2 = -0.05, esy2 = -0.07, tilt2 = -7,
  lock = 1, bdy = 2.6,
})

--- A hard `\ /` of flat bars over a body that compresses, leans and runs hot.
---
--- The only pose in the first roster that spends `heat` and `shake`, and the
--- reason both channels exist: two capsule eyes with no brows cannot reach anger
--- on geometry alone. `esx` widens the capsules until the tilt has a bar to work
--- on; `edx` stays slightly positive because the widening already closes the
--- inner gap far more than a convergence would.
M.mad = expr({
  esx = 1.85, esy = 0.26, tilt = -33, edy = 0.4, edx = 0.6,
  esx2 = 0, esy2 = -0.03, tilt2 = 5,
  lock = 1, heat = 0.62, shake = 0.55, bdy = 0.8,
}, color.HOT)

--- Eyes enlarged rather than squashed: the one direction the first roster never
--- went. Every other pose reduces `esy`; against three poses that all live
--- between 0.26 and 0.56, a pose at 1.2 cannot be mistaken for any of them at
--- any size.
M.surprised = expr({
  esx = 1.34, esy = 1.2, tilt = -6, edy = -1.05, edx = 0.5,
  esx2 = 0.05, esy2 = 0.07, tilt2 = 3,
  lock = 1, bdy = -1.4,
})

--- One eye a flat arc, the other open. The pose the per-eye differentials were
--- built for, and the only one whose meaning *is* the asymmetry.
M.wink = expr({
  esx = 1.32, esy = 0.76, tilt = 5, edy = -0.6, edx = 0.8,
  esx2 = 0.26, esy2 = -0.56, tilt2 = -11,
  lock = 1, bdy = -1.1,
})

--- Flat bars with no angle in them, sitting low over a sunk body.
---
--- `tilt = 0` under `lock = 1` is not a no-op: it cancels the seeded lean, which
--- is the whole point. A level pair of bars is what reads as lidded, and a
--- seed's 12 degree lean on that pose reads as suspicion instead.
M.sleepy = expr({
  esx = 1.14, esy = 0.22, tilt = 0, edy = 2.4, edx = 0.3,
  esx2 = -0.04, esy2 = 0.03, tilt2 = 4,
  lock = 1, bdy = 1.2,
})

--- Half-lidded, lifted, and leaning in parallel.
---
--- `tilt2 = -2 * tilt` exactly: the mirroring makes the left eye -tilt and the
--- right tilt + tilt2, so setting the differential to -2t puts both at -t and the
--- pair tilts together rather than symmetrically. A symmetric tilt is a brow and
--- reads as an emotion; a parallel tilt is a head cocked and reads as an
--- attitude.
M.smug = expr({
  esx = 1.3, esy = 0.42, tilt = 18, edy = -0.5, edx = 0.5,
  esx2 = 0.06, esy2 = -0.06, tilt2 = -36,
  lock = 1, bdy = -1,
})

--- One eye narrowed, the other open: the second differential-first pose, and
--- the quieter one. Two eyes at different heights on the same face is a thing no
--- symmetric pose can say.
M.unsure = expr({
  esx = 0.95, esy = 1.02, tilt = 4, edy = -0.2, edx = 0.3,
  esx2 = 0.24, esy2 = -0.44, tilt2 = -18,
  lock = 1, bdy = 0,
})

--- Small eyes held high and pulled together, over a body that trembles.
---
--- The second pose to spend `shake`, and the one that shows the channel is not
--- mad's private property. A tremor is arousal, and arousal is not only anger.
--- No tint, which is the point of listing it next to `mad`: fear is not hot.
M.scared = expr({
  esx = 0.78, esy = 0.96, tilt = -12, edy = -1.5, edx = -0.8,
  esx2 = -0.04, esy2 = 0.05, tilt2 = 4,
  lock = 1, shake = 0.35, bdy = -0.6,
})

--- Tall narrow eyes, drawn together, lifted, and rose.
---
--- The two large-eyed poses disagree on shape rather than only on direction.
--- `surprised` is wide and spread; this is narrow and drawn together: startled
--- *by* you against looking *at* you. A pose that only works in colour is a pose
--- that stops working in a screenshot.
M.love = expr({
  esx = 0.86, esy = 1.28, tilt = -14, edy = -0.5, edx = -0.35,
  esx2 = 0.05, esy2 = 0.06, tilt2 = 6,
  lock = 1, heat = 0.6, bdy = -1.6,
}, color.ROSE)

--- Small squeezed eyes, low and wide apart, over a body that sinks and blushes.
--- `BLUSH` pulls only 0.4 of the way and lands pale on purpose; a shy blobatar
--- that goes as red as an angry one is an angry one.
M.shy = expr({
  esx = 0.62, esy = 0.5, tilt = 10, edy = 1.4, edx = -0.2,
  esx2 = -0.05, esy2 = -0.04, tilt2 = -8,
  lock = 1, heat = 0.55, bdy = 0.9,
}, color.BLUSH)

--- Flat bars slumped into a `/ \`, over a body that sinks, greens and trembles.
---
--- The tilt is positive and that is not a typo. On a landscape bar the sign
--- inverts, so +20 raises the inner ends into the worried `/ \` while mad's -33
--- drops them into the angry `\ /`.
M.sick = expr({
  esx = 1.25, esy = 0.34, tilt = 20, edy = 1.8, edx = 0.8,
  esx2 = 0.05, esy2 = -0.05, tilt2 = -6,
  lock = 1, heat = 0.6, shake = 0.18, bdy = 1.4,
}, color.BILE)

--- Every pose by name, for callers that hold one as configuration.
M.byName = {
  idle = M.idle, happy = M.happy, sad = M.sad, mad = M.mad,
  surprised = M.surprised, wink = M.wink, sleepy = M.sleepy, smug = M.smug,
  unsure = M.unsure, scared = M.scared, love = M.love, shy = M.shy,
  sick = M.sick,
}

--- In roster order, which is the order they were added and the order a picker
--- should show them in.
M.names = {
  "idle", "happy", "sad", "mad", "surprised", "wink", "sleepy", "smug",
  "unsure", "scared", "love", "shy", "sick",
}

--- Resolves a name or a value to an expression, so callers can pass either.
function M.resolve(e)
  if e == nil then return nil end
  if type(e) == "string" then return M.byName[e] end
  return e
end

--- The palette a pose wears, given the one it starts from.
function M.tint(e, pal)
  if not e or not e.tint then return pal end
  return M.tintWith(pal, e.p, e.tint)
end

return M
