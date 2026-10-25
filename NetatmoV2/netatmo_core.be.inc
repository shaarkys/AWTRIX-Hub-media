# @name    NetatmoV2
# @desc    Signed-in Netatmo weather station pages for TC002
# @version 2.0.0
# @display 52x16
# @oauth authorize=https://api.netatmo.com/oauth2/authorize token=https://api.netatmo.com/oauth2/token api=api.netatmo.com scope="read_station" auth=body
# @config indoor bool "Indoor station" default=true group="Modules"
# @config outdoor bool "Outdoor module" default=true group="Modules"
# @config extra bool "Extra indoor modules" default=true group="Modules"
# @config rain bool "Rain module" default=true group="Modules"
# @config wind bool "Wind module" default=true group="Modules"
# @config station_id text "Station ID filter" default="" maxlen=64 group="Account" help="Empty shows all owned stations."
# @config seconds number "Seconds per page" default=6 min=3 max=12 unit=s group="Display"
# @config every number "Refresh interval" default=10 min=5 max=60 unit=min group="Freshness"
# @config stale_minutes number "Stale after" default=45 min=20 max=240 unit=min group="Freshness"
# @config max_age_minutes number "No data after" default=180 min=60 max=1440 unit=min group="Freshness"
# @config clow number "CO2 amber threshold" default=800 min=400 max=2500 unit=ppm group="Air quality"
# @config chigh number "CO2 red threshold" default=1500 min=500 max=5000 unit=ppm group="Air quality"
# @config quiet bool "Quiet hours" default=false group="Quiet hours"
# @config qfrom number "Quiet from" default=23 min=0 max=23 group="Quiet hours"
# @config qto number "Quiet until" default=8 min=0 max=23 group="Quiet hours"

import json
import oauth
import string

