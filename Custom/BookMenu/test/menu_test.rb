# Test script for a COPY of the project (replaces "Main" there).
# Checks the Book Menu with the real RGSS engine: writes menu_log.txt and
# composites out_<name>.rgb (640x480 raw RGB). Actors added here only exist
# in this test.
$log = []
def log(s)
  $log.push(s)
  File.open("menu_progress.txt", "a") { |f| f.write(s + "\n") }
end
def check(name, ok)
  log((ok ? "OK    " : "FAIL  ") + name)
end

#--- simulated keys ----------------------------------------------------------
$press = []
module Input
  class << self
    def trigger?(k); return $press.include?(k); end
    def press?(k);   return $press.include?(k); end
    def repeat?(k);  return $press.include?(k); end
  end
end
def key(scene, k)
  $press = [k]
  scene.update
  $press = []
  scene.update
end

def composite(scene, file)
  canvas = Bitmap.new(640, 480)
  list = scene.sprites + scene.instance_variable_get(:@row_sprites)
  list = list.select { |s| !s.disposed? and s.visible and s.bitmap != nil and s.opacity > 0 }
  list = list.sort_by { |s| s.z * 10000 + list.index(s) }
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
def names(scene)
  return scene.rows.collect { |r| r["type"] == :group ? "[" + r["ids"].collect { |i| $game_actors[i].name }.join(",") + "]" : (r["active"] ? "(leer)" : "(leer,zu)") }.join(" ")
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
  Graphics.frame_count = 31 * Graphics.frame_rate
  log("party: " + $game_party.actors.collect { |a| a.id.to_s + " " + a.name }.join(", "))

  #=== 1 today's party ========================================================
  s = Scene_Menu.new
  s.create
  $scene = s
  log("rows: " + names(s))
  check("Gruppe I = first 3, Gruppe II = 4th", s.rows[0]["ids"] == $game_party.actors[0, 3].collect { |a| a.id } && s.rows[1]["ids"] == [$game_party.actors[3].id])
  check("then locked empty rows up to 4 rows", s.rows.size == 4 && !s.rows[2]["active"] && !s.rows[3]["active"])
  composite(s, "out_1_menu.rgb")
  # left menu
  key(s, Input::DOWN)
  check("Down moves the menu cursor", s.index == 1)
  key(s, Input::C)
  check("Einheiten opens the placeholder", s.placeholder != nil)
  key(s, Input::C)
  check("C does not close it", s.placeholder != nil)
  key(s, Input::B)
  check("B closes it", s.placeholder == nil && $scene != nil)
  key(s, Input::UP)
  key(s, Input::RIGHT)
  check("Right enters the groups at the first character", s.focus == :groups && s.row == 0 && s.col == 0)
  composite(s, "out_2_cursor_leader.rgb")
  key(s, Input::RIGHT); key(s, Input::RIGHT); key(s, Input::RIGHT)
  check("Right x3 -> Begleiter slot", s.col == 3)
  key(s, Input::RIGHT)
  check("Right at the end stays", s.col == 3)
  $scene = s
  key(s, Input::C)
  check("C on Begleiter -> placeholder", s.placeholder != nil)
  key(s, Input::B)
  key(s, Input::LEFT)
  key(s, Input::DOWN)
  check("Down keeps the column (row 1, col 2)", s.row == 1 && s.col == 2)
  composite(s, "out_3_cursor_free.rgb")
  key(s, Input::C)
  check("C on Freier Platz -> buzzer, nothing opens", s.placeholder == nil && $scene == s)
  key(s, Input::DOWN)
  check("empty row is one spot", s.row == 2 && s.col == 0)
  key(s, Input::C)
  check("locked empty group -> buzzer", s.placeholder == nil && $scene == s)
  key(s, Input::UP)
  check("Up goes back to the remembered column", s.row == 1 && s.col == 2)
  key(s, Input::UP)
  key(s, Input::LEFT); key(s, Input::LEFT)
  check("back on the leader", s.col == 0)
  key(s, Input::LEFT)
  check("Left from the leader -> menu", s.focus == :left)
  key(s, Input::RIGHT)
  key(s, Input::RIGHT)
  key(s, Input::C)
  check("C on a character opens Scene_Status for it", $scene.is_a?(Scene_Status) && $scene.instance_variable_get(:@actor_index) == 1)
  $scene = s
  # entries
  s.instance_variable_set(:@index, 0); s.set_focus(:left)
  key(s, Input::C)
  check("Inventar -> Scene_Item", $scene.is_a?(Scene_Item))
  $scene = s
  s.instance_variable_set(:@index, 5)
  key(s, Input::C)
  check("Speichern -> Scene_Save", $scene.is_a?(Scene_Save))
  $scene = s
  s.instance_variable_set(:@index, 6)
  key(s, Input::C)
  check("Spiel Verlassen -> Scene_End", $scene.is_a?(Scene_End))
  $scene = s
  s.instance_variable_set(:@index, 3)
  key(s, Input::C)
  check("Status -> groups, first character", s.focus == :groups && s.row == 0 && s.col == 0)
  key(s, Input::B)
  check("B in groups -> menu", s.focus == :left)
  key(s, Input::B)
  check("B in menu -> map", $scene.is_a?(Scene_Map))
  list = s.sprites.dup + s.instance_variable_get(:@row_sprites)
  s.dispose
  check("all sprites disposed", list.all? { |x| x.disposed? })

  #=== 2 returns from other screens ===========================================
  check("Save returns to Speichern", Scene_Menu.new(4).index == 5)
  check("End returns to Spiel Verlassen", Scene_Menu.new(5).index == 6)
  check("Item returns to Inventar", Scene_Menu.new(0).index == 0)
  st = Scene_Status.new(2)
  st.instance_variable_set(:@actor, $game_party.actors[2])
  $press = [Input::B]
  st.update
  $press = []
  m = $scene
  m.create
  check("Status B -> menu on the same character", m.focus == :groups && m.row == 0 && m.col == 2)
  m.dispose

  #=== 3 five actors ==========================================================
  ids = []
  for i in 1...$data_actors.size
    ids.push(i) if $data_actors[i] != nil and !$game_party.actors.include?($game_actors[i])
  end
  $game_party.add_actor(ids[0])
  check("5th actor can join (" + $game_party.actors.size.to_s + ")", $game_party.actors.size == 5)
  s = Scene_Menu.new
  s.create
  log("rows: " + names(s))
  check("5th actor fills Gruppe II", s.rows[1]["ids"].size == 2)
  composite(s, "out_4_party5.rgb")
  s.dispose
  $game_party.add_actor(ids[1])
  s = Scene_Menu.new
  s.create
  log("rows: " + names(s))
  check("6 actors: Gruppe III row active", s.rows[2]["type"] == :empty && s.rows[2]["active"] && !s.rows[3]["active"])
  s.instance_variable_set(:@index, 3)
  key(s, Input::C)
  key(s, Input::DOWN); key(s, Input::DOWN)
  $scene = s
  key(s, Input::C)
  check("active empty group -> placeholder", s.placeholder != nil)
  key(s, Input::B)
  s.dispose

  #=== 4 many actors: scrolling ===============================================
  for i in ids[2, 6]
    $game_party.add_actor(i)
  end
  log("party size " + $game_party.actors.size.to_s)
  s = Scene_Menu.new
  s.create
  log("rows: " + names(s))
  check("weitere Gruppen while more rows below (last visible " + s.last_visible.to_s + " of " + (s.rows.size - 1).to_s + ")", s.last_visible < s.rows.size - 1)
  composite(s, "out_5_many.rgb")
  key(s, Input::RIGHT)
  (s.rows.size - 1).times { key(s, Input::DOWN) }
  check("scrolled to the last row (top " + s.top.to_s + ")", s.row == s.rows.size - 1 && s.top > 0 && s.last_visible == s.rows.size - 1)
  composite(s, "out_6_scrolled.rgb")
  (s.rows.size - 1).times { key(s, Input::UP) }
  check("scrolled back up", s.row == 0 && s.top == 0)
  s.dispose

  #=== 5 item target window scrolls ===========================================
  w = Window_Target.new
  w.index = $game_party.actors.size - 1
  w.update
  check("item target: last actor visible (oy " + w.oy.to_s + ")", w.oy > 0 && w.oy + w.height - 32 >= w.index * 116 + 96)
  w.dispose

  #=== 6 old save without groups ==============================================
  $game_party.instance_variable_set(:@menu_groups, nil)
  g = $game_party.menu_groups
  check("old save: groups rebuilt in party order", g.flatten == $game_party.actors.collect { |a| a.id })
  $game_party.remove_actor($game_party.actors[1].id)
  g = $game_party.menu_groups
  check("removed actor leaves a free spot in Gruppe I", g[0].size == 2 && g.flatten.sort == $game_party.actors.collect { |a| a.id }.sort)
  log("groups after remove: " + g.inspect)
  #=== 7 no limit: 40 party members (placeholder actors, test copy only) ====
  base = $data_actors[2]
  n = $data_actors.size
  while $data_actors.size <= 45
    c = Marshal.load(Marshal.dump(base))
    c.id = $data_actors.size
    c.name = "Platzh. " + c.id.to_s
    $data_actors.push(c)
  end
  log("database actors in this test: " + ($data_actors.size - 1).to_s)
  for i in 1...$data_actors.size
    $game_party.add_actor(i)
  end
  check("every actor joined (" + $game_party.actors.size.to_s + ")", $game_party.actors.size == $data_actors.size - 1)
  g = $game_party.menu_groups
  check("groups of 3, only the last one may be short (" + g.collect { |x| x.size }.join(",") + ")",
    g[0...-1].all? { |x| x.size == 3 } && g.flatten.size == $game_party.actors.size)
  check("roman numerals", [1, 4, 9, 12, 14, 19, 39, 40, 49, 99, 1994].collect { |x| BookMenu.roman(x) } ==
    ["I", "IV", "IX", "XII", "XIV", "XIX", "XXXIX", "XL", "XLIX", "XCIX", "MCMXCIV"])
  s = Scene_Menu.new
  s.create
  $scene = s
  log("rows: " + s.rows.size.to_s + " (" + g.size.to_s + " groups + " + (s.rows.size - g.size).to_s + " empty)")
  check("one empty group after the last group", s.rows.size == g.size + 1)
  key(s, Input::RIGHT)
  4.times { key(s, Input::DOWN) }
  check("4 rows down: scrolled by one per step (top " + s.top.to_s + ", row " + s.row.to_s + ")", s.row == 4 && s.top == 2)
  composite(s, "out_7_groups_V.rgb")
  t0 = Time.now
  steps = 0
  while s.row < s.rows.size - 1
    $press = [Input::DOWN]; s.update; $press = []
    steps += 1
    weiter = s.last_visible < s.rows.size - 1
    if !weiter and s.row < s.rows.size - 1
      log("FAIL weitere Gruppen missing at row " + s.row.to_s)
    end
  end
  ms = ((Time.now - t0) * 1000 / steps).round
  log("scroll step (redraw only): about " + ms.to_s + " ms (" + steps.to_s + " steps)")
  check("reached the last row " + s.row.to_s + ", nothing more below", s.last_visible == s.rows.size - 1)
  composite(s, "out_8_end.rgb")
  while s.row > 0
    $press = [Input::UP]; s.update; $press = []
  end
  check("back at the top", s.top == 0)
  s.dispose
  # long numerals
  s = Scene_Menu.new
  s.create
  s.instance_variable_set(:@focus, :groups)
  s.move_to(s.rows.size - 1, 0) rescue nil
  s.dispose

  check("scroll redraw under one frame (25 ms): " + ms.to_s + " ms", ms <= 25)

  #=== 8 save preview shows only the main character ===========================
  File.open("Save4.rxdata", "wb") { |f| Scene_Save.new.write_save_data(f) }
  w = Window_SaveFile.new(3, "Save4.rxdata")
  ch = w.instance_variable_get(:@characters)
  check("save file still has all characters, preview shows 1 (" + ch.size.to_s + ")", ch.size == 1)
  w.dispose
rescue Exception => e
  log("ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace.join("\n"))
end
File.open("menu_log.txt", "w") { |f| f.write($log.join("\n")) }
exit
