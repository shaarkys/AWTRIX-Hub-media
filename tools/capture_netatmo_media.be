# Synthetic station data captured through the generated app's actual draw path.
# No Netatmo connection is made; new_app/deliver are the local test harness.
def save_netatmo_frames(name, frames)
  var file = open("netatmo-captures/" + name + ".json", "w")
  file.write(json.dump(frames))
  file.close()
end

def netatmo_media_sample()
  # The regression fixture intentionally has zero rain/mean wind. Give the
  # publication demo explicit synthetic wet/breezy readings for animation.
  var payload = json.load(load_fixture("stations-v1.json"))
  for device : payload["body"]["devices"]
    for module : device.find("modules", [])
      var values = module.find("dashboard_data", {})
      if module.find("type") == "NAModule3"
        values["Rain"] = 0.4 values["sum_rain_1"] = 1.2
      elif module.find("type") == "NAModule2"
        values["WindStrength"] = 12.4 values["WindAngle"] = 225
      end
    end
  end
  return json.dump(payload)
end

var scene_names = {"indoor/climate":"indoor-climate", "indoor/air":"indoor-air",
  "outdoor/climate":"outdoor-climate", "outdoor/range":"outdoor-range",
  "extra/climate":"couch-climate", "extra/air":"couch-air", "rain/rain":"rain",
  "rain/rain_day":"rain-day", "wind/wind":"wind", "wind/wind_dir":"wind-direction"}
var app = new_app({"seconds":4})
deliver(app, netatmo_media_sample(), 200)
app.on_show()
assert(size(app.frozen_pages) == 8, "default media fixture must produce eight real module pages")
var showcase = []
for index : 0 .. size(app.frozen_pages) - 1
  var page = app.frozen_pages[index]
  var name = scene_names[page.find("kind") + "/" + page.find("view")]
  var frames = []
  for frame : 0 .. 39
    clock_ms = index * 4000 + frame * 100
    app.draw()
    frames.push(drawing)
    showcase.push(drawing)
  end
  save_netatmo_frames(name, frames)
end
save_netatmo_frames("netatmov2-showcase", showcase)

# Capture optional detail pages separately from the default rotation.
app = new_app({"seconds":4, "show_minmax":true, "show_direction":true})
deliver(app, netatmo_media_sample(), 200)
app.on_show()
assert(size(app.frozen_pages) == 10, "optional details add two pages")
for index : 0 .. size(app.frozen_pages) - 1
  var page = app.frozen_pages[index]
  if page.find("view") == "range" || page.find("view") == "wind_dir"
    var frames = []
    for frame : 0 .. 39
      clock_ms = index * 4000 + frame * 100
      app.draw()
      frames.push(drawing)
    end
    save_netatmo_frames(scene_names[page.find("kind") + "/" + page.find("view")], frames)
  end
end

# Optional labels identify multiple rooms without changing the default look.
app = new_app({"seconds":4, "show_names":true})
deliver(app, netatmo_media_sample(), 200)
app.on_show()
for index : 0 .. size(app.frozen_pages) - 1
  var page = app.frozen_pages[index]
  if page.find("kind") == "extra" && page.find("view") == "climate"
    var frames = []
    for frame : 0 .. 39
      clock_ms = index * 4000 + frame * 100
      app.draw()
      frames.push(drawing)
    end
    save_netatmo_frames("couch-climate-named", frames)
  end
end

for age : [46, 184]
  app = new_app({"seconds":4})
  deliver(app, netatmo_media_sample(), 200)
  clock_ms = age * 60000
  epoch_value = 1700000000000.0 + age * 60000.0
  var base = clock_ms
  app.on_show()
  var outdoor_index = -1
  for index : 0 .. size(app.frozen_pages) - 1
    var page = app.frozen_pages[index]
    if page.find("kind") == "outdoor" && (page.find("view") == "climate" || page.find("view") == "offline") outdoor_index = index end
  end
  assert(outdoor_index >= 0, "outdoor media fixture is missing")
  var frames = []
  for frame : 0 .. 39
    clock_ms = base + outdoor_index * 4000 + frame * 100
    app.draw()
    frames.push(drawing)
  end
  save_netatmo_frames(age == 46 ? "stale-outdoor" : "expired-outdoor", frames)
end

for state : ["no-modules", "signin"]
  app = new_app({"seconds":4, "__oauth_ready":state != "signin"})
  if state != "signin" deliver(app, load_fixture("stations-empty.json"), 200) end
  app.on_show()
  var frames = []
  for frame : 0 .. 39
    clock_ms = frame * 100
    app.draw()
    frames.push(drawing)
  end
  save_netatmo_frames(state, frames)
end
print("Captured eight default NetatmoV2 pages, two optional details, a room label, four diagnostic states and a 32-second synthetic rotation")
