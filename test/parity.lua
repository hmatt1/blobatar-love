--- Diffs the port against the original, row by row.
---
--- `test/fixtures.txt` is what the TypeScript library produced for a wide slice
--- of its input space (every option, every expression, 3000 seeds) written by
--- `tools/gen_fixtures.mjs`. Every row here re-renders the same input through the
--- port and compares.
---
--- The SVG rows are the load-bearing ones. A blobatar's whole pipeline (hash,
--- traits, palette, layout, containment fit, pose baking, path construction and
--- rounding) is in that string, so a byte comparison covers all of it at once
--- and a difference points at a coordinate rather than at a feeling. Those are
--- compared byte for byte, and so are the palettes, the motion variables and the
--- pose variables.
---
--- The layout rows are the exception, and they are compared to 1e-9 rather than
--- exactly. They report twelve decimals of numbers that never reach the markup at
--- that precision, and at the twelfth decimal the comparison stops being about
--- this port: `Math.sin` and `Math.hypot` are approximated rather than specified,
--- and JavaScript engines disagree with each other about their last bit. V8 and
--- JavaScriptCore return different `Math.hypot` results for about a third of all
--- inputs. So does the C library Lua calls. A tolerance of 1e-9 is four orders of
--- magnitude tighter than the rounding the renderer applies and still leaves room
--- for that. The count of rows that are not bit-identical is reported separately,
--- because a jump in it is worth looking at even though a small number is not.
---
---   luajit test/parity.lua
---   lua5.4 test/parity.lua [path/to/fixtures.txt]

package.path = "./?.lua;./?/init.lua;" .. package.path

local blobatar = require("blobatar")
local animate = require("blobatar.animate")
local expression = require("blobatar.expression")
local traits = require("blobatar.traits")

local FIXTURES = arg and arg[1] or "test/fixtures.txt"

