local blobatar = require("blobatar")

--------------------------------------------------------------------------------
-- 🟢 BLOBATAR LIVE DEMO
-- Edit these variables to see the changes update live!
--------------------------------------------------------------------------------

local SEED_NAME = "blobatar"

-- Available Expressions:
-- "idle", "happy", "sad", "mad", "surprised", "wink", "sleepy", 
-- "smug", "unsure", "scared", "love", "shy", "sick"
local EXPRESSION = "idle"

-- Animation Modes:
-- "hover"  (animate when mouse is over)
-- "always" (constantly animate)
-- false    (no idle animation)
local ANIMATION_MODE = "hover"

-- Set to true to disable loops and morphs, but keep poses
local REDUCED_MOTION = false

--------------------------------------------------------------------------------

local b = nil

local function randomize()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    SEED_NAME = ""
    for i = 1, 8 do
        local r = love.math.random(1, #chars)
        SEED_NAME = SEED_NAME .. chars:sub(r, r)
    end
    buildBlobatar()
end

function love.load()
    love.graphics.setBackgroundColor(0.06, 0.06, 0.07)
    buildBlobatar()
end

function buildBlobatar()
    -- Create the blobatar with our options
    b = blobatar.new(SEED_NAME, { 
        animate = ANIMATION_MODE, 
        reduced = REDUCED_MOTION 
    })
    
    -- Set the expression (if not idle)
    if EXPRESSION ~= "idle" then 
        b:setExpression(EXPRESSION) 
    end
    
    -- Print details to the console (visible in the live editor)
    print("\n--- Blobatar Info ---")
    print("Seed:  " .. SEED_NAME)
    print("Shape: " .. (b.layout.shape or "N/A"))
    print("Body:  " .. (b.palette.head or "N/A"))
    print("Eye:   " .. (b.palette.eye or "N/A"))
    print("---------------------\n")
end

function love.update(dt)
    if not b then return end

    local w, h = love.graphics.getDimensions()
    local size = math.min(w, h) * 0.6
    local x = w / 2 - size / 2
    local y = h / 2 - size / 2

    local button_w, button_h = 140, 40
    local button_x = w / 2 - button_w / 2
    local button_y = y + size + 30

    local mx, my = love.mouse.getPosition()

    -- Hit testing for hover animations
    local is_hovered = b:hitTest(mx, my, x, y, size)
    b:setHover(is_hovered)
    
    -- Hit testing for randomize button cursor
    local hover_btn = mx >= button_x and mx <= button_x + button_w and my >= button_y and my <= button_y + button_h
    if hover_btn then
        love.mouse.setCursor(love.mouse.getSystemCursor("hand"))
    else
        love.mouse.setCursor()
    end
    
    -- Update the animation state
    b:update(dt)
end

function love.draw()
    if not b then return end

    local w, h = love.graphics.getDimensions()
    local size = math.min(w, h) * 0.6
    local x = w / 2 - size / 2
    local y = h / 2 - size / 2

    local button_w, button_h = 140, 40
    local button_x = w / 2 - button_w / 2
    local button_y = y + size + 30

    -- Draw the blobatar
    love.graphics.setColor(1, 1, 1)
    b:draw(x, y, size)
    
    -- Draw the randomize button
    local mx, my = love.mouse.getPosition()
    local hover_btn = mx >= button_x and mx <= button_x + button_w and my >= button_y and my <= button_y + button_h
    
    if hover_btn then
        love.graphics.setColor(1, 1, 1, 0.2)
    else
        love.graphics.setColor(1, 1, 1, 0.1)
    end
    love.graphics.rectangle("fill", button_x, button_y, button_w, button_h, 8)
    
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.printf("Randomize", button_x, button_y + 13, button_w, "center")

    -- Draw a helpful hint
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.printf("Edit the constants at the top of main.lua to change the blobatar!", 0, h - 50, w, "center")
end

function love.mousepressed(mx, my, button)
    if button == 1 then
        local w, h = love.graphics.getDimensions()
        local size = math.min(w, h) * 0.6
        local y = h / 2 - size / 2

        local button_w, button_h = 140, 40
        local button_x = w / 2 - button_w / 2
        local button_y = y + size + 30

        if mx >= button_x and mx <= button_x + button_w and my >= button_y and my <= button_y + button_h then
            randomize()
        end
    end
end
