# Run from PelletStove/ with a Berry 1.1 interpreter. No network/device calls.
import json
import string
var cfg = {}
var clock_ms = 0
var subscriptions = {}
var messages = []
var drawing = []
var checks = 0
var advances = {" ":2, "!":2, "'":2, "(":3, ")":3, ",":3, ".":2, ":":2, ";":3,
  "I":2, "M":6, "N":5, "Q":5, "W":6, "`":3, "i":2, "|":2}
var store = module("store")
store.get = def (key, fallback) return cfg.find(key, fallback) end
var mqtt = module("mqtt")
mqtt.subscribe = def (topic, callback) subscriptions[topic] = callback end
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
def font(name) assert(name == "small") end
# Native small-font ASCII advances, checked against the vendored BDF by verify.py.
def text_width(label)
  var width = 0
  for index : 0 .. size(label) - 1
    var ch = label[index .. index]
    width += advances.find(ch, 4)
  end
  return width
end
def clear() drawing = [] end
def point_ok(x, y) assert(x >= 0 && x < 52 && y >= 0 && y < 16, "point out of bounds") end
def pixel(x, y, color)
  point_ok(x, y)
  drawing.push(["pixel", x, y, color])
end
def line(x, y, x2, y2, color)
  point_ok(x, y) point_ok(x2, y2)
  drawing.push(["line", x, y, x2, y2, color])
end
def rect_fill(x, y, w, h, color)
  assert(w > 0 && h > 0, "invalid rectangle")
  point_ok(x, y) point_ok(x + w - 1, y + h - 1)
  drawing.push(["fill", x, y, w, h, color])
end
def text(x, y, label, color)
  assert(x == 17 && text_width(label) <= 34, "text exceeds allocated area: " + label)
  assert(y == 6 || y == 14, "unexpected baseline")
  drawing.push(["text", x, y, label, color])
end
def check(condition, message)
  assert(condition, message)
  checks += 1
end
def has_label(label)
  for call : drawing
    if call[0] == "text" && call[3] == label return true end
  end
  return false
end
def has_art()
  for call : drawing
    if call[0] != "text" && call[1] < 16 return true end
  end
  return false
end
def new_app(settings)
  cfg = settings
  clock_ms = 0
  subscriptions = {}
  messages = []
  var app = compile("PelletStove.ax", "file")()
  app.setup()
  return app
end
def feed(app, index, payload) app.receive(app.topics[index], payload) end
def state(app)
  app.receive(app.topics[9], '{"onoff":true,"stove_mode":"heating","stove_status":true,"measure_temperature":21.4,"target_temperature":22,"stove_pellets_actual":8.4,"measure_stove_cleaning_in":32.5,"measure_stove_maintenance_in":45,"stove_error_state":false}')
end
def full_app(settings)
  settings["topic_state"] = "test/state"
  var app = new_app(settings)
  state(app)
  app.on_show()
  return app
end
def capture(path, value)
  var f = open(path, "w")
  f.write(json.dump(value))
  f.close()
end

var app = new_app({})
check(size(subscriptions) == 1, "nine default topics grouped under one parent wildcard")
app.draw()
check(has_label("NO DATA"), "startup has no invented values")
check(!app.fault() && !app.fresh(5), "unknown error is not confirmed clear")
feed(app, 8, "Yes")
feed(app, 0, " heating ")
feed(app, 1, "false")
app.on_show() app.draw()
check(app.values[0] == "HEATING", "plain mode trimmed and normalized")
check(app.values[1] == false && has_label("ON"), "power ON and false heating status are distinct")
check(!app.on_button("left") && !app.on_button("right"), "firmware navigation preserved")

app = full_app({})
check(size(subscriptions) == 1, "JSON overrides scalar topics to stay under eight subscriptions")
check(app.view == 0, "starts on stove")
check(app.duration() == 39000, "one full cycle plus one change hold")
var order = [0,5,1,2,3,4]
var expected = ["HEATING", "21.4C", "8.4kg", "32.5h", "45.0%", "CLEAR"]
for slot : 0 .. 5
  clock_ms = slot * 5000
  app.loop() app.draw()
  check(app.view == order[slot] && has_label(expected[slot]), "normal rotation slot " + str(slot))
end
clock_ms = 30000 app.loop()
check(app.view == 0, "normal rotation wraps")
check(app.on_button("select") && app.view == 5, "select advances")

# Boolean variants, JSON primitives and Homey-style value envelopes.
for raw : ["false", "0", "OFF", '"no"', '{"value":false}']
  feed(app, 5, raw)
  check(app.values[5] == false, "false must never become a fault: " + raw)
end
for raw : ["true", "1", "ON", '"yes"', '{"value":true}']
  feed(app, 5, raw)
  check(app.values[5] == true, "true fault variant: " + raw)
