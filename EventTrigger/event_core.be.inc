# @name    Event trigger
# @desc    MQTT event-triggered animated scenes for the TC002 display
# @version 1.0.0
# @display 52x16
# @config topic text "MQTT topic filter" default="homey/events/+" group="MQTT"
# @config event_mode select "Event mode" default=auto options=auto,motion,mail_received,mail_collected,heat,water,doorbell,garage group="Matching"
# @config trigger_mode select "Trigger mode" default=pulse options=pulse,edge group="Matching"
# @config payload_field text "Activity JSON field" default="" group="Matching" help="Empty uses value or active."
# @config match_mode select "Value matching" default=boolean options=boolean,exact,any group="Matching"
# @config active_value text "Exact active value" default="true" group="Matching"
# @config inactive_value text "Exact inactive value" default="false" group="Matching"
# @config display_seconds number "Display seconds" default=8 min=2 max=30 group="Display"
# @config alarm_seconds number "Alarm display seconds" default=12 min=2 max=60 group="Display"
# @config cooldown_seconds number "Per-event cooldown seconds" default=3 min=0 max=60 group="Input limits"
# @config queue_seconds number "Pending event lifetime seconds" default=30 min=5 max=300 group="Input limits"
# @config show_labels bool "Show event labels" default=false group="Display"
# @config wake_display bool "Wake display for events" default=false group="Display" help="Calls display.power(true) only when an event starts."

import json
import string

