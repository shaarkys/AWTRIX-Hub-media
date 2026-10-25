class EventArtwork
  # Original pixel art. Compact mode is composed at 26 pixels, never squeezed.
  # The caller supplies elapsed time; MQTT and rotation stay in EventTrigger.
  var canvas_width, colors, clip_left

  def compact(labels)
    if type(labels) == "bool" return labels end
    return labels != nil && size(labels) > 0 && labels[0] != ""
  end

  def phase(elapsed_ms)
    var value = int(elapsed_ms) % 4000
    return value < 0 ? value + 4000 : value
  end

  def rf(x, y, width, height, color)
    # Clip sprite entrances/exits to the artwork viewport, including label mode.
    var right = min(self.canvas_width, x + width)
    var bottom = min(16, y + height)
    x = max(self.clip_left, x) y = max(0, y)
    if right > x && bottom > y rect_fill(x, y, right - x, bottom - y, color) end
  end

  def px(x, y, color)
    self.rf(x, y, 1, 1, color)
  end

  def ln(x, y, x2, y2, color)
    if x >= 0 && x < self.canvas_width && x2 >= 0 && x2 < self.canvas_width && y >= 0 && y < 16 && y2 >= 0 && y2 < 16
      line(x, y, x2, y2, color)
    end
  end

  def stamp(rows, x, y)
    # Equal-color horizontal runs avoid a native call per sprite pixel.
    for row : 0 .. size(rows) - 1
      var data = rows[row]
      var column = 0
      while column < size(data)
        var ink = data[column]
        var first = column
        while column < size(data) && data[column] == ink column += 1 end
        if ink != "." self.rf(x + first, y + row, column - first, 1, self.colors[ink]) end
      end
    end
  end

  def ease(t, start, finish, first, last)
    var span = finish - start
    var n = int(clamp(t - start, 0, span))
    return first + int((last - first) * n * (2 * span - n) / (span * span))
  end

  def sky()
    self.rf(0, 0, self.canvas_width, 5, 0x080C19)
    self.rf(0, 5, self.canvas_width, 7, 0x10192A)
    self.rf(0, 12, self.canvas_width, 4, 0x1A2733)
  end

  def sparkle(x, y, bright)
    self.px(x, y, bright ? 0xFFF1BD : 0x9A773E)
    if bright
      self.px(x - 1, y, 0xC99546) self.px(x + 1, y, 0xC99546)
      self.px(x, y - 1, 0xC99546) self.px(x, y + 1, 0xC99546)
    end
  end

  def house(x, y)
    self.stamp([
      "........r........", ".......rRr.......", "......rRRRr......",
      ".....rRRRRRr.....", "....rRRRRRRRr....", "...rRRRRRRRRRr...",
      "..rRRRRRRRRRRRr..", ".rrrrrrrrrrrrrrr.", "..hhhhhhhhhhhhh..",
      "..hYYhdddhYYhh..", "..hYyhdddhYyhh..", "..hhhhdddhhhhhh..",
      "..hhhhddDhhhhhh..", "..hhhhdddhhhhhh.."], x, y)
  end

  def walker(x, y, step)
    self.stamp(["..kkk..", "..kss..", "..sSs..", "...s...",
      "..tTt..", ".tTTTt.", ".stTTs.", "..tTt..", "..nnn.."], x, y)
    if step == 0
      self.stamp(["..n.n..", ".nn..n.", ".K...KK"], x, y + 9)
    elif step == 1
      self.stamp(["..nn...", "..n.n..", "..K.KK."], x, y + 9)
    elif step == 2
      self.stamp(["..n.n..", ".n..nn.", "KK...K."], x, y + 9)
    else
      self.stamp(["...nn..", "..n.n..", ".KK.K.."], x, y + 9)
    end
  end

  def motion(t)
    var w = self.canvas_width
    self.sky()
    self.house(w == 52 ? 1 : 7, 0)
    if w == 52
      self.house(35, 1)
      self.px(25, 0, 0xA8BBC2) self.px(27, 1, 0x638294)
      self.px(29, 3, 0x638294) self.px(32, 0, 0x638294)
      self.rf(19, 11, 14, 1, 0x31515A)
      for post : 0 .. 4 self.rf(20 + post * 3, 9, 1, 4, 0x436573) end
    end
    self.rf(0, 14, w, 2, 0x263E40)
    self.rf(0, 15, w, 1, 0x152B2E)
    var x = int(t * (w + 7) / 4000) - 7
    self.rf(x, 14, 9, 1, 0x0A121C)
    self.walker(x, 3, int(t / 140) % 4)
    # A camera LED and fading footsteps identify a detection without obscuring
    # the walker's face or attaching a floating symbol to its silhouette.
    var detected = t >= 800 && t < 3500
    self.rf(w - 5, 2, 4, 2, 0x8A9AA4)
    self.px(w - 5, 3, detected ? 0xFF7355 : 0x48525C)
    if detected
      self.rf(x - 3, 14, 2, 1, 0x71D1BB)
      self.rf(x - 7, 14, 2, 1, 0x427E76)
      self.rf(x - 11, 14, 2, 1, 0x2C5556)
    end
  end

  def envelope(x, y)
    self.stamp(["WWWWWWW", "WYwwwYW", "WwYYYwW", "WwwYwwW", "YYYYYYY"], x, y)
  end

  def mailbox(x, open_door, raised)
    self.stamp([
      "...aaaaaaabbbbb......", "..aAAAAAAAABBBbb.....", ".aAAAaaaaAABBBBbb....",
      "aAAAaAAAAaABBBBbbb...", "aAAAaAAAAaABBBBbbb...", "aAAAaAAAAaABBBBbbb...",
      "aAAAaaaaaaABBBBbbb...", ".aaaaaaaaaabbbbbb...."], x, 3)
    self.rf(x + 9, 11, 3, 4, 0x866A4C)
    self.rf(x + 9, 11, 1, 4, 0xC39A68)
    self.rf(x + 5, 15, 11, 1, 0x33454A)
    if open_door
      self.rf(x + 12, 6, 5, 4, 0x0A1820)
      self.rf(x + 16, 10, 5, 1, 0x8BD0CE)
      self.px(x + 20, 9, 0xD0E4D6)
    else
      self.rf(x + 13, 5, 3, 4, 0x2B7177)
      self.px(x + 15, 7, 0xB6E0D8)
    end
    self.rf(x + 10, raised ? 1 : 5, 1, raised ? 6 : 3, 0xDED1AC)
    self.rf(x + 11, raised ? 1 : 7, 4, 2, 0xD44F53)
    self.rf(x + 11, raised ? 1 : 7, 3, 1, 0xFF8F76)
  end

  def mail_background()
    self.sky()
    self.rf(0, 13, self.canvas_width, 3, 0x182D29)
    for blade : 0 .. int(self.canvas_width / 4) - 1 self.px(blade * 4 + 1, 13, 0x315244) end
    if self.canvas_width == 52
      self.rf(1, 10, 7, 1, 0x3B5353)
      self.rf(2, 8, 1, 5, 0x54716A) self.rf(6, 8, 1, 5, 0x54716A)
      self.px(43, 2, 0x45616F) self.px(48, 5, 0x45616F)
    end
  end

  def mail_received(t)
    self.mail_background()
    var bx = self.canvas_width == 52 ? 17 : 2
    self.mailbox(bx, t < 2700, t >= 2800)
    if t < 2700
      var ex = self.ease(t, 0, 2700, self.canvas_width + 1, bx + 5)
      # Arrival and collection both use the opening on the right. The leading
      # edge disappears behind its lip rather than through the metal side.
      self.clip_left = bx + 12
      self.envelope(ex, 6)
      self.clip_left = 0
    end
    if t >= 2800
      self.sparkle(bx - 3, 5, int(t / 250) % 2 == 0)
      self.sparkle(bx + 23, 3, int(t / 250) % 2 != 0)
    end
  end

  def mail_collected(t)
    self.mail_background()
    var bx = self.canvas_width == 52 ? 10 : 0
    self.mailbox(bx, t >= 400, t < 2000)
    if self.canvas_width == 52
      self.walker(43, 3, 1)
      self.rf(38, 8, 7, 1, 0xF5B38C)
    end
    var ex = self.ease(t, 500, 2600, bx + 12, self.canvas_width == 52 ? 37 : 22)
    if t >= 400 && t < 3100 self.envelope(ex, t > 2200 ? 5 : 6) end
    if t >= 2500 self.sparkle(bx + 6, 1, int(t / 250) % 2 == 0) end
  end

  def bell(x, y, lean)
    self.stamp([
      "......YY.......", ".....YWWY......", "....YOYYOY.....", "...YOYYYYOY....",
      "...YWYYYYOY....", "..YOWYYYYYOY...", "..YOWYYYYYOY...", "..YOWYYYYYOY...",
      ".YOYYYYYYYYOY..", "YWWWWWWWWWWWWY.", ".OOOOOOOOOOOO.."], x + lean, y)
    self.rf(x + 6 - lean, y + 11, 3, 1, 0xE69A37)
    self.px(x + 7 - lean, y + 12, 0xFFE7A0)
  end

  def doorbell(t)
    var w = self.canvas_width
    self.sky()
    if w == 52
      self.rf(1, 2, 12, 13, 0x735345)
      self.rf(3, 3, 8, 12, 0x2C313D)
      self.rf(4, 4, 6, 5, 0xD89850)
      self.rf(5, 5, 4, 3, 0xFFE0A0)
      self.rf(4, 10, 6, 4, 0x443D3B)
      self.px(9, 10, 0xE8C98D)
      self.rf(0, 1, 14, 1, 0xC18D62)
      self.rf(0, 15, 15, 1, 0x997455)
    end
    var bx = w == 52 ? 26 : 6
    var beat = int(t / 120) % 8
    var lean = (beat == 1 || beat == 2) ? 1 : ((beat == 5 || beat == 6) ? -1 : 0)
    self.rf(bx - 3, 14, 21, 1, 0x34342D)
    self.bell(bx, 1, lean)
    var ring = int(t / 160) % 5
    for arc : 0 .. 2
      if ring > arc
        var c = arc == 0 ? 0xFFE7A0 : (arc == 1 ? 0xE9B44D : 0x96703B)
        var left = bx - 2 - arc * 3
        var right = bx + 16 + arc * 3
        self.ln(left, 4, left - 1, 7, c) self.ln(left - 1, 7, left, 10, c)
        self.ln(right, 4, right + 1, 7, c) self.ln(right + 1, 7, right, 10, c)
      end
    end
  end

  def heat(t)
    var w = self.canvas_width
    self.rf(0, 0, w, 5, 0x190D1C)
    self.rf(0, 5, w, 6, 0x32151E)
    self.rf(0, 11, w, 5, 0x57221E)
    var x = w == 52 ? 8 : 0
    var sway = int(t / 140) % 4
    self.stamp(sway < 2 ? [
      "........o.........", ".......oY.........", ".......oYo........",
      "...o...oYYo.......", "..oYo.oYYYyo......", "..oYYooYYYyo..o...",
      ".oYYYYYYYYYYooYo..", ".oYYYYYYYYYYYYYYo.", "oYYYYYYYYYYYYYYYyo",
      "oYYYYYWYYYYYYYYYyo", "oyYYYWWWYYYYYYYyyo", ".oyYWWWWWYYYYYyyo.",
      "..oyWWWWWYYYYyyo..", "...oYYYYYYYYyyo..."] : [
      ".........o........", "........oYo.......", "...o....oYo.......",
      "...Yo..oYYo.......", "..oYYo.oYYYo......", "..oYYYooYYYYo.....",
      ".oYYYYYYYYYYYo.o..", ".oYYYYYYYYYYYYoYo.", "oYYYYYYYYYYYYYYYyo",
      "oYYYYYYYYYYYYYYYyo", "oyYYYYWWYYYYYYYyyo", ".oyYYWWWWYYYYYyyo.",
      "..oyWWWWWYYYYyyo..", "...oYYYYYYYYyyo..."], x, 0)
    self.rf(0, 14, w, 2, 0x8A3928)
    for ember : 0 .. int(w / 3) - 1
      self.px(ember * 3 + (int(t / 200) % 2), 14, ember % 2 == 0 ? 0xF5A346 : 0xC85C32)
    end
    if w == 52
      self.stamp(["..HHH..", ".HLLLH.", ".HLdLH.", ".HLdLH.", ".HLdLH.",
        ".HLdLH.", ".HLdLH.", ".HLdLH.", "HLdddLH", "HLdddLH", "HLdddLH", ".HLLLH.", "..HHH.."], 34, 1)
      var level = 3 + int(t / 250) % 5
      self.rf(37, 10 - level, 1, level + 1, 0xF96A55)
      self.rf(36, 10, 3, 2, 0xFF7857)
      self.px(36, 10, 0xFFD39A)
      self.rf(46, 3, 2, 5, 0xF96A55)
      self.rf(46, 10, 2, 2, int(t / 250) % 2 == 0 ? 0xFFF1BD : 0xA84538)
      self.rf(0, 0, 2, 2, 0xC95940) self.rf(50, 0, 2, 2, 0xC95940)
    end
    for ember : 0 .. 2
      var rise = (int(t / 120) + ember * 4) % 12
      self.px(x + 2 + ember * 6, 12 - rise, rise % 3 == 0 ? 0xFFD787 : 0xB95435)
    end
  end

  def droplet(x, y)
    self.stamp(["....c....", "...cCc...", "...cWCc..", "..cWCCCc.",
      ".cWWCCCcb", ".cWCCCCcb", "cWCCCCCCb", "cCCCCCCCb", ".cCCCCCbb", "..ccbbbb."], x, y)
  end

  def water(t)
    var w = self.canvas_width
    self.rf(0, 0, w, 5, 0x0A1520)
    self.rf(0, 5, w, 8, 0x102A36)
    self.rf(0, 13, w, 3, 0x174355)
    var pipe = w == 52 ? 3 : 0
    self.rf(pipe, 2, 19, 4, 0x666666)
    self.rf(pipe, 2, 19, 1, 0xB5B5B5)
    self.rf(pipe, 3, 19, 1, 0x929292)
    self.rf(pipe + 1, 1, 2, 6, 0xC1C1C1)
    self.rf(pipe + 12, 1, 2, 6, 0xC1C1C1)
    self.rf(pipe + 16, 4, 4, 4, 0x888888)
    self.rf(pipe + 17, 4, 1, 3, 0xD0D0D0)
    self.rf(pipe + 16, 7, 4, 1, 0x4EAFCA)
    var drop = int(t / 100) % 12
    if drop < 6
      self.px(pipe + 18, 8 + drop, 0xB3F5F5)
      self.px(pipe + 17, 7 + drop, 0x46ADC5)
    end
    if w == 52
      self.droplet(34, 2 + (int(t / 500) % 2))
      self.px(29, 5, 0x2E687C) self.px(46, 9, 0x2E687C)
    end
    var swell = int(t / 160) % 6
    for wave : 0 .. int(w / 8)
      var wx = wave * 8 + swell - 4
      self.rf(wx, 13, 5, 1, 0x3D9BB5)
      self.rf(wx + 2, 14, 4, 1, 0x79D4DD)
      self.rf(wx - 1, 15, 4, 1, 0x215E79)
    end
    if drop >= 6 && drop <= 9
      var radius = drop - 5
      self.px(pipe + 18 - radius, 12, 0xB3F5F5)
      self.px(pipe + 18 + radius, 12, 0xB3F5F5)
    end
  end

  def garage(t)
    var w = self.canvas_width
    var left = w == 52 ? 5 : 0
    var width = w == 52 ? 40 : 26
    self.sky()
    self.rf(left, 2, width, 13, 0x846B63)
    self.rf(left + 1, 3, width - 2, 12, 0xB59A80)
    self.rf(left + 3, 4, width - 6, 10, 0x151E2D)
    self.rf(left - 2, 0, width + 4, 2, 0x5A3440)
    self.rf(left - 1, 1, width + 2, 1, 0xAC7263)
    self.rf(left, 15, width, 1, 0x35434F)
    var cx = left + int(width / 2) - 9
    self.stamp(["....LLLLLLL......", "...LaCCCCCaL.....", "..LaCCCCCCCaL....",
      ".rrrrrrrrrrrrr...", "rYYYYrrrrYYYYrr..", "rWWWWrrrrWWWWrr..", ".krrrkkkkrrrk...."], cx, 8)
    var bottom = self.ease(t, 200, 2200, 14, 4)
    self.rf(left + 3, 4, width - 6, bottom - 3, 0x777C83)
    for row : 4 .. bottom
      if row % 3 == 1 self.rf(left + 3, row, width - 6, 1, 0xB8BEC2) end
      if row % 3 == 0 self.rf(left + 3, row, width - 6, 1, 0x4E5863) end
    end
    self.rf(left + 3, bottom, width - 6, 1, 0xCDD1CC)
    self.rf(left + int(width / 2) - 2, bottom, 4, 1, 0x414A55)
    if t > 1700
      self.rf(cx + 2, 15, 3, 1, 0x796A49) self.rf(cx + 10, 15, 3, 1, 0x796A49)
    end
    if w == 52
      var rise = int(t / 240) % 3
      self.ln(48, 8 - rise, 49, 7 - rise, 0x7BD4B6)
      self.ln(49, 7 - rise, 50, 8 - rise, 0x7BD4B6)
      self.rf(1, 5, 2, 2, 0xF3C079) self.rf(46, 5, 2, 2, 0xF3C079)
    end
  end

  def quiet(t)
    self.sky()
    var x = int(self.canvas_width / 2)
    self.rf(x - 5, 6, 11, 5, 0x263D4B)
    self.rf(x - 3, 4, 7, 1, 0x4C7880)
    self.rf(x - 1, 2, 3, 1, int(t / 500) % 2 == 0 ? 0x82C9B4 : 0x426C68)
    self.px(x, 8, 0x82C9B4)
  end

  def draw_labels(scene)
    var upper = ["MOVE", "NEW", "MAIL", "HEAT", "WATER", "DING", "OPEN"]
    var lower = ["FRONT", "MAIL", "PICKUP", "ALARM", "LEAK", "DONG", "GARAGE"]
    var ink = [0x82C9B4, 0xF6D28A, 0x82C9B4, 0xFF9670, 0x7BDAE3, 0xF6D28A, 0x82C9B4]
    text(28, 6, scene < 0 ? "IDLE" : upper[scene], scene < 0 ? 0x82C9B4 : ink[scene])
    text(28, 14, scene < 0 ? "READY" : lower[scene], 0xA6A6A6)
  end

  def paint(scene, elapsed_ms, labels)
    clear() font("small")
    self.canvas_width = self.compact(labels) ? 26 : 52
    self.clip_left = 0
    if self.colors == nil
      self.colors = {"r":0xA94E54, "R":0xCA6B62, "h":0xBEA186, "d":0x3C3944, "D":0xDBBA81,
        "Y":0xFFD16F, "y":0xE3973D, "W":0xFFF1C5, "w":0xE6CB91, "O":0xAA642E, "o":0xE86736,
        "k":0x172331, "K":0xD8B588, "s":0xD39B7A, "S":0xFFD2A1, "t":0x267A78, "T":0x7BD4B6,
        "n":0x38516C, "a":0x7DBDB7, "A":0x47999B, "b":0x26495C, "B":0x326A7A,
        "H":0x9E9E9E, "L":0xDBDBDB, "c":0x4CAEC5, "C":0x74D7E2}
    end
    var t = self.phase(elapsed_ms)
    if scene == 0 self.motion(t)
    elif scene == 1 self.mail_received(t)
    elif scene == 2 self.mail_collected(t)
    elif scene == 3 self.heat(t)
    elif scene == 4 self.water(t)
    elif scene == 5 self.doorbell(t)
    elif scene == 6 self.garage(t)
    else self.quiet(t)
    end
    if self.compact(labels) self.draw_labels(scene >= 0 && scene <= 6 ? scene : -1) end
  end
end
