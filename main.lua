--- A demo of the port. The library itself is `blobatar/`.
---
---   love .
---
--- Hover a blobatar to wake it: the idle loops are gated on hover, because
--- ambient motion seen constantly is motion worth removing. The number and
--- letter keys switch the expression on every blobatar at once, which is the
--- view that makes the roster's separation rule visible: no two poses should be
--- confusable at this size.

local blobatar = require("blobatar")

local COLS, ROWS = 8, 5
local CELL = 96
local PAD = 12
local MARGIN_TOP = 108

local grid = {}
local focus = nil
local expr = "idle"
local mode = "hover"
local reduced = false
local showSvg = false

local NAMES = {
  "alain", "matt", "grace",
  "linus", "margaret", "katherine", "tim", "barbara", "radia", "vint",
  "donald", "alan", "edsger", "niklaus", "ken", "dennis", "bjarne", "guido",
  "yukihiro", "rich", "joe", "anders", "brendan", "roberto", "waldemar",
  "jose", "luiz", "carlos", "ana", "sofia", "yuki", "kenji", "mei", "nadia",
  "omar", "priya", "sven", "tomas",
}

local function build()
  grid = {}
  for i = 1, COLS * ROWS do
    local name = NAMES[(i - 1) % #NAMES + 1] .. (i > #NAMES and ("-" .. i) or "")
    local b = blobatar.new(name, { animate = mode, reduced = reduced })
    if expr ~= "idle" then b:setExpression(expr) end
    grid[i] = { blob = b, name = name }
  end
end

local function cellRect(i)
  local col = (i - 1) % COLS
  local row = math.floor((i - 1) / COLS)
  return PAD + col * (CELL + PAD), MARGIN_TOP + row * (CELL + PAD), CELL
end

function love.load()
  love.graphics.setBackgroundColor(0.05, 0.05, 0.06)
  font = love.graphics.newFont(13)
  small = love.graphics.newFont(11)
  love.graphics.setFont(font)
  build()
end

function love.update(dt)
  local mx, my = love.mouse.getPosition()
  focus = nil
  for i, cell in ipairs(grid) do
    local x, y, s = cellRect(i)
    local over = cell.blob:hitTest(mx, my, x, y, s)
    cell.blob:setHover(over)
    if over then focus = cell end
    cell.blob:update(dt)
  end
end

function love.draw()
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("blobatar for LOVE", PAD, 12)
  love.graphics.setFont(small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print(
    "expression: " .. expr .. "   [1-9 0 q w e] cycle    [a] animate: " .. mode
      .. "    [r] reduced motion: " .. tostring(reduced)
      .. "    [s] svg to console", PAD, 36)
  love.graphics.print(
    focus and (focus.name .. "   " .. focus.blob.layout.shape
               .. "   body " .. focus.blob.palette.head
               .. "   eye " .. focus.blob.palette.eye)
          or "hover a blobatar", PAD, 56)
  love.graphics.setFont(font)

  for i, cell in ipairs(grid) do
    local x, y, s = cellRect(i)
    cell.blob:draw(x, y, s)
  end

  love.graphics.setFont(small)
  love.graphics.setColor(0.4, 0.4, 0.45)
  love.graphics.print(
    "the same names render the same blobatars as the JavaScript library. "
      .. "test/parity.lua is what says so",
    PAD, love.graphics.getHeight() - 22)
  love.graphics.setFont(font)

  if focus then
    local x = love.graphics.getWidth() - 110
    love.graphics.setColor(0.1, 0.1, 0.12)
    love.graphics.rectangle("fill", x - 12, 4, 116, 100, 8)
    focus.blob:draw(x - 4, 8, 96)
  end
end

local ORDER = blobatar.expression.names

function love.keypressed(key)
  local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "q", "w", "e" }
  for i, k in ipairs(keys) do
    if key == k and ORDER[i] then
      expr = ORDER[i]
      for _, cell in ipairs(grid) do cell.blob:setExpression(expr) end
      return
    end
  end

  if key == "a" then
    mode = mode == "hover" and "always" or "hover"
    build()
  elseif key == "r" then
    reduced = not reduced
    build()
  elseif key == "s" and focus then
    print(blobatar.svg(focus.name, { size = 96 }))
  elseif key == "escape" then
    love.event.quit()
  end
end
