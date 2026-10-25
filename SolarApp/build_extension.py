from pathlib import Path

ROOT = Path(__file__).resolve().parent
graphics = (ROOT / 'graphics.be.inc').read_text(encoding='utf-8')
original = (ROOT / 'SolarApp.original.ax').read_text(encoding='utf-8-sig')
sprites = original[original.index('    # Sonnenpartikel'):original.index('  def setup()')]
blend = original[original.index('  def blend_color'):original.index('  def draw()')]
sun = original[original.index('    var sun_list ='):original.index('    # ----------------------------------------------------\n    # 4.')]
panel = original[original.index('      # === YIELD-MODUS'):original.index('\n    else\n      # === CONSUMPTION-MODUS')]
panel = '\n'.join(line[2:] if line.startswith('  ') else line for line in panel.splitlines())

header = '''# @name    SolarApp
# @desc    MQTT solar/yield, FVE battery, house load and grid import/export with rotating views
# @version 4.3.1
# @display 52x16
# Local extension of SolarApp 4.3.1; original Hub identity intentionally omitted.
# Local build: source-aware house activity (2026-10-23).
# @config visual_style select "Visual Style" default=sun_large options=sun_large,sun_half
# @config topic_power text "Power MQTT Topic" default="inverter/total/P_AC" group="MQTT topics"
# @config topic_yield text "Daily Yield MQTT Topic" default="inverter/total/YieldDay" group="MQTT topics"
# @config topic_consumption text "Consumption MQTT Topic" default="house/total/power" group="MQTT topics"
# @config topic_battery_soc text "FVE Battery Capacity MQTT Topic (%)" default="" group="MQTT topics" help="Empty disables the battery view. State of charge, 0-100 percent."
# @config topic_battery_power text "FVE Battery Power MQTT Topic (W)" default="" group="MQTT topics" help="Optional signed charge/discharge power."
# @config topic_grid_power text "Grid Power MQTT Topic (W)" default="" group="MQTT topics" help="Signed net power: import and export. Empty disables the grid view."
# @config default_view select "Starting View" default=yield options=yield,consumption,battery,grid
# @config rotate_seconds number "Seconds per View" default=5 min=2 max=60
# @config max_power number "Max Solar Power (W)" default=800 min=100
# @config anim_speed number "Animation Speed (1-10)" default=4 min=1 max=10
# @config yield_unit select "Yield Display Unit" default=auto options=auto,kWh,Wh
# @config yield_input_unit select "MQTT Yield Input Unit" default=Wh options=Wh,kWh group="Input interpretation"
# @config grid_sign select "Grid Sign Convention" default=import_positive options=import_positive,export_positive group="Input interpretation"
# @config battery_sign select "Battery Sign Convention" default=charge_positive options=charge_positive,discharge_positive group="Input interpretation"
# @config solar_threshold number "Solar Production Threshold (W)" default=1 min=0 max=1000 group="Rotation" help="Show solar only when fresh production is above this value."
# @config grid_deadband number "Grid Idle Threshold (W)" default=10 min=0 max=1000 group="Rotation"
# @config battery_deadband number "Battery Idle Threshold (W)" default=10 min=0 max=1000 group="Rotation"
# @config data_timeout number "Live Data Timeout (seconds)" default=120 min=0 max=3600 group="Rotation" help="0 disables expiry. Yield has a separate timeout."
# @config yield_timeout number "Daily Yield Timeout (seconds)" default=3600 min=0 max=86400 group="Rotation" help="0 disables expiry. Prevents showing an old daily total indefinitely."
# @config show_solar bool "Show Solar View" default=true group="Rotation"
# @config show_battery bool "Show Battery View" default=true group="Rotation"
# @config show_house bool "Show House View" default=true group="Rotation"
# @config show_grid bool "Show Grid View" default=true group="Rotation"
# @config field_power text "Solar JSON Field" default="" group="Optional JSON fields" help="Top-level key; empty uses known aliases. Numeric MQTT payloads need no key."
# @config field_yield text "Yield JSON Field" default="" group="Optional JSON fields"
# @config field_consumption text "House JSON Field" default="" group="Optional JSON fields" help="Must be actual house load, not a signed net grid reading."
# @config field_battery_soc text "Battery Capacity JSON Field" default="" group="Optional JSON fields"
# @config field_battery_power text "Battery Power JSON Field" default="" group="Optional JSON fields"
# @config field_grid_power text "Grid Power JSON Field" default="" group="Optional JSON fields"

import math
import json

class SolarApp
  var cfg_style, cfg_max_power, cfg_speed, cfg_yield_unit
  var topics, fields, aliases, values, updated, bad_input, labels, last_source_status
  var enabled, view, view_started, rotate_ms, timeout_ms, yield_timeout_ms
  var solar_threshold, grid_deadband, battery_deadband
  var grid_multiplier, battery_multiplier, yield_multiplier
  var smooth_power, smooth_ratio, sun_rot, anim_phase
  var sun_large_pixels, sun_half_pixels, solar_particles

  def init()
    self.cfg_style = store.get("visual_style", "sun_large")
    self.cfg_max_power = max(100, num(store.get("max_power"), 800))
    self.cfg_speed = clamp(num(store.get("anim_speed"), 4), 1, 10)
    self.cfg_yield_unit = store.get("yield_unit", "auto")
    self.rotate_ms = int(clamp(num(store.get("rotate_seconds"), 5), 2, 60)) * 1000
    self.timeout_ms = int(clamp(num(store.get("data_timeout"), 120), 0, 3600)) * 1000
    self.yield_timeout_ms = int(clamp(num(store.get("yield_timeout"), 3600), 0, 86400)) * 1000
    self.solar_threshold = max(0, num(store.get("solar_threshold"), 1))
    self.grid_deadband = max(0, num(store.get("grid_deadband"), 10))
    self.battery_deadband = max(0, num(store.get("battery_deadband"), 10))
    self.grid_multiplier = store.get("grid_sign") == "export_positive" ? -1 : 1
    self.battery_multiplier = store.get("battery_sign") == "discharge_positive" ? -1 : 1
    self.yield_multiplier = store.get("yield_input_unit") == "kWh" ? 1000.0 : 1.0
    self.topics = [store.get("topic_power", "inverter/total/P_AC"),
                   store.get("topic_yield", "inverter/total/YieldDay"),
                   store.get("topic_consumption", "house/total/power"),
                   store.get("topic_battery_soc", ""),
                   store.get("topic_battery_power", ""),
                   store.get("topic_grid_power", "")]
    self.fields = [store.get("field_power", ""), store.get("field_yield", ""),
                   store.get("field_consumption", ""), store.get("field_battery_soc", ""),
                   store.get("field_battery_power", ""), store.get("field_grid_power", "")]
    self.aliases = [
      ["production", "Production", "P_AC", "power", "Power", "solar_power", "solar_production", "P_PV", "p_ac", "val", "value", "p", "P"],
      ["YieldDay", "yield", "Yield", "production", "Production", "daily_production", "today_production", "energy_today", "yield_day", "val", "value", "energy", "Energy", "y", "E_Day"],
      ["consumption", "Consumption", "house_power", "load", "Load", "P_Load", "p_load", "total_power", "act_power", "apower", "power", "Power", "val", "value", "p", "P"],
      ["soc", "SOC", "battery_soc", "battery_pct", "battery_percent", "capacity", "percentage", "val", "value"],
      ["battery_power", "battery_w", "P_Bat", "p_bat", "power", "Power", "val", "value"],
      ["grid_power", "grid_w", "P_Grid", "p_grid", "net_power", "power", "Power", "val", "value"]
    ]
    self.values = [nil, nil, nil, nil, nil, nil]
    self.labels = ["--", "--", "--", "--", "BAT", "--"]
    self.updated = [nil, nil, nil, nil, nil, nil]
    self.bad_input = [false, false, false, false, false, false]
    self.last_source_status = nil
    self.enabled = [store.get("show_solar", true), store.get("show_battery", true),
                    store.get("show_house", true), store.get("show_grid", true)]
    self.view = 0
    var first = store.get("default_view", "yield")
    if first == "battery" self.view = 1 end
    if first == "consumption" self.view = 2 end
    if first == "grid" self.view = 3 end
    self.view_started = now_ms()
    self.smooth_power = 0.0
    self.smooth_ratio = 0.0
    self.sun_rot = 0.0
    self.anim_phase = 0.0

'''

