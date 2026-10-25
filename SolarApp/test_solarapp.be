import json
import string
var cfg = {}
var clock_ms = 0
var subscriptions = {}
var logs = []
var texts = []
var drawing = []
var checks = 0
var store = module("store")
store.get = def (key, fallback) return cfg.find(key, fallback) end
var mqtt = module("mqtt")
mqtt.subscribe = def (topic, callback) subscriptions[topic] = callback end
def now_ms() return clock_ms end
def log(message) logs.push(message) end
def num(value, fallback)
  var result = value
  if type(value) == "string"
    try
      result = json.load(value)
    except ..
      return fallback
    end
  end
  return type(result) == "int" || type(result) == "real" ? result : fallback
end
def format(pattern, value) return string.format(pattern, value) end
def max(a, b) return a > b ? a : b end
def min(a, b) return a < b ? a : b end
def clamp(v, a, b) return max(a, min(v, b)) end
def font(name) assert(name == "small") end
def text_width(value) return size(value) * 4 end
def clear() texts = [] drawing = [] end
def text(x, y, value, color)
  assert(x >= 0 && x + text_width(value) <= 52, "text width: " + value)
  assert(y == 6 || y == 14, "text baseline")
  texts.push(value)
  drawing.push(["text", x, y, value, color])
end
def pixel(x, y, color)
  assert(x >= 0 && x < 52 && y >= 0 && y < 16, "pixel out of bounds")
  drawing.push(["pixel", x, y, color])
end
def rect_fill(x, y, w, h, color)
  assert(w > 0 && h > 0, "non-positive rectangle")
  assert(x >= 0 && y >= 0 && x + w <= 52 && y + h <= 16, "rectangle out of bounds")
  drawing.push(["fill", x, y, w, h, color])
end
def rect(x, y, w, h, color)
  drawing.push(["rect", x, y, w, h, color])
end
def line(x, y, x2, y2, color)
  drawing.push(["line", x, y, x2, y2, color])
end
def check(condition, message)
  assert(condition, message)
  checks += 1
end
def has_label(value)
  for label : texts
    if label == value return true end
  end
  return false
end
def new_app(settings)
  cfg = settings
  clock_ms = 0
  subscriptions = {}
  logs = []
  return compile("SolarApp.ax", "file")()
end
def feed(app, index, payload)
  app.on_mqtt(app.topics[index], payload)
end
def full_app()
  var app = new_app({"topic_battery_soc":"battery/soc", "topic_battery_power":"battery/w", "topic_grid_power":"grid/w"})
  app.setup()
  feed(app, 0, "2500")
  feed(app, 1, "12345")
  feed(app, 2, "900")
  feed(app, 3, "76")
  feed(app, 4, "850")
  feed(app, 5, "-420")
  return app
end
def snapshot(name)
  var f = open("preview-" + name + ".json", "w")
  f.write(json.dump(drawing))
  f.close()
end

var app = new_app({})
app.setup()
check(size(subscriptions) == 3, "existing MQTT defaults")
check(app.view_count() == 0, "no readings are not zero")
app.draw()
check(has_label("NO DATA"), "startup placeholder")
feed(app, 0, "0")
feed(app, 2, "500")
app.on_show()
check(app.view == 2, "night skips solar")
check(app.duration() == 6000, "one view dwell time")
app.draw()
check(has_label("500W"), "house load")
feed(app, 0, "1")
check(!app.eligible(0), "threshold is strictly above")
feed(app, 0, "1.1")
check(app.eligible(0), "production activates solar")

