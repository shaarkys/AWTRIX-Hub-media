import json

var drawing = []
var labels_seen = []
var checks = 0

def max(a, b) return a > b ? a : b end
def min(a, b) return a < b ? a : b end
def clamp(v, a, b) return max(a, min(v, b)) end

def clear()
  drawing = []
  labels_seen = []
end

def font(name)
  assert(name == "small", "artwork must use the documented small font")
end

var advances = {" ":2, "!":2, "'":2, "(":3, ")":3, ",":3, ".":2, ":":2, ";":3,
  "I":2, "M":6, "N":5, "Q":5, "W":6, "`":3, "i":2, "|":2}

def text_width(value)
  # Complete source-notices/awtrix-small.bdf ASCII advance map; all other
  # printable glyphs use the documented four-pixel default.
  var width = 0
  for index : 0 .. size(value) - 1
    width += advances.find(value[index .. index], 4)
  end
  return width
end

def text(x, y, value, color)
  assert(x >= 0 && x + text_width(value) <= 52, "label text clipped")
  assert(y == 6 || y == 14, "label baseline outside contract")
  labels_seen.push(value)
  drawing.push(["text", x, y, value, color])
end

def pixel(x, y, color)
  assert(x >= 0 && x < 52 && y >= 0 && y < 16, "pixel outside panel")
  drawing.push(["pixel", x, y, color])
end

def line(x, y, x2, y2, color)
  assert(x >= 0 && x < 52 && x2 >= 0 && x2 < 52, "line x outside panel")
  assert(y >= 0 && y < 16 && y2 >= 0 && y2 < 16, "line y outside panel")
  drawing.push(["line", x, y, x2, y2, color])
end

def rect_fill(x, y, width, height, color)
  assert(width > 0 && height > 0, "non-positive rectangle")
  assert(x >= 0 && y >= 0 && x + width <= 52 && y + height <= 16, "rectangle outside panel")
  drawing.push(["fill", x, y, width, height, color])
end

def check(condition, message)
  assert(condition, message)
  checks += 1
end

var source_file = open("EventTrigger/event_graphics.be.inc", "r")
var artwork_source = source_file.read()
var artwork = compile(artwork_source + "\nreturn EventArtwork()")()
source_file.close()

var names = ["MOVE", "NEW", "MAIL", "HEAT", "WATER", "DING", "OPEN", "DISH", "COOK", "WASH", "DRY"]
var lower = ["FRONT", "MAIL", "PICKUP", "ALARM", "LEAK", "DONG", "GARAGE", "DONE", "DONE", "DONE", "DONE"]
for scene : -1 .. 10
  artwork.paint(scene, 0, false)
  check(size(drawing) > 0, "scene has no drawing: " + str(scene))
  var first = json.dump(drawing)
  artwork.paint(scene, 500, false)
  check(json.dump(drawing) != first, "scene does not animate from elapsed time: " + str(scene))
end

for scene : -1 .. 10
  for tick : 0 .. 15
    artwork.paint(scene, tick * 250, false)
    check(size(drawing) > 0, "phase frame has no drawing: " + str(scene) + ":" + str(tick))
  end
end

for scene : 0 .. 10
  for tick : 0 .. 15
    artwork.paint(scene, tick * 250, true)
    check(size(drawing) > 0, "compact phase frame has no drawing: " + str(scene) + ":" + str(tick))
  end
end

artwork.paint(0, -1, false)
check(size(drawing) > 0, "negative elapsed time wraps to a valid phase")

for scene : 0 .. 10
  artwork.paint(scene, 1000, true)
  check(size(labels_seen) == 2, "labels should draw exactly two fixed rows")
  check(labels_seen[0] == names[scene], "unexpected upper label")
  check(labels_seen[1] == lower[scene], "unexpected lower label")
end

for scene : 7 .. 10
  artwork.paint(scene, 1000, false)
  var frame = json.dump(drawing)
  artwork.paint(scene, 3500, false)
  check(json.dump(drawing) != frame, "completion scene animation is static: " + str(scene))
end

# The completed contents settle after the opening/unloading action. Suppress
# decorative glints so a moving rack, food or towel cannot pass as a rest pose.
var settled = compile(artwork_source + "\nclass SettledArtwork : EventArtwork\n  def sparkle(x, y, bright) end\nend\nreturn SettledArtwork()")()
for compact : [false, true]
  for scene : 7 .. 10
    settled.paint(scene, 3000, compact)
    var rest_frame = json.dump(drawing)
    settled.paint(scene, 3500, compact)
    check(json.dump(drawing) == rest_frame, "finished contents must hold still: " + str(scene))
    settled.paint(scene, 0, compact)
    check(json.dump(drawing) != rest_frame, "completion needs an opening action before its rest pose: " + str(scene))
  end
end

var completion_frames = []
for scene : 7 .. 10
  artwork.paint(scene, 1000, false)
  completion_frames.push(json.dump(drawing))
end
for first : 0 .. 2
  for second : first + 1 .. 3
    check(completion_frames[first] != completion_frames[second],
      "completion scenes are not visually distinct: " + str(first + 7) + "/" + str(second + 7))
  end
end

for scene : 7 .. 10
  artwork.paint(scene, 1000, true)
  check(size(labels_seen) == 2, "completion labels should draw exactly two fixed rows")
  check(labels_seen[0] == names[scene], "unexpected completion upper label")
  check(labels_seen[1] == lower[scene], "unexpected completion lower label")
end

artwork.paint(1000, 0, ["MOVE", "EVENT"])
check(size(labels_seen) == 2, "nonempty label pair should enable compact mode")
artwork.paint(1000, 0, ["", ""])
check(size(labels_seen) == 0, "empty label pair should keep full-width mode")

# Check every 25ms phase, including eased sprite entrances/exits. Compact art
# must not bleed into the two-pixel gutter or the label column.
var peak_calls = 0
for compact : [false, true]
  for scene : 0 .. 10
    for tick : 0 .. 159
      artwork.paint(scene, tick * 25, compact)
      assert(artwork.clip_left == 0, "temporary mailbox mask leaked into another frame")
      peak_calls = max(peak_calls, size(drawing))
      if compact
        for call : drawing
          if call[0] == "fill"
            assert(call[1] + call[3] <= 26, "sprite bleeds into label gutter")
          elif call[0] == "line"
            assert(call[1] < 26 && call[3] < 26, "line bleeds into label gutter")
          end
        end
      end
    end
    check(true, "complete phase sweep: " + str(scene))
    artwork.paint(scene, 875, compact)
    var loop_start = json.dump(drawing)
    artwork.paint(scene, 4875, compact)
    check(json.dump(drawing) == loop_start, "four-second loop must be deterministic")
  end
end
check(peak_calls < 512, "sprite run batching regressed")
print("Peak native draw calls per frame: " + str(peak_calls))

print("PASS: EventArtwork bounds, eleven scenes, quiet frame, completion artwork, elapsed animation and labels (" + str(checks) + " checks)")