class NetatmoV2 : NetatmoArtwork
  var enabled, station_id
  var page_ms, poll_ms, stale_ms, max_age_ms
  var co2_low, co2_high
  var quiet, quiet_from, quiet_to
  var modules, module_order
  var pages, frozen_pages, shown_at
  var status_code
  var last_logged_status
  var busy, request_generation, request_started
  var last_attempt, next_delay_ms

  def init()
    self.enabled = {
      "indoor": store.get("indoor", true) == true,
      "outdoor": store.get("outdoor", true) == true,
      "extra": store.get("extra", true) == true,
      "rain": store.get("rain", true) == true,
      "wind": store.get("wind", true) == true
    }
    self.station_id = store.get("station_id", "")
    if type(self.station_id) != "string" self.station_id = "" end
    self.page_ms = int(clamp(num(store.get("seconds"), 6), 3, 12)) * 1000
    self.poll_ms = int(clamp(num(store.get("every"), 10), 5, 60)) * 60000
    self.stale_ms = int(clamp(num(store.get("stale_minutes"), 45), 20, 240)) * 60000
    self.max_age_ms = int(clamp(num(store.get("max_age_minutes"), 180), 60, 1440)) * 60000
    if self.max_age_ms < self.stale_ms self.max_age_ms = self.stale_ms end
    self.co2_low = int(clamp(num(store.get("clow"), 800), 400, 2500))
    self.co2_high = int(clamp(num(store.get("chigh"), 1500), 500, 5000))
    if self.co2_high <= self.co2_low self.co2_high = self.co2_low + 1 end
    self.quiet = store.get("quiet", false) == true
    self.quiet_from = int(clamp(num(store.get("qfrom"), 23), 0, 23))
    self.quiet_to = int(clamp(num(store.get("qto"), 8), 0, 23))

    self.modules = {}
    self.module_order = []
    self.pages = []
    self.frozen_pages = []
    self.shown_at = now_ms()
    self.status_code = self.any_enabled() ? "loading" : "disabled"
    self.last_logged_status = nil
    self.busy = false
    self.request_generation = 0
    self.request_started = nil
    self.last_attempt = nil
    self.next_delay_ms = 0
  end

  def setup()
    self.poll()
  end

  def any_enabled()
    return self.enabled.find("indoor") || self.enabled.find("outdoor") || self.enabled.find("extra") || self.enabled.find("rain") || self.enabled.find("wind")
  end

  def elapsed(stamp)
    if stamp == nil return 0 end
    return (now_ms() - stamp) & 0x7FFFFFFF
  end

  def due()
    if self.last_attempt == nil return true end
    return self.elapsed(self.last_attempt) >= self.next_delay_ms
  end

  def loop()
    # A sign-out must hide cached account data immediately, not at the next
    # ten-minute cloud poll. Invalidate any callback still on its way.
    if self.any_enabled() && !oauth.ready()
      if self.busy
        self.busy = false
        self.request_generation += 1
      end
      self.set_status("signin", nil)
      self.last_attempt = now_ms()
      self.next_delay_ms = 1000
      return
    end
    if self.busy && self.elapsed(self.request_started) >= 45000
      self.busy = false
      self.request_generation += 1
      self.set_status("network", nil)
      self.last_attempt = now_ms()
      self.next_delay_ms = 60000
    end
    if !self.busy && self.due() self.poll() end
  end

  def poll()
    if self.busy return end
    self.last_attempt = now_ms()
    if !self.any_enabled()
      self.set_status("disabled", nil)
      self.next_delay_ms = self.poll_ms
      return
    end
    if !oauth.ready()
      self.set_status("signin", nil)
      self.next_delay_ms = 1000
      return
    end

    self.request_generation += 1
    var generation = self.request_generation
    self.busy = true
    self.request_started = now_ms()
    var accepted = nil
    var threw = false
    try
      accepted = oauth.get("https://api.netatmo.com/api/getstationsdata", / body, status -> self.on_response(generation, body, status), {"cap":65536})
    except ..
      threw = true
    end
    # A test double or firmware failure can answer synchronously. Only clear the
    # request if its callback has not already completed it.
    if (accepted == false || threw) && self.busy && generation == self.request_generation
      self.busy = false
      self.set_status(oauth.ready() ? "network" : "signin", nil)
      self.last_attempt = now_ms()
      self.next_delay_ms = 60000
    end
  end

  def on_response(generation, body, status)
    if generation != self.request_generation || !self.busy return end
    self.busy = false
    self.last_attempt = now_ms()
    if status == 401 || status == 403
      self.set_status("auth", status)
      self.next_delay_ms = 60000
      return
    end
    if status == 429
      self.set_status("network", status)
      self.next_delay_ms = max(self.poll_ms, 600000)
      return
    end
    if status != 200 || type(body) != "string"
      self.set_status("network", status)
      self.next_delay_ms = 60000
      return
    end
    if size(body) == 0 || size(body) > 65536
      self.set_status("parse", status)
      self.next_delay_ms = 60000
      return
    end

    var payload = nil
    try
      payload = json.load(body)
    except ..
      payload = nil
    end
    if !isinstance(payload, map) || !isinstance(payload.find("body"), map) || !isinstance(payload.find("body").find("devices"), list)
      self.set_status("parse", status)
      self.next_delay_ms = 60000
      return
    end
    self.merge_devices(payload.find("body").find("devices"))
    self.pages = self.make_pages()
    if size(self.pages) == 0
      self.set_status("no_modules", nil)
    else
      self.status_code = "loading"
    end
    self.next_delay_ms = self.poll_ms
  end

  def set_status(code, http_status)
    self.status_code = code
    if code == "loading" || code == self.last_logged_status return end
    var message = "NetatmoV2: " + code
    if type(http_status) == "int" || type(http_status) == "real"
      message += " HTTP " + str(int(http_status))
    end
    log(message)
    self.last_logged_status = code
  end

  def kind_for(api_type)
    if api_type == "NAMain" return "indoor" end
    if api_type == "NAModule1" return "outdoor" end
    if api_type == "NAModule4" return "extra" end
    if api_type == "NAModule3" return "rain" end
    if api_type == "NAModule2" return "wind" end
    return nil
  end

  def numeric(value)
    if type(value) != "int" && type(value) != "real" return nil end
    if value != value || value < -10000000 || value > 10000000 return nil end
    return value
  end

  def valid_field(key, value)
    var v = self.numeric(value)
    if v == nil return nil end
    if key == "Temperature" || key == "min_temp" || key == "max_temp"
      return v >= -100 && v <= 100 ? v : nil
    end
    if key == "Humidity" return v >= 0 && v <= 100 ? v : nil end
    if key == "CO2" return v >= 0 && v <= 10000 ? v : nil end
    if key == "Noise" return v >= 0 && v <= 200 ? v : nil end
    if key == "Pressure" return v >= 300 && v <= 1200 ? v : nil end
    if key == "Rain" || key == "sum_rain_1" || key == "sum_rain_24"
      return v >= 0 && v <= 10000 ? v : nil
    end
    if key == "WindStrength" || key == "GustStrength" || key == "max_wind_str"
      return v >= 0 && v <= 1000 ? v : nil
    end
    if key == "WindAngle" || key == "GustAngle"
      return v >= 0 && v <= 360 ? v : nil
    end
    return nil
  end

  def source_stamp(dashboard)
    var stamp = dashboard.find("time_utc")
    if (type(stamp) != "int" && type(stamp) != "real") || stamp != stamp || stamp <= 0 || stamp > 2147483647 return nil end
    var epoch = epoch_ms()
    if epoch >= 0 && stamp > epoch / 1000.0 + 300 return nil end
    return stamp
  end

  def clean_name(entry, kind)
    var name = entry.find("module_name")
    if type(name) != "string" || size(name) == 0 name = entry.find("station_name") end
    if type(name) != "string" || size(name) == 0 name = kind end
    if size(name) > 96 name = name[0 .. 95] end
    return name
  end

  def merge_entry(entry, forced_kind)
    if !isinstance(entry, map) return end
    var kind = forced_kind
    if kind == nil kind = self.kind_for(entry.find("type")) end
    if kind == nil return end
    var id = entry.find("_id")
    if type(id) != "string" || size(id) == 0 || size(id) > 96 return end
    var old = self.modules.find(id)
    if old == nil && size(self.module_order) >= 12 && !self.evict_expired() return end

    var dashboard = entry.find("dashboard_data")
    var values = {}
    var fields = ["Temperature", "Humidity", "CO2", "Noise", "Pressure", "min_temp", "max_temp", "Rain", "sum_rain_1", "sum_rain_24", "WindStrength", "WindAngle", "GustStrength", "GustAngle", "max_wind_str"]
    if isinstance(dashboard, map)
      for key : fields
        var value = self.valid_field(key, dashboard.find(key))
        if value != nil values[key] = value end
      end
    end
    var battery = self.numeric(entry.find("battery_percent"))
    if battery != nil && (battery < 0 || battery > 100) battery = nil end

    if old == nil
      old = {"kind":kind, "name":self.clean_name(entry, kind), "id":id, "values":{}, "stamp":nil, "received":nil, "battery":battery, "reachable":false}
      self.modules[id] = old
      self.module_order.push(id)
    else
      old["kind"] = kind
      old["name"] = self.clean_name(entry, kind)
      if battery != nil old["battery"] = battery end
    end
    var api_reachable = entry.find("reachable") != false
    if size(values) > 0 && api_reachable
      var old_stamp = old.find("stamp")
      var next_stamp = self.source_stamp(dashboard)
      old["values"] = values
      old["stamp"] = next_stamp
      # Netatmo commonly returns the same V1 cloud sample for several polls.
      # Preserve its monotonic receipt baseline when its source stamp is the
      # same; otherwise an unknown device clock could stay fresh forever.
      if old.find("received") == nil || next_stamp == nil || old_stamp == nil || next_stamp != old_stamp
        old["received"] = now_ms()
      end
      old["reachable"] = true
    else
      # Presence without a usable dashboard never republishes the old sample.
      old["reachable"] = false
    end
  end

  def evict_expired()
    var index = 0
    while index < size(self.module_order)
      var id = self.module_order[index]
      var module = self.modules.find(id)
      if module != nil && module.find("reachable") != true && self.health(module) == "expired"
        self.modules.remove(id)
        self.module_order.remove(index)
        return true
      end
      index += 1
    end
    return false
  end

  def merge_devices(devices)
    for id : self.module_order
      self.modules.find(id)["reachable"] = false
    end
    for device : devices
      if isinstance(device, map)
        var device_id = device.find("_id")
        if self.station_id == "" || device_id == self.station_id
          self.merge_entry(device, self.kind_for(device.find("type")))
          var children = device.find("modules")
          if isinstance(children, list)
            for child : children self.merge_entry(child, nil) end
          end
        end
      end
    end
  end

  def has_value(values, a, b, c)
    return values.find(a) != nil || (b != nil && values.find(b) != nil) || (c != nil && values.find(c) != nil)
  end

  def page_for(module, view)
    var celsius = settings.get("useCelsius")
    if type(celsius) != "bool" celsius = true end
    return {
      "kind":module.find("kind"), "view":view, "name":module.find("name"), "id":module.find("id"),
      "values":module.find("values"), "stamp":module.find("stamp"), "received":module.find("received"),
      "battery":module.find("battery"), "reachable":module.find("reachable"),
      "celsius":celsius, "co2_low":self.co2_low, "co2_high":self.co2_high
    }
  end

  def make_pages()
    var result = []
    for id : self.module_order
      var module = self.modules.find(id)
      var kind = module.find("kind")
      if self.enabled.find(kind)
        var values = module.find("values")
        var added = 0
        if self.health(module) == "expired" || size(values) == 0
          result.push(self.page_for(module, "offline"))
          added = 1
        elif kind == "indoor" || kind == "extra"
          if self.has_value(values, "Temperature", "Humidity", nil)
            result.push(self.page_for(module, "climate")) added += 1
          end
          if added < 2 && self.has_value(values, "CO2", "Noise", "Pressure")
            result.push(self.page_for(module, "air")) added += 1
          end
        elif kind == "outdoor"
          if self.has_value(values, "Temperature", "Humidity", nil)
            result.push(self.page_for(module, "climate")) added += 1
          end
          if added < 2 && self.has_value(values, "min_temp", "max_temp", nil)
            result.push(self.page_for(module, "range")) added += 1
          end
        elif kind == "rain"
          if self.has_value(values, "Rain", "sum_rain_1", nil)
            result.push(self.page_for(module, "rain")) added += 1
          end
          if added < 2 && self.has_value(values, "sum_rain_24", nil, nil)
            result.push(self.page_for(module, "rain_day")) added += 1
          end
        elif kind == "wind"
          if self.has_value(values, "WindStrength", "GustStrength", nil)
            result.push(self.page_for(module, "wind")) added += 1
          end
          if added < 2 && self.has_value(values, "WindAngle", "GustAngle", "max_wind_str")
            result.push(self.page_for(module, "wind_dir")) added += 1
          end
        end
        if added == 0 result.push(self.page_for(module, "offline")) end
      end
    end
    return result
  end

  def age_ms(module)
    var stamp = module.find("stamp")
    var epoch = epoch_ms()
    if stamp != nil && epoch >= 0
      var delta = epoch - stamp * 1000.0
      if delta < 0 delta = 0 end
      return delta
    end
    var received = module.find("received")
    if received == nil return self.max_age_ms end
    return self.elapsed(received)
  end

  def health(module)
    var age = self.age_ms(module)
    if age >= self.max_age_ms return "expired" end
    if module.find("reachable") != true || age >= self.stale_ms return "stale" end
    return "fresh"
  end

  def page_health(page)
    return self.health(page)
  end

  def in_quiet_hours()
    if !self.quiet return false end
    var h = hour()
    if h < 0 || self.quiet_from == self.quiet_to return false end
    if self.quiet_from < self.quiet_to return h >= self.quiet_from && h < self.quiet_to end
    return h >= self.quiet_from || h < self.quiet_to
  end

  def should_show()
    return !self.in_quiet_hours()
  end

  def on_show()
    self.shown_at = now_ms()
    self.pages = self.make_pages()
    self.frozen_pages = []
    for page : self.pages self.frozen_pages.push(page) end
  end

  def on_hide()
    self.frozen_pages = []
  end

  def duration()
    return self.page_ms * max(1, size(self.frozen_pages))
  end

  def draw()
    var elapsed_ms = self.elapsed(self.shown_at)
    if self.status_code == "signin" || self.status_code == "auth"
      self.paint_status(self.status_code, elapsed_ms)
      return
    end
    var total = size(self.frozen_pages)
    if total == 0
      self.paint_status(self.status_code, elapsed_ms)
      return
    end
    var index = int(elapsed_ms / self.page_ms)
    if index >= total index = total - 1 end
    var page = self.frozen_pages[index]
    var page_elapsed = elapsed_ms - index * self.page_ms
    self.paint_page(page, page_elapsed % 4000, index, total, self.page_health(page))
  end
end
