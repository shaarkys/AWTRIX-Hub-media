# Run from EventTrigger/ with the Berry 1.1 32-bit/single-precision interpreter.
# This is a device-free harness: all MQTT, rotation, display and drawing calls
# are local mocks. The reusable prefix ends immediately before the first app
# construction below; tools/build.py copies that prefix for media capture.
import json
import string

var cfg = {}
var clock_ms = 0
var subscriptions = {}
var messages = []
var show_calls = 0
var next_calls = 0
var power_calls = 0
var show_mode = "deferred"
var show_result = nil
var app_ref = nil
var drawing = []
var text_calls = []
var pixel_calls = []
var line_calls = []
var fill_calls = []
var rect_calls = []
var checks = 0

# Native small-font ASCII advances, copied from the PelletStove harness and
# checked against source-notices/awtrix-small.bdf by the Python validator.
var advances = {" ":2, "!":2, "'":2, "(":3, ")":3, ",":3, ".":2, ":":2, ";":3,
  "I":2, "M":6, "N":5, "Q":5, "W":6, "`":3, "i":2, "|":2}

var store = module("store")
store.get = def (key, fallback) return cfg.find(key, fallback) end
var mqtt = module("mqtt")
mqtt.subscribe = def (topic, callback) subscriptions[topic] = callback end
var rotation = module("rotation")
rotation.show = def()
  show_calls += 1
  if show_mode == "sync" && app_ref != nil app_ref.on_show() end
  return show_result
end
rotation.next = def() next_calls += 1 end
var display = module("display")
display.power = def(on) if on == true power_calls += 1 end end

def now_ms() return clock_ms end
def log(message) messages.push(message) end
def num(value, fallback)
  if type(value) == "string"
    try value = json.load(value) except .. return fallback end
  end
  return type(value) == "int" || type(value) == "real" ? value : fallback
end
def format(pattern, value) return string.format(pattern, value) end
def max(a, b) return a > b ? a : b end
def min(a, b) return a < b ? a : b end
def clamp(v, a, b) return max(a, min(v, b)) end
def font(name) assert(name == "small", "unexpected font") end
def text_width(label)
  var width = 0
  for index : 0 .. size(label) - 1
    width += advances.find(label[index .. index], 4)
  end
  return width
end
def clear()
  drawing = []
  text_calls = []
  pixel_calls = []
  line_calls = []
  fill_calls = []
  rect_calls = []
end
def point_ok(x, y)
  assert(x >= 0 && x < 52 && y >= 0 && y < 16, "draw point out of bounds")
end
def pixel(x, y, color)
  point_ok(x, y)
  var call = ["pixel", x, y, color]
  pixel_calls.push(call)
  drawing.push(call)
end
def line(x, y, x2, y2, color)
  point_ok(x, y) point_ok(x2, y2)
  var call = ["line", x, y, x2, y2, color]
  line_calls.push(call)
  drawing.push(call)
end
def rect_fill(x, y, width, height, color)
  assert(width > 0 && height > 0, "invalid fill rectangle")
  point_ok(x, y) point_ok(x + width - 1, y + height - 1)
  var call = ["fill", x, y, width, height, color]
  fill_calls.push(call)
  drawing.push(call)
end
def rect(x, y, width, height, color)
  assert(width > 0 && height > 0, "invalid outline rectangle")
  point_ok(x, y) point_ok(x + width - 1, y + height - 1)
  var call = ["rect", x, y, width, height, color]
  rect_calls.push(call)
  drawing.push(call)
end
def text(x, y, label, color)
  assert(x >= 0 && x + text_width(label) <= 52, "text exceeds panel bounds: " + label)
  assert(y >= 1 && y <= 15, "text baseline outside panel")
  var call = ["text", x, y, label, color]
  text_calls.push(call)
  drawing.push(call)
end
def check(condition, message)
  assert(condition, message)
  checks += 1
end
def has_label(label)
  for call : text_calls
    if call[3] == label return true end
  end
  return false
