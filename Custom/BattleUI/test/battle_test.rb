# Test script for a COPY of the project (replaces "Main" there): Battle UI.
# Runs a battle with 3 party members against a 4-enemy troop (only 3 may
# fight), drives it with simulated keys, checks the flow and the previews and
# writes out_*.rgb screenshots and battle_log.txt. Data changed here only
# exists in this test.
$log = []
def log(s)
  $log.push(s)
  File.open("battle_progress.txt", "a") { |f| f.write(s + "\n") }
end
def check(name, ok)
  log((ok ? "OK    " : "FAIL  ") + name)
end

#--- simulated keys -----------------------------------------------------------
$press = []
$next = nil
module Input
  class << self
    alias bt_update update
    def update
      bt_update
      $press = $next || []
      $next = nil
    end
    def trigger?(k); return $press.include?(k); end
    def press?(k);   return $press.include?(k); end
    def repeat?(k);  return $press.include?(k); end
    def dir4; return 0; end
    def dir8; return 0; end
  end
end

$events = []
class Scene_Battle
  alias bt_update_phase4_step2 update_phase4_step2
  def update_phase4_step2
    $events.push("act " + @active_battler.name) if @phase4_step == 2
    bt_update_phase4_step2
  end
  alias bt_bui_start_input bui_start_input
  def bui_start_input
    $events.push("input " + @active_battler.name)
    bt_bui_start_input
  end
  # the setup part of main (no transition, no main loop)
  def bt_open
    $game_temp.in_battle = true
    $game_temp.battle_turn = 0
    $game_temp.battle_event_flags.clear
    $game_temp.battle_abort = false
    $game_temp.battle_main_phase = false
    $game_temp.battleback_name = $game_map.battleback_name
    $game_temp.forcing_battler = nil
    $game_system.battle_interpreter.setup(nil, 0)
    @troop_id = $game_temp.battle_troop_id
    $game_troop.setup(@troop_id)
    s1 = $data_system.words.attack
    s2 = $data_system.words.skill
    s3 = $data_system.words.guard
    s4 = $data_system.words.item
    @actor_command_window = Window_Command.new(160, [s1, s2, s3, s4])
    @actor_command_window.active = false
    @actor_command_window.visible = false
    @party_command_window = Window_PartyCommand.new
    @help_window = Window_Help.new
    @help_window.visible = false
    @status_window = Window_BattleStatus.new
    @message_window = Window_Message.new
    @spriteset = Spriteset_Battle.new
    @wait_count = 0
    start_phase1
  end
  def bt_close
    @actor_command_window.dispose
    @party_command_window.dispose
    @help_window.dispose
    @status_window.dispose
    @message_window.dispose
    @skill_window.dispose if @skill_window != nil
    @item_window.dispose if @item_window != nil
    @spriteset.dispose
  end
end

def frame(s)
  Graphics.update
  Input.update
  s.update
end
def run_until(s, max = 900)
  max.times do
    return true if yield
    frame(s)
  end
  return yield
end
def key(s, k)
  $next = [k]
  frame(s)
  frame(s)
end
def iv(o, n); return o.instance_variable_get(n); end

#--- screenshots ---------------------------------------------------------------
def mirrored(bmp)
  m = Bitmap.new(bmp.width, bmp.height)
  for x in 0...bmp.width
    m.blt(bmp.width - 1 - x, 0, bmp, Rect.new(x, 0, 1, bmp.height))
  end
  return m
end
def draw_sprite(canvas, sp)
  return if sp == nil or sp.disposed? or !sp.visible or sp.bitmap == nil or sp.opacity == 0
  bmp = sp.mirror ? mirrored(sp.bitmap) : sp.bitmap
  r = sp.src_rect
  dw = (r.width * sp.zoom_x).round
  dh = (r.height * sp.zoom_y).round
  canvas.stretch_blt(Rect.new((sp.x - sp.ox * sp.zoom_x).round, (sp.y - sp.oy * sp.zoom_y).round, dw, dh), bmp, r, sp.opacity)
  bmp.dispose if sp.mirror