end
feed(app, 5, "false")
feed(app, 2, '{"value":"12.7"}')
check(app.values[2] == 12.7, "numeric envelope")
for raw : ["oops", "null", "true", "-1", "1000", '{"other":0}', "1e99"]
  var previous = app.values[2]
  feed(app, 2, raw)
  check(app.values[2] == previous, "invalid fuel preserves last good reading: " + raw)
end
feed(app, 4, "101") check(app.values[4] == 45, "ash percentages over 100 rejected")
feed(app, 3, "-0.1") check(app.values[3] == 32.5, "negative cleaning rejected")
feed(app, 1, "unknown") check(app.values[1] == true, "invalid status preserves value")

# Invalid inputs do not refresh freshness, repeated invalid input logs once per field.
app = full_app({"data_timeout":10})
clock_ms = 9000 feed(app, 2, "bad") feed(app, 2, "bad")
check(size(messages) == 2, "startup log plus one invalid reading log")
clock_ms = 10000 app.loop() app.draw()
check(!app.fresh(2), "invalid payload did not refresh age")
check(has_label("POWER?") && has_label("STALE"), "expired power hides metric pages")
feed(app, 8, "Yes") feed(app, 0, "heating")
app.choose(1, 5000) app.draw()
check(has_label("--") && has_label("STALE"), "expired value explicitly stale")
clock_ms = 0 app.loop()
check(!app.fresh(2), "expired reading does not revive after clock wrap")
feed(app, 2, "7.2") check(!app.fresh(2), "stale mode closes update gate")
feed(app, 8, "Yes") feed(app, 0, "heating") feed(app, 2, "7.2") check(app.fresh(2), "fresh mode and data recover")

# Optional timeout disabled for Homey Flows which publish only changes.
app = full_app({})
clock_ms = 100000000 app.loop()
check(app.fresh(2), "timeout defaults to disabled")

# Fault preemption, stale fault visibility, clearance, and recurring reminders.
app = full_app({"data_timeout":10, "show_error":false})
clock_ms = 1000 feed(app, 5, "true") app.loop() app.draw()
check(app.view == 4 && has_label("FAULT"), "fault interrupts current view")
clock_ms = 8999 app.loop()
check(app.view == 4, "fault hold lasts 8 seconds")
clock_ms = 9000 app.loop()
check(app.view != 4, "fault does not lock all other views")
feed(app, 8, "Yes") feed(app, 0, "heating")
clock_ms = 11000 app.loop()
check(app.fault() && !app.fresh(5) && app.eligible(4), "stale fault remains eligible even if clear view disabled")
clock_ms = 31000 feed(app, 8, "Yes") feed(app, 0, "heating") app.loop() app.draw()
check(app.view == 4 && has_label("FAULT") && has_label("STALE"), "stale fault repeats with stale label")
feed(app, 8, "Yes") feed(app, 0, "heating") feed(app, 5, "false") app.loop()
check(!app.fault() && !app.eligible(4), "explicit false clears forced fault view")

# Threshold changes, refills and resets are queued; minor consumption isn't noisy.
app = full_app({})
feed(app, 2, "8.3")
feed(app, 3, "32.4")
feed(app, 4, "45.1")
check(app.pending == [0,0,0,0,0,0], "routine small changes do not interrupt")
feed(app, 2, "2.9")
check(app.pending[1] == 2, "fuel threshold")
clock_ms = 5000 app.loop()
check(app.view == 1 && app.hold_ms == 8000, "changed low fuel brought forward")
feed(app, 3, "0") feed(app, 4, "100")
clock_ms = 13000 app.loop()
check(app.view == 2, "due cleaning priority")
clock_ms = 21000 app.loop()
check(app.view == 3, "ash due next")
feed(app, 2, "12") feed(app, 3, "40") feed(app, 4, "0")
check(app.pending[1] == 1 && app.pending[2] == 1 && app.pending[3] == 1, "refill/cleaning/ash reset queued")
feed(app, 0, "standby") feed(app, 1, "false")
check(app.pending[0] == 1, "mode and status merge into one pending stove view")

# Same retained/state payload must not generate change alerts on every refresh.
app = full_app({})
for repeat : 0 .. 10 state(app) end
check(app.pending == [0,0,0,0,0,0], "identical state deduplicated")
feed(app, 9, '{"stove_pellets_actual":5}')
check(app.values[0] == "HEATING" && app.values[2] == 5, "partial JSON preserves missing fields")
feed(app, 9, '{"stove_pellets_actual":"bad","stove_error_state":true}')
app.loop()
check(app.values[2] == 5 && app.view == 4, "invalid numeric field cannot suppress valid fault")

# Subscription deduplication and wildcard capture.
app = new_app({"topic_mode":"", "topic_status":"", "topic_pellets":"", "topic_cleaning":"", "topic_ash":"", "topic_error":"", "topic_state":"stoves/+/state"})
check(size(subscriptions) == 1, "JSON-only setup")
subscriptions["stoves/+/state"]("stoves/living/state", '{"onoff":true,"stove_mode":"ignite","stove_status":true}')
check(app.values[0] == "IGNITE" && app.values[1] == true, "wildcard callback routed using filter")
app = new_app({"topic_mode":"shared", "topic_status":"shared"})
check(size(subscriptions) == 2, "duplicate and sibling topics subscribed only once")