class EventTrigger : EventArtwork
  var topic, event_mode, trigger_mode, payload_field, match_mode
  var active_value, inactive_value
  var display_ms, alarm_ms, cooldown_ms, queue_ms
  var show_labels, wake_display
  var names
  var pending, edge_active, last_accepted, failed, rejection_logged
  var recent_ids, sequence
  var current_scene, current_started, current_priority, current_duration_ms
  var request_scene, show_requested, cancelled_request, shown, manual_idle
  var idle_started

  def init()
    self.names = ["motion", "mail_received", "mail_collected", "heat", "water", "doorbell", "garage"]
    self.topic = store.get("topic", "homey/events/+")
    if type(self.topic) != "string" self.topic = "homey/events/+" end
    self.event_mode = string.tolower(str(store.get("event_mode", "auto")))
    if self.event_mode != "auto" && self.scene_index(self.event_mode) < 0
      self.event_mode = "auto"
    end
    self.trigger_mode = string.tolower(str(store.get("trigger_mode", "pulse")))
    if self.trigger_mode != "edge" self.trigger_mode = "pulse" end
    self.payload_field = store.get("payload_field", "")
    if type(self.payload_field) != "string" self.payload_field = "" end
    self.match_mode = string.tolower(str(store.get("match_mode", "boolean")))
    if self.match_mode != "exact" && self.match_mode != "any" self.match_mode = "boolean" end
    self.active_value = self.clean_setting(store.get("active_value", "true"), "true")
    self.inactive_value = self.clean_setting(store.get("inactive_value", "false"), "false")
    self.display_ms = int(clamp(num(store.get("display_seconds"), 8), 2, 30)) * 1000
    self.alarm_ms = int(clamp(num(store.get("alarm_seconds"), 12), 2, 60)) * 1000
    self.cooldown_ms = int(clamp(num(store.get("cooldown_seconds"), 3), 0, 60)) * 1000
    self.queue_ms = int(clamp(num(store.get("queue_seconds"), 30), 5, 300)) * 1000
    self.show_labels = store.get("show_labels", false) == true
    self.wake_display = store.get("wake_display", false) == true

    self.pending = [nil, nil, nil, nil, nil, nil, nil]
    self.edge_active = [false, false, false, false, false, false, false]
    self.last_accepted = [nil, nil, nil, nil, nil, nil, nil]
    self.failed = [false, false, false, false, false, false, false]
    self.rejection_logged = [false, false, false, false, false, false, false]
    self.recent_ids = []
    self.sequence = 0
    self.current_scene = -1
    self.current_started = nil
    self.current_priority = 0
    self.current_duration_ms = self.display_ms
    self.request_scene = -1
    self.show_requested = false
    self.cancelled_request = false
    self.shown = false
    self.manual_idle = false
    self.idle_started = now_ms()
  end

  def setup()
    if self.topic == ""
      log("EventTrigger: empty MQTT topic filter; input disabled")
      return
    end
    mqtt.subscribe(self.topic, / topic, payload -> self.receive(topic, payload))
  end

  def clean_setting(value, fallback)
    if type(value) != "string" return fallback end
    var result = self.trim(value)
    return size(result) > 0 ? result : fallback
  end

  def trim(value)
    if type(value) != "string" return "" end
    var first = 0
    var last = size(value) - 1
    while first <= last && (value[first] == " " || value[first] == "\n" || value[first] == "\r" || value[first] == "\t")
      first += 1
    end
    while last >= first && (value[last] == " " || value[last] == "\n" || value[last] == "\r" || value[last] == "\t")
      last -= 1
    end
    return first > last ? "" : value[first .. last]
  end

  def scene_index(value)
    if type(value) != "string" return -1 end
    var candidate = string.tolower(self.trim(value))
    for index : 0 .. size(self.names) - 1
      if candidate == self.names[index] return index end
    end
    return -1
  end

  def topic_scene(topic)
    if type(topic) != "string" || size(topic) == 0 return -1 end
    var slash = -1
    for index : 0 .. size(topic) - 1
      if topic[index] == "/" slash = index end
    end
    if slash < 0 || slash >= size(topic) - 1 return -1 end
    return self.scene_index(topic[slash + 1 .. size(topic) - 1])
  end

  def has_key(body, key)
    if !isinstance(body, map) return false end
    for existing : body.keys()
      if existing == key return true end
    end
    return false
  end

  def parse_payload(payload)
    if type(payload) == "string"
      if size(payload) > 512 return nil end
      var raw = self.trim(payload)
      if raw == "" return nil end
      if raw == "null" return nil end
      var parsed = nil
      try
        parsed = json.load(raw)
      except ..
        parsed = nil
      end
      if parsed != nil return parsed end
      try
        # JSON false and zero are valid parsed scalars, while Berry's JSON
        # helper may answer nil for a plain unquoted MQTT string.
        parsed = json.load(raw)
        if type(parsed) == "bool" || type(parsed) == "int" || type(parsed) == "real"
          return parsed
        end
      except ..
        parsed = nil
      end
      if parsed == nil
        # Plain MQTT scalar strings are useful for boolean and event-name flows.
        # JSON-shaped input that failed to parse remains invalid, rather than being
        # silently interpreted as an event.
        if raw[0] == "{" || raw[0] == "[" || raw[0] == "\"" || raw[0] == "'"
          return nil
        end
        return raw
      end
      return parsed
    end
    if type(payload) == "bool" || type(payload) == "int" || type(payload) == "real"
      return payload
    end
    if isinstance(payload, map) return payload end
    return nil
  end

  def boolean_state(value)
    if type(value) == "bool" return value ? 1 : 0 end
    if type(value) == "int" || type(value) == "real"
      if value == 1 return 1 end
      if value == 0 return 0 end
      return -1
    end
    if type(value) != "string" return -1 end
    var candidate = string.tolower(self.trim(value))
    if candidate == "true" || candidate == "1" || candidate == "yes" || candidate == "on" || candidate == "✓" || candidate == "✔" || candidate == "✅"
      return 1
    end
    if candidate == "false" || candidate == "0" || candidate == "no" || candidate == "off" || candidate == "x" || candidate == "×" || candidate == "✕" || candidate == "✖" || candidate == "✗" || candidate == "✘" || candidate == "❌"
      return 0
    end
    return -1
  end

  def text_value(value)
    if type(value) == "string" return self.trim(value) end
    if type(value) == "bool" return value ? "true" : "false" end
    if type(value) == "int" || type(value) == "real" return str(value) end
    return nil
  end

  def exact_state(value)
    var candidate = self.text_value(value)
    if candidate == nil || candidate == "" return -1 end
    candidate = string.tolower(candidate)
    var active = string.tolower(self.trim(self.active_value))
    var inactive = string.tolower(self.trim(self.inactive_value))
    if candidate == active return 1 end
    if candidate == inactive return 0 end
    return -1
  end

  def any_state(value, present)
    if !present return 1 end
    if type(value) == "string" && self.trim(value) == "" return -1 end
    if value == nil || isinstance(value, map) || isinstance(value, list) return -1 end
    var bool_state = self.boolean_state(value)
    if bool_state == 0 return 0 end
    if bool_state == 1 return 1 end
    return 1
  end

  def matched_state(value, present)
    if self.match_mode == "any" return self.any_state(value, present) end
    if !present return -1 end
    if self.match_mode == "exact" return self.exact_state(value) end
    return self.boolean_state(value)
  end

  def parse_event(topic, payload)
    var body = self.parse_payload(payload)
    if body == nil return nil end
    if isinstance(body, list) return nil end
    if isinstance(body, map) && size(body) == 0 && self.match_mode == "any" return nil end

    var explicit_scene = -1
    var explicit_event = false
    if isinstance(body, map) && self.has_key(body, "event")
      explicit_event = true
      var event_value = body.find("event")
      if type(event_value) != "string" return nil end
      explicit_scene = self.scene_index(event_value)
      # An invalid explicit event is never guessed from the topic.
      if explicit_scene < 0 return nil end
    end

    var scene = -1
    if self.event_mode == "auto"
      scene = explicit_scene >= 0 ? explicit_scene : self.topic_scene(topic)
    else
      scene = self.scene_index(self.event_mode)
    end

    # A bare canonical event name is a pulse in auto mode, independent of the
    # configured boolean matcher. It is intentionally not a scene guess for
    # arbitrary values or unknown topics.
    if self.event_mode == "auto" && !explicit_event && type(body) == "string" && size(self.payload_field) == 0
      var bare_scene = self.scene_index(body)
      if bare_scene >= 0
        return {"scene": bare_scene, "state": 1, "id": nil}
      end
    end
    if scene < 0 return nil end

    var present = true
    var activity = body
    if isinstance(body, map)
      present = false
      if size(self.payload_field) > 0
        if self.has_key(body, self.payload_field)
          present = true
          activity = body.find(self.payload_field)
        end
      elif self.has_key(body, "active")
        present = true
        activity = body.find("active")
      elif self.has_key(body, "value")
        present = true
        activity = body.find("value")
      end
    elif size(self.payload_field) > 0
      present = false
    end

    if size(self.payload_field) > 0 && !present return nil end
    var state = self.matched_state(activity, present)
    if state < 0 return nil end

    var event_id = nil
    if state == 1 && isinstance(body, map) && self.has_key(body, "id")
      event_id = body.find("id")
      if type(event_id) != "string" || size(event_id) > 64 return nil end
      if size(event_id) == 0 event_id = nil end
    end
    return {"scene": scene, "state": state, "id": event_id}
  end

  def elapsed(stamp)
    if stamp == nil return 0 end
    return (now_ms() - stamp) & 0x7FFFFFFF
  end

  def id_key(scene, event_id)
    return str(scene) + "/" + event_id
  end

  def id_seen(scene, event_id)
    if event_id == nil return false end
    var key = self.id_key(scene, event_id)
    for recent : self.recent_ids
      if recent == key return true end
    end
    return false
  end

  def remember_id(scene, event_id)
    if event_id == nil return end
    if size(self.recent_ids) >= 16 self.recent_ids.remove(0) end
    self.recent_ids.push(self.id_key(scene, event_id))
  end

  def priority(scene)
    if scene == 3 || scene == 4 return 3 end
    if scene == 5 return 2 end
    return 1
  end

  def expire()
    for scene : 0 .. 6
      var item = self.pending[scene]
      if item != nil && self.elapsed(item.find("stamp")) >= self.queue_ms
        self.pending[scene] = nil
        if self.request_scene == scene
          self.request_scene = -1
          self.show_requested = false
          self.cancelled_request = true
        end
      end
    end
    # A deferred rotation request must not hold an expired event forever.
    if self.request_scene >= 0 && self.pending[self.request_scene] == nil
      self.request_scene = -1
      self.show_requested = false
      self.cancelled_request = true
    end
  end

  def choose_pending()
    var best = -1
    var best_priority = -1
    var best_order = 0
    for scene : 0 .. 6
      var item = self.pending[scene]
      if item != nil && !self.failed[scene]
        var item_priority = item.find("priority")
        var item_order = item.find("order")
        if best < 0 || item_priority > best_priority || (item_priority == best_priority && item_order < best_order)
          best = scene
          best_priority = item_priority
          best_order = item_order
        end
      end
    end
    return best
  end

  def request_show()
    self.expire()
    if self.shown || self.show_requested return end
    var scene = self.choose_pending()
    if scene < 0 return end
    self.request_scene = scene
    self.show_requested = true
    self.cancelled_request = false
    var result = nil
    var rejected = false
    try
      result = rotation.show()
    except ..
      rejected = true
    end
    if result == false || rejected
      # A synchronous mock/device may call on_show before returning. In that
      # case the request was already fulfilled and must not be discarded.
      if !self.shown && self.pending[scene] != nil
        self.pending[scene] = nil
        self.request_scene = -1
        self.show_requested = false
          self.cancelled_request = true
        self.failed[scene] = true
        if !self.rejection_logged[scene]
          log("EventTrigger: rotation.show rejected " + self.names[scene])
          self.rejection_logged[scene] = true
        end
      end
    end
  end

  def accept(scene, event_id)
    var now = now_ms()
    if event_id != nil && self.id_seen(scene, event_id) return end
    if self.last_accepted[scene] != nil && self.cooldown_ms > 0 && self.elapsed(self.last_accepted[scene]) < self.cooldown_ms
      return
    end
    if event_id != nil self.remember_id(scene, event_id) end
    self.last_accepted[scene] = now
    self.failed[scene] = false
    self.rejection_logged[scene] = false
    var item = self.pending[scene]
    if item == nil
      self.sequence += 1
      self.pending[scene] = {"stamp": now, "order": self.sequence, "priority": self.priority(scene)}
    else
      # Coalesce a repeated pending pulse while refreshing its finite lifetime;
      # its original order remains the FIFO position within this priority.
      item["stamp"] = now
    end
    if !self.shown self.request_show() end
  end

  def clear_scene(scene)
    if scene < 0 || scene > 6 return end
    self.edge_active[scene] = false
    self.pending[scene] = nil
    if self.request_scene == scene
      self.request_scene = -1
      self.show_requested = false
      self.cancelled_request = true
    end
    if self.current_scene == scene
      if self.shown
        self.current_scene = -1
        self.current_started = nil
        self.current_priority = 0
        self.current_duration_ms = self.display_ms
        rotation.next()
      else
        self.current_scene = -1
        self.current_started = nil
      end
    end
  end

  def receive(topic, payload)
    self.expire()
    var parsed = self.parse_event(topic, payload)
    if parsed == nil return end
    var scene = parsed.find("scene")
    var state = parsed.find("state")
    if state == 0
      self.clear_scene(scene)
      return
    end
    if state != 1 return end
    var event_id = parsed.find("id")
    # Reject a late duplicate before changing edge state. A duplicate that
    # arrives after a false rearm must not latch the edge again.
    if event_id != nil && self.id_seen(scene, event_id) return end
    if self.trigger_mode == "edge"
      if self.edge_active[scene] return end
      self.edge_active[scene] = true
    end
    self.accept(scene, event_id)
  end

  def should_show()
    self.expire()
    if self.shown return true end
    if self.current_scene >= 0 return true end
    return self.choose_pending() >= 0
  end

  def on_show()
    var was_requested = self.show_requested
    var was_cancelled = self.cancelled_request
    self.expire()
    if self.shown return end
    # A deferred show can receive additional events before the firmware calls
    # on_show(). Re-evaluate priority at that boundary so the highest-priority
    # pending scene gets the turn; the request itself remains single-shot.
    var scene = self.choose_pending()
    if scene < 0 && (was_requested || was_cancelled)
      # The event that summoned this turn expired or was cleared before the
      # deferred callback arrived. Do not turn that stale request into a quiet
      # blank rotation turn; leave immediately and wait for a fresh event.
      self.show_requested = false
      self.request_scene = -1
      self.cancelled_request = false
      rotation.next()
      return
    end
    self.show_requested = false
    self.request_scene = -1
    self.cancelled_request = false
    if scene >= 0 && self.pending[scene] != nil && !self.failed[scene]
      var item = self.pending[scene]
      self.pending[scene] = nil
      self.current_scene = scene
      self.current_priority = item.find("priority")
      self.current_started = now_ms()
      self.current_duration_ms = (scene == 3 || scene == 4) ? self.alarm_ms : self.display_ms
      self.manual_idle = false
      if self.wake_display display.power(true) end
    else
      # Device-menu/manual Show may enter the app without an event. Paint the
      # quiet frame briefly; it must not manufacture an event scene.
      self.current_scene = -1
      self.current_priority = 0
      self.current_started = now_ms()
      self.current_duration_ms = self.display_ms
      self.idle_started = self.current_started
      self.manual_idle = true
    end
    self.shown = true
  end

  def on_hide()
    self.shown = false
    self.manual_idle = false
    self.current_scene = -1
    self.current_started = nil
    self.current_priority = 0
    self.current_duration_ms = self.display_ms
    self.cancelled_request = false
  end

  def loop()
    self.expire()
    if !self.shown && self.current_scene < 0 self.request_show() end
  end

  def duration()
    return self.current_duration_ms
  end

  def on_button(button)
    if button != "select" return false end
    for scene : 0 .. 6
      self.pending[scene] = nil
      self.failed[scene] = false
    end
    self.request_scene = -1
    self.show_requested = false
    self.cancelled_request = false
    self.current_scene = -1
    self.current_started = nil
    self.manual_idle = false
    rotation.next()
    return true
  end

  def draw()
    var scene = self.current_scene
    var elapsed_ms = scene >= 0 ? self.elapsed(self.current_started) : self.elapsed(self.idle_started)
    var labels = self.show_labels && scene >= 0
    self.paint(scene, elapsed_ms, labels)
  end
end
