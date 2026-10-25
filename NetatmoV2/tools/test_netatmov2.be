# Run from NetatmoV2/ with the Berry 1.1 32-bit/single-precision interpreter.
# The reusable prefix ends immediately before the first app construction below;
# tools/build.py copies that prefix for native media capture.
import json
import os
import string
import sys

# The desktop Berry interpreter has no firmware-native OAuth module. Briefly
# create and import a one-line local module, then remove it. The generated app
# itself still compiles and executes its real `import oauth`, now from cache.
var oauth_stub_exists = false
try
  var existing_oauth_stub = open("oauth.be", "r")
  existing_oauth_stub.close()
  oauth_stub_exists = true
except ..
end
assert(!oauth_stub_exists, "refusing to overwrite a pre-existing oauth.be")
var oauth_module_file = open("oauth.be", "w")
oauth_module_file.write("return module(\"oauth\")\n")
oauth_module_file.close()
# Berry first searches beside this harness (tools/), while the guarded scratch
# file lives in the process working directory. Add that directory explicitly;
# the same prefix then works when copied into work/ for media capture.
sys.path().push(".")
import oauth
os.remove("oauth.be")

var cfg = {}
var clock_ms = 0
var epoch_value = 1700000000000.0
var hour_value = 12
var oauth_is_ready = true
var oauth_mode = "async"
var sync_body = nil
var sync_status = 200
var requests = []
var settings_state = {"useCelsius":true, "textColor":0xFFFFFF}
var messages = []
var drawing = []
var text_calls = []
var checks = 0

# Native small-font ASCII advances. tools/verify.py checks this map against the
# checked-in AWTRIX BDF instead of trusting approximate fixed-width metrics.
var advances = {" ":2, "!":2, "'":2, "(":3, ")":3, ",":3, ".":2, ":":2, ";":3,
  "I":2, "M":6, "N":5, "Q":5, "W":6, "`":3, "i":2, "|":2}

var fixture_data = {
  "stations-v1.json":"{\"status\":\"ok\",\"body\":{\"user\":{\"administrative\":{\"unit\":0}},\"devices\":[{\"station_name\":\"Météo Demo\",\"type\":\"NAMain\",\"_id\":\"synthetic-station-01\",\"place\":{\"city\":\"Example\"},\"modules\":[{\"battery_percent\":81,\"module_name\":\"Balkón Süd\",\"_id\":\"synthetic-outdoor-01\",\"type\":\"NAModule1\",\"dashboard_data\":{\"Humidity\":67,\"max_temp\":18.6,\"time_utc\":1700000000,\"Temperature\":12.4,\"min_temp\":7.2}},{\"module_name\":\"Vind renamed\",\"type\":\"NAModule2\",\"_id\":\"synthetic-wind-01\",\"battery_percent\":64,\"dashboard_data\":{\"GustAngle\":225,\"WindStrength\":0,\"time_utc\":1700000000,\"WindAngle\":0,\"max_wind_str\":24,\"GustStrength\":18}},{\"type\":\"NAModule3\",\"dashboard_data\":{\"sum_rain_24\":4.8,\"Rain\":0,\"time_utc\":1700000000,\"sum_rain_1\":0},\"_id\":\"synthetic-rain-01\",\"module_name\":\"Pluie zéro\",\"battery_percent\":73},{\"dashboard_data\":{\"CO2\":987,\"Humidity\":48,\"time_utc\":1700000000,\"Temperature\":20.1},\"_id\":\"synthetic-extra-01\",\"battery_percent\":92,\"type\":\"NAModule4\",\"module_name\":\"Couch 🛋 renamed\"}],\"dashboard_data\":{\"Noise\":39,\"Pressure\":1016.2,\"CO2\":612,\"Humidity\":44,\"time_utc\":1700000000,\"Temperature\":21.6}}]}}",
  "stations-partial.json":"{\"body\":{\"devices\":[{\"_id\":\"synthetic-station-01\",\"type\":\"NAMain\",\"station_name\":\"Météo Demo\",\"dashboard_data\":{\"time_utc\":1700000600,\"Temperature\":22.0,\"Humidity\":43},\"modules\":[{\"_id\":\"synthetic-rain-01\",\"type\":\"NAModule3\",\"module_name\":\"Pluie zéro\",\"dashboard_data\":{\"time_utc\":1700000600,\"Rain\":0,\"sum_rain_1\":0,\"sum_rain_24\":5.1}},{\"_id\":\"synthetic-extra-01\",\"type\":\"NAModule4\",\"module_name\":\"Couch renamed\",\"dashboard_data\":{\"time_utc\":\"not-a-number\",\"Temperature\":\"21.0\",\"CO2\":null}}]}]}}",
  "stations-empty.json":"{\"body\":{\"devices\":[]}}",
  "stations-invalid-values.json":"{\"body\":{\"devices\":[{\"_id\":\"synthetic-invalid-01\",\"type\":\"NAMain\",\"station_name\":\"Invalid sample\",\"dashboard_data\":{\"time_utc\":1700000000,\"Temperature\":999,\"Humidity\":-1,\"CO2\":\"800\",\"Noise\":null,\"Pressure\":0},\"modules\":[{\"_id\":\"synthetic-rain-invalid\",\"type\":\"NAModule3\",\"module_name\":\"Invalid rain\",\"dashboard_data\":{\"time_utc\":1700000000,\"Rain\":-0.1,\"sum_rain_1\":\"0\",\"sum_rain_24\":null}},{\"_id\":\"synthetic-wind-zero\",\"type\":\"NAModule2\",\"module_name\":\"Calm\",\"dashboard_data\":{\"time_utc\":1700000000,\"WindStrength\":0,\"GustStrength\":0,\"WindAngle\":0,\"GustAngle\":360,\"max_wind_str\":0}}]}]}}"
}