end
def has_art()
  return size(pixel_calls) > 0 || size(line_calls) > 0 || size(fill_calls) > 0 || size(rect_calls) > 0
end
def new_app(settings)
  cfg = settings
  clock_ms = 0
  subscriptions = {}
  messages = []
  show_calls = 0
  next_calls = 0
  power_calls = 0
  show_mode = cfg.find("__show_mode", "deferred")
  show_result = cfg.find("__show_result", nil)
  clear()
  var app = compile("EventTrigger.ax", "file")()
  app_ref = app
  app.setup()
  return app
end
def show_event(app, name, payload)
  app.receive("test/events/" + name, payload)
  app.loop()
  app.on_show()
  return app
end

var app = new_app({})
check(size(subscriptions) == 1, "default MQTT filter is subscribed once")
check(!app.should_show(), "idle app is skipped while MQTT remains active")
app.draw()
check(app.current_scene == -1 && has_art(), "idle manual frame is real artwork")

# Deferred and synchronous rotation.show both request exactly once.
app = new_app({"cooldown_seconds":0})
app.receive("test/events/motion", "true")
check(show_calls == 1 && !app.shown && app.should_show(), "deferred event requests one turn")
app.loop()
check(show_calls == 1, "deferred request is not retried every loop")
app.on_show()
check(app.shown && app.current_scene == 0 && app.duration() == 8000, "deferred on_show starts the motion event")
app.draw()
check(has_art(), "motion draws actual generated artwork")
app.on_hide()
check(!app.should_show(), "displayed event is consumed on hide")

app = new_app({"cooldown_seconds":0, "__show_result":false})
app.receive("test/events/motion", "true")
check(show_calls == 1 && !app.should_show() && size(messages) == 1, "rejected show drops one request and logs once")
app.loop() app.loop()
check(show_calls == 1, "rejected show cannot spin in a retry loop")

app = new_app({"cooldown_seconds":0, "queue_seconds":5})
app.receive("test/events/motion", "true")
clock_ms = 5000 app.loop()
check(!app.should_show(), "deferred request expires with its pending event")
app.on_show()
check(!app.shown && next_calls == 1, "expired deferred request skips an idle blank turn")

app = new_app({"cooldown_seconds":0, "__show_mode":"sync"})
app.receive("test/events/heat", "true")
check(show_calls == 1 && app.shown && app.current_scene == 3, "synchronous rotation.show is safe")
check(app.duration() == 12000, "priority alarm event uses alarm dwell")
app.on_hide()
app = show_event(new_app({"cooldown_seconds":0}), "doorbell", "true")
check(app.duration() == 8000, "doorbell keeps the normal dwell despite priority two")
app.on_hide()

# All canonical routes and a bare event-name pulse are accepted in auto mode.
var names = ["motion", "mail_received", "mail_collected", "heat", "water", "doorbell", "garage", "dishwasher_finished", "cooker_finished", "washing_machine_finished", "dryer_finished"]
for scene : 0 .. size(names) - 1
  app = show_event(new_app({"cooldown_seconds":0}), names[scene], "true")
  check(app.current_scene == scene, "topic suffix routes " + names[scene])
  app.on_hide()
  app = show_event(new_app({"cooldown_seconds":0}), names[scene], names[scene])
  check(app.current_scene == scene, "bare event-name pulse routes " + names[scene])
  app.on_hide()
end
app = new_app({"cooldown_seconds":0})
app.receive("homey/other", "true")
check(!app.should_show(), "auto mode never guesses a scene from an unknown topic")
app = show_event(new_app({"topic":"homey/events", "cooldown_seconds":0}), "ignored", "doorbell")
check(app.current_scene == 5, "bare event name works on a single configured topic")
app.on_hide()
app.receive("homey/other", '{"event":"heat","active":true}')
app.on_show()
check(app.current_scene == 3, "explicit JSON event routes without a topic suffix")
app.on_hide()
app = new_app({"cooldown_seconds":0})
app.receive("homey/events/heat", '{"event":"not-a-scene","active":true}')
check(!app.should_show(), "invalid explicit event cannot fall through to topic")

