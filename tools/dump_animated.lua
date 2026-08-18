--- Writes the animated markup for the parity grid, for `tools/motion_shot.mjs`.
---
---   luajit tools/dump_animated.lua <expression> > /tmp/animated.html

package.path = "./?.lua;./?/init.lua;" .. package.path
local blobatar = require("blobatar")

local expr = arg[1] or "idle"
local out = {}

out[#out + 1] = [[<html><head><link rel="stylesheet" href="motion.css"></head>]]
out[#out + 1] = [[<body style="margin:0;background:#0f0f12;width:900px;height:620px;position:relative">]]

for i = 1, 40 do
  local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
  local svg = blobatar.animatedSvg("seed-" .. i,
    { size = 96, expression = expr ~= "idle" and expr or nil }, "always")
  out[#out + 1] = string.format(
    '<div style="position:absolute;left:%dpx;top:%dpx;width:96px;height:96px">%s</div>',
    12 + col * 108, 12 + row * 108, svg)
end

out[#out + 1] = "</body></html>"
io.write(table.concat(out, "\n"))