var store = module("store")
store.get = def (key, fallback) return cfg.find(key, fallback) end
var settings = module("settings")
settings.get = def (key) return settings_state.find(key) end
oauth.ready = def () return oauth_is_ready end
oauth.get = def (url, callback, opts)
  if oauth_mode == "throw" raise "mock oauth failure" end
  if oauth_mode == "false" return false end
  var request = {"url":url, "callback":callback, "opts":opts}
  if oauth_mode == "sync"
    callback(sync_body, sync_status)
    return true
  end
  requests.push(request)
  if oauth_mode == "nil" return nil end
  return true
end

def now_ms() return clock_ms end
def epoch_ms() return epoch_value end
def hour() return hour_value end
def log(message) messages.push(message) end
def num(value, fallback)
  if type(value) == "int" || type(value) == "real" return value end
  return fallback
end
def max(a, b) return a > b ? a : b end
def min(a, b) return a < b ? a : b end
def clamp(v, a, b) return max(a, min(v, b)) end
def text_width(label)
  var width = 0
  if size(label) == 0 return 0 end
  for index : 0 .. size(label) - 1 width += advances.find(label[index .. index], 4) end
  return width
end
def text_ink_width(label) return text_width(label) end
def format(pattern, value) return string.format(pattern, value) end
def font(name) assert(name == "small", "unexpected font") end
def clear() drawing = [] text_calls = [] end
def point_ok(x, y) assert(x >= 0 && x < 52 && y >= 0 && y < 16, "draw point out of bounds") end
def pixel(x, y, color) point_ok(x, y) drawing.push(["pixel", x, y, color]) end
def line(x, y, x2, y2, color) point_ok(x, y) point_ok(x2, y2) drawing.push(["line", x, y, x2, y2, color]) end
def rect_fill(x, y, width, height, color)
  assert(width > 0 && height > 0, "invalid fill rectangle")
  point_ok(x, y) point_ok(x + width - 1, y + height - 1)
  drawing.push(["fill", x, y, width, height, color])
end
def rect(x, y, width, height, color)
  assert(width > 0 && height > 0, "invalid outline rectangle")
  point_ok(x, y) point_ok(x + width - 1, y + height - 1)
  drawing.push(["rect", x, y, width, height, color])
end
def text(x, y, label, color)
  assert(x >= 0 && x + text_ink_width(label) <= 52, "text exceeds panel bounds: " + label)
  assert(y >= 1 && y <= 15, "text baseline outside panel")
  var call = ["text", x, y, label, color]
  drawing.push(call) text_calls.push(call)
end
def check(condition, message) assert(condition, message) checks += 1 end
def has_label(label)
  for call : text_calls if call[3] == label return true end end
  return false