end
def shot(s, file)
  ss = iv(s, :@spriteset)
  hud = ss.hud
  low = [iv(ss, :@battleback_sprite)] + iv(ss, :@enemy_sprites) + iv(ss, :@actor_sprites) +
        iv(hud, :@plates).values + [iv(hud, :@ring), iv(hud, :@pointer)]
  high = [iv(hud, :@command), iv(hud, :@bar)] + iv(hud, :@brackets).collect { |x| x[1] } +
         iv(hud, :@info_sprites) + [iv(hud, :@placeholder)]
  canvas = Bitmap.new(640, 480)
  canvas.fill_rect(canvas.rect, Color.new(0, 0, 0))
  low.compact.sort_by { |x| x.z }.each { |x| draw_sprite(canvas, x) }
  high.compact.sort_by { |x| x.disposed? ? 0 : x.z }.each { |x| draw_sprite(canvas, x) }
  out = ""
  for y in 0...480
    Graphics.update if y % 60 == 0
    for x in 0...640
      c = canvas.get_pixel(x, y)
      out << [c.red.to_i, c.green.to_i, c.blue.to_i].pack("C3")
    end
  end
  File.open(file, "wb") { |f| f.write(out) }
  canvas.dispose
end

def graphic_ok?(name, hue)
  return false if name == nil or name == ""
  begin
    RPG::Cache.battler(name, hue)
    return true
  rescue Exception
    return false
  end
end
def inside?(r)
  return (r[0] >= 0 and r[1] >= 0 and r[0] + r[2] <= 640 and r[1] + r[3] <= 480)
end
def info_rects(hud)
  m = BattleUI::TAIL + 2
  return iv(hud, :@info_sprites).collect do |sp|
    [sp.x + m, sp.y + m, sp.bitmap.width - m * 2 - 3, sp.bitmap.height - m * 2 - 3]
  end
end

