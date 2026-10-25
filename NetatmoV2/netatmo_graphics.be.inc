# Original procedural Netatmo artwork for the TC002 52x16 panel.
#
# The renderer deliberately has no knowledge of OAuth, polling, rotation or
# clock time.  The core gives it a frozen page, an elapsed value for the
# deterministic four-second animation loop, and a health state.
class NetatmoArtwork
  var bg, bg_mid, bg_floor, steel, steel_hi, teal, teal_hi, warm, amber, red
  var palette_ready, current_health
  var upper_map, translit_map, glyphs

  def init_palette()
    # Lazily initialized so the artwork is also usable in the standalone
    # Berry harness, where a derived core may not call a superclass init.
    self.bg = 0x080D19
    self.bg_mid = 0x101C2A
    self.bg_floor = 0x1A2B35
    self.steel = 0x304A57
    self.steel_hi = 0x89B8BA
    self.teal = 0x55BDB4
    self.teal_hi = 0xC8F4DD
    self.warm = 0xE29A4A
    self.amber = 0xFFC56E
    self.red = 0xFF806D
    self.upper_map = {"a":"A", "b":"B", "c":"C", "d":"D", "e":"E", "f":"F", "g":"G",
      "h":"H", "i":"I", "j":"J", "k":"K", "l":"L", "m":"M", "n":"N",
      "o":"O", "p":"P", "q":"Q", "r":"R", "s":"S", "t":"T", "u":"U",
      "v":"V", "w":"W", "x":"X", "y":"Y", "z":"Z"}
    # Common station-room characters are transliterated before byte-wise
    # fallback. Unknown UTF-8 runs are collapsed to one '?' below, so a
    # multibyte name can never leak broken continuation glyphs into a caption.
    self.translit_map = {"ä":"A", "ö":"O", "ü":"U", "Ä":"A", "Ö":"O", "Ü":"U",
      "ß":"S", "á":"A", "à":"A", "â":"A", "é":"E", "è":"E", "ê":"E",
      "í":"I", "ì":"I", "î":"I", "ó":"O", "ò":"O", "ô":"O", "ú":"U",
      "ù":"U", "û":"U", "č":"C", "ď":"D", "ě":"E", "ň":"N", "ř":"R",
      "š":"S", "ť":"T", "ů":"U", "ž":"Z", "Č":"C", "Ď":"D", "Ě":"E",
      "Ň":"N", "Ř":"R", "Š":"S", "Ť":"T", "Ů":"U", "Ž":"Z", "ç":"C",
      "ñ":"N", "ø":"O", "å":"A"}
    self.glyphs = {
      "A":["010", "101", "111", "101", "101"], "B":["110", "101", "110", "101", "110"],
      "C":["011", "100", "100", "100", "011"], "D":["110", "101", "101", "101", "110"],
      "E":["111", "100", "110", "100", "111"], "F":["111", "100", "110", "100", "100"],
      "G":["011", "100", "101", "101", "011"], "H":["101", "101", "111", "101", "101"],
      "I":["111", "010", "010", "010", "111"], "J":["001", "001", "001", "101", "010"],
      "K":["101", "101", "110", "101", "101"], "L":["100", "100", "100", "100", "111"],
      "M":["101", "111", "111", "101", "101"], "N":["101", "111", "111", "111", "101"],
      "O":["010", "101", "101", "101", "010"], "P":["110", "101", "110", "100", "100"],
      "Q":["010", "101", "101", "011", "001"], "R":["110", "101", "110", "101", "101"],
      "S":["011", "100", "010", "001", "110"], "T":["111", "010", "010", "010", "010"],
      "U":["101", "101", "101", "101", "111"], "V":["101", "101", "101", "101", "010"],
      "W":["101", "101", "101", "111", "010"], "X":["101", "101", "010", "101", "101"],
      "Y":["101", "101", "010", "010", "010"], "Z":["111", "001", "010", "100", "111"],
      "0":["111", "101", "101", "101", "111"], "1":["010", "110", "010", "010", "111"],
      "2":["110", "001", "010", "100", "111"], "3":["110", "001", "010", "001", "110"],
      "4":["101", "101", "111", "001", "001"], "5":["111", "100", "110", "001", "110"],
      "6":["011", "100", "110", "101", "010"], "7":["111", "001", "010", "010", "010"],
      "8":["010", "101", "010", "101", "010"], "9":["010", "101", "011", "001", "110"],
      "-":["000", "000", "111", "000", "000"], "_":["000", "000", "000", "000", "111"],
      "?":["110", "001", "010", "000", "010"], " ":["000", "000", "000", "000", "000"]
    }
    self.palette_ready = true
  end

  def phase(elapsed_ms)
    if type(elapsed_ms) != "int" && type(elapsed_ms) != "real" return 0 end
    var value = int(elapsed_ms) % 4000
    return value < 0 ? value + 4000 : value
  end

  def rf(x, y, width, height, color)
    # Clipping keeps partial animation frames and malformed page values inside
    # the physical panel without asking the native renderer to clip for us.
    var left = max(0, x)
    var top = max(0, y)
    var right = min(52, x + width)
    var bottom = min(16, y + height)
    if right > left && bottom > top
      rect_fill(left, top, right - left, bottom - top, color)
    end
  end

  def px(x, y, color)
    if x >= 0 && x < 52 && y >= 0 && y < 16 pixel(x, y, color) end
  end

  def ln(x, y, x2, y2, color)
    if x >= 0 && x < 52 && x2 >= 0 && x2 < 52 && y >= 0 && y < 16 && y2 >= 0 && y2 < 16
      line(x, y, x2, y2, color)
    end
  end

  def is_numeric(value)
    if type(value) != "int" && type(value) != "real" return false end
    # NaN is the only Berry numeric value that is not equal to itself.  The
    # broad finite guard also prevents an infinity from reaching format().
    if value != value || value > 1000000000000000000000000000000.0 || value < -1000000000000000000000000000000.0 return false end
    return true
  end

  def value(page, key)
    if !isinstance(page, map) return nil end
    var values = page.find("values", nil)
    if !isinstance(values, map) return nil end
    var candidate = values.find(key, nil)
    return self.is_numeric(candidate) ? candidate : nil
  end

  def page_string(page, key, fallback)
    if !isinstance(page, map) return fallback end
    var result = page.find(key, fallback)
    return type(result) == "string" ? result : fallback
  end

  def stale(health)
    return health == "stale" || health == 1
  end

  def expired(health)
    return health == "expired" || health == 2
  end

  def lowercase_char(ch)
    return self.upper_map.find(ch, ch)
  end

  def safe_name(raw)
    if !self.palette_ready self.init_palette() end
    if type(raw) != "string" return "ROOM" end
    var result = ""
    var used = 0
    var index = 0
    while index < size(raw) && used < 5
      var ch = nil
      if index + 1 < size(raw) ch = self.translit_map.find(raw[index .. index + 1], nil) end
      if ch != nil
        index += 2
      else
        ch = self.translit_map.find(raw[index .. index], nil)
        index += 1
      end
      if ch == nil ch = self.lowercase_char(ch == nil ? raw[index - 1 .. index - 1] : ch) end
      var safe = false
      if (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9")
        safe = true
      elif ch == " " || ch == "-" || ch == "_"
        safe = true
      else
        # Unknown UTF-8 bytes and punctuation become a visible but safe glyph;
        # no source name can escape the five-character caption.
        ch = "?"
        safe = true
      end
      if safe
        result += ch
        used += 1
      end
      # If the byte was not ASCII/transliterated, skip the remainder of this
      # UTF-8 run so invalid continuation bytes do not become repeated '?'.
      if ch == "?"
        while index < size(raw)
          var next = raw[index .. index]
          var pair = index + 1 < size(raw) ? raw[index .. index + 1] : ""
          if self.translit_map.find(pair, nil) != nil || self.translit_map.find(next, nil) != nil break end
          if (next >= "A" && next <= "Z") || (next >= "a" && next <= "z") || (next >= "0" && next <= "9") || next == " " || next == "-" || next == "_" break end
          index += 1
        end
      end
    end
    return size(result) > 0 ? result : "ROOM"
  end

  def glyph(ch)
    return self.glyphs.find(ch, self.glyphs.find("?"))
  end

  def micro(ch, x, y, color)
    var rows = self.glyph(ch)
    for row : 0 .. size(rows) - 1
      var data = rows[row]
      var column = 0
      while column < size(data)
        if data[column .. column] == "1"
          var first = column
          while column < size(data) && data[column .. column] == "1" column += 1 end
          self.rf(x + first, y + row, column - first, 1, color)
        else
          column += 1
        end
      end
    end
  end

  def name_caption(page, color)
    self.rf(0, 10, 19, 6, 0x0C1822)
    var caption = self.safe_name(isinstance(page, map) ? page.find("name", "ROOM") : "ROOM")
    for index : 0 .. size(caption) - 1
      if index >= 5 break end
      self.micro(caption[index .. index], index * 4, 11, color)
    end
  end

  def backplate()
    self.rf(0, 0, 52, 4, self.bg)
    self.rf(0, 4, 52, 6, self.bg_mid)
    self.rf(0, 10, 52, 6, self.bg_floor)
    self.rf(18, 0, 34, 7, 0x0B1823)
    self.rf(18, 8, 34, 8, 0x0D202A)
    self.rf(17, 0, 1, 16, 0x2B4650)
    self.rf(19, 0, 1, 16, 0x07131E)
    self.rf(18, 7, 34, 1, 0x17313A)
  end

  def page_markers(index, total, color)
    var count = 1
    if self.is_numeric(total) count = max(1, min(24, int(total))) end
    var selected = 0
    if self.is_numeric(index) selected = clamp(int(index), 0, count - 1) end
    # The bottom row is unused by the two metric baselines.  A 32px track
    # preserves the exact relative position for all 1..24 page turns instead
    # of collapsing larger page lists into four dots over the first metric.
    self.rf(20, 15, 32, 1, 0x294650)
    var marker = 20
    if count > 1 marker = 20 + int(selected * 31.0 / (count - 1) + 0.5) end
    self.rf(marker, 15, 1, 1, color)
  end

  def battery(page)
    if !isinstance(page, map) return end
    var amount = page.find("battery", nil)
    if !self.is_numeric(amount) return end
    amount = clamp(amount, 0, 100)
    self.rf(14, 1, 3, 3, 0x263F4A)
    self.rf(17, 2, 1, 1, 0x56717A)
    var fill = int(amount / 34.0 + 0.5)
    if fill > 0 self.rf(14, 1 + (3 - fill), 1, fill, amount < 20 ? self.red : self.teal) end
    self.px(16, 1, 0x84A5A7)
  end

  def stale_marker(health)
    if self.stale(health)
      self.rf(16, 0, 2, 2, self.amber)
      self.px(16, 2, 0xA16B35)
    end
  end

  def safe_temp(value, celsius)
    if !self.is_numeric(value) return nil end
    return celsius ? value : (value * 9.0 / 5.0 + 32.0)
  end

  def number(value, decimals)
    if !self.is_numeric(value) return "--" end
    # Preserve every finite value: once a value cannot fit the lane, emit an
    # explicit overflow marker rather than silently replacing it with a made-
    # up bound such as 999.  The core/page data is never changed.
    var limit = decimals == 0 ? 9999.0 : 999.0
    if value > limit return "HI" end
    if value < -limit return "-HI" end
    var bounded = value
    var negative = bounded < 0
    var magnitude = negative ? -bounded : bounded
    if decimals == 0
      return (negative ? "-" : "") + str(int(magnitude + 0.5))
    end
    var scaled = int(magnitude * 10.0 + 0.5)
    var whole = int(scaled / 10)
    var fraction = scaled % 10
    return (negative ? "-" : "") + str(whole) + "." + str(fraction)
  end

  def int_number(value)
    return self.number(value, 0)
  end

  def compact_decimal(value)
    if !self.is_numeric(value) return "--" end
    # Two metric rows have a strict 32px lane.  Values at or above three
    # digits use an integer; smaller values retain one decimal place.
    # A negative sign costs four pixels; use an integer earlier on that side
    # so the wind row remains inside its 32px lane even around -10.0.  Beyond
    # the compact range, HI is an explicit overflow state, never a clamp.
    if value >= 1000 return "HI" end
    if value <= -999 return "-HI" end
    if value >= 99 || value <= -10
      return self.int_number(value)
    end
    return self.number(value, 1)
  end

  def compact_integer(value)
    if !self.is_numeric(value) return "--" end
    if value > 999 return "HI" end
    if value < -999 return "-HI" end
    return self.int_number(value)
  end

  def day_total(value)
    # Keep the normal one-decimal dashboard precision.  The day badge is
    # drawn in the illustration, leaving the right row for value + mm.
    return self.compact_decimal(value)
  end

  def wind_decimal(value, wide)
    if !self.is_numeric(value) return "--" end
    # W is the widest prefix (6px). Keep its signed three-digit boundary
    # explicit so W...KPH remains inside 32px; G has two spare pixels.
    if wide && value < -99 return "-HI" end
    if wide && value >= 999.5 return "HI" end
    return self.compact_decimal(value)
  end

  def wind_integer(value)
    if !self.is_numeric(value) return "--" end
    if value > 999 return "HI" end
    if value < -99 return "-HI" end
    return self.int_number(value)
  end

  def direction_degrees(value)
    if !self.is_numeric(value) return "--" end
    if value > 999 return "HI" end
    if value < -999 return "-HI" end
    return self.int_number(value)
  end

  def metric(page, health, key, fallback)
    var result = self.value(page, key)
    if self.expired(health) return fallback end
    return result != nil ? result : nil
  end

  def temp_label(page, health, key, unit)
    var value = self.metric(page, health, key, nil)
    if value == nil return "T--" + unit end
    var celsius = true
    if isinstance(page, map) celsius = page.find("celsius", true) != false end
    return "T" + self.number(self.safe_temp(value, celsius), 1) + unit
  end

  def humidity_label(page, health)
    var value = self.metric(page, health, "Humidity", nil)
    return value == nil ? "H--%" : "H" + self.number(value, 0) + "%"
  end

  def co2_color(page, value, base)
    if value == nil return base end
    var low = 800
    var high = 1500
    if isinstance(page, map)
      var candidate = page.find("co2_low", 800)
      if self.is_numeric(candidate) low = candidate end
      candidate = page.find("co2_high", 1500)
      if self.is_numeric(candidate) high = candidate end
    end
    if value >= high return self.red end
    if value >= low return self.amber end
    return base
  end

  def text_metric(y, value, color)
    # All strings assembled by the page methods are <=32 pixels at the native
    # font's actual advances and start after the one-pixel gutter.
    text(20, y, value, color)
  end

  def draw_climate(page, health, unit, primary)
    var temperature = self.metric(page, health, "Temperature", nil)
    var humidity = self.metric(page, health, "Humidity", nil)
    var t = temperature == nil ? "T--" + unit : self.temp_label(page, health, "Temperature", unit)
    var h = humidity == nil ? "H--%" : self.humidity_label(page, health)
    self.text_metric(6, t, primary)
    self.text_metric(14, h, self.stale(health) ? self.amber : self.teal_hi)
  end

  def draw_air(page, health, primary, elapsed_ms)
    var co2 = self.metric(page, health, "CO2", nil)
    var pressure = self.metric(page, health, "Pressure", nil)
    var noise = self.metric(page, health, "Noise", nil)
    if co2 != nil
      self.text_metric(6, "CO2 " + self.int_number(co2), self.co2_color(page, co2, primary))
      if pressure != nil && noise != nil
        var alternate = int(self.phase(elapsed_ms) / 1200) % 2 == 0
        self.text_metric(14, alternate ? self.int_number(pressure) + "hPa" : self.int_number(noise) + "dB", self.stale(health) ? self.amber : self.teal)
      elif pressure != nil
        self.text_metric(14, self.int_number(pressure) + "hPa", self.stale(health) ? self.amber : self.teal)
      elif noise != nil
        self.text_metric(14, self.int_number(noise) + "dB", self.stale(health) ? self.amber : self.teal)
      else
        # Additional indoor modules normally have CO2 without pressure/noise.
        # Show its unit and a relative CO2 indicator, not a missing-data alert.
        self.text_metric(14, "ppm", self.stale(health) ? self.amber : self.steel_hi)
        var level = int(clamp((co2 - 400) * 5 / 1600, 0, 5))
        for bar : 0 .. 4
          self.rf(35 + bar * 3, 13 - bar, 2, bar + 1, bar < level ? self.co2_color(page, co2, primary) : 0x294650)
        end
      end
    elif pressure != nil && noise != nil
      # Without CO2, pressure and noise get their own stable readable rows;
      # only the CO2-present secondary row alternates above.
      self.text_metric(6, self.int_number(pressure) + "hPa", primary)
      self.text_metric(14, self.int_number(noise) + "dB", self.stale(health) ? self.amber : self.teal)
    elif pressure != nil
      self.text_metric(6, self.int_number(pressure) + "hPa", primary)
      self.text_metric(14, "NO CO2", self.stale(health) ? self.amber : self.steel_hi)
    elif noise != nil
      self.text_metric(6, self.int_number(noise) + "dB", primary)
      self.text_metric(14, "NO CO2", self.stale(health) ? self.amber : self.steel_hi)
    else
      self.text_metric(6, "AIR --", self.stale(health) ? self.amber : self.steel_hi)
      self.text_metric(14, "NO DATA", self.stale(health) ? self.amber : self.steel_hi)
    end
  end

  def draw_range(page, health, unit)
    var low = self.metric(page, health, "min_temp", nil)
    var high = self.metric(page, health, "max_temp", nil)
    var celsius = true
    if isinstance(page, map) celsius = page.find("celsius", true) != false end
    var low_display = low == nil ? nil : self.safe_temp(low, celsius)
    var high_display = high == nil ? nil : self.safe_temp(high, celsius)
    var lo_number = low_display == nil ? "--" : self.compact_decimal(low_display)
    var hi_number = high_display == nil ? "--" : self.compact_decimal(high_display)
    var lo = "LO" + lo_number + unit
    var hi = "HI" + hi_number + unit
    self.text_metric(6, lo, self.stale(health) ? self.amber : self.warm)
    self.text_metric(14, hi, self.stale(health) ? self.amber : self.teal_hi)
  end

  def draw_rain(page, health, day)
    var latest = self.metric(page, health, "Rain", nil)
    var hour = self.metric(page, health, "sum_rain_1", nil)
    var total = self.metric(page, health, "sum_rain_24", nil)
    var color = self.stale(health) ? self.amber : self.teal_hi
    if day
      self.text_metric(6, total == nil ? "24H--" : self.day_total(total) + "mm", color)
      self.text_metric(14, latest == nil ? (hour == nil ? "RAIN--" : "1H" + self.compact_decimal(hour) + "mm") : "R" + self.compact_decimal(latest) + "mm", self.stale(health) ? self.amber : self.teal)
    else
      self.text_metric(6, latest == nil ? "RAIN--" : "R" + self.compact_decimal(latest) + "mm", color)
      self.text_metric(14, hour == nil ? (total == nil ? "1H--" : "24" + self.day_total(total) + "mm") : "1H" + self.compact_decimal(hour) + "mm", self.stale(health) ? self.amber : self.teal)
    end
  end

  def rain_day_badge()
    # A compact 24H badge keeps the unit/context clear without stealing the
    # metric lane's width from a normal decimal total such as 12.5mm.
    # Keep the badge left of the battery overlay at x=14..17.
    self.rf(1, 0, 13, 6, 0x102B36)
    self.rf(1, 0, 13, 1, 0x668F91)
    self.rf(1, 5, 13, 1, 0x294B54)
    self.micro("2", 2, 1, self.amber)
    self.micro("4", 6, 1, self.amber)
    self.micro("H", 10, 1, self.amber)
  end

  def draw_wind(page, health, direction)
    var speed = self.metric(page, health, "WindStrength", nil)
    var gust = self.metric(page, health, "GustStrength", nil)
    var angle = self.metric(page, health, "WindAngle", nil)
    var gust_angle = self.metric(page, health, "GustAngle", nil)
    var maximum = self.metric(page, health, "max_wind_str", nil)
    var color = self.stale(health) ? self.amber : self.teal_hi
    if direction
      if angle != nil
        self.text_metric(6, "D" + self.direction_degrees(angle) + "DEG", color)
      elif gust_angle != nil
        self.text_metric(6, "G" + self.direction_degrees(gust_angle) + "DEG", color)
      else
        self.text_metric(6, "DIR--", color)
      end
      if maximum != nil
        self.text_metric(14, "M" + self.wind_integer(maximum) + "KPH", self.stale(health) ? self.amber : self.warm)
      elif gust != nil
        self.text_metric(14, "G" + self.wind_integer(gust) + "KPH", self.stale(health) ? self.amber : self.teal)
      else
        self.text_metric(14, "GUST--", self.stale(health) ? self.amber : self.teal)
      end
    else
      # KPH is the explicit kilometers-per-hour unit; row prefixes identify
      # mean wind (W) and gust (G) without relying on a history-derived label.
      self.text_metric(6, speed == nil ? "WIND--" : "W" + self.wind_decimal(speed, true) + "KPH", color)
      self.text_metric(14, gust == nil ? "GUST--" : "G" + self.wind_decimal(gust, false) + "KPH", self.stale(health) ? self.amber : self.teal)
    end
  end

  def room_scene(elapsed_ms, kind, view, active)
    var pulse = int(self.phase(elapsed_ms) / 500) % 2
    self.rf(0, 0, 18, 10, kind == "outdoor" ? 0x0A1C2B : 0x111F2B)
    self.rf(0, 8, 18, 2, kind == "outdoor" ? 0x183A39 : 0x2A3040)
    if kind == "outdoor"
      self.rf(1, 5, 5, 4, 0x244E4A)
      self.rf(3, 3, 1, 6, 0x39756A)
      self.rf(2, 2, 3, 3, 0x3E907F)
      self.rf(1, 3, 5, 2, 0x2B706B)
      self.px(2, 3, 0x9BD6B2) self.px(4, 2, 0x75C8A3)
      self.rf(10, 1, 6, 1, 0x27445A)
      self.rf(12, 0, 2, 5, 0x5E8C93)
      self.rf(13, 1, 1, 3, 0xDBA25A)
      self.rf(13, 5, 2, 1, 0x304D56)
      self.px(14, pulse == 0 ? 4 : 3, self.warm)
    else
      # A shaded room and warm window provide a shared domestic setting; the
      # kind-specific couch/tower overlays below identify the module.
      self.rf(1, 1, 7, 5, 0x1A3A47)
      self.rf(2, 2, 5, 3, pulse == 0 ? 0x397A83 : 0x4B9AA0)
      self.rf(1, 1, 7, 1, 0x688E90)
      self.rf(4, 1, 1, 5, 0x3B5961)
      self.rf(2, 5, 5, 1, 0x203642)
      self.rf(9, 6, 6, 3, 0x6B4E41)
      self.rf(10, 5, 4, 1, 0xBD7A4F)
      self.rf(10, 7, 4, 2, 0xA36C47)
      self.rf(11, 4, 2, 2, 0x5B8C6D)
      self.px(11, 3, 0x8BC79A)
      self.rf(2, 8, 14, 1, 0x45616A)
      self.rf(3, 9, 12, 1, 0x1C2A31)
      if kind == "extra"
        # Extra indoor modules get a recognizable couch silhouette instead of
        # reusing the main station's tower scene.
        self.rf(1, 6, 2, 4, 0x6B4E41)
        self.rf(14, 6, 2, 4, 0x6B4E41)
        self.rf(2, 5, 13, 3, 0xA36C47)
        self.rf(3, 5, 11, 1, 0xC18A54)
        self.rf(3, 8, 11, 1, 0x704A3B)
        self.rf(4, 9, 2, 1, 0x3A3C3D)
        self.rf(12, 9, 2, 1, 0x3A3C3D)
        self.rf(5, 6, 1, 2, pulse == 0 ? 0xB9774D : 0x8F5D43)
        self.rf(10, 6, 1, 2, pulse == 0 ? 0xB9774D : 0x8F5D43)
      else
        # Main indoor station: a narrow Netatmo tower beside the warm room.
        self.rf(13, 2, 3, 5, 0x45616A)
        self.rf(14, 1, 1, 1, 0xB7D4CE)
        self.rf(14, 3, 1, 2, pulse == 0 ? 0x6DBDB4 : 0x3F7777)
        self.rf(13, 6, 3, 1, active ? self.teal : 0x4A666A)
      end
    end
    if active
      self.px(16, 7 + pulse, self.warm)
    else
      self.px(16, 7, 0x4C6C70)
    end
  end

  def rain_scene(elapsed_ms, active)
    self.rf(0, 0, 18, 10, 0x0B1D2B)
    self.rf(0, 8, 18, 2, 0x16404B)
    self.rf(2, 3, 13, 4, 0x4A6971)
    self.rf(4, 2, 8, 1, 0x67888C)
    self.rf(1, 5, 4, 2, 0x5E7B80)
    self.rf(13, 5, 3, 2, 0x385760)
    self.px(4, 3, 0xC3D9D2)
    if active
      var phase = int(self.phase(elapsed_ms) / 250)
      for drop : 0 .. 2
        var x = 4 + drop * 5
        var y = 7 + ((phase + drop * 3) % 3)
        self.px(x, y, self.teal_hi)
        if y < 9 self.px(x, y + 1, self.teal) end
      end
      self.rf(7, 9, 4, 1, 0x6CC1B7)
    else
      self.px(15, 1, self.warm)
      self.px(14, 1, 0xB26C32)
      self.px(15, 2, 0xB26C32)
      self.rf(5, 9, 7, 1, 0x547A73)
    end
  end

  def wind_scene(elapsed_ms, active, angle)
    self.rf(0, 0, 18, 10, 0x0A1B2A)
    self.rf(0, 8, 18, 2, 0x1B3A3B)
    self.rf(8, 4, 2, 6, 0x7B8D86)
    self.rf(6, 9, 7, 1, 0x40615D)
    self.rf(4, 3, 4, 1, 0xC5A764)
    self.rf(3, 4, 6, 1, 0x9A8458)
    self.rf(4, 5, 4, 1, 0x6B5B42)
    var turn = int(self.phase(elapsed_ms) / 400) % 4
    if !active turn = 0 end
    var base = angle == nil ? 0 : int(clamp(angle, -360.0, 360.0) / 45.0)
    var spoke = (base + turn) % 4
    if spoke == 0
      self.ln(9, 3, 14, 3, self.teal_hi) self.ln(9, 3, 7, 1, self.teal)
      self.ln(9, 3, 11, 6, self.teal)
    elif spoke == 1
      self.ln(9, 3, 13, 7, self.teal_hi) self.ln(9, 3, 13, 2, self.teal)
      self.ln(9, 3, 6, 4, self.teal)
    elif spoke == 2
      self.ln(9, 3, 9, 8, self.teal_hi) self.ln(9, 3, 5, 5, self.teal)
      self.ln(9, 3, 13, 5, self.teal)
    else
      self.ln(9, 3, 5, 7, self.teal_hi) self.ln(9, 3, 6, 2, self.teal)
      self.ln(9, 3, 12, 4, self.teal)
    end
    self.px(9, 3, active ? self.warm : 0x70898A)
  end

  def offline_scene(elapsed_ms)
    self.rf(0, 0, 18, 10, 0x0D1722)
    self.rf(2, 2, 13, 6, 0x283C49)
    self.rf(3, 3, 11, 4, 0x0C1A27)
    self.rf(4, 4, 8, 1, 0x41636A)
    self.rf(4, 6, 5, 1, 0x41636A)
    self.rf(13, 3, 1, 4, 0x6C8788)
    self.px(6, 5, self.red)
    self.px(8, 5, int(self.phase(elapsed_ms) / 400) % 2 == 0 ? self.amber : 0x76493D)
    self.rf(2, 9, 13, 1, 0x354E54)
  end

  def page_active(page, view)
    var current = 0
    if view == "rain" || view == "rain_day"
      var rain = self.value(page, "Rain")
      # Rain is the latest reported amount, not a rate. Historical one-hour
      # and daily totals do not prove that it is raining right now.
      if rain != nil && rain > current current = rain end
    elif view == "wind" || view == "wind_dir"
      var wind = self.value(page, "WindStrength")
      var gust = self.value(page, "GustStrength")
      if wind != nil && wind > current current = wind end
      if gust != nil && gust > current current = gust end
    end
    # Negative dashboard readings remain visible as data, but cannot claim
    # active precipitation/wind; only a positive measured magnitude animates
    # the corresponding illustration.
    return current != nil && current > 0
  end

  def draw_page_scene(page, elapsed_ms, kind, view)
    if self.expired(self.current_health)
      self.offline_scene(elapsed_ms)
      return
    end
    var active = self.page_active(page, view)
    if kind == "rain"
      self.rain_scene(elapsed_ms, active)
    elif kind == "wind"
      self.wind_scene(elapsed_ms, active, self.value(page, "WindAngle"))
    elif kind == "outdoor"
      self.room_scene(elapsed_ms, kind, view, active)
    else
      self.room_scene(elapsed_ms, kind, view, active)
    end
  end

  def paint_page(page, elapsed_ms, index, total, health)
    if !self.palette_ready self.init_palette() end
    self.current_health = health
    clear()
    font("small")
    self.backplate()
    var kind = self.page_string(page, "kind", "indoor")
    var view = self.page_string(page, "view", "offline")
    var caption_color = self.stale(health) ? self.amber : self.teal_hi
    var no_data = self.expired(health) || view == "offline"
    if no_data
      self.offline_scene(elapsed_ms)
      self.name_caption(page, self.red)
      self.text_metric(6, "NO DATA", self.red)
      self.text_metric(14, "OFFLINE", self.red)
    else
      self.draw_page_scene(page, elapsed_ms, kind, view)
      if kind == "rain" && view == "rain_day" self.rain_day_badge() end
      self.name_caption(page, caption_color)
      var unit = "C"
      if isinstance(page, map) && page.find("celsius", true) == false unit = "F" end
      var primary = self.stale(health) ? self.amber : self.teal_hi
      if view == "climate"
        self.draw_climate(page, health, unit, primary)
      elif view == "air"
        self.draw_air(page, health, primary, elapsed_ms)
      elif view == "range"
        self.draw_range(page, health, unit)
      elif view == "rain"
        self.draw_rain(page, health, false)
      elif view == "rain_day"
        self.draw_rain(page, health, true)
      elif view == "wind"
        self.draw_wind(page, health, false)
      elif view == "wind_dir"
        self.draw_wind(page, health, true)
      else
        self.text_metric(6, "DATA", primary)
        self.text_metric(14, "NO VIEW", primary)
      end
    end
    self.page_markers(index, total, no_data ? self.red : (self.stale(health) ? self.amber : self.teal))
    if !no_data self.battery(page) end
    self.stale_marker(health)
  end

  def status_key(code)
    if type(code) != "string" return "wait" end
    # Core status codes are lower-case contract values.  Accept the common
    # upper-case spellings without importing a module into this class-only
    # artwork include.
    var key = code
    if key == "SIGNIN" || key == "SIGN_IN" || key == "SIGN-IN" key = "signin" end
    if key == "LOADING" key = "loading" end
    if key == "NO_MODULES" || key == "NOMODULES" key = "no_modules" end
    if key == "DISABLED" key = "disabled" end
    if key == "NETWORK" key = "network" end
    if key == "AUTH" key = "auth" end
    if key == "PARSE" key = "parse" end
    if key == "signin" || key == "sign_in" || key == "sign-in" return "signin" end
    if key == "loading" return "loading" end
    if key == "no_modules" || key == "nomodules" return "no_modules" end
    if key == "disabled" return "disabled" end
    if key == "network" return "network" end
    if key == "auth" return "auth" end
    if key == "parse" return "parse" end
    return "wait"
  end

  def status_scene(key, elapsed_ms)
    if key == "signin"
      self.room_scene(elapsed_ms, "indoor", "climate", false)
      self.rf(10, 3, 5, 4, 0x1A2836)
      self.rf(11, 4, 3, 2, 0x81B8B2)
      self.rf(12, 5, 1, 1, self.amber)
    elif key == "loading"
      self.room_scene(elapsed_ms, "outdoor", "climate", false)
      var phase = int(self.phase(elapsed_ms) / 300) % 4
      self.rf(10 + phase, 4, 3, 1, self.teal)
      self.rf(10, 6, 3, 1, phase == 0 ? self.teal_hi : 0x3F7375)
    elif key == "no_modules"
      self.offline_scene(elapsed_ms)
      self.rf(6, 4, 6, 1, self.amber)
    elif key == "disabled"
      self.offline_scene(elapsed_ms)
      self.rf(5, 4, 8, 1, self.red)
      self.rf(8, 2, 1, 5, self.red)
    elif key == "network"
      self.wind_scene(elapsed_ms, true, nil)
      self.rf(3, 2, 2, 1, self.amber)
      self.rf(1, 4, 3, 1, self.amber)
    elif key == "auth"
      self.room_scene(elapsed_ms, "indoor", "air", false)
      self.rf(5, 2, 8, 1, self.red)
      self.rf(5, 7, 8, 1, self.red)
      self.rf(8, 2, 1, 6, self.red)
    elif key == "parse"
      self.offline_scene(elapsed_ms)
      self.rf(4, 3, 9, 1, self.red)
      self.rf(4, 6, 5, 1, self.amber)
    else
      self.offline_scene(elapsed_ms)
    end
  end

  def paint_status(code, elapsed_ms)
    if !self.palette_ready self.init_palette() end
    clear()
    font("small")
    var key = self.status_key(code)
    self.backplate()
    self.status_scene(key, elapsed_ms)
    var top = "DATA"
    var bottom = "WAIT"
    if key == "signin"
      top = "SIGN IN" bottom = "NETATMO"
    elif key == "loading"
      top = "LOADING" bottom = "SYNC..."
    elif key == "no_modules"
      top = "NO MODS" bottom = "STATION"
    elif key == "disabled"
      top = "DISABLED" bottom = "MODS OFF"
    elif key == "network"
      top = "NETWORK" bottom = "RETRYING"
    elif key == "auth"
      top = "AUTH" bottom = "SIGN IN"
    elif key == "parse"
      top = "BAD JSON" bottom = "RETRY"
    end
    var color = key == "auth" || key == "parse" ? self.red : self.teal_hi
    self.text_metric(6, top, color)
    self.text_metric(14, bottom, key == "loading" ? self.teal : self.amber)
    self.page_markers(0, 1, color)
  end
end