# Appliance completions work through either JSON routing or a fixed scene on an
# existing appliance topic; they retain ordinary dwell and lower alarm priority.
for scene : 7 .. 10
  app = new_app({"cooldown_seconds":0})
  app.receive("homey/events", '{"event":"' + names[scene] + '","active":true}')
  app.on_show()
  check(app.current_scene == scene && app.duration() == 8000, "JSON completion uses normal dwell: " + names[scene])
  app.receive("homey/events", '{"event":"' + names[scene] + '","active":false}')
  check(app.current_scene == -1 && next_calls == 1, "inactive clears visible appliance scene: " + names[scene])
  app = new_app({"event_mode":names[scene], "match_mode":"exact", "active_value":"finished", "inactive_value":"running", "trigger_mode":"edge", "cooldown_seconds":0})
  app.receive("existing/appliance/state", "finished")
  app.on_show() app.on_hide()
  app.receive("existing/appliance/state", "finished")
  check(!app.should_show(), "repeated finished state does not replay: " + names[scene])
  app.receive("existing/appliance/state", "running")
  app.receive("existing/appliance/state", "finished")
  check(app.pending[scene] != nil, "next completion rearms after running: " + names[scene])
end

app = new_app({"cooldown_seconds":0})
app.receive("homey/events/dryer_finished", "true")
app.receive("homey/events/heat", "true")
app.on_show()
check(app.current_scene == 3 && app.pending[10] != nil, "alarm outranks queued appliance completion")
app.on_hide() app.loop() app.on_show()
check(app.current_scene == 10, "dryer completion survives queued alarm selection")
app.on_hide()

# Boolean variants, malformed input, explicit false and unknown inactive values.
app = new_app({"cooldown_seconds":0})
for raw : [true, 1, "yes", "ON", "✓", '{"value":true}']
  app.receive("test/events/motion", raw)
  check(app.pending[0] != nil, "active boolean variant accepted")
  app.pending[0] = nil
end
app.receive("test/events/motion", false)
check(app.pending[0] == nil && !app.should_show(), "false never creates an event")
app.receive("test/events/motion", "unclear")
check(!app.should_show(), "unknown value is ignored and does not clear")
app.receive("test/events/motion", "{")
check(!app.should_show(), "malformed JSON is rejected")
app.receive("test/events/motion", "[]")
check(!app.should_show(), "JSON arrays are rejected as invalid activity types")
var oversized = ""
for index : 0 .. 512 oversized += "x" end
app.receive("test/events/motion", oversized)
check(!app.should_show(), "oversized payload is rejected")

# Explicit false clears only the matching pending/current scene and rearms edge.
app = new_app({"cooldown_seconds":0})
app.receive("test/events/heat", "true")
app.receive("test/events/water", "true")
app.receive("test/events/heat", "false")
check(app.pending[3] == nil && app.pending[4] != nil, "false clears only its scene")
app.on_show()
check(app.current_scene == 4, "remaining pending scene is selected")
app.receive("test/events/water", '{"active":false,"id":"clear-1"}')
check(app.current_scene == -1 && next_calls == 1, "false ends a matching visible scene")
app.on_hide()

app = new_app({"trigger_mode":"edge", "cooldown_seconds":0})
app.receive("test/events/doorbell", "true")
app.receive("test/events/doorbell", "true")
check(app.pending[5] != nil && app.sequence == 1, "edge ignores repeated active values")
app.receive("test/events/doorbell", "false")
check(app.pending[5] == nil && !app.edge_active[5], "edge false clears and rearms")
app.receive("test/events/doorbell", "true")
check(app.sequence == 2, "edge can trigger again after rearm")