app = full_app()
check(app.view_count() == 4, "all views eligible")
check(app.duration() == 21000, "full cycle device dwell")
app.on_show()
app.draw()
check(has_label("2.5kW") && has_label("12.3kWh"), "solar and actual yield")
snapshot("solar")
clock_ms = 4999
app.draw()
check(app.view == 0, "no early rotation")
clock_ms = 5000
app.draw()
check(app.view == 1 && has_label("76%") && has_label("+850W"), "rotate to battery")
snapshot("battery")
clock_ms = 10000
app.draw()
check(app.view == 2 && has_label("900W"), "rotate to house")
snapshot("house")
clock_ms = 15000
app.draw()
check(app.view == 3 && has_label("EXPORT") && has_label("420W"), "rotate to export")
snapshot("export")
clock_ms = 20000
app.draw()
check(app.view == 0, "cycle wraps")
check(app.on_button("select") && app.view == 1, "select advances")
check(!app.on_button("left"), "navigation belongs to firmware")
feed(app, 0, "0")
app.view = 0
app.draw()
check(app.view == 1, "stop solar immediately on zero")
clock_ms = 120001
app.loop()
app.draw()
check(app.view_count() == 0 && has_label("NO DATA"), "stale live readings expire")
clock_ms = 0
check(!app.eligible(3), "expired data cannot revive after a counter cycle")
feed(app, 2, "123")
app.draw()
check(app.view == 2 && has_label("123W"), "fresh data recovers")

app = full_app()
feed(app, 5, "650")
app.view = 3
app.draw()
check(has_label("IMPORT") && has_label("650W"), "positive imports")
snapshot("import")
feed(app, 5, "-5")
app.draw()
check(has_label("IDLE"), "grid noise deadband")
feed(app, 4, "-350")
app.view = 1
app.draw()
check(has_label("-350W"), "battery discharging")
feed(app, 4, "5")
app.draw()
check(has_label("IDLE"), "battery idle")
clock_ms = 120001
feed(app, 3, "50")
app.draw()
check(has_label("50%") && has_label("--"), "SOC and battery power expire independently")

app = new_app({"topic_battery_soc":"soc", "topic_battery_power":"bat", "topic_grid_power":"grid", "grid_sign":"export_positive", "battery_sign":"discharge_positive"})
feed(app, 3, "50")
feed(app, 4, "300")
feed(app, 5, "-700")
check(app.values[4] == -300 && app.values[5] == 700, "configured sign reversals")

app = new_app({"topic_power":"all", "topic_yield":"all", "topic_consumption":"all", "topic_battery_soc":"all", "topic_battery_power":"all", "topic_grid_power":"all", "field_power":"pv", "field_yield":"day", "field_consumption":"home", "field_battery_soc":"percent", "field_battery_power":"bat", "field_grid_power":"grid"})
app.setup()
check(size(subscriptions) == 1, "shared JSON topic deduplicated")
subscriptions["all"]("all", '{"pv":2000,"day":15000,"home":1000,"percent":"75","bat":500,"grid":-500}')
check(app.values[0] == 2000 && app.values[1] == 15000 && app.values[2] == 1000 && app.values[3] == 75 && app.values[4] == 500 && app.values[5] == -500, "shared callback routes every field")

app = new_app({"topic_power":"", "topic_yield":"", "topic_consumption":"", "topic_battery_soc":"bat/+", "topic_grid_power":"grid/#"})
app.setup()
check(size(subscriptions) == 2, "empty topics disabled")
subscriptions["bat/+"]("bat/soc", '{"SOC":80}')
subscriptions["grid/#"]("grid/meter", '{"grid_power":-900}')
check(app.values[3] == 80 && app.values[5] == -900, "wildcard callbacks route using subscription filter")

app = full_app()
var valid = app.values[3]
var stamp = app.updated[3]
var initial_logs = size(logs)
clock_ms = 9000
feed(app, 3, "101")
feed(app, 3, "-1")
feed(app, 3, "true")
feed(app, 3, "not-json")
feed(app, 3, '{"SOC":false}')
check(app.values[3] == valid && app.updated[3] == stamp, "invalid data never refreshes good reading")
check(size(logs) == initial_logs + 1, "bad input logging throttled")
feed(app, 3, '"81"')
check(app.values[3] == 81 && !app.bad_input[3] && size(logs) == initial_logs + 2, "JSON numeric string recovers")
feed(app, 3, "1e309")
check(app.values[3] == 81, "infinity rejected")
feed(app, 0, "-20")
check(app.values[0] == 0, "legacy negative solar clamps to zero")

