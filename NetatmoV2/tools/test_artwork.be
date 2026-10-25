# Focused, device-free Netatmo artwork harness.
# Run from the repository root with the pinned Berry 1.1 32-bit interpreter.
import json

var drawing = []
var text_calls = []
var checks = 0
var peak_calls = 0

# Native small-font advances, copied from the vendored BDF.  Printable glyphs
# not listed here have the documented four-pixel advance.
var advances = {" ":2, "!":2, "'":2, "(":3, ")":3, ",":3, ".":2, ":":2, ";":3,
  "I":2, "M":6, "N":5, "Q":5, "W":6, "`":3, "i":2, "|":2}

def text_width(value)
  var width = 0
  var index = 0
  while index < size(value)
    if value[index .. index + 1] == "°"
      width += 3
      index += 2
    else
      width += advances.find(value[index .. index], 4)
      index += 1
    end
  end
  return width
end

def clear()
  drawing = []
  text_calls = []
end

def font(name)
  assert(name == "small", "artwork must use the documented small font")
end

def point_ok(x, y)
  assert(x >= 0 && x < 52 && y >= 0 && y < 16, "draw point outside panel")
end

def pixel(x, y, color)
  point_ok(x, y)
  drawing.push(["pixel", x, y, color])
end

def line(x, y, x2, y2, color)
  point_ok(x, y) point_ok(x2, y2)
  drawing.push(["line", x, y, x2, y2, color])
end

def rect_fill(x, y, width, height, color)
  assert(width > 0 && height > 0, "non-positive fill")
  point_ok(x, y) point_ok(x + width - 1, y + height - 1)
  drawing.push(["fill", x, y, width, height, color])
end

def text(x, y, value, color)
  assert(type(value) == "string", "text value must be a string")
  assert(x == 20 && text_width(value) <= 32, "text outside 32px metric lane: " + value)
  assert(y >= 1 && y <= 15, "text baseline outside panel")
  var index = 0
  while index < size(value)
    if value[index .. index + 1] == "°"
      index += 2
    else
      var code = value[index .. index]
      assert(code >= " " && code <= "~", "unsupported text glyph emitted")
      index += 1
    end
  end
  text_calls.push([x, y, value, color])
  drawing.push(["text", x, y, value, color])
end

def check(condition, message)
  assert(condition, message)
  checks += 1
end

def has_text_value(value)
  for call : text_calls
    if call[2] == value return true end
  end
  return false
end

def has_fill(x, y)
  for call : drawing
    if call[0] == "fill" && call[1] == x && call[2] == y return true end
  end
  return false
end

def max(a, b) return a > b ? a : b end
def min(a, b) return a < b ? a : b end
def clamp(v, a, b) return max(a, min(v, b)) end

var source_file = open("NetatmoV2/netatmo_graphics.be.inc", "r")
var artwork = compile(source_file.read() + "\nreturn NetatmoArtwork()")()
source_file.close()

def page(kind, view, name, values)
  return {"kind":kind, "view":view, "name":name, "id":"fixture-1", "values":values,
    "stamp":1700000000, "received":0, "battery":78, "reachable":true,
    "celsius":true, "co2_low":800, "co2_high":1500}
end

def render(item, elapsed, index, total, health)
  artwork.paint_page(item, elapsed, index, total, health)
  peak_calls = max(peak_calls, size(drawing))
  check(size(drawing) > 0, "page emitted no drawing")
end

var indoor_values = {"Temperature":21.4, "Humidity":48, "CO2":940, "Pressure":1012,
  "Noise":34}
var outdoor_values = {"Temperature":-3.2, "Humidity":81, "min_temp":-6.4, "max_temp":4.8}
var rain_values = {"Rain":0.7, "sum_rain_1":1.2, "sum_rain_24":12.5}
var wind_values = {"WindStrength":12.4, "WindAngle":225, "GustStrength":23.9,
  "GustAngle":240, "max_wind_str":28.2}