end
def has_pixel(x, y, color)
  for call : drawing
    if call[0] == "pixel" && call[1] == x && call[2] == y && call[3] == color return true end
  end
  return false
end
def load_fixture(name)
  var body = fixture_data.find(name)
  assert(type(body) == "string", "unknown fixture " + name)
  return body
end
def deliver(app, body, status)
  assert(size(requests) > 0, "no pending OAuth request")
  var request = requests[0]
  requests.remove(0)
  var callback = request.find("callback")
  callback(body, status)
  return app
end
def new_app(settings_override)
  cfg = settings_override
  clock_ms = 0
  epoch_value = 1700000000000.0
  hour_value = 12
  oauth_is_ready = cfg.find("__oauth_ready", true)
  oauth_mode = cfg.find("__oauth_mode", "async")
  sync_body = cfg.find("__sync_body", nil)
  sync_status = cfg.find("__sync_status", 200)
  requests = []
  messages = []
  settings_state = {"useCelsius":cfg.find("__celsius", true), "textColor":0xFFFFFF}
  clear()
  var instance = compile("NetatmoV2.ax", "file")()
  instance.setup()
  return instance
end
def page_count_for(app, module_id)
  var count = 0
  for page : app.pages if page.find("id") == module_id count += 1 end end
  return count
end
def view_exists(app, view)
  for page : app.pages if page.find("view") == view return true end end
  return false
end
def find_page(app, view)
  for page : app.pages if page.find("view") == view return page end end
  return nil
end

var app = new_app({})
check(size(requests) == 1 && app.busy, "setup starts exactly one signed-in request")
check(requests[0].find("url") == "https://api.netatmo.com/api/getstationsdata", "request uses the owned-stations endpoint")
check(requests[0].find("opts").find("cap") == 65536, "response cap is explicit and bounded")
deliver(app, load_fixture("stations-v1.json"), 200)
check(!app.busy && size(app.module_order) == 5, "all five API module types are discovered by ID and type")
check(size(app.pages) == 10, "five complete modules produce at most two pages each")
for id : app.module_order check(page_count_for(app, id) <= 2, "module page count is capped at two") end
check(app.modules.find("synthetic-wind-01").find("values").find("WindStrength") == 0, "zero wind remains a valid reading")
check(app.modules.find("synthetic-rain-01").find("values").find("Rain") == 0, "zero rain remains a valid reading")
check(view_exists(app, "range") && view_exists(app, "rain_day") && view_exists(app, "wind_dir"), "type-specific second pages are built")
app.loop()
check(size(requests) == 0, "successful poll does not overlap another request")
app = new_app({"seconds":99, "every":1, "stale_minutes":240, "max_age_minutes":60, "clow":2000, "chigh":500, "qfrom":99, "qto":-1})
check(app.page_ms == 12000 && app.poll_ms == 300000, "display and poll settings clamp to declared bounds")
check(app.max_age_ms == app.stale_ms && app.co2_high == 2001, "expiry and CO2 thresholds preserve valid ordering")
check(app.quiet_from == 23 && app.quiet_to == 0, "quiet-hour settings clamp to clock bounds")

# Malformed account shapes cannot grow memory beyond twelve modules / 24 pages.
app = new_app({})
var many_modules = []
for index : 0 .. 14
  many_modules.push({"_id":"bounded-" + str(index), "type":"NAModule4", "module_name":"Renamed " + str(index), "dashboard_data":{"time_utc":1700000000, "Temperature":index, "CO2":500 + index}})
end
many_modules.push({"_id":"bounded-1", "type":"NAModule4", "dashboard_data":{"time_utc":1700000000, "Temperature":19}})
var bounded_body = json.dump({"body":{"devices":[{"_id":"bounded-main", "type":"NAMain", "dashboard_data":{"time_utc":1700000000, "Temperature":20}, "modules":many_modules}]}})
deliver(app, bounded_body, 200)
check(size(app.module_order) == 12 && size(app.pages) <= 24, "module IDs dedupe and account size stays bounded")
clock_ms = 600000 epoch_value = 1700010860000.0 app.loop()
deliver(app, "{\"body\":{\"devices\":[{\"_id\":\"replacement-main\",\"type\":\"NAMain\",\"dashboard_data\":{\"time_utc\":1700010860,\"Temperature\":18}}]}}", 200)
check(size(app.module_order) == 12 && app.modules.find("replacement-main") != nil, "expired missing cache entry yields a bounded slot for new hardware")