app = new_app({"yield_input_unit":"kWh", "yield_unit":"kWh"})
feed(app, 1, "12.5")
check(app.yield_label() == "12.5kWh", "kWh source conversion")
clock_ms = 3600001
check(app.yield_label() == "--", "yield expires independently")
app = new_app({"yield_unit":"Wh"})
feed(app, 1, "500")
check(app.yield_label() == "500Wh", "Wh formatting")
app = new_app({"data_timeout":0})
feed(app, 2, "0")
clock_ms = 9000000
check(app.eligible(2), "expiry can be disabled; zero house load valid")

app = full_app()
app.enabled = [false, true, false, false]
app.on_show()
check(app.view == 1 && app.view_count() == 1, "visibility switches")
clock_ms = 5000
app.draw()
check(app.view == 1, "single view does not go blank")
app.enabled = [false, false, false, false]
app.draw()
check(has_label("NO DATA"), "all views disabled fallback")

app = new_app({"default_view":"consumption"})
feed(app, 0, "1000")
feed(app, 2, "500")
app.on_show()
check(app.view == 2, "existing default consumption maps to house")
app = full_app()
clock_ms = 0x7FFFFFF0
feed(app, 3, "60")
app.view = 1
app.view_started = clock_ms
clock_ms = -2147483632
check(app.fresh(3) && app.age(app.view_started) == 32, "millisecond signed boundary")

app = full_app()
app.cfg_style = "sun_half"
for i : 0 .. 159
  app.draw()
end
snapshot("solar-half")
check(has_label("2.5kW"), "half sun draws without errors")
app.cfg_style = "sun_large"
for i : 0 .. 159
  app.draw()
end
check(has_label("12.3kWh"), "large sun animation draws without errors")
check(app.power_label(12000) == "12.0kW", "large power formatting")
clear()
app.anim_phase = 0.0
app.draw_energy(1, 0x00E676, 1000)
check(drawing[0][1] == 16, "import/discharge particles start at left")
var clear_lanes = true
for command : drawing
  if command[2] != 7 && command[2] != 15 clear_lanes = false end
end
check(clear_lanes, "energy particles leave both text rows clear")
clear()
app.draw_energy(-1, 0x00E676, 1000)
check(drawing[0][1] == 44, "export/charging particles start at right")
clear()
app.draw_energy(0, 0x00E676, 0)
check(size(drawing) == 0, "idle has no directional energy stream")
app = full_app()
app.view = 1
feed(app, 3, "0")
app.draw()
check(has_label("0%"), "empty battery draws safely")
feed(app, 3, "100")
app.draw()
check(has_label("100%"), "full battery draws safely")
app.view = 2
feed(app, 0, "0")
feed(app, 4, "-500")
app.draw()
check(has_label("900W"), "night house with measured battery source draws")
feed(app, 4, "0")
feed(app, 5, "400")
app.draw()
check(has_label("900W"), "night house with measured grid source draws")
check(app.source_mode() == 3, "measured grid source is preserved")

# Regression: the reported 3 kW house / zero production must not display a dead sun.
app = new_app({})
feed(app, 2, "3000")
feed(app, 0, "0")
app.view = 2
app.draw()
snapshot("house-unknown")
var first_house_frame = json.dump(drawing)
check(has_label("3.0kW") && has_label("LOAD"), "house-only reading retains actual load")
check(app.source_mode() == 0 && !app.eligible(0), "zero production never activates solar")
check(!app.eligible(3) && app.values[5] == nil, "house load does not invent grid import")
app.anim_phase += 1.0
app.draw()
check(json.dump(drawing) != first_house_frame, "unknown-source positive house load animates")
var reported = size(logs)
for tick : 0 .. 4 app.loop() end
check(size(logs) == reported, "source-status logging is transition-only")
feed(app, 0, "2000")
check(app.source_mode() == 1 && app.eligible(0), "solar production resumes its normal view")
clock_ms = 120001
feed(app, 2, "3000")
app.draw()
check(app.source_mode() == 0 && has_label("3.0kW"), "expired solar uses animated load fallback")
feed(app, 2, "0")
clear()
app.draw_load_activity()
var zero_house_frame = json.dump(drawing)
app.anim_phase += 1.0
clear()
app.draw_load_activity()
check(json.dump(drawing) == zero_house_frame, "zero load has no activity pulse or sparks")
print("PASS: " + str(checks) + " checks; Berry logic and mocked drawing/MQTT")
