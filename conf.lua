function love.conf(t)
  t.identity = "blobatar-love"
  t.window.title = "blobatar"
  t.window.width = 900
  t.window.height = 700
  t.window.resizable = true
  t.window.highdpi = true
  t.window.msaa = 4
  t.modules.physics = false
  t.modules.joystick = false
end