# Hidden app queues changes without taking over firmware rotation.
app = full_app({}) app.on_hide()
feed(app, 5, "true")
clock_ms = 1000 app.loop()
check(app.view == 0, "hidden loop doesn't paint or change firmware app")
app.on_show()
check(app.view == 4, "pending fault first on next appearance")

# Temperature inputs: actual changes are quiet; a changed target queues the pair.
app = full_app({})
feed(app, 6, "21.5")
check(app.pending[5] == 0 && app.values[6] == 21.5, "actual temperature updates without preemption")
feed(app, 7, "23")
check(app.pending[5] == 1, "target temperature change brings temperature view forward")
app.choose(5, 5000) app.draw()
check(has_label("21.5C") && has_label("SET23.0C"), "both temperatures displayed")
var arrow = false
for call : drawing
  if call[0] == "pixel" && call[1] == 12 && call[-1] == 0x70C7BB arrow = true end
  check(!(call[0] == "line" && call[-1] == 0xFFD98B), "yellow minus-shaped target marker removed")
end
check(arrow, "target temperature uses cyan arrow")
for target : ["5", "35"]
  feed(app, 7, target) app.draw()
  check(has_art(), "target arrow stays in bounds at range endpoint")
end
feed(app, 7, "23")
feed(app, 7, "36") feed(app, 6, "101")
check(app.values[7] == 23 && app.values[6] == 21.5, "temperature input bounds")
feed(app, 6, "-40") app.draw()
check(has_label("-40.0C"), "negative actual temperature supported")
app = full_app({"show_temperature":false})
check(!app.eligible(5), "temperature page can be disabled")

# Standby is the mandatory gate, even if the last heating/status reading was true.
app = full_app({})
clock_ms = 1000
feed(app, 0, " StandBy ")
var frozen = json.dump(app.values)
var ages = json.dump(app.updated)
for index : [1,2,3,4,7] feed(app, index, "0") end
check(json.dump(app.values) == frozen && json.dump(app.updated) == ages, "standby scalar readings and timestamps are frozen")
app.choose(0, 5000) app.draw()
check(has_label("STANDBY") && has_label("21.4C") && !has_label("PAUSED"), "standby shows mode and usable current temperature")
for call : drawing
  check(!(call[0] == "line" && call[-1] == 0xE64D0A), "no heating flame in standby")
end
feed(app, 9, '{"stove_error_state":true,"stove_pellets_actual":1,"target_temperature":25,"stove_mode":"standby"}')
check(json.dump(app.values) == frozen && !app.fault(), "standby JSON gates every non-mode value regardless of key order")
feed(app, 9, '{"stove_pellets_actual":1,"target_temperature":25,"stove_mode":"heating"}')
check(app.values[2] == 1 && app.values[7] == 25 && !app.paused(), "non-standby JSON resumes using mode first")
app = new_app({})
feed(app, 2, "8") feed(app, 5, "true")
check(app.values[2] == nil && app.values[5] == nil, "unknown mode cannot open gate")
feed(app, 8, "Yes") feed(app, 0, "off") feed(app, 2, "8")
check(app.values[2] == 8, "only standby blocks known fresh modes, as requested")

# The ordinary standby page keeps current temperature live without opening other pages.
app = full_app({})
feed(app, 0, "standby") feed(app, 6, "24.02")
feed(app, 7, "30") feed(app, 2, "1")
app.loop() app.draw()
check(app.view == 0 && has_label("STANDBY") && has_label("24.0C"), "current temperature updates in ordinary standby")
check(app.values[7] == 22 && app.values[2] == 8.4 && !app.eligible(5), "standby current reading does not enable target updates or metric rotation")
check(app.pending[5] == 0 && !app.standby_changed() && app.should_show(), "ordinary standby temperature has no one-shot skip event")
feed(app, 6, "bad") app.draw()
check(has_label("24.0C"), "invalid current temperature preserves the last usable reading")
feed(app, 8, "No") feed(app, 6, "25") app.draw()
check(app.values[6] == 24.02 && has_label("OFF") && !has_label("24.0C"), "power No still blocks and hides standby temperature")
app = new_app({"topic_state":"test/state"})
feed(app, 9, '{"stove_mode":"standby","onoff":true}')
app.on_show() app.draw()
check(has_label("STANDBY") && has_label("--") && app.values[6] == nil, "missing standby temperature stays unknown")
feed(app, 9, '{"measure_temperature":23.57,"stove_mode":"standby","onoff":true,"target_temperature":25}')
app.loop() app.draw()
check(has_label("23.6C") && app.values[7] == nil, "combined JSON accepts current but gates target in ordinary standby")
app = full_app({"data_timeout":2})
feed(app, 0, "standby")
clock_ms = 1500 feed(app, 8, "Yes") feed(app, 0, "standby")
clock_ms = 2100 app.loop() app.draw()
check(has_label("STANDBY") && has_label("STALE") && !has_label("21.4C"), "expired current reading is not shown as live")
feed(app, 6, "24") app.loop() app.draw()
check(has_label("24.0C"), "fresh current reading recovers the standby page")
clock_ms = 3600 feed(app, 6, "25") app.draw()
check(!app.fresh(8) && app.values[6] == 24 && has_label("POWER?"), "stale power cannot admit new standby temperatures")

