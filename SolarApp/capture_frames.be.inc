app = full_app()
var frames = []
for scene : [0, 1, 2, 3, 4, 5]
  app.view = min(scene, 3)
  if scene == 3 feed(app, 5, "650") end
  if scene == 4 feed(app, 5, "-420") end
  if scene == 5
    app = new_app({})
    feed(app, 0, "0")
    feed(app, 2, "3000")
    app.view = 2
  end
  for frame : 0 .. 79
    clock_ms += 25
    app.view_started = clock_ms
    app.draw()
    if frame % 4 == 0 frames.push(drawing) end
  end
end
var output = open("animation-frames.json", "w")
output.write(json.dump(frames))
output.close()
print("Captured " + str(size(frames)) + " frames from actual Berry drawing calls")
