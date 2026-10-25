# This file is appended to a copied prefix of test_pelletstove.be only after
# the parent marks the PelletStove source ready. It never reads or writes the
# application repository.
def write_json(path, value)
  var f = open(path, "w")
  f.write(json.dump(value))
  f.close()
end

def normal_scene(view, updates)
  var app = new_app({"topic_state":"test/state"})
  state(app)
  for update : updates
    feed(app, update[0], update[1])
  end
  # Warm the real Berry drawing path before exposing this page.
  for warmup : 0 .. 79
    clock_ms += 25
    app.draw()
  end
  app.on_show()
  app.choose(view, 5000)
  return app
end

def standby_scene()
  var app = new_app({"topic_state":"test/state", "standby_skip":true})
  state(app)
  feed(app, 0, "standby")
  for warmup : 0 .. 79
    clock_ms += 25
    app.draw()
  end
  # A changed actual temperature is the one-shot temperature-only visit.
  feed(app, 6, "21.5")
  app.on_show()
  return app
end

def sample_frames(app, samples)
  var frames = []
  for sample : 0 .. samples - 1
    for tick : 0 .. 3
      clock_ms += 25
      app.draw()
    end
    frames.push(drawing)
  end
  return frames
end

var scenes = [
  ["heating", 0, []],
  ["temperatures", 5, []],
  ["pellets-empty", 1, [[2, "0"]]],
  ["pellets-half", 1, [[2, "15"]]],
  ["pellets-full", 1, [[2, "30"]]],
  ["cleaning-1h3", 2, [[3, "1.3"]]],
  ["cleaning-due", 2, [[3, "0"]]],
  ["ash-20", 3, [[4, "20"]]],
  ["ash-50", 3, [[4, "50"]]],
  ["ash-100", 3, [[4, "100"]]],
  ["cooling", 0, [[0, "cooling"]]],
  ["error-clear", 4, [[5, "false"]]],
  ["error-fault", 4, [[5, "true"]]],
  ["off", 0, [[8, "No"]]],
  ["standby-status", 0, [[0, "standby"], [6, "24.02"]]]
]

for scene : scenes
  var app = normal_scene(scene[1], scene[2])
  write_json("pellet-captures/" + scene[0] + ".json", sample_frames(app, 40))
end

var standby = standby_scene()
write_json("pellet-captures/standby-temperature.json", sample_frames(standby, 40))

# The normal rotation uses the app's once-per-second loop and elapsed timing.
var showcase = new_app({"topic_state":"test/state"})
state(showcase)
for warmup : 0 .. 79
  clock_ms += 25
  showcase.draw()
end
showcase.on_show()
var rotation = []
for sample : 0 .. 299
  for tick : 0 .. 3
    clock_ms += 25
    showcase.draw()
  end
  if sample % 10 == 9 showcase.loop() end
  rotation.push(drawing)
end
write_json("pellet-captures/pelletstove-showcase.json", rotation)
print("Captured PelletStove media scenes, standby temperature visit, and 30-second rotation")