var pages = [
  page("indoor", "climate", "Kitchen", indoor_values),
  page("indoor", "air", "Küche / Küche", indoor_values),
  page("extra", "climate", "Couch", {"Temperature":19.8}),
  page("extra", "air", "Aß室", {"CO2":0, "Noise":0}),
  page("outdoor", "climate", "Garden", outdoor_values),
  page("outdoor", "range", "Outside", outdoor_values),
  page("rain", "rain", "Rain", rain_values),
  page("rain", "rain_day", "Roof", rain_values),
  page("wind", "wind", "Wind", wind_values),
  page("wind", "wind_dir", "Roof", wind_values),
  page("indoor", "offline", "Missing", {})
]

# Names identify additional rooms only when explicitly enabled. Changing a
# hidden name must not change a single drawing call in the default layout.
var unnamed = page("extra", "climate", "COUCH", {"Temperature":23.2, "Humidity":56})
render(unnamed, 500, 0, 1, "fresh")
check(has_text_value("23.2°C") && has_text_value("56%"), "climate readings must omit T/H prefixes and include the degree glyph")
var anonymous_frame = json.dump(drawing)
unnamed["name"] = "OFFICE"
render(unnamed, 500, 0, 1, "fresh")
check(json.dump(drawing) == anonymous_frame, "module names leaked into the default graphic")
unnamed["show_name"] = true
render(unnamed, 500, 0, 1, "fresh")
check(json.dump(drawing) != anonymous_frame, "room-name option did not change the caption layout")
var labelled_frame = json.dump(drawing)
unnamed["name"] = "COUCH"
render(unnamed, 500, 0, 1, "fresh")
check(json.dump(drawing) != labelled_frame, "distinct rooms are not identifiable with labels on")
unnamed["celsius"] = false
unnamed.find("values")["Temperature"] = 0
render(unnamed, 500, 0, 1, "fresh")
check(has_text_value("32.0°F"), "Fahrenheit degree/unit rendering is incorrect")

check(artwork.safe_name("Küche") == "KUCHE", "German room name was not transliterated")
check(artwork.safe_name("Žluť") == "ZLUT", "Czech room name was not transliterated")
check(artwork.safe_name("Couch 🛋") == "COUCH", "common room name was not preserved")
check(size(artwork.safe_name("室内")) == 1, "unknown UTF-8 was expanded into broken caption bytes")
clear()
artwork.room_scene(0, "indoor", "climate", false)
var main_room_art = json.dump(drawing)
clear()
artwork.room_scene(0, "extra", "climate", false)
check(json.dump(drawing) != main_room_art, "main station and extra couch scenes are identical")

for index : 0 .. size(pages) - 1
  render(pages[index], 0, index, size(pages), "fresh")
  render(pages[index], 1750, index, size(pages), "fresh")
  render(pages[index], 1750, index, size(pages), "stale")
end

for named : [false, true]
  for index : 0 .. size(pages) - 1
    pages[index]["show_name"] = named
    for tick : 0 .. 15
      render(pages[index], tick * 250, index, size(pages), "fresh")
    end
  end
end

var offline_text = false
for call : text_calls
  if call[2] == "NO DATA" || call[2] == "OFFLINE" offline_text = true end
end
check(offline_text, "offline view did not show NO DATA/OFFLINE")

# A health-expired page must hide retained values and expose a useful frame.
render(pages[0], 250, 0, 2, "expired")
var expired_text = false
for call : text_calls
  if call[2] == "NO DATA" || call[2] == "OFFLINE" expired_text = true end
end
check(expired_text, "expired page did not show NO DATA/OFFLINE")