begin
  Graphics.frame_rate = 120
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
  $game_temp = Game_Temp.new; $game_system = Game_System.new
  $game_switches = Game_Switches.new; $game_variables = Game_Variables.new
  $game_self_switches = Game_SelfSwitches.new; $game_screen = Game_Screen.new
  $game_actors = Game_Actors.new; $game_party = Game_Party.new
  $game_troop = Game_Troop.new; $game_map = Game_Map.new; $game_player = Game_Player.new
  $game_party.setup_starting_members
  $game_map.setup(2)
  $game_map.battleback_name = "001-Grassland01"
  log("fonts: heading " + BattleUI.head_font + ", body " + BattleUI.body_font)

  # party: 5 actors with a battler graphic
  aids = (1...$data_actors.size).select { |i| $data_actors[i] != nil and graphic_ok?($data_actors[i].battler_name, $data_actors[i].battler_hue) }
  party = aids[0, 5].collect { |i| $game_actors[i] }
  party.each { |a| a.recover_all }
  log("party: " + party.collect { |a| a.name }.join(", "))
  # troop 1: 4 enemies (only 3 may fight), no troop events
  eids = (1...$data_enemies.size).select { |i| $data_enemies[i] != nil and graphic_ok?($data_enemies[i].battler_name, $data_enemies[i].battler_hue) }
  t = RPG::Troop.new
  t.id = 1
  t.name = "Test"
  # test enemies with RTP graphics (like the reference pictures)
  cfg = Attributes.config
  cfg["enemies"] = {} unless cfg["enemies"].is_a?(Hash)
  made = []
  [["Ritter A", "049-Soldier01", 120], ["Söldner", "009-Lancer01", 180], ["Ritter B", "049-Soldier01", 120]].each do |x|
    e = Marshal.load(Marshal.dump($data_enemies[eids[0]]))
    e.id = $data_enemies.size
    e.name = x[0]
    e.battler_name = x[1]
    e.battler_hue = 0
    e.maxhp = x[2]
    e.str = 30; e.dex = 10; e.agi = 9; e.int = 10; e.pdef = 8; e.mdef = 6
    $data_enemies.push(e)
    cfg["enemies"].delete(e.id)
    made.push(e.id)
  end
  [made[0], made[1], made[2], made[0]].each_with_index do |id, i|
    m = RPG::Troop::Member.new
    m.enemy_id = id
    m.x = 100 + i * 100
    m.y = 300
    t.members.push(m)
  end
  t.pages = [RPG::Troop::Page.new]
  $data_troops[1] = t
  $game_temp.battle_troop_id = 1
  $game_temp.battle_can_lose = true
  # area skill for everyone (variance 15: must be ignored)
  sk = RPG::Skill.new
  sk.id = $data_skills.size
  sk.name = "Flächenangriff A"
  sk.scope = 2
  sk.occasion = 0
  sk.power = 40
  sk.int_f = 100
  sk.mdef_f = 100
  sk.variance = 15
  sk.sp_cost = 0
  sk.animation1_id = 0
  sk.animation2_id = 0
  $data_skills.push(sk)
  party.each { |a| a.instance_variable_set(:@skills, [sk.id]) }

  #=== 1 battle start ==========================================================
  $game_party.battle_ui_actors = party[0, 3]
  s = Scene_Battle.new
  $scene = s
  s.bt_open
  check("troop with 4 enemies -> 3 fight (#{$game_troop.enemies.size})", $game_troop.enemies.size == 3)
  ok = run_until(s) { iv(s, :@phase) == 3 and iv(s, :@actor_command_window).visible }
  check("battle starts without the Fight/Escape window, a command window opens", ok && !iv(s, :@party_command_window).visible)
  list = []
  $game_party.actors.each_with_index { |a, i| list.push([a, 0, i]) }
  $game_troop.enemies.each_with_index { |e, i| list.push([e, 1, i]) }
  list = list.sort_by { |x| [-x[0].agi, -x[0].luck, x[1], x[2]] }
  want = list.collect { |x| x[0] }
  log("turn order: " + want.collect { |b| b.name + "(Spd #{b.agi})" }.join(" > "))
  log("events: " + $events.join(", "))
  first_actor = want.find { |b| b.is_a?(Game_Actor) }
  before = want[0, want.index(first_actor)].collect { |b| "act " + b.name }
  check("faster enemies act before the first party member, then it chooses", $events == before + ["input " + first_actor.name])
  hud = s.instance_variable_get(:@spriteset).hud
  cw = iv(s, :@actor_command_window)
  check("command window is the new panel at the top right", cw.is_a?(BattleUI::CommandPanel) && cw.x == 640 - 10 - 220 && cw.y == 10)
  check("active character: ring + pointer", iv(hud, :@ring).visible && iv(hud, :@pointer).visible && hud.active_battler == first_actor)
  check("ring behind its battler", iv(hud, :@ring).z < s.instance_variable_get(:@spriteset).battler_sprite(first_actor).z)
  sp = s.instance_variable_get(:@spriteset)
  e0 = $game_troop.enemies[0]
  check("enemies mirrored, party not", sp.battler_sprite(e0).mirror && !sp.battler_sprite($game_party.actors[0]).mirror)
  pr = BattleUI.plate_rect($game_party.actors[0])
  check("plate of party member 1 at 400,136 (#{pr[0]},#{pr[1]})", pr[0] == 400 && pr[1] == 136)
  pr = BattleUI.plate_rect($game_troop.enemies[1])
  check("plate of enemy 2 at 24,186 (#{pr[0]},#{pr[1]})", pr[0] == 24 && pr[1] == 186)
  zs = ($game_party.actors + $game_troop.enemies).collect { |b| [b.screen_y, sp.battler_sprite(b).z] }
  check("lower battlers drawn in front (z from foot y)", zs.sort == zs.sort_by { |x| x[1] })
  check("battleback fills the screen", iv(sp, :@battleback_sprite).bitmap.width * iv(sp, :@battleback_sprite).zoom_x >= 640 && iv(sp, :@battleback_sprite).bitmap.height * iv(sp, :@battleback_sprite).zoom_y >= 480)
  shot(s, "out_01_command.rgb")

  #=== 2 command grid ==========================================================
  key(s, Input::RIGHT); i1 = cw.index
  key(s, Input::DOWN);  i2 = cw.index
  key(s, Input::LEFT);  i3 = cw.index
  key(s, Input::UP);    i4 = cw.index
  check("2x2 grid: right 1, down 3, left 2, up 0 (#{[i1, i2, i3, i4].inspect})", [i1, i2, i3, i4] == [1, 3, 2, 0])
  key(s, Input::B)
  check("cancel in the command window does nothing", cw.visible && cw.active && iv(s, :@phase) == 3)

  #=== 3 Angreifen: one enemy =================================================
  actor = hud.active_battler
  key(s, Input::C)
  tg = iv(s, :@enemy_arrow)
  living = $game_troop.enemies.select { |e| e.exist? }
  check("Angreifen -> first living enemy targeted", tg.is_a?(BattleUI::Targeter) && hud.targets == [living[0]] && !cw.visible)
  check("top bar '#{tg.title}'", tg.title == "Angreifen · Ziel wählen" && iv(hud, :@bar).visible)
  key(s, Input::DOWN)
  check("Down -> next enemy (#{tg.index})", hud.targets == [living[1]])
  key(s, Input::B)
  check("Cancel -> back to the command window", iv(s, :@enemy_arrow) == nil && cw.visible && cw.active && hud.targets.empty?)
  key(s, Input::C)
  key(s, Input::DOWN)
  tg = iv(s, :@enemy_arrow)
  target = hud.targets[0]
  r = info_rects(hud)
  check("one info window (180 wide), on screen", r.size == 1 && r[0][2] == 180 && inside?(r[0]))
  check("info window does not cover the active character", BattleUI.overlap(r[0], BattleUI.visible_rect(actor)) == 0)
  check("info window does not cover its target", BattleUI.overlap(r[0], BattleUI.visible_rect(target)) == 0)
  pv = BattleUI.preview(actor, target, :attack, nil)
  log("preview on #{target.name}: KP #{pv['hp']} -> #{pv['after']}, Schaden #{pv['dmg']}, Treffer #{pv['hit']} %, Krit #{pv['crit']} %")
  check("preview = Str - Def / 100 + Luck - Luck / CrtR + Luck", pv["dmg"] == [actor.str - target.pdef, 0].max && pv["hit"] == [100 + actor.luck - target.luck, 100].min && pv["crit"] == (pv["dmg"] > 0 ? actor.crit_chance : 0))
  shot(s, "out_02_target.rgb")
  hp0 = target.hp
  key(s, Input::C)
  run_until(s, 60) { target.hp != hp0 or target.damage == "Miss" }
  loss = hp0 - target.hp
  check("the hit deals the previewed damage (#{loss}, preview #{pv['dmg']}, crit #{actor.apply_crit_damage(pv['dmg'])})", [0, pv["dmg"], [actor.apply_crit_damage(pv["dmg"]), hp0].min, [pv["dmg"], hp0].min].include?(loss))
  check("after choosing: command gone, ring gone, the character acts", !cw.visible && hud.active_battler == nil && $events.include?("act " + actor.name))

  #=== 4 area skill ============================================================
  ok = run_until(s) { iv(s, :@phase) == 3 and cw.visible or $game_temp.battle_turn > 1 }
  actor = hud.active_battler
  check("next party member gets the command window (#{actor ? actor.name : '-'})", ok && actor != nil)
  key(s, Input::RIGHT)
  key(s, Input::C)
  check("Skill -> skill list", iv(s, :@skill_window) != nil)
  key(s, Input::C)
  tg = iv(s, :@enemy_arrow)
  living = $game_troop.enemies.select { |e| e.exist? }
  check("area skill: all living enemies targeted (#{hud.targets.size})", tg != nil && tg.all && hud.targets == living)
  check("top bar '#{tg.title}'", tg.title == "Skill · Ziel: alle Gegner")
  r = info_rects(hud)
  check("one small window (124 wide) per enemy", r.size == living.size && r.all? { |x| x[2] == 124 })
  bad = []
  r.each_with_index { |a, i| r.each_with_index { |b, j| bad.push([i, j]) if i < j and BattleUI.overlap(a, b) > 0 } }
  check("small windows do not overlap each other (#{bad.inspect})", bad.empty?)
  check("small windows are on screen", r.all? { |x| inside?(x) })
  cover = r.select { |x| $game_party.actors.find { |a| BattleUI.overlap(x, BattleUI.visible_rect(a)) > 0 } }
  check("small windows do not cover the party", cover.empty?)
  key(s, Input::DOWN)
  check("Down does not change area targets", hud.targets == living)
  pvs = living.collect { |e| BattleUI.preview(actor, e, :skill, sk) }
  pvs.each_with_index { |p, i| log("preview #{living[i].name}: KP #{p['hp']} -> #{p['after']}, Schaden #{p['dmg']}, Treffer #{p['hit']} %, Krit #{p['crit']} %") }
  shot(s, "out_03_area.rgb")
  key(s, Input::B)
  check("Cancel -> back to the skill list", iv(s, :@enemy_arrow) == nil && iv(s, :@skill_window) != nil)
  frame(s)
  check("skill list visible again", iv(s, :@skill_window).visible)
  key(s, Input::C)
  hp0 = living.collect { |e| e.hp }
  key(s, Input::C)
  run_until(s, 60) { iv(s, :@phase4_step) >= 4 }
  losses = []
  living.each_with_index { |e, i| losses.push(hp0[i] - e.hp) }
  okd = true
  living.each_with_index { |e, i| okd = false unless [0, [pvs[i]["dmg"], hp0[i]].min].include?(losses[i]) }
  check("area skill deals exactly the previewed damage, no variance (#{losses.inspect} vs #{pvs.collect { |p| p['dmg'] }.inspect})", okd)

  #=== 5 Checken / next rounds =================================================
  ok = run_until(s) { (iv(s, :@phase) == 3 and cw.visible) or $game_temp.gameover }
  if ok and iv(s, :@phase) == 3
    key(s, Input::RIGHT)
    key(s, Input::DOWN)
    key(s, Input::C)
    check("Checken opens the placeholder", hud.placeholder? && !cw.active)
    shot(s, "out_04_check.rgb")
    key(s, Input::B)
    check("Cancel closes it", !hud.placeholder? && cw.active && cw.visible)
    key(s, Input::UP)
    key(s, Input::LEFT)
    key(s, Input::C)
    key(s, Input::C)
  end
  ok = run_until(s, 1500) { $game_temp.battle_turn >= 2 and iv(s, :@phase) == 3 and cw.visible or $game_temp.gameover or iv(s, :@phase) == 5 }
  check("round 2 starts directly with the next turn (turn #{$game_temp.battle_turn}, phase #{iv(s, :@phase)})", ok)
  log("events: " + $events.join(", "))
  s.bt_close
  $game_temp.in_battle = false

  #=== 6 only the first 3 party members fight; the party is kept ============
  $game_party.battle_ui_actors = party
  $game_party.actors.each { |a| a.recover_all }
  s2 = Scene_Battle.new
  $bt_size = nil
  class << s2
    def update
      $bt_size = $game_party.actors.size
      $scene = nil
    end
  end
  $scene = s2
  s2.main
  check("5 in the party: 3 fight (#{$bt_size}), all 5 still in the party afterwards (#{$game_party.actors.size})", $bt_size == 3 && $game_party.actors.size == 5)
rescue Exception => ex
  log("ERROR " + ex.class.to_s + ": " + ex.message + "\n" + ex.backtrace[0, 10].join("\n"))
end
File.open("battle_log.txt", "w") { |f| f.write($log.join("\n")) }
exit