app = new_app({"trigger_mode":"edge", "cooldown_seconds":0})
app.receive("test/events/motion", '{"active":true,"id":"a"}')
app.receive("test/events/motion", '{"active":false}')
app.receive("test/events/motion", '{"active":true,"id":"a"}')
check(!app.edge_active[0] && app.pending[0] == nil, "late duplicate ID cannot relatch a rearmed edge")
app.receive("test/events/motion", '{"active":true,"id":"b"}')
check(app.edge_active[0] && app.pending[0] != nil, "fresh ID triggers after the late duplicate")

# Fixed mode accepts arbitrary topics; exact and payload-field matching stay strict.
app = new_app({"event_mode":"garage", "match_mode":"exact", "active_value":"OPEN", "inactive_value":"CLOSED", "cooldown_seconds":0})
app.receive("arbitrary/topic", " open ")
check(app.pending[6] != nil, "fixed exact mode accepts its active value")
app.receive("arbitrary/topic", "unknown")
check(app.pending[6] != nil, "fixed exact unknown does not clear")
app.receive("arbitrary/topic", "closed")
check(app.pending[6] == nil, "fixed exact inactive clears")
app = new_app({"event_mode":"water", "payload_field":"state", "cooldown_seconds":0})
app.receive("arbitrary/topic", '{"state":true,"id":"water-1"}')
check(app.pending[4] != nil, "configured payload field is used")
app.receive("arbitrary/topic", '{"value":true}')
check(app.pending[4] != nil, "missing configured field is rejected")
app = new_app({"event_mode":"garage", "match_mode":"any", "payload_field":"state", "cooldown_seconds":0})
app.receive("arbitrary/topic", '{"unrelated":1}')
app.receive("arbitrary/topic", "true")
check(app.pending[6] == nil, "configured payload field is required in any mode")
app.receive("arbitrary/topic", '{"state":"open"}')
check(app.pending[6] != nil, "any mode accepts a nonempty configured field")

app = new_app({"event_mode":"garage", "match_mode":"any", "cooldown_seconds":0})
app.receive("arbitrary/topic", "anything")
check(app.pending[6] != nil, "any mode treats a nonempty message as an event")
app.receive("arbitrary/topic", false)
check(app.pending[6] == nil, "any mode excludes explicit false")
app.receive("arbitrary/topic", '{"active":false,"id":"inactive"}')
check(app.pending[6] == nil, "any mode excludes JSON active false")
app.receive("arbitrary/topic", "{}")
check(app.pending[6] == nil, "any mode excludes an empty JSON object")

# IDs, cooldown and first event at clock zero.
app = new_app({"cooldown_seconds":3})
app.receive("test/events/motion", '{"active":true,"id":"same"}')
app.receive("test/events/motion", '{"active":true,"id":"same"}')
check(app.sequence == 1, "duplicate ID is ignored")
clock_ms = 3001
app.receive("test/events/motion", '{"active":true,"id":"same"}')
check(app.sequence == 1, "old ID remains in bounded dedup cache")
app.receive("test/events/motion", '{"active":true,"id":"new"}')
check(app.sequence == 1 && app.last_accepted[0] == 3001, "new ID is accepted after cooldown")
app = new_app({"cooldown_seconds":0})
for index : 0 .. 16
  app.receive("test/events/motion", '{"active":true,"id":"id-' + str(index) + '"}')
end
check(size(app.recent_ids) == 16 && !app.id_seen(0, "id-0") && app.id_seen(0, "id-16"), "ID cache stays bounded to its newest 16 entries")
app.receive("test/events/heat", '{"active":true,"id":"id-16"}')
check(app.pending[3] != nil, "the same ID may be used independently by another scene")
app = new_app({"cooldown_seconds":3})
app.receive("test/events/motion", "true")
check(app.sequence == 1, "first event at boot is not mistaken for cooldown")
clock_ms = 2999 app.receive("test/events/motion", "true")
check(app.sequence == 1, "cooldown suppresses an early pulse")
clock_ms = 3000 app.receive("test/events/motion", "true")
check(app.sequence == 1 && app.last_accepted[0] == 3000, "cooldown expires at its boundary")