logic = '''  def setup()
    # One subscription per distinct filter; shared JSON topics feed all matching inputs.
    var subscribed = []
    for topic_filter : self.topics
      if size(topic_filter) == 0 continue end
      var found = false
      for existing : subscribed
        if existing == topic_filter found = true end
      end
      if !found
        self.subscribe_topic(topic_filter)
        subscribed.push(topic_filter)
      end
    end
  end

  def subscribe_topic(topic_filter)
    mqtt.subscribe(topic_filter, / topic, payload -> self.on_mqtt(topic_filter, payload))
  end

  def numeric(value)
    var kind = type(value)
    if kind != "int" && kind != "real" && kind != "string" return nil end
    var result = num(value)
    # Reject NaN, infinity and values too large for meaningful display arithmetic.
    if result == nil return nil end
    if !(result >= -1000000000.0 && result <= 1000000000.0) return nil end
    return real(result)
  end

  def read_value(body, index)
    if !isinstance(body, map) return self.numeric(body) end
    if size(self.fields[index]) > 0
      return self.numeric(body.find(self.fields[index]))
    end
    for key : self.aliases[index]
      var value = body.find(key)
      if value != nil return self.numeric(value) end
    end
    return nil
  end

  def on_mqtt(topic_filter, payload)
    var body = self.numeric(payload)
    if body == nil
      try
        body = json.load(payload)
      except ..
        body = nil
      end
    end
    for index : 0 .. 5
      if self.topics[index] != topic_filter continue end
      var value = self.read_value(body, index)
      if value != nil && index == 3
        if value < 0 || value > 100 value = nil end
      end
      if value == nil
        if !self.bad_input[index]
          log("SolarApp: invalid/missing numeric input " + str(index) + "; check MQTT field and units")
          self.bad_input[index] = true
        end
        continue
      end
      if self.bad_input[index]
        log("SolarApp: input " + str(index) + " recovered")
        self.bad_input[index] = false
      end
      if index <= 2 && value < 0 value = 0.0 end
      if index == 1 value *= self.yield_multiplier end
      if index == 4 value *= self.battery_multiplier end
      if index == 5 value *= self.grid_multiplier end
      self.values[index] = value
      self.updated[index] = now_ms()
    end
    self.refresh_labels()
  end

  def loop()
    # Forget expired values so an uptime-counter wrap cannot revive old readings.
    for index : 0 .. 5
      if self.values[index] != nil && !self.fresh(index)
        self.values[index] = nil
        self.updated[index] = nil
      end
    end
    self.refresh_labels()
  end

  def refresh_labels()
    # Build strings on input changes and in loop(), never at frame rate.
    for index : [0, 2, 5]
      self.labels[index] = self.fresh(index) ? self.power_label(self.values[index]) : "--"
    end
    self.labels[1] = self.yield_label()
    self.labels[3] = self.fresh(3) ? str(int(self.values[3] + 0.5)) + "%" : "--"
    self.labels[4] = size(self.topics[4]) == 0 ? "BAT" : "--"
    if self.fresh(4)
      var watt = self.values[4]
      self.labels[4] = "IDLE"
      if math.abs(watt) > self.battery_deadband
        self.labels[4] = (watt > 0 ? "+" : "-") + self.power_label(watt)
      end
    end
    self.report_source_status()
  end

  def age(stamp)
    # Safe across the signed 32-bit millisecond boundary for these short intervals.
    return (now_ms() - stamp) & 0x7FFFFFFF
  end

  def fresh(index)
    if self.values[index] == nil || self.updated[index] == nil return false end
    var limit = index == 1 ? self.yield_timeout_ms : self.timeout_ms
    return limit == 0 || self.age(self.updated[index]) <= limit
  end

  def eligible(page)
    if !self.enabled[page] return false end
    if page == 0
      return self.fresh(0) && self.values[0] > self.solar_threshold
    elif page == 1
      return self.fresh(3)
    elif page == 2
      return self.fresh(2)
    end
    return self.fresh(5)
  end

  def view_count()
    var count = 0
    for page : 0 .. 3
      if self.eligible(page) count += 1 end
    end
    return count
  end

  def next_view()
    for offset : 1 .. 4
      var page = (self.view + offset) % 4
      if self.eligible(page)
        self.view = page
        self.view_started = now_ms()
        return
      end
    end
    self.view_started = now_ms()
  end

  def on_show()
    self.view_started = now_ms()
    if !self.eligible(self.view) self.next_view() end
  end

  def duration()
    # Keep this app visible long enough to show one full cycle alongside other apps.
    return self.rotate_ms * max(1, self.view_count()) + 1000
  end

  def on_button(btn)
    if btn != "select" return false end
    self.next_view()
    return true
  end

  def power_label(value)
    var amount = math.abs(value)
    if amount < 1000 return str(int(amount + 0.5)) + "W" end
    if amount < 1000000 return format("%.1fkW", amount / 1000.0) end
    return format("%.1fMW", amount / 1000000.0)
  end

  def yield_label()
    if !self.fresh(1) return "--" end
    var wh = self.values[1]
    if self.cfg_yield_unit == "Wh" || (self.cfg_yield_unit == "auto" && wh < 1000)
      return format("%.0fWh", wh)
    end
    return format("%.1fkWh", wh / 1000.0)
  end

  def label(x, y, value, color, room)
    # Fit wide numbers in the text region instead of painting over the icons.
    if text_width(value) <= room
      text(x, y, value, color)
    else
      text(x, y, "OVR", color)
    end
  end

  def draw_battery(color)
    rect(1, 3, 12, 11, color)
    rect_fill(5, 1, 4, 2, color)
    var level = int(self.values[3] * 9.0 / 100.0 + 0.5)
    if level > 0 rect_fill(3, 13 - level, 8, level, color) end
    if self.fresh(4) && math.abs(self.values[4]) > self.battery_deadband
      # White arrow goes down into the battery when charging, up when discharging.
      var down = self.values[4] > 0
      var tip_y = down ? 11 : 5
      line(6, 5, 6, 11, 0xFFFFFF)
      pixel(5, down ? tip_y - 1 : tip_y + 1, 0xFFFFFF)
      pixel(7, down ? tip_y - 1 : tip_y + 1, 0xFFFFFF)
    end
  end

  def draw_house(color)
    line(0, 7, 7, 0, color)
    line(7, 0, 14, 7, color)
    rect(2, 7, 11, 8, color)
    rect_fill(6, 10, 3, 5, color)
    pixel(4, 9, 0xFFD54F)
    pixel(10, 9, 0xFFD54F)
  end

  def draw_grid(color, direction)
    line(7, 1, 2, 14, color)
    line(7, 1, 12, 14, color)
    line(2, 5, 12, 5, color)
    line(1, 8, 13, 8, color)
    line(4, 14, 10, 14, color)
    if direction != 0
      var tip = direction > 0 ? 13 : 1
      line(1, 11, 13, 11, 0xFFFFFF)
      pixel(tip - direction, 10, 0xFFFFFF)
      pixel(tip - direction, 12, 0xFFFFFF)
    end
  end

  def draw()
    clear()
    font("small")
    if !self.eligible(self.view)
      self.next_view()
    elif self.age(self.view_started) >= self.rotate_ms
      self.next_view()
    end
    if !self.eligible(self.view)
      text(1, 6, "NO DATA", 0x9E9E9E)
      text(1, 14, "MQTT", 0x607D8B)
      return
    end
    self.anim_phase += real(self.cfg_speed) * 0.05
    if self.view == 0
      self.draw_solar()
    elif self.view == 1
      var color = self.values[3] <= 20 ? 0xFF6548 : 0x39E5A7
      var direction = 0
      if self.fresh(4) && math.abs(self.values[4]) > self.battery_deadband
        direction = self.values[4] > 0 ? -1 : 1
      end
      self.draw_battery(color)
      self.draw_house(0x4FBAA8)
      if direction != 0 self.draw_energy(direction, color, self.values[4]) end
      self.label(17, 6, self.labels[3], color, 28)
      var detail = size(self.topics[4]) == 0 ? "BAT" : (self.fresh(4) ? self.labels[4] : "--")
      self.label(17, 14, detail, 0xB8D8D0, 28)
    elif self.view == 2
      var source_color = self.draw_source()
      self.draw_house(0x63BFA7)
      if source_color != 0 && self.values[2] > 0
        self.draw_energy(1, source_color, self.values[2])
      end
      self.label(17, 6, self.labels[2], 0xFFE3B0, 28)
      text(17, 14, "LOAD", 0x63BFA7)
    else
      var watt = self.values[5]
      var direction = math.abs(watt) <= self.grid_deadband ? 0 : (watt > 0 ? 1 : -1)
      var color = direction > 0 ? 0xFF9100 : (direction < 0 ? 0x00E676 : 0x90A4AE)
      self.draw_grid(color)
      self.draw_house(color)
      self.draw_energy(direction, color, watt)
      self.label(17, 6, self.labels[5], color, 28)
      text(17, 14, direction > 0 ? "IMPORT" : (direction < 0 ? "EXPORT" : "IDLE"), color)
    end
  end

  def draw_solar()
    var target = self.values[0]
    self.smooth_power += (target - self.smooth_power) * 0.15
    var target_ratio = clamp(self.smooth_power / real(self.cfg_max_power), 0.0, 1.0)
    self.smooth_ratio += (target_ratio - self.smooth_ratio) * 0.10
    var is_producing = true
    var speed_mult = real(self.cfg_speed) * 0.25
    self.sun_rot += (0.04 + 0.18 * self.smooth_ratio) * speed_mult
    var C_YELLOW = 0xFEC940
    var C_AMBER = 0xFFA10E
    var C_WARM_O = 0xFF8105
    var C_FIRE_O = 0xFF7502
    var C_DEEP_O = 0xEC4E03
    var C_LOBE_A = 0x9A3E07
'''