local function unhex(h)
  return (h:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
end

--- The option sets are written as JSON, and every one of them is flat, so this
--- reads them without a JSON library. Anything more structured than the shapes
--- `gen_fixtures.mjs` emits would need one.
local function parse_opts(s)
  local o = {}
  local body = s:match("^%s*{(.*)}%s*$")
  if not body or body:match("^%s*$") then return o end

  -- `traits` and `palette` are the two nested objects.
  body = body:gsub('"(%w+)"%s*:%s*{(.-)}', function(key, inner)
    local sub = {}
    for k, v in inner:gmatch('"([^"]+)"%s*:%s*("?[^,"]*"?)') do
      sub[k] = tonumber(v) or v:gsub('"', "")
    end
    o[key] = sub
    return ""
  end)

  for k, v in body:gmatch('"([%w]+)"%s*:%s*([^,]+)') do
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "true" then
      o[k] = true
    elseif v == "false" then
      o[k] = false
    elseif v:sub(1, 1) == '"' then
      o[k] = v:sub(2, -2)
    else
      o[k] = tonumber(v)
    end
  end
  return o
end

local counts, fails = {}, {}
local inexact = 0
local shown = 0

local function check(kind, ok, detail)
  counts[kind] = (counts[kind] or 0) + 1
  if not ok then
    fails[kind] = (fails[kind] or 0) + 1
    if shown < 8 then
      shown = shown + 1
      print("FAIL [" .. kind .. "] " .. detail)
    end
  end
end

--- Field-by-field comparison of two layout rows: strings must match, numbers
--- must agree to `TOL`.
local TOL = 1e-9

local function close_enough(got, want)
  if got == want then return true end
  local gi = got:gmatch("[^ ]+")
  local wi = want:gmatch("[^ ]+")
  while true do
    local g, w = gi(), wi()
    if g == nil and w == nil then return true end
    if g == nil or w == nil then return false, "field count" end
    if g ~= w then
      local gn = g:gmatch("[^,;]+")
      local wn = w:gmatch("[^,;]+")
      while true do
        local a, c = gn(), wn()
        if a == nil and c == nil then break end
        if a == nil or c == nil then return false, "value count" end
        if a ~= c then
          local x, y = tonumber(a), tonumber(c)
          if not x or not y then return false, "not a number: " .. a .. " vs " .. c end
          if math.abs(x - y) > TOL then
            return false, string.format("%.12g vs %.12g", x, y)
          end
        end
      end
    end
  end
end

local f = io.open(FIXTURES, "r")
if not f then
  print("no fixtures at " .. FIXTURES .. "; run tools/gen_fixtures.sh first")
  os.exit(1)
end

for line in f:lines() do
  local kind, a, b, payload = line:match("^(%a)\t([^\t]*)\t([^\t]*)\t(.*)$")
  if kind == "S" then
    local name = unhex(a)
    local opts = parse_opts(unhex(b))
    local got = blobatar.svg(name, opts)
    check("svg", got == payload,
      string.format("seed=%q opts=%s\n  want %s\n  got  %s", name, unhex(b), payload, got))
  elseif kind == "E" then
    local name = unhex(a)
    local got = blobatar.svg(name, { expression = b })
    check("expression", got == payload,
      string.format("seed=%q expr=%s\n  want %s\n  got  %s", name, b, payload, got))
  elseif kind == "L" then
    local name = unhex(a)
    local l = blobatar.layout(name, { expression = b })
    -- `(-0).toFixed(12)` is "0.000000000000" in JavaScript and
    -- "-0.000000000000" in Lua. The value is the same negative zero either way
    -- A rotation of -0 turns nothing, and the serializer folds the sign, so
    -- this normalizes the printing rather than the number.
    local fmt = function(v)
      if v == 0 then return string.format("%.12f", 0) end
      return string.format("%.12f", v)
    end
    local radii = {}
    for i = 1, #l.body.radii do radii[i] = fmt(l.body.radii[i]) end
    local petals = {}
    for i = 1, #l.petals do
      local p = l.petals[i]
      petals[i] = fmt(p.cx) .. "," .. fmt(p.cy) .. "," .. fmt(p.r)
    end
    local eyes = {}
    for i = 1, #l.eyes do
      local e = l.eyes[i]
      eyes[i] = table.concat({ fmt(e.cx), fmt(e.cy), fmt(e.rx), fmt(e.ry), fmt(e.n), fmt(e.rot) }, ",")
    end
    local got = table.concat({
      l.shape, fmt(l.body.cx), fmt(l.body.cy), fmt(l.body.rx), fmt(l.body.ry),
      fmt(l.body.n), fmt(l.body.rot), table.concat(radii, ","),
      #petals > 0 and table.concat(petals, ";") or "-",
      table.concat(eyes, ";"),
      l.palette.bg, l.palette.head, l.palette.eye,
    }, " ")
    local ok, why = close_enough(got, payload)
    if got ~= payload then inexact = inexact + 1 end
    check("layout", ok,
      string.format("seed=%q expr=%s (%s)\n  want %s\n  got  %s",
                    name, b, why or "", payload, got))
  elseif kind == "M" then
    local name = unhex(a)
    local vars, order = animate.motionVars(traits.traits(name))
    local out = {}
    for i = 1, #order do out[i] = order[i] .. ":" .. vars[order[i]] end
    local got = table.concat(out, ";")
    check("motion", got == payload,
      string.format("seed=%q\n  want %s\n  got  %s", name, payload, got))
  elseif kind == "P" then
    local e = expression.byName[b]
    local vars, order = expression.poseVars(e.p)
    local out = {}
    for i = 1, #order do out[i] = order[i] .. ":" .. vars[order[i]] end
    local got = table.concat(out, ";")
    check("pose", got == payload,
      string.format("expr=%s\n  want %s\n  got  %s", b, payload, got))
  end
end
f:close()

local total, bad = 0, 0
local kinds = { "svg", "expression", "layout", "motion", "pose" }
print("")
for _, k in ipairs(kinds) do
  local n = counts[k] or 0
  local e = fails[k] or 0
  total = total + n
  bad = bad + e
  print(string.format("  %-11s %6d checked  %d failed", k, n, e))
end
print(string.format("\n%d rows, %d failures", total, bad))
if inexact > 0 then
  print(string.format("(%d layout rows agreed to %g but not bit for bit: "
    .. "the last-bit disagreement between engines on Math.sin and Math.hypot)",
    inexact, TOL))
end
os.exit(bad == 0 and 0 or 1)