# Partial and extreme values must remain readable without inventing zeroes.
render(page("indoor", "climate", "Very long/Ünicode room", {"Humidity":-999999}), 250, 0, 1, "fresh")
render(page("outdoor", "range", "Extremely wide room", {"min_temp":-100000000, "max_temp":100000000}), 250, 0, 1, "fresh")
render(page("wind", "wind", "WIND", {"WindStrength":-999999999, "GustStrength":0}), 250, 0, 1, "fresh")
render(page("wind", "wind", "WIND", {"WindStrength":-9.9, "GustStrength":-10.1}), 250, 0, 1, "fresh")
render(page("indoor", "air", "AIR", {"CO2":-100000000, "Pressure":100000000, "Noise":-100000000}), 250, 0, 1, "fresh")
render(page("rain", "rain_day", "RAIN", {"Rain":-100000000, "sum_rain_1":100000000, "sum_rain_24":-100000000}), 250, 0, 1, "fresh")
render(page("wind", "wind_dir", "WIND", {"WindAngle":-100000000, "GustAngle":100000000,
  "GustStrength":-100000000, "max_wind_str":-100000000}), 250, 0, 1, "fresh")
render(page("rain", "rain", "DRY", {"Rain":0, "sum_rain_1":0}), 0, 0, 1, "fresh")

# Overflow is explicit and never silently clamped to a fabricated edge value;
# units remain readable at the same time.
var edge_air = page("indoor", "air", "EDGE", {"CO2":10000, "Pressure":10000, "Noise":-10000})
render(edge_air, 0, 0, 1, "fresh")
check(has_text_value("CO2 HI"), "CO2 edge was silently clamped")
check(has_text_value("HIhPa"), "pressure edge was silently clamped or lost hPa")
check(!has_text_value("AIR OK"), "high CO2 incorrectly claimed AIR OK")
render(page("extra", "air", "COUCH", {"CO2":987}), 500, 0, 1, "fresh")
check(has_text_value("ppm") && !has_text_value("NO AUX"), "normal indoor CO2-only page must show its unit without a missing-data alert")
render(edge_air, 1250, 0, 1, "fresh")
check(has_text_value("-HIdB"), "noise edge was silently clamped or lost dB")

render(page("rain", "rain", "UNITS", {"Rain":1.2, "sum_rain_1":2.3}), 0, 0, 1, "fresh")
check(has_text_value("R1.2mm") && has_text_value("1H2.3mm"), "rain metric units are not explicit")
render(page("rain", "rain_day", "DAY", {"sum_rain_24":12.5}), 0, 0, 1, "fresh")
check(has_text_value("12.5mm") && has_fill(1, 0), "24-hour rain total lost decimal precision or its badge")
render(page("rain", "rain_day", "DAY", {"sum_rain_24":-998}), 0, 0, 1, "fresh")
check(has_text_value("-998mm"), "24-hour negative total was silently altered")
render(page("rain", "rain", "NEG", {"Rain":-998.9, "sum_rain_1":-999}), 0, 0, 1, "fresh")
render(page("wind", "wind", "NEG", {"WindStrength":-998.9, "GustStrength":-999}), 0, 0, 1, "fresh")
render(page("indoor", "air", "EDGE", {"Pressure":-9999, "Noise":-9999}), 0, 0, 1, "fresh")
render(page("wind", "wind", "WIND", {"WindStrength":12.4, "GustStrength":23.9}), 0, 0, 1, "fresh")
check(has_text_value("W12.4KPH") && has_text_value("G23.9KPH"), "wind/gust prefixes or KPH unit missing")
render(page("wind", "wind", "WIDE", {"WindStrength":98.9, "GustStrength":98.9}), 0, 0, 1, "fresh")
check(has_text_value("W98.9KPH") && has_text_value("G98.9KPH"), "maximum decimal wind footprint exceeded 32px")
render(page("wind", "wind_dir", "WIND", {"WindAngle":225, "GustStrength":23.9, "max_wind_str":28.2}), 0, 0, 1, "fresh")
check(has_text_value("D225DEG") && has_text_value("M28KPH"), "direction or daily max unit/prefix missing")