# Exact screenshot-style values: cooling + cross means powered ON, not heating.
app = new_app({})
var grouped = subscriptions["homey/pellet_stove/+"]
grouped(app.topics[0], "cooling")
grouped(app.topics[4], "20.2")
check(app.values[4] == nil, "unknown power blocks readings even with a known mode")
app.draw()
check(has_label("POWER?") && !has_label("20.2%"), "missing new power input is explicit")
grouped(app.topics[8], "Yes")
for reading : [[1,"×"], [2,"13"], [3,"1.5"], [4,"20.2"], [5,"x"], [6,"23.12"], [7,"23"]]
  grouped(app.topics[reading[0]], reading[1])
end
app.on_show() app.choose(0, 5000) app.draw()
check(app.active() && app.values[1] == false && app.values[5] == false, "cross Booleans accepted")
check(has_label("ON") && has_label("COOLING") && !has_label("UNKNOWN"), "first page distinguishes power and heating")
check(app.values[2] == 13 && app.values[3] == 1.5 && app.values[4] == 20.2, "grouped callback routes each actual topic")
var untouched = json.dump(app.values)
grouped("homey/pellet_stove/unrelated", "0")
check(json.dump(app.values) == untouched, "unconfigured sibling messages ignored")

# Common Boolean glyphs work on all three Boolean inputs; malformed text stays invalid.
for raw : ["x", "×", "✕", "✖", "✗", "✘", "❌", "No", "false", "0"]
  app = full_app({})
  feed(app, 1, raw) feed(app, 5, raw)
  check(app.values[1] == false && app.values[5] == false, "false glyph on status and fault: " + raw)
  feed(app, 8, raw) app.draw()
  check(!app.active() && has_label("OFF"), "false power hides values: " + raw)
end
for raw : ["✓", "✔", "✅", "Yes", "true", "1"]
  app = new_app({})
  feed(app, 8, raw) feed(app, 0, "heating")
  feed(app, 1, raw) feed(app, 5, raw)
  check(app.active() && app.values[1] == true && app.fault(), "true glyph accepted across Boolean inputs: " + raw)
end
check(app.normalize(8, "heating") == nil, "mode text cannot substitute for turned-on state")

# A true fault followed by any valid false must clear the whole alert episode.
for raw : ["false", "0", "No", "x", "×", "✗", "✘", '{"value":"✗"}']
  app = full_app({})
  feed(app, 5, "true")
  check(app.pending[4] == 4, "fault queued before being displayed")
  feed(app, 5, raw)
  check(!app.fault() && app.pending[4] < 4 && app.error_shown == nil, "clear cancels queued fault and reminder: " + raw)
  app.choose(4, 5000) app.draw()
  check(has_label("CLEAR") && has_label("ALL OK") && !has_label("ERROR"), "clear page is unambiguous")
  clock_ms = 31000 app.loop()
  check(!app.fault() && app.pending[4] == 0, "cleared episode does not repeat")
end
app = full_app({})
clock_ms = 1000 feed(app, 5, "true") app.loop()
check(app.view == 4 && app.hold_ms == app.change_ms, "active fault is being displayed")
feed(app, 5, "✗") app.draw()
check(app.view == 4 && app.hold_ms == app.rotate_ms && has_label("ALL OK"), "displayed fault becomes a normal clear page immediately")
check(size(messages) == 2, "one startup log and one fault-cleared log")
feed(app, 5, "✗")
check(size(messages) == 2, "duplicate clear payload is quiet")
clock_ms = 6000 app.loop()
check(app.view != 4, "clear page no longer holds the fault alert duration")
feed(app, 5, "true") app.loop()
check(app.view == 4 && app.fault(), "new fault after clearance still interrupts")
app = full_app({"show_error":false})
feed(app, 5, "true") app.loop()
feed(app, 5, "✘") app.draw()
check(app.view != 4 && !app.eligible(4) && !app.fault(), "hidden clear-error view exits immediately on clearance")
app = full_app({})
feed(app, 5, "true")
feed(app, 9, '{"stove_error_state":"✗","onoff":"✓","stove_mode":"heating"}')
check(!app.fault() && app.labels[5] == "CLEAR" && app.pending[4] < 4, "JSON cross clears a previously true fault")
app = full_app({})
feed(app, 5, "true") feed(app, 5, "✗")
check(app.view == 0 && app.pending[4] == 1, "clear acknowledgement is queued before it is visible")
feed(app, 5, "✗") feed(app, 5, "false")
check(app.pending[4] == 1, "duplicate false preserves the queued clear acknowledgement")
clock_ms = 5000 app.loop() app.draw()
check(app.view == 4 && has_label("ALL OK") && !app.fault(), "queued acknowledgement is still displayed after duplicates")
app = full_app({})
feed(app, 5, "true")
for raw : ["null", "", "unclear", '{"other":false}']
  feed(app, 5, raw)
  check(app.fault() && app.pending[4] == 4, "invalid or missing value must not clear a real fault")