app = new_app({"__celsius":false})
deliver(app, load_fixture("stations-v1.json"), 200)
check(app.pages[0].find("celsius") == false && app.pages[0].find("co2_low") == 800 && app.pages[0].find("co2_high") == 1500, "display settings are copied onto every page")
for page : app.pages
  check(page.find("kind") != nil && page.find("view") != nil && page.find("name") != nil && page.find("id") != nil && isinstance(page.find("values"), map), "stable page interface is complete")
end

app = new_app({"station_id":"does-not-exist"})
deliver(app, load_fixture("stations-v1.json"), 200)
check(size(app.module_order) == 0 && size(app.pages) == 0 && app.status_code == "no_modules", "station filter never guesses by room name")
app.on_show() app.draw()
check(size(drawing) > 0 && size(text_calls) > 0, "signed-in no-module state paints a readable diagnostic")

app = new_app({"indoor":false, "outdoor":false, "extra":false, "rain":true, "wind":false})
deliver(app, load_fixture("stations-v1.json"), 200)
check(size(app.pages) == 2 && app.pages[0].find("kind") == "rain", "visibility toggles only filter discovered hardware")
app = new_app({"indoor":false, "outdoor":false, "extra":false, "rain":false, "wind":false})
check(size(requests) == 0 && app.status_code == "disabled" && app.should_show(), "all-disabled stays diagnostic without network traffic")
app = new_app({"rain":false})
deliver(app, "{\"body\":{\"devices\":[{\"_id\":\"\",\"type\":\"NAMain\",\"modules\":[{\"_id\":\"only-rain\",\"type\":\"NAModule3\",\"dashboard_data\":{\"time_utc\":1700000000,\"Rain\":1}}]}]}}", 200)
check(size(app.module_order) == 1 && size(app.pages) == 0 && app.status_code == "no_modules", "response containing only hidden module types shows no-modules diagnostic")

app = new_app({})
deliver(app, load_fixture("stations-invalid-values.json"), 200)
check(size(app.module_order) == 3 && size(app.pages) == 4, "invalid fields become offline pages while valid zero wind remains visible")
check(app.modules.find("synthetic-invalid-01").find("received") == nil, "invalid and string-valued measurements never become a sample")
check(app.modules.find("synthetic-wind-zero").find("values").find("WindAngle") == 0, "zero direction is not treated as missing")

# Source timestamp age, not value changes or HTTP receipt time, controls health.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
var main = app.modules.find("synthetic-station-01")
epoch_value = 1700000600000.0
check(app.health(main) == "fresh", "unchanged V1 data is fresh after ten minutes")
epoch_value = 1700001200000.0
check(app.health(main) == "fresh", "unchanged V1 data is fresh after twenty minutes")
epoch_value = 1700002700000.0
check(app.health(main) == "stale", "source data becomes stale at forty-five minutes")
epoch_value = 1700010800000.0
check(app.health(main) == "expired", "source data expires at one hundred eighty minutes")
app.on_show()
check(size(app.frozen_pages) == 5, "expired modules collapse to one page each")
var first_expired_page = app.frozen_pages[0]
check(first_expired_page.find("view") == "offline", "expired modules hide all numeric views")
epoch_value = 1699996400000.0
check(app.health(main) == "fresh", "backward wall-clock jump clamps source age to zero")

# Without wall-clock time, the monotonic receipt timestamp is the fallback.
app = new_app({})
epoch_value = -1
deliver(app, load_fixture("stations-v1.json"), 200)
main = app.modules.find("synthetic-station-01")
clock_ms = 1200000
check(app.health(main) == "fresh", "monotonic fallback keeps a twenty-minute sample fresh")
clock_ms = 2700000
check(app.health(main) == "stale", "monotonic fallback reaches stale threshold")
clock_ms = 10800000
check(app.health(main) == "expired", "monotonic fallback reaches expiry threshold")