# At most 24 pages use the full progress track; the last page must reach its
# scaled endpoint without drawing over either metric baseline.
render(page("indoor", "climate", "TRACK", {"Temperature":0, "Humidity":0}), 0, 23, 24, "fresh")
check(has_fill(51, 15), "24-page progress endpoint is not scaled to the track")
for call : drawing
  if call[0] == "text" check(call[1] == 20 && (call[2] == 6 || call[2] == 14), "metric text collided with progress row") end
end

# Fahrenheit conversion affects only temperature display and remains bounded.
render({"kind":"outdoor", "view":"climate", "name":"F", "values":{"Temperature":0,
  "Humidity":20}, "celsius":false, "co2_low":800, "co2_high":1500}, 250, 0, 1, "fresh")

# Zero weather must have a different frame from active weather and active
# weather must animate inside the deterministic four-second loop.
var rain_zero = page("rain", "rain", "DRY", {"Rain":0, "sum_rain_1":0})
var rain_active = page("rain", "rain", "WET", {"Rain":4.0, "sum_rain_1":2.0})
render(rain_zero, 500, 0, 1, "fresh")
var dry_frame = json.dump(drawing)
render(rain_active, 500, 0, 1, "fresh")
check(json.dump(drawing) != dry_frame, "zero and active rain look identical")
var rain_frame = json.dump(drawing)
render(rain_active, 500, 0, 1, "fresh")
check(json.dump(drawing) == rain_frame, "same elapsed rain frame is not deterministic")
render(rain_active, 500, 0, 1, "fresh")
var loop_a = json.dump(drawing)
render(rain_active, 4500, 0, 1, "fresh")
check(json.dump(drawing) == loop_a, "four-second rain loop is not deterministic")
var rain_history = page("rain", "rain", "HIST", {"Rain":0, "sum_rain_1":2, "sum_rain_24":8})
clear()
artwork.rain_scene(500, false)
var dry_scene = json.dump(drawing)
clear()
artwork.rain_scene(500, artwork.page_active(rain_history, "rain"))
check(json.dump(drawing) == dry_scene, "rain history falsely animated current precipitation")
var rain_missing = page("rain", "rain", "MISSING", {"sum_rain_24":8})
clear()
artwork.rain_scene(500, artwork.page_active(rain_missing, "rain"))
check(json.dump(drawing) == dry_scene, "daily rain falsely animated missing latest precipitation")

var wind_zero = page("wind", "wind", "CALM", {"WindStrength":0, "GustStrength":0})
var wind_active = page("wind", "wind", "BREEZ", {"WindStrength":12, "WindAngle":90, "GustStrength":20})
render(wind_zero, 500, 0, 1, "fresh")
var calm_frame = json.dump(drawing)
clear()
artwork.wind_scene(500, false, nil)
var calm_scene = json.dump(drawing)
render(wind_active, 500, 0, 1, "fresh")
check(json.dump(drawing) != calm_frame, "zero and active wind look identical")
var wind_max_only = page("wind", "wind", "MAX", {"max_wind_str":50})
clear()
artwork.wind_scene(500, artwork.page_active(wind_max_only, "wind"), nil)
check(json.dump(drawing) == calm_scene, "historical max wind falsely animated current wind")

for code : ["signin", "loading", "no_modules", "disabled", "network", "auth", "parse", "unknown"]
  artwork.paint_status(code, 0)
  check(size(drawing) > 0, "status has no drawing: " + code)
  artwork.paint_status(code, 1750)
  check(size(drawing) > 0, "status phase has no drawing: " + code)
end

# Missing pages and malformed health inputs still produce bounded diagnostic
# art rather than throwing from the renderer.
render(nil, -1, nil, nil, "unknown")
artwork.paint_status(nil, -1)
check(size(drawing) > 0, "nil status has no drawing")

print("Peak native draw calls per frame: " + str(peak_calls))
print("PASS: NetatmoArtwork all page views, status states, finite bounds, stale/expired handling, conversion and animation (" + str(checks) + " checks)")
