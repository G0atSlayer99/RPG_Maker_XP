# Test script for a COPY of the project (replaces "Main" there).
# Checks the FE Tactics squads with the real RGSS engine on Map001
# (fe_battle(1) map) and writes squad_log.txt. Actors and values changed
# here only exist in this test.
$log = []
def log(s)
  $log.push(s)
  File.open("squad_progress.txt", "a") { |f| f.write(s + "\n") }
end
def check(name, ok)
  log((ok ? "OK    " : "FAIL  ") + name)
end

#--- simulated keys: C every 4 frames ---------------------------------------
$frame = 0
$press = []
module Input
  class << self
    alias sq_update update
    def update
      sq_update
      $frame += 1
      $press = ($frame % 4 == 0) ? [Input::C] : []
      raise "test timeout" if $frame > 20000
    end
    def trigger?(k); return $press.include?(k); end
    def press?(k);   return $press.include?(k); end
    def repeat?(k);  return $press.include?(k); end
    def dir4; return 0; end
    def dir8; return 0; end
  end
end
# record the party that the battle screen really uses
class Scene_FESkirmish
  alias sq_start_phase3 start_phase3
  def start_phase3
    $battle_party = $game_party.actors.collect { |a| a.id } if $battle_party == nil
    sq_start_phase3
  end
end
# record where the level-up screen opens
class LevelUp::Screen
  alias sq_init initialize
  def initialize(actor, entry, focus = nil)
    sq_init(actor, entry, focus)
    $lv_screens.push([actor.id, @px, @py]) if $lv_screens
  end
end
def ids(list)
  return list.collect { |a| a.id }