end

# A clear received with closed gates must retire the old fault episode.
for gate : ["standby", "off", "stale_power", "stale_mode"]
  for raw : ["false", "0", "No", "✗", '{"value":false}']
    app = full_app({"data_timeout":10,"show_error":false})
    clock_ms = 1000 feed(app, 5, "true") app.loop()
    check(app.fault() && app.error_shown != nil, "fault episode exists before closing gate")
    if gate == "standby" feed(app, 0, "standby")
    elif gate == "off" feed(app, 8, "No")
    else
      clock_ms = 11000
      if gate == "stale_power" feed(app, 0, "cooling")
      else feed(app, 8, "Yes") end
      app.loop()
    end
    check(!app.active(), "test gate is closed: " + gate)
    feed(app, 5, raw)
    check(!app.fault() && app.pending[4] == 0 && app.error_shown == nil, "clear retires fault while gated: " + gate + " " + raw)
    feed(app, 5, "true")
    check(!app.fault(), "a new true reading still cannot bypass the closed gate")
    app.draw()
    check(!has_label("FAULT") && !app.eligible(4), "clear never exposes a measurement page through a closed gate")
    feed(app, 8, "Yes") feed(app, 0, "cooling") app.loop() app.draw()
    check(!app.fault() && !app.eligible(4) && !has_label("FAULT"), "resuming cannot resurrect a cleared gated fault")
    clock_ms += 31000 feed(app, 8, "Yes") feed(app, 0, "cooling") app.loop()
    check(app.pending[4] == 0 && app.error_shown == nil, "old fault reminder remains cancelled after resume")
  end
end
app = full_app({})
feed(app, 5, "true") feed(app, 0, "standby")
for raw : ["null", "", "unclear", '{"other":false}']
  feed(app, 5, raw)
  check(app.fault(), "missing or invalid gated error cannot clear a stored fault")
end
feed(app, 9, '{"stove_error_state":false,"stove_mode":"standby","onoff":false}')
check(!app.fault() && !app.active(), "JSON false clears even when both controls close the gate")
app = full_app({})
feed(app, 5, "true") feed(app, 8, "No")
feed(app, 5, "false") feed(app, 8, "Yes") feed(app, 0, "cooling")
feed(app, 5, "true") app.loop()
check(app.fault() && app.view == 4, "a genuinely new active fault still interrupts after gated clearance")
app = new_app({})
feed(app, 5, "false")
check(app.values[5] == false && !app.active(), "retained false is accepted before either control")
app = new_app({})
grouped = subscriptions["homey/pellet_stove/+"]
grouped(app.topics[8], "true") grouped(app.topics[0], "heating")
grouped(app.topics[5], "true")
grouped(app.topics[8], "false") grouped(app.topics[5], "false")
grouped(app.topics[0], "cooling") grouped(app.topics[8], "true")
app.on_show() app.draw()
check(app.active() && !app.fault() && !has_label("FAULT"), "real grouped-topic callback clears before power and mode recover")
# Capability values from the supplied Homey export, reduced to the supported MQTT shape.
app = full_app({}) feed(app, 5, "true")
feed(app, 9, '{"onoff":true,"stove_mode":"cooling","stove_status":false,"stove_error_state":false,"measure_temperature":23.57,"target_temperature":23,"stove_pellets_actual":10,"measure_stove_cleaning_in":29.3,"measure_stove_maintenance_in":20.7}')
app.choose(4, 5000) app.draw()
check(app.active() && !app.fault() && has_label("CLEAR") && has_label("ALL OK"), "supplied Homey values produce clear error while cooling")

# Explicit OFF immediately hides every measurement/fault and freezes their timestamps.
app = full_app({})
feed(app, 5, "true") app.loop()
clock_ms = 1000 feed(app, 8, "No")
var frozen_power = json.dump(app.values)
var frozen_power_ages = json.dump(app.updated)
for index : [1,2,3,4,6,7] feed(app, index, "0") end
app.draw()
check(has_label("OFF") && !has_label("FAULT") && !has_label("8.4kg"), "OFF is effective before the next loop tick")
check(json.dump(app.values) == frozen_power && json.dump(app.updated) == frozen_power_ages, "OFF freezes readings and ages")
for page : 1 .. 5 check(!app.eligible(page), "OFF disables metric rotation") end
check(app.on_button("select") && app.view == 0, "select cannot reveal old metrics while OFF")
feed(app, 8, "Yes") feed(app, 0, "cooling")
check(app.active() && !app.fresh(2), "resuming requires a fresh measurement, not old-run data")
feed(app, 2, "12.8")
check(app.fresh(2) && app.values[2] == 12.8, "fresh values recover after power-on")

