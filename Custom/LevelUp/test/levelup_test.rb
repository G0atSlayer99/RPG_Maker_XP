# Test script for a COPY of the project (replaces "Main" there).
# Checks the Level Up script with the real RGSS engine and writes
# levelup_log.txt plus composites out_<name>.rgb (640x480 raw RGB).
# The EXP gains here exist only in this test (copy of the project).
$log = []
def log(s)
  $log.push(s)
  File.open("levelup_progress.txt", "a") { |f| f.write(s + "
") }
end
def check(name, ok)
  log((ok ? "OK    " : "FAIL  ") + name)
end

#--- simulated keys ----------------------------------------------------------
$press = []
$frame = 0
$schedule = nil     # proc(frame) -> keys pressed on that frame
module Input
  class << self
    alias test_update update
    alias test_trigger trigger?
    def update
      test_update
      $frame += 1
      $press = $schedule ? $schedule.call($frame) : []
      $on_frame.call($frame) if $on_frame
    end
    def trigger?(k)
      return $press.include?(k)
    end
    def press?(k)
      return $press.include?(k)
    end
    def repeat?(k)
      return $press.include?(k)
    end
    def dir4
      return 0
    end
  end
end
module LevelUp
  def self.log(text)
    @trace.push($frame.to_s + " " + text) if @trace != nil
  end
end

#--- composite of the screen's sprites over the map --------------------------
def draw_map(canvas)
  canvas.fill_rect(canvas.rect, Color.new(60, 90, 60))
  tb = RPG::Cache.tileset($game_map.tileset_name)
  ox = $game_map.display_x / 4
  oy = $game_map.display_y / 4
  for z in 0...3
    for ty in (oy / 32)..((oy + 480) / 32)
      for tx in (ox / 32)..((ox + 640) / 32)
        next if tx >= $game_map.width or ty >= $game_map.height
        id = $game_map.data[tx, ty, z]
        next if id == nil or id == 0
        if id >= 384
          i = id - 384
          canvas.blt(tx * 32 - ox, ty * 32 - oy, tb, Rect.new(i % 8 * 32, i / 8 * 32, 32, 32))
        else
          name = $game_map.autotile_names[id / 48 - 1]
          next if name == nil or name == ""
          ab = RPG::Cache.autotile(name)
          canvas.blt(tx * 32 - ox, ty * 32 - oy, ab, Rect.new(32, 64, 32, 32))
        end
      end
    end
  end
  # the player's walk sprite as on the map
  c = RPG::Cache.character($game_player.character_name, $game_player.character_hue)
  cw = c.width / 4
  ch = c.height / 4
  canvas.blt($game_player.screen_x - cw / 2, $game_player.screen_y - ch, c, Rect.new(0, 0, cw, ch))
end
def composite(screen, file)
  canvas = Bitmap.new(640, 480)
  draw_map(canvas)
  list = screen.sprites.select { |s| s.visible and s.bitmap != nil and s.opacity > 0 }
  list = list.sort_by { |s| s.z * 10000 + screen.sprites.index(s) }
  for s in list
    r = s.src_rect
    dw = (r.width * s.zoom_x).round
    dh = (r.height * s.zoom_y).round
    dx = (s.x - s.ox * s.zoom_x).round
    dy = (s.y - s.oy * s.zoom_y).round
    canvas.stretch_blt(Rect.new(dx, dy, dw, dh), s.bitmap, r, s.opacity)
  end
  out = ""
  for y in 0...480
    Graphics.update if y % 80 == 0
    for x in 0...640
      c = canvas.get_pixel(x, y)
      out << [c.red.to_i, c.green.to_i, c.blue.to_i].pack("C3")
    end
  end
  File.open(file, "wb") { |f| f.write(out) }
  canvas.dispose
end

begin
  $data_actors   = load_data("Data/Actors.rxdata")
  $data_classes  = load_data("Data/Classes.rxdata")
  $data_skills   = load_data("Data/Skills.rxdata")
  $data_items    = load_data("Data/Items.rxdata")
  $data_weapons  = load_data("Data/Weapons.rxdata")
  $data_armors   = load_data("Data/Armors.rxdata")
  $data_enemies  = load_data("Data/Enemies.rxdata")
  $data_troops   = load_data("Data/Troops.rxdata")
  $data_states   = load_data("Data/States.rxdata")
  $data_animations = load_data("Data/Animations.rxdata")
  $data_tilesets = load_data("Data/Tilesets.rxdata")
  $data_common_events = load_data("Data/CommonEvents.rxdata")
  $data_system   = load_data("Data/System.rxdata")
  $game_system   = Game_System.new
  $game_temp          = Game_Temp.new
  $game_switches      = Game_Switches.new
  $game_variables     = Game_Variables.new
  $game_self_switches = Game_SelfSwitches.new
  $game_screen        = Game_Screen.new
  $game_actors        = Game_Actors.new
  $game_party         = Game_Party.new
  $game_troop         = Game_Troop.new
  $game_map           = Game_Map.new
  $game_player        = Game_Player.new
  $game_party.setup_starting_members
  $game_map.setup($data_system.start_map_id)
  $game_player.moveto($data_system.start_x, $data_system.start_y)
  $game_player.refresh
  $game_map.update
  log("font: " + StatusBook.font_name + "   number font: " + StatusBook.number_font_name)
  log("party: " + $game_party.actors.collect { |a| a.id.to_s + " " + a.name + " Lv" + a.level.to_s + " edited=" + Attributes.actor_edited?(a.id).to_s }.join(", "))

  cfg = Attributes.config
  cfg["classes"] = {} unless cfg["classes"].is_a?(Hash)
  edited = $game_party.actors.select { |a| Attributes.actor_edited?(a.id) }
  if edited.size < 2
    # make a second party member edited for the queue test (copy of the first)
    other = $game_party.actors.find { |a| !Attributes.actor_edited?(a.id) }
    if other != nil and edited.size == 1
      cfg["actors"][other.id] = cfg["actors"][edited[0].id].dup
      cfg["actors"][other.id].delete("name")
      cfg["actors"][other.id].delete("class_id")
      log("test: actor " + other.id.to_s + " marked edited (copy of " + edited[0].id.to_s + ")")
    end
  end
  a = edited[0]
  # class values for the test actor: Str always +2, Mg never, Spd always +1
  cfg["classes"][a.class_id] = { "str_p1" => 0, "str_p2" => 100, "mg_p1" => 0, "mg_p2" => 0,
                                 "spd_p1" => 100, "spd_p2" => 0 }
  keys = ["hp", "sp", "str", "mg", "spd", "luck", "def", "res"]

  #=== 1 per-level log ========================================================
  srand(7)
  lv0 = a.level
  q = $game_temp.levelup_queue
  a.exp += 3 * Attributes.actor_level(a.id)[2]
  check("3 levels -> 3 queue entries (got " + q.size.to_s + ")", q.size == 3)
  ok = true
  for k in 0...q.size
    e = q[k]
    ok = false unless e["actor"] == a.id and e["from"] == lv0 + k and e["to"] == lv0 + k + 1
    ok = false if k > 0 and e["old"] != q[k - 1]["new"]
    for i in 0...8
      g = e["new"][i] - e["old"][i]
      ok = false unless g == e["growth"][keys[i]].to_i
    end
    log("  Lv " + e["from"].to_s + "->" + e["to"].to_s + " old " + e["old"].inspect + " new " + e["new"].inspect + " growth " + e["growth"].inspect)
  end
  check("levels consecutive, old = previous new, gain = roll", ok)
  check("old of first = values before", q[0]["old"] != nil)
  tot = {}
  q.each { |e| e["growth"].each { |k2, v| tot[k2] = tot[k2].to_i + v } }
  check("last_growth = sum of the 3 levels " + a.last_growth.inspect, a.last_growth == tot)
  check("Str +2 every level", q.all? { |e| e["growth"]["str"] == 2 })
  check("Mg never", q.all? { |e| e["growth"]["mg"].to_i == 0 })
  check("Spd +1 every level", q.all? { |e| e["growth"]["spd"] == 1 })
  check("Status values match last entry", LevelUp.values(a) == q[-1]["new"])
  entries = q.dup
  q.clear

  n = q.size
  a.level += 2
  check("Change Level +2 -> 2 entries", q.size == n + 2)
  q.clear
  b = $game_party.actors.find { |x| !Attributes.actor_edited?(x.id) }
  b ||= Game_Actor.new($data_actors.size - 1) if !Attributes.actor_edited?($data_actors.size - 1)
  if b != nil
    b.exp += 1000
    check("not edited actor -> no screen", q.empty?)
  end
  cfg["actors"][a.id]["level"] = 5.0
  r = Game_Actor.new(a.id)
  check("recruit set-up above Lv1 -> no screen (Lv" + r.level.to_s + ")", q.empty?)
  cfg["actors"][a.id]["level"] = 1.0
  q.clear

  #=== 2 one screen frame by frame, keys pressed every 7 frames ===============
  LevelUp.trace = []
  $frame = 0
  $schedule = proc { |f| f % 7 == 0 ? [Input::C] : (f % 11 == 0 ? [Input::A] : []) }
  s = LevelUp::Screen.new(a, entries[0])
  log("gains " + s.gains.inspect)
  shots = {}
  loop do
    Graphics.update
    Input.update
    s.update
    t = s.instance_variable_get(:@t)
    ph = s.phase
    break if s.done? or $frame > 2000
  end
  tr = LevelUp.trace
  log("timeline:")
  tr.each { |x| log("  " + x) }
  fr = lambda { |re| x = tr.find { |y| y =~ re }; x ? x.split(" ")[0].to_i : -1 }
  lv = fr.call(/ level /)
  shown = fr.call(/skip shown/)
  closed = fr.call(/closed by key/)
  stats = tr.select { |x| x =~ / stat / }.collect { |x| x.split(" ")[2] }
  skipped = tr.select { |x| x =~ / skip [A-Z]/ }.collect { |x| x.split(" ")[2] }
  check("level moment after intro (frame " + lv.to_s + ")", lv == LevelUp::FADE_IN + LevelUp::INTRO_HOLD + 1)
  order = LevelUp::LABELS.select { |l| stats.include?(l) }
  check("stats in order KP..Res: " + stats.join(","), stats == order)
  check("+0 stats skipped: " + skipped.join(","), skipped.all? { |l| s.gains[LevelUp::LABELS.index(l)] == 0 } && (stats + skipped).size == 8)
  sf = tr.select { |x| x =~ / stat / }.collect { |x| x.split(" ")[0].to_i }
  gap_ok = true
  for k in 1...sf.size
    gap_ok = false unless sf[k] - sf[k - 1] == LevelUp::VALUE_AT + LevelUp::POP + LevelUp::STAT_GAP + 1
  end
  check("each stat starts after the previous one finished (frames " + sf.join(",") + ")", gap_ok)
  check("first stat right after level pop", sf[0] == lv + LevelUp::POP + LevelUp::AFTER_LEVEL + 1 + LevelUp::VALUE_AT)
  check("Skip after the last stat + delay (" + shown.to_s + ")", shown == sf[-1] + LevelUp::POP + LevelUp::STAT_GAP + 1 + LevelUp::SKIP_DELAY)
  check("keys pressed before Skip were ignored (closed at " + closed.to_s + ")", closed > shown + LevelUp::SKIP_FADE - 1)
  check("closed on a key frame", closed % 7 == 0)
  list = s.sprites.dup
  s.dispose
  check("all sprites disposed", list.all? { |x| x.disposed? })
  LevelUp.trace = nil

  #=== 2b pictures (no keys) ==================================================
  $schedule = proc { |f| [] }
  s = LevelUp::Screen.new(a, entries[0])
  shots = {}
  s0 = LevelUp::Screen.new(a, entries[0])
  12.times { s0.update }
  check("start: every row equally faded (" + s0.instance_variable_get(:@rows).collect { |x| x.opacity }.inspect + ")",
    s0.instance_variable_get(:@rows).all? { |x| x.opacity == 128 })
  s0.dispose
  shots_at = [[:intro, LevelUp::FADE_IN + 2, "1_start"], [:level, 9, "2_level"],
              [:stat, LevelUp::VALUE_AT + 3, "3_stat"], [:skip, 30, "4_skip_white"],
              [:skip, 60, "5_skip_red"]]
  loop do
    Graphics.update
    Input.update
    s.update
    t = s.instance_variable_get(:@t)
    for x in shots_at
      if s.phase == x[0] and t == x[1] and !shots[x[2]]
        shots[x[2]] = true
        composite(s, "out_" + x[2] + ".rgb")
      end
    end
    break if shots.size == shots_at.size or $frame > 4000
  end
  check("Skip stays open without a key", !s.done?)
  rows = s.instance_variable_get(:@rows)
  check("after: rising rows dark, others faded (" + rows.collect { |x| x.opacity }.inspect + ")",
    (0...8).all? { |i| rows[i].opacity == (s.gains[i] > 0 ? 255 : 128) })
  s.dispose

  #=== 3 window at the top when the player stands low on the screen ===========
  $game_player.moveto($data_system.start_x, $game_map.height - 1)
  log("player low: screen_y " + $game_player.screen_y.to_s)
  s = LevelUp::Screen.new(a, entries[1])
  80.times { s.update }
  composite(s, "out_6_top.rgb")
  check("window moves to the top", s.instance_variable_get(:@top))
  s.dispose
  $game_player.moveto($data_system.start_x, $data_system.start_y)
  $game_map.update

  check("window at the bottom at the start position", !LevelUp::Screen.new(a, entries[2]).instance_variable_get(:@top))

  #=== 4 real map: Change EXP (whole party), then Show Text ===================
  LevelUp.trace = []
  srand(11)
  list = []
  list.push(RPG::EventCommand.new(315, 0, [0, 0, 0, 2 * Attributes.actor_level(a.id)[2]]))
  list.push(RPG::EventCommand.new(101, 0, ["Nach dem Level-Up"]))
  list.push(RPG::EventCommand.new(0, 0, []))
  $game_system.map_interpreter.setup(list, 0)
  $lv_before = {}
  $game_party.actors.each { |x| $lv_before[x.id] = x.level }
  $frame = 0
  $msg = []
  $was = false
  $schedule = proc { |f| f % 15 == 0 ? [Input::C] : [] }
  $on_frame = proc do |f|
    m = $game_temp.message_window_showing
    $msg.push([f, m]) if m != $was
    $was = m
    $scene = nil if f > 2500
  end
  $scene = Scene_Map.new
  begin
    $scene.main
  rescue SystemExit
    log("SystemExit at frame " + $frame.to_s)
  end
  $on_frame = nil
  tr = LevelUp.trace
  log("map timeline:")
  tr.each { |x| log("  " + x) }
  $msg.each { |x| log("  message showing=" + x[1].to_s + " at " + x[0].to_s) }
  opens = tr.select { |x| x =~ /open actor/ }
  want = $game_party.actors.select { |x| Attributes.actor_edited?(x.id) }.inject(0) { |t, x| t + x.level - $lv_before[x.id] }
  check("one screen per level and actor (" + opens.size.to_s + " screens, " + want.to_s + " levels gained)", opens.size == want)
  last_close = tr.select { |x| x =~ /close actor/ }.collect { |x| x.split(" ")[0].to_i }.max
  first_open = opens.empty? ? -1 : opens[0].split(" ")[0].to_i
  msg_on = $msg.find { |x| x[1] }
  msg_off = $msg.find { |x| !x[1] }
  check("screens opened before the message", msg_on != nil && first_open < msg_on[0] && last_close <= msg_on[0])
  check("Skip key did not close the message", msg_off != nil && msg_off[0] > last_close + 1)
  check("queue empty", $game_temp.levelup_queue.empty?)
rescue Exception => e
  log("ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace.join("\n"))
end
File.open("levelup_log.txt", "w") { |f| f.write($log.join("\n")) }
exit