end
def names(list)
  return list.collect { |a| a.name }.join(",")
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
  # test copy only: enemy graphics that don't exist in Graphics/Characters
  for e in $data_enemies.compact
    if !FileTest.exist?("Graphics/Characters/" + e.battler_name + ".png") and
       !FileTest.exist?("C:/Program Files (x86)/Common Files/Enterprise Brain/RGSS/Standard/Graphics/Characters/" + e.battler_name + ".png")
      begin
        RPG::Cache.character(e.battler_name, 0)
      rescue Exception
        log("test: enemy " + e.id.to_s + " " + e.name + " graphic '" + e.battler_name + "' missing -> 001-Fighter01")
        e.battler_name = "001-Fighter01"
      end
    end
  end
  $game_map.setup(1)
  $game_player.moveto($data_system.start_x, $data_system.start_y)
  $game_player.refresh
  $game_map.update
  log("party: " + names($game_party.actors))

  #=== 1 averages =============================================================
  check("average 5,6 -> 5 (x.5 down)", FE_Squad.average([5, 6]) == 5)
  check("average 5,6,6 -> 6 (5.67 up)", FE_Squad.average([5, 6, 6]) == 6)
  check("average 5,5,6 -> 5 (5.33 down)", FE_Squad.average([5, 5, 6]) == 5)
  check("average 4,5,7 -> 5 (5.33)", FE_Squad.average([4, 5, 7]) == 5)

  #=== 2 deploy: one unit per squad ===========================================
  party_before = $game_party.actors.dup
  def new_battle
    s = Scene_FEBattle.new(1, false)
    s.instance_eval do
      @saved_dx = $game_map.display_x
      @saved_dy = $game_map.display_y
      @player_was_transparent = $game_player.transparent
      @map_bgm = $game_system.playing_bgm
      @units = []
      @turn = 0
      @ended = false
      @state = :busy
      @sel = nil
      @shown_enemy = nil
      @spriteset = Spriteset_Map.new
      create_graphics
      build_grid
      @deploy_ok = deploy
      @cam_x = $game_map.display_x
      @cam_y = $game_map.display_y
    end
    return s
  end
  def dispose_battle(s)
    s.instance_eval { dispose_graphics }
  end
  b = new_battle
  units = b.instance_variable_get(:@units)
  pl = units.select { |u| u.player? }
  en = units.select { |u| !u.player? }
  log("player units: " + pl.collect { |u| "[" + names(u.members) + "]" }.join(" ") + "   enemy units: " + en.size.to_s)
  check("2 player units for 2 squads", pl.size == 2)
  check("unit 1 = Caelith, Basil, Gloria (real actors, no copies)", ids(pl[0].members) == ids(party_before[0, 3]) && pl[0].members.all? { |m| $game_actors[m.id].equal?(m) })
  check("unit 2 = Hilda only", ids(pl[1].members) == [party_before[3].id])
  check("unit sprite = leader's walk sprite", pl[0].character_name == party_before[0].character_name)
  mv = pl[0].members.collect { |m| FE_Squad.actor_move(m) }
  check("move = squad average " + mv.inspect + " -> " + pl[0].move_points.to_s, pl[0].move_points == FE_Squad.average(mv))
  check("main character deployed", b.instance_variable_get(:@main_deployed))
  check("enemies still 3 copies", en.all? { |u| u.members.size == FE_Config::STACK_SIZE })

  #=== 3 a real fight: Caelith's squad vs an enemy unit =======================
  foe = en[0]
  foe.members.each { |e| e.hp = 1 }                  # so that kills happen
  de = $data_enemies[foe.members[0].id]
  de.atk = 0; de.str = 0; de.int = 0                 # harmless: nobody falls
  de.actions.each { |a| a.kind = 0; a.basic = 0 }
  cfg = Attributes.config
  cfg["actors"][2] = cfg["actors"][1].dup             # Basil edited too
  cfg["actors"][2].delete("name"); cfg["actors"][2].delete("class_id")
  $data_enemies[foe.members[0].id].exp = 150         # big EXP -> level-ups
  $game_party.gain_gold(0)
  gold0 = $game_party.gold
  exp0 = pl[0].members.collect { |m| m.exp }
  lv0 = pl[0].members.collect { |m| m.level }
  hp_obj = pl[0].members[1]
  $battle_party = nil
  $lv_screens = []
  FE_Reward.trace = []
  LevelUp.trace = []
  alive0 = foe.alive_members.size
  b.instance_eval { run_combat(pl[0], foe) }
  log("battle party was " + $battle_party.inspect + "; level-up screens " + $lv_screens.inspect)
  check("battle used exactly the squad, leader first", $battle_party == ids(pl[0].members))
  check("party restored in original order", ids($game_party.actors) == ids(party_before) && $game_party.actors.each_with_index.all? { |a, i| a.equal?(party_before[i]) }) rescue check("party restored in original order", ids($game_party.actors) == ids(party_before))
  check("HP after the fight is on the real actor (" + hp_obj.name + " " + hp_obj.hp.to_s + "/" + hp_obj.maxhp.to_s + ")", $game_actors[hp_obj.id].equal?(hp_obj))
  killed = alive0 - foe.alive_members.size
  want = killed * 150
  got = pl[0].members.each_with_index.collect { |m, i| m.dead? ? 0 : m.exp - exp0[i] } rescue nil
  got = (0...pl[0].members.size).collect { |i| m = pl[0].members[i]; m.dead? ? -1 : m.exp - exp0[i] }
  log("killed " + killed.to_s + " -> EXP per living member " + got.inspect + " (levels " + lv0.inspect + " -> " + pl[0].members.collect { |m| m.level }.inspect + ")")
  check("every living member got the full EXP of each kill (" + want.to_s + ")", got.all? { |g| g == -1 or g == want })
  log("reward trace: " + FE_Reward.trace.join(" | "))
  check("EXP panel shown in the battle screen and closed with C", FE_Reward.trace.include?("filled") && FE_Reward.trace[-1] == "closed")
  lv_ups = pl[0].members.inject(0) { |t, m| t + m.level - lv0[pl[0].members.index(m)] }
  ok = pl[0].members.all? { |m| m.level == lv0[pl[0].members.index(m)] || FE_Reward.trace.include?("lvl up " + m.name + " " + m.level.to_s) }
  check("LVL UP! shown for every member that levelled, up to the final level", ok)
  check("level-up screens only after the panel closed", $lv_screens.size == 0 || FE_Reward.trace.index("closed") != nil)
  edited = pl[0].members.select { |m| Attributes.actor_edited?(m.id) and !m.dead? }
  ups = pl[0].members.inject(0) { |t, m| t + (Attributes.actor_edited?(m.id) ? m.level - lv0[pl[0].members.index(m)] : 0) }
  check("level-up screens shown on the battle map (" + $lv_screens.size.to_s + " for " + ups.to_s + " levels)", $lv_screens.size == ups)
  check("level-up screen on the squad's tile", $lv_screens.all? { |x| x[1] == pl[0].screen_x && x[2] == pl[0].screen_y })
  wiped = foe.dead?
  gold_want = wiped ? foe.members.inject(0) { |t, m| t + m.gold } : 0
  check("gold only for a wiped enemy unit (wiped " + wiped.to_s + ", +" + ($game_party.gold - gold0).to_s + ", want " + gold_want.to_s + ")", $game_party.gold - gold0 == gold_want)
  other = b.instance_variable_get(:@units).find { |u| !u.player? and u != foe and !u.dead? }
  other = foe if other == nil and b.instance_variable_get(:@units).include?(foe)
  other.members.each { |m| m.hp = 1 }
  $data_enemies[other.members[0].id].gold = 7
  g0 = $game_party.gold
  other.members[0].hp = 0
  d = FE_Reward.give(pl[0], [], other.dead? ? [other] : [])
  check("enemy unit not wiped -> no gold, nothing to show", !other.dead? && $game_party.gold == g0 && d == nil)
  other.members.each { |m| m.hp = 0 }
  d = FE_Reward.give(pl[0], [], [other])
  check("enemy unit wiped -> gold of all 3 copies once (+" + ($game_party.gold - g0).to_s + ")", $game_party.gold - g0 == 7 * other.members.size && d["gold"] == 7 * other.members.size)
  b.instance_eval { kill_unit(other) }
  check("removing the unit adds no gold again", $game_party.gold - g0 == 7 * other.members.size)
  check("no EXP and no gold -> nothing to show", FE_Reward.give(pl[0], [], []) == nil)
  check("queue empty afterwards", !LevelUp.pending?)

  #=== 4 squad II with 3 members: leader falls -> next member leads ===========
  dispose_battle(b)
  $game_party.actors.each { |a| a.recover_all }
  extra = []
  for i in 1...$data_actors.size
    extra.push(i) if !$game_party.actors.include?($game_actors[i])
  end
  $game_party.add_actor(extra[0])
  $game_party.add_actor(extra[1])
  b = new_battle
  pl = b.instance_variable_get(:@units).select { |u| u.player? }
  u2 = pl[1]
  log("unit 2: " + names(u2.members))
  check("unit 2 has 3 members", u2.members.size == 3)
  u2.members[0].hp = 0
  u2.update
  check("leader fell: next member leads (" + u2.battler.name + ")", u2.battler.equal?(u2.members[1]))
  check("map sprite changed to the new leader", u2.character_name == u2.members[1].character_name)
  check("unit stays on the map", !u2.dead?)
  mv = u2.alive_members.collect { |m| FE_Squad.actor_move(m) }
  check("move = average of the living members", u2.move_points == FE_Squad.average(mv))
  u2.members.each { |m| m.hp = 0 }
  check("all members fell -> unit counts as dead (removed)", u2.dead?)
  b.instance_eval { kill_unit(u2) }
  check("unit removed from the map", !b.instance_variable_get(:@units).include?(u2))
  check("battle not over while others fight", !b.instance_eval { check_battle_end })

  #=== 5 main character falls -> Game Over ====================================
  $game_actors[FE_Config::MAIN_ACTOR_ID].hp = 0
  $scene = b
  b.instance_variable_set(:@can_lose, true)
  ended = b.instance_eval { check_battle_end }
  check("main character fell -> battle ends", ended)
  check("-> Game Over even if losing is allowed", $scene.is_a?(Scene_Gameover))
  check("party still complete after the battle", $game_party.actors.size == party_before.size + 2)
  dispose_battle(b)

  #=== 6 spells: award_exp for map kills ======================================
  $game_party.actors.each { |a| a.recover_all }
  b = new_battle
  pl = b.instance_variable_get(:@units).select { |u| u.player? }
  e = b.instance_variable_get(:@units).find { |u| !u.player? }
  x0 = pl[0].members.collect { |m| m.exp }
  FE_Reward.give(pl[0], e.members[0, 2], [])
  d = (0...pl[0].members.size).collect { |i| pl[0].members[i].exp - x0[i] }
  check("spell/item kills: EXP to the caster's squad " + d.inspect, d.uniq.size == 1 && d[0] == 2 * e.members[0].exp)
  LevelUp.queue.clear
  dispose_battle(b)
  #=== 7 <Squad N> markers =====================================================
  $game_actors[FE_Config::MAIN_ACTOR_ID].recover_all
  $game_party.actors.each { |x| x.recover_all }
  starts = $game_map.events.values.sort_by { |ev| ev.id }.select { |ev| ev.fe_name.include?("<start>") }
  names_set = ["<Squad 2>", "<Squad 1>", "<squad 1>", "<Squad 5>"]
  starts.each_with_index { |ev, i| ev.instance_variable_get(:@event).name = names_set[i] if names_set[i] }
  log("markers: " + starts.collect { |ev| ev.fe_name + "@" + ev.x.to_s + "," + ev.y.to_s }.join("  "))
  squads = $game_party.menu_groups
  b = new_battle
  pl = b.instance_variable_get(:@units).select { |u| u.player? }
  log("placed: " + pl.collect { |u| "[" + names(u.members) + "]@" + u.x.to_s + "," + u.y.to_s }.join("  "))
  check("deploy ok with <Squad N> markers", b.instance_variable_get(:@deploy_ok))
  check("Squad 1 on its <Squad 1> event (first one)", pl.find { |u| ids(u.members) == squads[0] }.x == starts[1].x && pl.find { |u| ids(u.members) == squads[0] }.y == starts[1].y)
  check("Squad 2 on its <Squad 2> event", pl.find { |u| ids(u.members) == squads[1] }.x == starts[0].x && pl.find { |u| ids(u.members) == squads[1] }.y == starts[0].y)
  check("duplicate <Squad 1> and <Squad 5> (no such squad) ignored -> " + pl.size.to_s + " units", pl.size == 2)
  check("marker events count as markers (not obstacles)", b.instance_eval { marker?(starts[2]) and marker?(starts[3]) })
  dispose_battle(b)
  starts.each_with_index { |ev, i| ev.instance_variable_get(:@event).name = (i == 0 ? "<Squad 2>" : "x") }
  b = new_battle
  pl = b.instance_variable_get(:@units).select { |u| u.player? }
  check("only <Squad 2> on the map -> only squad 2 placed", pl.size == 1 && ids(pl[0].members) == squads[1])
  check("main character not placed -> no Game Over check", !b.instance_variable_get(:@main_deployed))
  dispose_battle(b)
  #=== 8 pictures of the panel ===============================================
  def composite_sprites(list, file)
    canvas = Bitmap.new(640, 480)
    canvas.fill_rect(canvas.rect, Color.new(70, 90, 120))
    canvas.fill_rect(0, 320, 640, 160, Color.new(30, 30, 60))
    list = list.select { |s| s.visible and s.bitmap != nil and s.opacity > 0 }
    for s in list.sort_by { |s| s.z }
      r = s.src_rect
      dw = (r.width * s.zoom_x).round
      dh = (r.height * s.zoom_y).round
      canvas.stretch_blt(Rect.new((s.x - s.ox * s.zoom_x).round, (s.y - s.oy * s.zoom_y).round, dw, dh), s.bitmap, r, s.opacity)
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
  a1 = $game_actors[pl[0].members[0].id]
  a2 = $game_actors[pl[0].members[1].id]
  a3 = $game_actors[pl[0].members[2].id]
  [a1, a2, a3].each { |x| x.recover_all }
  a3.hp = 0
  rows = []
  [[a1, 250], [a2, 40], [a3, 0]].each do |x|
    m = x[0]
    r = { "actor" => m, "exp0" => m.exp, "lv0" => m.level, "dead" => m.dead?, "gain" => 0 }
    if !m.dead?
      m.exp += x[1]
      r["gain"] = m.exp - r["exp0"]
    end
    rows.push(r)
  end
  data = { "rows" => rows, "gold" => 21, "exp" => 250 }
  $press = []
  FE_Reward.trace = []
  pn = FE_Reward::Panel.new(data, :battle)
  20.times { pn.update }
  composite_sprites(pn.sprites, "out_1_filling.rgb")
  45.times { pn.update }
  composite_sprites(pn.sprites, "out_2_done.rgb")
  log("panel trace: " + FE_Reward.trace.join(" | "))
  check("panel waits for C after filling", !pn.done?)
  pn.dispose
  pn = FE_Reward::Panel.new(data, :map)
  70.times { pn.update }
  composite_sprites(pn.sprites, "out_3_map.rgb")
  pn.dispose
  #=== 9 <Enemy N> markers: Troop N as one unit, EXP once per enemy ==========
  $game_party.actors.each { |x| x.recover_all }
  evs = $game_map.events.values.sort_by { |ev| ev.id }
  starts = evs.select { |ev| ev.fe_name =~ /squad|start/i }
  starts.each_with_index { |ev, i| ev.instance_variable_get(:@event).name = (i == 0 ? "<Squad 1>" : "-") }
  foes_ev = evs.select { |ev| ev.fe_name.include?("<enemy>") }
  foes_ev[0].instance_variable_get(:@event).name = "<Enemy 1>"
  $data_enemies[$data_troops[1].members[0].enemy_id].battler_name = "does-not-exist"
  b = new_battle
  us = b.instance_variable_get(:@units)
  pl = us.select { |u| u.player? }
  en = us.select { |u| !u.player? }
  t1 = $data_troops[1].members.select { |m| !m.hidden and $data_enemies[m.enemy_id] != nil }
  log("<Enemy 1> unit: " + en.collect { |u| u.members.collect { |m| m.name }.join(",") + " sprite " + u.character_name }.join("  "))
  check("<Enemy 1> = all members of Troop 1 as one unit, no copies", en.size == 1 && en[0].members.size == t1.size)
  check("missing enemy graphic -> default graphic, no crash", en[0].character_name == FE_Config::DEFAULT_ENEMY_CHARSET[0])
  foe = en[0]
  foe.members.each { |m| m.hp = 0 }
  x0 = pl[0].members.collect { |m| m.exp }
  g0 = $game_party.gold
  d = FE_Reward.give(pl[0], foe.members, foe.dead? ? [foe] : [])
  want = foe.members.inject(0) { |t, m| t + m.exp }
  gw = foe.members.inject(0) { |t, m| t + m.gold }
  got = (0...pl[0].members.size).collect { |i| pl[0].members[i].exp - x0[i] }
  check("EXP: each defeated enemy once (" + foe.members.collect { |m| m.exp }.inspect + " -> " + got.inspect + ")", got.all? { |g| g == want })
  check("gold: each enemy of the troop once (+" + ($game_party.gold - g0).to_s + ")", $game_party.gold - g0 == gw)
  LevelUp.queue.clear
  # info window follows level / EXP changes
  w = b.instance_variable_get(:@info_window)
  w.unit = pl[0]
  s1 = w.instance_variable_get(:@sig)
  pl[0].members[0].exp += 500
  w.unit = pl[0]
  check("info window redraws after a level-up (Lv " + pl[0].members[0].level.to_s + ")", w.instance_variable_get(:@sig) != s1)
  LevelUp.queue.clear
  dispose_battle(b)
rescue Exception => e
  log("ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace[0, 12].join("\n"))
end
File.open("squad_log.txt", "w") { |f| f.write($log.join("\n")) }
exit
