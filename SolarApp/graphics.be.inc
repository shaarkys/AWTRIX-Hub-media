  def draw_energy(direction, color, watt)
    if direction == 0 return end
    var strength = clamp(math.abs(watt) / real(self.cfg_max_power), 0.0, 1.0)
    var travel = self.anim_phase * (1.3 + strength * 2.0)
    # Two quiet lanes between the text rows keep the readings unobscured.
    for packet : 0 .. 3
      var offset = (travel + packet * 7.1) % 28.0
      var head = direction > 0 ? 16.0 + offset : 44.0 - offset
      var y = packet % 2 == 0 ? 7 : 15
      for tail : 0 .. 3
        var x = int(head) - direction * tail
        if x >= 15 && x <= 44
          var glow = (4.0 - tail) / 4.0
          pixel(x, y, self.blend_color(0x000000, color, glow * glow * 0.75))
        end
      end
    end
  end

  def draw_battery(color)
    # Bevelled case, shaded glass and individually lit cells.
    rect_fill(4, 0, 7, 2, 0x263746)
    rect_fill(5, 0, 5, 1, 0xC4DBE2)
    rect_fill(1, 3, 13, 11, 0x13242E)
    rect_fill(2, 2, 11, 13, 0x375260)
    rect_fill(3, 3, 9, 11, 0x071A23)
    line(2, 3, 2, 13, 0x9FBFC8)
    line(3, 2, 11, 2, 0xCEE2E4)
    line(3, 14, 12, 14, 0x1A313C)
    line(13, 4, 13, 12, 0x0B141C)
    var fill = int(self.values[3] * 10.0 / 100.0 + 0.5)
    var direction = 0
    if self.fresh(4) && math.abs(self.values[4]) > self.battery_deadband
      direction = self.values[4] > 0 ? -1 : 1
    end
    for row : 0 .. 9
      var y = 13 - row
      for x : 4 .. 10
        var col = 0x102B34
        if row < fill
          var shine = 0.60 + 0.25 * math.sin(real(x - 3) * 0.5)
          if row == 2 || row == 5 || row == 8 shine *= 0.55 end
          if direction != 0
            var phase = real(row) * 0.8 + real(direction) * self.anim_phase * 2.0
            shine += max(0.0, math.sin(phase)) * 0.15
          end
          col = self.blend_color(0x000000, color, clamp(shine, 0.0, 1.0))
          if x == 4 col = self.blend_color(col, 0xD8FFF0, 0.22) end
        end
        pixel(x, y, col)
      end
    end
    pixel(3, 3, 0xECFAFA)
    pixel(3, 4, 0x759FA9)
    pixel(11, 13, self.blend_color(0x13242E, color, 0.20))
  end

  def draw_house(color)
    # Original right-edge house: chimney, sloping roof, shaded walls and warm windows.
    var roof_col = color
    var wall_col = self.blend_color(0x101A24, color, 0.13)
    var edge_col = self.blend_color(0x263238, color, 0.24)
    pixel(50, 1, 0x546E7A)
    pixel(50, 2, 0x455A64)
    for dy : 0 .. 4
      var py = 3 + dy
      var start_x = 49 - dy
      for px : start_x .. 51
        var is_top = px == start_x || py == 3
        pixel(px, py, is_top ? roof_col : self.blend_color(wall_col, roof_col, 0.35))
      end
    end
    for py : 8 .. 14
      for px : 46 .. 51
        pixel(px, py, px == 46 || py == 14 ? edge_col : wall_col)
      end
    end
    var pulse_top = 0.5 + 0.35 * math.sin(self.anim_phase * 2.8) + 0.15 * math.sin(self.anim_phase * 6.4 + 1.2)
    var pulse_bot = 0.5 + 0.35 * math.cos(self.anim_phase * 2.5 + 2.1)
    var top = self.blend_color(0xE67E08, 0xFFF0A0, pulse_top)
    var bot = self.blend_color(0xC66906, 0xFFD46D, pulse_bot)
    for x : 48 .. 49
      pixel(x, 8, top)
      pixel(x, 9, self.blend_color(top, 0xFFF8CF, 0.22))
      pixel(x, 11, bot)
      pixel(x, 12, self.blend_color(bot, 0xFFF1B2, 0.18))
    end
  end

  def draw_grid(color)
    # Filled steel pylon with a lit edge, dark lattice and glowing insulators.
    for y : 1 .. 14
      var spread = int(real(y - 1) * 0.36)
      for x : 7 - spread .. 7 + spread
        var edge = x == 7 - spread || x == 7 + spread
        var col = edge ? 0x91AAB7 : 0x1A2A39
        if !edge && (x + y) % 4 == 0 col = 0x425D6F end
        if edge && x <= 7 col = self.blend_color(col, color, 0.32) end
        pixel(x, y, col)
      end
    end
    line(2, 5, 12, 5, 0x7E9EAB)
    line(0, 8, 14, 8, 0x506C7C)
    line(2, 15, 12, 15, 0x273B48)
    var pulse = 0.60 + 0.40 * math.sin(self.anim_phase * 1.5)
    var live = self.blend_color(0x102C3E, color, pulse)
    for index : 0 .. 3
      var x = index < 2 ? 1 + index * 3 : 4 + index * 3
      pixel(x, 9, live)
      pixel(x, 10, self.blend_color(live, 0xECF8FF, 0.45))
    end
  end

  def source_mode()
    # Choose a measured active source without treating solar-minus-load as grid power.
    if self.fresh(0) && self.values[0] > self.solar_threshold
      return 1
    elif self.fresh(3) && self.fresh(4) && self.values[4] < -self.battery_deadband
      return 2
    elif self.fresh(5) && self.values[5] > self.grid_deadband
      return 3
    end
    return 0
  end

  def report_source_status()
    if !self.fresh(2) || self.values[2] <= 0 return end
    var mode = self.source_mode()
    var solar_state = self.fresh(0) ? "zero/below threshold" : "missing or expired"
    var status = str(mode) + (mode == 0 ? solar_state : "")
    if status == self.last_source_status return end
    self.last_source_status = status
    if mode == 0
      log("SolarApp: house load active; source unknown; solar " + solar_state + "; no measured battery discharge or grid import")
    elif mode == 1
      log("SolarApp: house illustration using measured solar production")
    elif mode == 2
      log("SolarApp: house illustration using measured battery discharge")
    else
      log("SolarApp: house illustration using measured grid import")
    end
  end

  def draw_load_activity()
    # A generic electricity symbol represents known load when its source is unknown.
    var active = self.values[2] > 0
    var pulse = active ? 0.55 + 0.45 * math.sin(self.anim_phase * 1.4) : 0.0
    for y : 1 .. 14
      for x : 0 .. 14
        var dx = real(x - 7) / 7.0
        var dy = real(y - 8) / 7.0
        var halo = max(0.0, 1.0 - dx * dx - dy * dy)
        pixel(x, y, self.blend_color(0x000000, 0x164859, halo * (0.25 + pulse * 0.35)))
      end
    end
    var glow = self.blend_color(0x486573, 0xFFE3A0, active ? 0.70 + pulse * 0.30 : 0.0)
    for y : 1 .. 7
      var start = 8 - int(real(y - 1) * 0.7)
      var finish = 11 - int(real(y - 1) * 0.45)
      rect_fill(start, y, finish - start + 1, 1, glow)
      pixel(finish, y, self.blend_color(glow, 0x9E671C, active ? 0.3 : 0.0))
    end
    for y : 8 .. 14
      var start = 8 - int(real(y - 8) * 0.5)
      var finish = 12 - (y - 8)
      rect_fill(start, y, finish - start + 1, 1, glow)
      pixel(finish, y, self.blend_color(glow, 0x9E671C, active ? 0.3 : 0.0))
    end
    line(8, 1, 4, 7, active ? 0xFFF4CE : 0x76909B)
    if active
      # Non-directional sparks convey activity, without asserting a source or flow.
      var orbit = self.anim_phase * 0.8
      pixel(int(7.0 + 6.0 * math.cos(orbit)), int(8.0 + 6.0 * math.sin(orbit)), 0x7DD8DF)
      pixel(int(7.0 - 6.0 * math.cos(orbit)), int(8.0 - 6.0 * math.sin(orbit)), 0x397A8A)
    end
  end

  def draw_source()
    var mode = self.source_mode()
    if mode == 1
      self.advance_sun()
      self.draw_sun(true)
      return 0xE68D26
    elif mode == 2
      self.draw_battery(0x31D4A0)
      return 0x31D4A0
    elif mode == 3
      self.draw_grid(0xFFA236)
      return 0xFFA236
    end
    self.draw_load_activity()
    return 0
  end

  def advance_sun()
    self.smooth_power += (self.values[0] - self.smooth_power) * 0.15
    var ratio = clamp(self.smooth_power / real(self.cfg_max_power), 0.0, 1.0)
    self.smooth_ratio += (ratio - self.smooth_ratio) * 0.10
    self.sun_rot += (0.04 + 0.18 * self.smooth_ratio) * real(self.cfg_speed) * 0.25
  end

