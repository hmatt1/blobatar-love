--- Runs every suite that needs no browser and no graphics context.
---
---   luajit test/all.lua
---   lua5.4 test/all.lua
---
--- `test/parity.lua` is separate because it needs `test/fixtures.txt`, and the
--- LOVE renderer is checked by `tools/motion_shot.mjs` against a real browser
--- rather than from here.

-- Each suite runs in its own process, so one that crashes outright still leaves
-- the others' results on screen.
local files = { "test/invariants.lua", "test/motion.lua" }
local failed = 0
local lua = os.getenv("LUA") or "luajit"

for _, f in ipairs(files) do
  io.write("=== " .. f .. " ===\n")
  io.flush()
  local ok = os.execute(lua .. " " .. f)
  -- 5.1 returns an exit code, 5.2+ returns a boolean and the code.
  if ok ~= true and ok ~= 0 then failed = failed + 1 end
  io.write("\n")
  io.flush()
end

os.exit(failed)
