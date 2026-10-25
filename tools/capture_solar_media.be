# Capture SolarApp scenes after the real Berry test harness has defined its mocks.
# Every frame below is the script's own draw-call array; no pixels are hand-authored here.
def write_json(path, value)
  var f = open(path, "w")
  f.write(json.dump(value))
  f.close()
end

def solar_settings(style)
  return {"topic_battery_soc":"battery/soc", "topic_battery_power":"battery/w",
    "topic_grid_power":"grid/w", "max_power":5000, "visual_style":style,
    "rotate_seconds":5, "anim_speed":4}
end

def prepared(values, view, style)
  var app = new_app(solar_settings(style))
  app.setup()
  for index : 0 .. 5
    if values[index] != nil feed(app, index, str(values[index])) end
  end
  app.view = view
  # Let smoothing and the frame-driven animation settle before the visible sample.
  for warmup : 0 .. 79
    clock_ms += 25
    app.draw()
  end
  app.on_show()
  app.view = view
  app.view_started = clock_ms
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
  ["solar-production-large", [2500, 12345, 900, 76, 850, -420], 0, "sun_large"],
  ["solar-production-half", [2500, 12345, 900, 76, 850, -420], 0, "sun_half"],
  ["battery-charging", [0, 12345, 900, 76, 850, 0], 1, "sun_large"],
  ["battery-discharging", [0, 12345, 900, 76, -850, 0], 1, "sun_large"],
  ["house-solar", [2500, 12345, 900, 76, 850, -420], 2, "sun_large"],
  ["house-battery", [0, 12345, 900, 76, -850, 0], 2, "sun_large"],
  ["house-grid", [0, 12345, 900, 76, 0, 420], 2, "sun_large"],
  ["house-unknown", [0, 12345, 3000, 76, 0, 0], 2, "sun_large"],
  ["grid-import", [0, 12345, 900, 76, 0, 420], 3, "sun_large"],
  ["grid-export", [0, 12345, 900, 76, 0, -420], 3, "sun_large"],
  ["grid-idle", [0, 12345, 900, 76, 0, 0], 3, "sun_large"]
]

for scene : scenes
  var app = prepared(scene[1], scene[2], scene[3])
  write_json("captures/" + scene[0] + ".json", sample_frames(app, 40))
end

# A normal four-view cycle: 5 seconds per page, 20 seconds total at 10 FPS output.
var showcase_app = prepared([2500, 12345, 900, 76, 850, -420], 0, "sun_large")
write_json("captures/solarapp-showcase.json", sample_frames(showcase_app, 200))
print("Captured SolarApp media scenes and a 20-second four-view rotation")