tail = '''
    var text_x = self.cfg_style == "sun_half" ? 15 : 17
    self.label(text_x, 6, self.labels[0], 0xFFC107, 47 - text_x)
    self.label(text_x, 14, self.fresh(1) ? self.labels[1] : "--", 0x00E676, 47 - text_x)
  end
end

return SolarApp()
'''

graphics_start = logic.index('  def draw_battery(')
graphics_end = logic.index('  def draw()\n', graphics_start)
logic = logic[:graphics_start] + graphics + logic[graphics_end:]
solar_start = logic.index('  def draw_solar()\n')
sun_constants = logic[logic.index('    var C_YELLOW =', solar_start):]
logic = logic[:solar_start] + '''  def draw_solar()
    self.advance_sun()
    var is_producing = true
    var speed_mult = real(self.cfg_speed) * 0.25
    self.draw_sun(true)
'''
sun_helper = '  def draw_sun(is_producing)\n' + sun_constants + sun + '  end\n\n'
script = header + sprites + logic + panel + tail
script = script.replace('  def draw_solar()\n', sun_helper + '  def draw_solar()\n')
script = script.replace('    self.win_flash = 1.0\n', '')
script = script.replace('  def draw_solar()\n', blend + '  def draw_solar()\n')
(ROOT / 'SolarApp.ax').write_text(script, encoding='utf-8', newline='\n')
for filename in ('SolarApp-TC002-Animated.ax', 'SolarApp-TC002-SourceAware.ax'):
    (ROOT / filename).write_text(script, encoding='utf-8', newline='\n')
print(f'SolarApp.ax: {len(script.encode())} bytes')