# JSON controls are applied before measurements even when listed last.
app = new_app({"topic_state":"test/state"})
feed(app, 9, '{"measure_temperature":23.12,"stove_status":"×","stove_mode":"cooling","onoff":"Yes"}')
check(app.active() && app.values[6] == 23.12 && app.values[1] == false, "JSON control key order is irrelevant")
feed(app, 9, '{"measure_temperature":99,"stove_mode":"heating","onoff":"No"}')
check(!app.active() && app.values[6] == 23.12 && app.values[0] == "HEATING", "OFF JSON only updates controls")
app = full_app({"data_timeout":1})
clock_ms = 900 feed(app, 0, "heating")
clock_ms = 1000 app.loop() app.draw()
check(!app.active() && has_label("POWER?") && has_label("STALE"), "power freshness independently gates display")
app = full_app({"data_timeout":1}) app.on_hide()
clock_ms = 1001
feed(app, 8, "Yes") feed(app, 0, "heating")
check(app.active() && !app.fresh(2), "control refresh after expiry cannot revive old measurements, even between loop calls")

# Custom subscriptions remain bounded; no partial setup if nine parents are needed.
app = new_app({"topic_mode":"a/mode","topic_status":"b/status","topic_pellets":"c/pellets",
  "topic_cleaning":"d/clean","topic_ash":"e/ash","topic_error":"f/error",
  "topic_actual":"g/actual","topic_target":"h/target","topic_onoff":"i/power"})
check(size(subscriptions) == 0 && size(messages) == 1, "over-limit setup reports the combined-JSON remedy without subscribing partially")
app = new_app({"topic_mode":"stoves/+/mode"})
subscriptions["stoves/+/mode"]("stoves/living/mode", "heating")
feed(app, 8, "Yes")
check(app.active(), "custom wildcard topic still routes to its configured field")

# Cooling has a rotating fan, never flames or feeding pellets, even with old true status.
app = full_app({})
feed(app, 0, "cooling")
app.choose(0, 5000) app.draw()
check(has_label("ON") && has_label("COOLING") && !app.heating(), "cooling overrides a previous heating status")
var fan_first = json.dump(drawing)
var fan_present = false
for call : drawing
  if call[-1] == 0x60BFCB fan_present = true end
  check(call[-1] != 0xE64D0A, "cooling has no flame")
end
check(fan_present, "cooling fan is inside the stove")
clock_ms = 220 app.draw()
check(json.dump(drawing) != fan_first, "fan rotates using elapsed time")
clear() app.draw_pellets(0)
for call : drawing check(call[-1] != 0xF6C783, "cooling does not depict pellet feeding") end
feed(app, 8, "No") app.draw()
check(has_label("OFF") && has_label("COOLING"), "power off can still depict the reported cooling phase")
var fan_off = false
for call : drawing
  if call[-1] == 0x60BFCB fan_off = true end
end
check(fan_off && !app.eligible(1), "cooling fan does not reopen measurement pages")
app = full_app({"data_timeout":1})
feed(app, 0, "cooling")
clock_ms = 1000 app.loop() app.draw()
for call : drawing check(call[-1] != 0x60BFCB, "stale cooling mode cannot animate a live fan") end

# Whole-number kg values have a visible, proportional hopper fill and level bar.
for fuel : [["0",0], ["15",4], ["30",8], ["45",8]]
  app = full_app({})
  feed(app, 2, fuel[0])
  clear() app.draw_pellets(0)
  var fill_height = 0
  var bar_height = 0
  for call : drawing
    if call[0] == "fill" && call[-1] == 0x7C491E fill_height = call[4] end
    if call[0] == "line" && call[-1] == 0xDAAD64 bar_height = call[4] - call[2] + 1 end
  end
  check(app.capacity == 30 && fill_height == fuel[1] && bar_height == fuel[1], "30kg hopper progress: " + fuel[0])
end
app = full_app({"hopper_kg":15})
feed(app, 2, "15")
check(app.capacity == 15, "explicit existing hopper settings remain supported")

# Ash dirtiness is empty at 0%, then gains a deeper bed and more soot as usage rises.
app = full_app({})
var last_height = -1
var last_soot = -1
for usage : ["0", "20.2", "50", "90", "100"]
  feed(app, 4, usage)
  clear() app.draw_ash(0)
  var height = 0
  var soot = 0
  for call : drawing
    if call[0] == "fill" && call[-1] == 0x77756C height = call[4] end
    if call[0] == "pixel" && call[-1] == 0x0B1115 soot += 1 end
  end
  check(height >= last_height && soot >= last_soot, "ash level and dirt increase with usage")
  if usage == "0" check(height == 0 && soot == 0, "zero ash is a clean tray") end
  if usage == "100" check(height == 10 && soot == 12, "full ash reaches the intended bounds") end
  last_height = height
  last_soot = soot