# A successful partial response replaces fields and does not refresh omissions.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
app.on_show()
var frozen_count = size(app.frozen_pages)
clock_ms = 600000 epoch_value = 1700000600000.0 app.loop()
check(size(requests) == 1, "default refresh occurs at ten minutes")
deliver(app, load_fixture("stations-partial.json"), 200)
check(app.modules.find("synthetic-station-01").find("values").find("CO2") == nil, "valid partial dashboard replaces rather than mixes fields")
check(app.health(app.modules.find("synthetic-outdoor-01")) == "stale", "missing prior module is retained but unreachable")
check(app.health(app.modules.find("synthetic-extra-01")) == "stale", "present module without numeric readings retains stale snapshot")
check(size(app.frozen_pages) == frozen_count && app.duration() == frozen_count * 6000, "visible turn keeps its frozen page count")
app.on_hide() app.on_show()
check(size(app.frozen_pages) == size(app.pages), "next visit adopts the updated page list")

# Repeated V1 GETs with the same source stamp do not refresh monotonic age.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
var first_received = app.modules.find("synthetic-station-01").find("received")
clock_ms = 600000 epoch_value = -1 app.loop()
deliver(app, load_fixture("stations-v1.json"), 200)
check(app.modules.find("synthetic-station-01").find("received") == first_received, "same source stamp preserves original receipt baseline")
clock_ms = 2700000
check(app.health(app.modules.find("synthetic-station-01")) == "stale", "same cloud sample becomes stale when wall clock is unknown")

# Explicit API unreachable state never republishes an embedded old dashboard.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
var outdoor_before = app.modules.find("synthetic-outdoor-01")
first_received = outdoor_before.find("received")
clock_ms = 600000 epoch_value = 1700000600000.0 app.loop()
var unreachable = "{\"body\":{\"devices\":[{\"_id\":\"synthetic-station-01\",\"type\":\"NAMain\",\"modules\":[{\"_id\":\"synthetic-outdoor-01\",\"type\":\"NAModule1\",\"reachable\":false,\"dashboard_data\":{\"time_utc\":1700000600,\"Temperature\":99}}]}]}}"
deliver(app, unreachable, 200)
check(outdoor_before.find("values").find("Temperature") == 12.4 && outdoor_before.find("received") == first_received, "reachable false preserves old value and receipt")
check(outdoor_before.find("reachable") == false && app.health(outdoor_before) == "stale", "reachable false is exposed as stale")

# Future source timestamps are unknown, so health falls back to receipt time.
app = new_app({})
var future = "{\"body\":{\"devices\":[{\"_id\":\"future-main\",\"type\":\"NAMain\",\"dashboard_data\":{\"time_utc\":1700001000,\"Temperature\":20}}]}}"
deliver(app, future, 200)
check(app.modules.find("future-main").find("stamp") == nil && app.health(app.modules.find("future-main")) == "fresh", "unreasonable future timestamp uses monotonic receipt age")

# Parse and transport failures retain last-good snapshots and expose diagnostics.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
var old_values = app.modules.find("synthetic-station-01").find("values")
clock_ms = 600000 app.loop() deliver(app, "{", 200)
check(app.status_code == "parse" && app.modules.find("synthetic-station-01").find("values") == old_values, "bad JSON retains the last good snapshot")
clock_ms = 660000 app.loop()
var oversized = ""
for index : 0 .. 65536 oversized += "x" end
deliver(app, oversized, 200)
check(app.status_code == "parse" && size(app.module_order) == 5, "oversize body is rejected without clearing modules")
clock_ms = 720000 app.loop() deliver(app, nil, 0)
check(app.status_code == "network" && size(app.module_order) == 5, "network failure retains last-good data")
clock_ms = 780000 app.loop() deliver(app, nil, 401)
check(app.status_code == "auth", "HTTP 401 exposes sign-in failure")
clock_ms = 840000 app.loop() deliver(app, nil, 429)
check(app.next_delay_ms >= 600000, "HTTP 429 backs off for at least ten minutes")