# Priority and FIFO use sequence order, even when several messages share a timestamp.
app = new_app({"cooldown_seconds":0})
app.receive("test/events/motion", "true")
app.receive("test/events/mail_received", "true")
app.receive("test/events/heat", "true")
app.receive("test/events/water", "true")
app.on_show()
check(app.current_scene == 3, "heat priority outranks normal scenes")
app.on_hide() app.loop() app.on_show()
check(app.current_scene == 4, "water FIFO follows heat within priority three")
app.on_hide() app.loop() app.on_show()
check(app.current_scene == 0, "normal priority preserves first arrival FIFO")
app.on_hide() app.loop() app.on_show()
check(app.current_scene == 1, "normal priority preserves second arrival FIFO")
app.on_hide()

app = show_event(new_app({"cooldown_seconds":0}), "motion", "true")
app.receive("test/events/heat", "true")
check(app.current_scene == 0 && app.pending[3] != nil, "event arriving while shown queues for a later turn")
app.on_hide() app.loop() app.on_show()
check(app.current_scene == 3, "queued event waits for the current turn to finish")
app.on_hide()

app = new_app({"cooldown_seconds":0, "queue_seconds":5})
for scene : 0 .. size(names) - 1 app.receive("test/events/" + names[scene], "true") end
check(app.sequence == size(names), "queue has at most one bounded entry per scene")
app.receive("test/events/motion", "true")
check(app.sequence == size(names) && app.pending[0] != nil, "coalesced scene refreshes without adding a second slot")
app.receive("test/events/dryer_finished", "false")
check(app.pending[10] == nil && app.pending[7] != nil, "last scene clear preserves another appliance event")
clock_ms = 5000
app.loop()
check(!app.should_show(), "pending entries expire at the finite queue lifetime")

app = new_app({"cooldown_seconds":0})
for scene : 0 .. size(names) - 1 app.receive("test/events/" + names[scene], "true") end
app.on_show() app.on_button("select") app.on_hide()
check(!app.should_show() && app.pending[10] == nil, "acknowledgement clears all eleven pending event slots")

# Clock arithmetic remains wrap-safe for short event lifetimes.
app = new_app({"cooldown_seconds":0})
clock_ms = 2147483000
app.receive("test/events/motion", "true")
clock_ms = -2147483000
check(app.should_show(), "event survives signed 32-bit clock wrap")

# Select acknowledges all local state, left/right remain firmware navigation,
# and wake_display is the only path that powers the panel on.
app = new_app({"cooldown_seconds":0})
app.receive("test/events/motion", "true") app.receive("test/events/heat", "true") app.on_show()
check(!app.on_button("left") && !app.on_button("right"), "left and right are not consumed")
check(app.on_button("select") && next_calls == 1, "select clears queue and advances rotation")
app.on_hide()
check(!app.should_show(), "acknowledged event does not return after hide")
app = new_app({"cooldown_seconds":0, "wake_display":true})
app.receive("test/events/heat", "true") app.on_show()
check(power_calls == 1, "explicit wake_display powers on only when event starts")
app.draw()
check(has_art(), "all generated event scenes draw through EventArtwork")

# Labels are optional but must still use the same bounded generated drawing path.
var completion_labels = ["DISH", "COOK", "WASH", "DRY"]
for scene : 0 .. size(names) - 1
  app = show_event(new_app({"show_labels":true, "cooldown_seconds":0}), names[scene], "true")
  app.draw()
  check(size(text_calls) == 2 && has_art(), "labels and art stay bounded for " + names[scene])
  if scene >= 7
    check(has_label(completion_labels[scene - 7]) && has_label("DONE"), "completion uses its appliance artwork, not idle fallback: " + names[scene])
  end
  app.on_hide()
end

print("PASS: EventTrigger Berry checks=" + str(checks))