end

# Microfiber cloth moves across the stove and stays within the icon area.
app = full_app({})
feed(app, 3, "1.3")
app.choose(2, 5000)
var cloth_positions = {}
var last_cloth_x = nil
for phase : 0 .. 23
  clock_ms = phase * 220
  app.draw()
  var found_cloth = false
  var safe_scene = true
  var cloth_x = nil
  for call : drawing
    if call[0] == "fill" && call[-1] == 0x78DEE1
      check(call[1] >= 2 && call[1] <= 8 && call[2] >= 4 && call[2] <= 5, "cloth motion bounds")
      cloth_positions[str(call[1]) + ":" + str(call[2])] = true
      found_cloth = true
      cloth_x = call[1]
    end
    if call[-1] == 0xE64D0A || call[-1] == 0x60BFCB safe_scene = false end
  end
  check(safe_scene, "cleaning depicts no fire or running fan")
  check(found_cloth && has_label("1.3h") && has_label("CLEAN IN"), "cloth and remaining cleaning time shown together")
  # Use the observed motion; turning-point frames belong to either stroke.
  if last_cloth_x != nil && phase % 12 != 0 && phase % 12 != 6
    var moving_right = cloth_x > last_cloth_x
    for call : drawing
      if call[0] == "pixel" && call[-1] == 0x6A6254
        check(moving_right && call[1] > cloth_x + 4, "dirt is only ahead of the outgoing wipe; return stroke stays clean")
      end
      if call[0] == "pixel" && call[-1] == 0xC6FFFF
        check(moving_right ? call[1] < cloth_x : call[1] > cloth_x + 4, "clean sparkle follows behind the cloth in either direction")
      end
    end
  end
  last_cloth_x = cloth_x
end
check(size(cloth_positions) > 6, "cloth wipes both ways across more than one row")

# Urgent values and their artwork blink once per second; labels remain readable.
# The strict boundaries are <1 hour and >90 percent, independent of warning settings.
for sample : [[3,2,"1.1",false], [3,2,"1",false], [3,2,"0.9",true], [3,2,"0",true],
              [4,3,"89.9",false], [4,3,"90",false], [4,3,"90.1",true], [4,3,"100",true]]
  app = full_app({"clean_warning":0, "ash_warning":100})
  feed(app, sample[0], sample[2])
  app.choose(sample[1], 5000)
  var label = app.labels[sample[0]]
  clock_ms = 499 app.draw()
  check(has_label(label) && has_art(), "blink on / normal visible: " + sample[2])
  clock_ms = 500 app.draw()
  check(has_label(label) == !sample[3] && has_art() == !sample[3], "blink half-second boundary: " + sample[2])
  check(has_label(sample[1] == 2 ? (sample[2] == "0" ? "DUE NOW" : "CLEAN IN") : "ASH USED"), "descriptive label stays visible")
  clock_ms = 1000 app.draw()
  check(has_label(label) && has_art(), "blink repeats at one second")
  if sample[3]
    check(app.severity(sample[0], app.values[sample[0]]) == 3, "urgent boundary receives priority")
  end
end
app = full_app({"data_timeout":1})
feed(app, 3, "0.5") feed(app, 4, "95")
clock_ms = 1500 app.loop()
feed(app, 8, "Yes") feed(app, 0, "heating")
for page : [2,3]
  app.choose(page, 5000) app.draw()
  check(has_label("--") && has_label("STALE") && has_art(), "stale values do not blink as live warnings")
end

# Drawing bounds, capacity clamp, long mode, extreme valid counter, unknown/stale views.
app = full_app({})
feed(app, 0, "a very long undocumented stove mode")
feed(app, 2, "999") feed(app, 3, "1000000")
for page : 0 .. 5
  app.choose(page, 5000)
  for frame : 0 .. 29
    clock_ms = frame * 110
    app.draw()
    check(size(drawing) > 0, "draw bounds page " + str(page))
  end
end