# Refused, thrown, synchronous, timed-out and late callbacks cannot stick busy.
app = new_app({"__oauth_ready":false})
check(app.status_code == "signin" && !app.busy && size(requests) == 0 && size(messages) == 1, "unsigned account is a logged sign-in diagnostic")
app.loop()
check(size(messages) == 1, "unchanged status is logged only once")
oauth_is_ready = true clock_ms = 1000 app.loop()
check(app.busy && size(requests) == 1, "sign-in becoming ready starts a request")
app = new_app({"__oauth_mode":"false"})
check(!app.busy && app.status_code == "network" && app.next_delay_ms == 60000, "oauth.get false clears busy and schedules retry")
app = new_app({"__oauth_mode":"throw"})
check(!app.busy && app.status_code == "network", "oauth.get exception clears busy")
app = new_app({"__oauth_mode":"nil"})
check(app.busy && size(requests) == 1, "non-false asynchronous return keeps the queued request active")
deliver(app, load_fixture("stations-v1.json"), 200)
check(!app.busy && size(app.module_order) == 5, "callback completes after a non-false nil return")
app = new_app({"__oauth_mode":"sync", "__sync_body":load_fixture("stations-v1.json"), "__sync_status":200})
check(!app.busy && size(app.module_order) == 5, "synchronous callback completes without busy being restored")

app = new_app({})
var late_request = requests[0]
clock_ms = 45000 app.loop()
check(!app.busy && app.status_code == "network", "watchdog clears a forty-five-second request")
var late_callback = late_request.find("callback")
late_callback(load_fixture("stations-v1.json"), 200)
check(size(app.module_order) == 0, "watchdog generation rejects its late callback")
clock_ms = 105000 app.loop()
check(app.busy && size(requests) == 2, "watchdog schedules one bounded retry")

# Signing out or an auth response overrides cached pages without erasing them.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
app.on_show()
oauth_is_ready = false clock_ms = 1 app.loop() app.draw()
check(app.status_code == "signin", "sign-out promptly changes status")
check(size(app.module_order) == 5, "sign-out retains cache for reauthentication")
check(has_label("SIGN IN"), "sign-out diagnostic hides retained account readings")
app.loop()
check(size(messages) == 1, "repeated signed-out loops do not spam logs")
oauth_is_ready = true clock_ms = 1001 app.loop()
deliver(app, nil, 401) app.draw()
check(app.status_code == "auth", "HTTP 401 changes status to auth")
check(has_label("AUTH"), "HTTP 401 diagnostic overrides cached page drawing")
check(size(messages) == 2, "HTTP auth transition adds one bounded log entry")
check(messages[1] == "NetatmoV2: auth HTTP 401", "auth log contains status only")
app = new_app({})
deliver(app, nil, 403)
check(app.status_code == "auth" && messages[0] == "NetatmoV2: auth HTTP 403", "HTTP 403 scope failure uses the same safe auth diagnostic")

# Quiet hours skip only the display turn; diagnostics otherwise always show.
app = new_app({"quiet":true, "qfrom":23, "qto":8})
hour_value = 23
check(!app.should_show() && app.busy, "overnight quiet skips display while polling continues")
hour_value = 8
check(app.should_show(), "quiet interval ends at its configured boundary")
hour_value = -1
check(app.should_show(), "unknown local time never hides diagnostics")

# Actual generated artwork is reached through core draw, with a frozen page.
app = new_app({})
deliver(app, load_fixture("stations-v1.json"), 200)
app.on_show() app.draw()
check(size(drawing) > 0 && size(text_calls) >= 2, "core draws one actual generated artwork page")
clock_ms = 6000 app.draw()
check(size(drawing) > 0, "page rotation remains bounded at its page boundary")
var climate_page = find_page(app, "climate")
climate_page.find("values")["Temperature"] = 0
climate_page.find("values")["Humidity"] = 0
app.frozen_pages = [climate_page]
app.shown_at = 0 clock_ms = 0 app.draw()
check(has_label("T0.0C") && has_label("H0%"), "generated artwork renders zero temperature and humidity as readings")
var rain_page = find_page(app, "rain")
app.frozen_pages = [rain_page]
app.draw()
check(has_label("R0.0mm") && has_label("1H0.0mm"), "generated artwork renders zero rain totals as readings")
var wind_page = find_page(app, "wind")
app.frozen_pages = [wind_page]
app.draw()
check(has_label("W0.0KPH"), "generated artwork renders calm wind as a reading")
rain_page.find("values")["Rain"] = 1
app.frozen_pages = [rain_page, rain_page]
app.shown_at = 0 clock_ms = 6000 app.draw()
check(has_pixel(4, 7, 0xC8F4DD), "each page starts its four-second animation at phase zero")

print("PASS: NetatmoV2 Berry checks=" + str(checks))
