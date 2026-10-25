# Staged sample events captured from the generated Event trigger app.
# Every frame is a real Berry draw-call list; this is not a device recording.
def write_event_json(path, value)
  var file = open(path, "w")
  file.write(json.dump(value))
  file.close()
end

var event_names = ["motion", "mail_received", "mail_collected", "heat", "water", "doorbell", "garage"]
var event_showcase = []
for labels : [false, true]
  for scene : 0 .. 6
    var app = new_app({"topic":"test/events/+", "show_labels":labels, "cooldown_seconds":0})
    app.receive("test/events/" + event_names[scene], "true")
    app.loop()
    app.on_show()
    var frames = []
    for frame : 0 .. 39
      clock_ms = frame * 100
      app.draw()
      frames.push(drawing)
      if !labels event_showcase.push(drawing) end
    end
    var name = event_names[scene] + (labels ? "-labels" : "")
    write_event_json("event-captures/" + name + ".json", frames)
    app.on_hide()
  end
end
write_event_json("event-captures/eventtrigger-showcase.json", event_showcase)
print("Captured seven Event trigger examples, optional labels, and a staged 28-second showcase")