# Optional standby skip monitors temperatures and grants one temperature-only turn.
app = new_app({})
check(app.should_show(), "default preserves normal app visibility")
app = new_app({"standby_skip":true, "topic_state":"test/state"})
feed(app, 9, '{"onoff":true,"stove_mode":"standby","measure_temperature":21.37,"target_temperature":23,"stove_pellets_actual":14}')
check(!app.should_show() && app.values[6] == 21.37 && app.values[7] == 23, "first standby temperatures establish a quiet baseline")
check(app.values[2] == nil, "standby exception does not accept other measurements")
feed(app, 6, "21.37") feed(app, 7, "23")
check(!app.should_show(), "unchanged retained temperatures do not wake the app")
feed(app, 6, "21.5")
check(app.should_show() && app.should_show(), "visibility probes do not consume a temperature event")
app.on_show() app.draw()
check(app.view == 5 && app.duration() == 8000 && has_label("21.5C") && has_label("SET23.0C"), "standby change shows only the temperature pair for the change duration")
clock_ms = 1000 app.loop() app.draw()
check(app.view == 5 && has_label("21.5C"), "hidden/background loop logic does not rotate away during a temperature visit")
check(app.on_button("select") && app.view == 5, "standby select stays on the temperature view")
feed(app, 7, "24")
app.on_hide()
check(app.should_show(), "change during a visit survives for the next appearance")
app.on_show() app.draw()
check(has_label("SET24.0C"), "target changes also wake the temperature page")
app.on_hide()
check(!app.should_show(), "consumed event skips subsequent standby rotations")
feed(app, 6, "bad") feed(app, 7, "36")
check(!app.should_show(), "invalid temperatures cannot wake the app")
feed(app, 0, "heating")
check(app.should_show() && app.active(), "normal rotation resumes when the stove leaves standby")
feed(app, 2, "15")
check(app.eligible(1), "normal measurements are available again after a fresh update")

app = full_app({"standby_skip":true}) app.on_hide()
feed(app, 0, "standby") feed(app, 6, "21.4") feed(app, 7, "22")
check(!app.should_show(), "entering standby with unchanged temperatures stays quiet")
feed(app, 7, "23") feed(app, 8, "Yes") feed(app, 0, "standby")
check(app.should_show(), "periodic control refreshes preserve queued temperature changes")
feed(app, 8, "No") feed(app, 6, "25")
check(!app.should_show() && app.values[6] == 21.4, "power No still blocks temperature updates and cancels the event")
app = full_app({"standby_skip":true,"show_temperature":false})
feed(app, 0, "standby") feed(app, 6, "22")
check(!app.should_show(), "disabled temperature view cannot wake standby")
app = full_app({"standby_skip":true,"data_timeout":2}) app.on_hide()
feed(app, 0, "standby") feed(app, 6, "22")
check(app.should_show(), "fresh standby event is eligible")
clock_ms = 2500 app.loop()
check(!app.should_show(), "expired controls or event cannot wake standby")
feed(app, 8, "Yes") feed(app, 0, "standby") feed(app, 6, "22")
check(!app.should_show(), "refreshing unchanged stale data does not resurrect an expired event")
app = full_app({"standby_skip":true,"data_timeout":2}) app.on_hide()
feed(app, 0, "standby") feed(app, 6, "22")
clock_ms = 1500 feed(app, 8, "Yes") feed(app, 0, "standby")
clock_ms = 2100
check(!app.should_show(), "expired temperature alone suppresses its event with fresh controls")
feed(app, 6, "22")
check(!app.should_show(), "identical refresh before the next background loop cannot revive an expired event")

# Animation depends on elapsed time, not how many frames were drawn.
app = full_app({})
clock_ms = 1200 app.draw()
var at_1200 = json.dump(drawing)
for frame : 0 .. 200
  clock_ms = frame * 5
  app.draw()
end
clock_ms = 1200 app.draw()
check(json.dump(drawing) == at_1200, "same time yields same animation after different draw counts")

# Deterministic draw-call captures for the simulated preview.
app = full_app({})
var frames = []
for slot : 0 .. 5
  var page = order[slot]
  if page == 2 feed(app, 3, "0.5") end
  if page == 3 feed(app, 4, "95") end
  if page == 4 feed(app, 5, "true") end
  app.choose(page, 5000)
  for frame : 0 .. (page == 4 ? 79 : 49)
    clock_ms = slot * 5000 + frame * 100
    app.draw()
    frames.push(drawing)
  end
end
capture("tools/preview-frames.json", frames)
app = full_app({})
clock_ms = 0
var progress = []
for fuel : ["0", "15", "30"]
  feed(app, 2, fuel)
  app.choose(1, 5000) app.draw()
  progress.push(drawing)
end
for usage : ["0", "50", "100"]
  feed(app, 4, usage)
  app.choose(3, 5000) app.draw()
  progress.push(drawing)
end
capture("tools/progress-frames.json", progress)
app = full_app({})
feed(app, 0, "cooling")
app.choose(0, 5000)
var cooling_frames = []
for frame : 0 .. 39
  clock_ms = frame * 100
  app.draw()
  cooling_frames.push(drawing)
end
capture("tools/cooling-frames.json", cooling_frames)
app = full_app({})
feed(app, 3, "1.3")
app.choose(2, 5000)
var cleaning_frames = []
for frame : 0 .. 59
  clock_ms = frame * 100
  app.draw()
  cleaning_frames.push(drawing)
end
capture("tools/cleaning-frames.json", cleaning_frames)
print("PASS: " + str(checks) + " assertions (Berry VM, mocked AWTRIX; no hardware test)")
