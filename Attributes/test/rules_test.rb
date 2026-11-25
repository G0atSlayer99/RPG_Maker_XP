# Test script for a COPY of the project (replaces "Main" there): battle rules
# of Attributes v2.4 and the enemy panel values. Writes rules_log.txt.
# Values set here only exist in this test.
$log = []
def log(s); $log.push(s); end
def check(name, ok); log((ok ? "OK    " : "FAIL  ") + name); end
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
  $game_temp = Game_Temp.new; $game_system = Game_System.new
  $game_switches = Game_Switches.new; $game_variables = Game_Variables.new
  $game_self_switches = Game_SelfSwitches.new; $game_screen = Game_Screen.new
  $game_actors = Game_Actors.new; $game_party = Game_Party.new
  $game_troop = Game_Troop.new; $game_map = Game_Map.new; $game_player = Game_Player.new
  $game_party.setup_starting_members
  cfg = Attributes.config
  cfg["enemies"] = {} unless cfg["enemies"].is_a?(Hash)
  dieb = $data_troops[1].members[0].enemy_id
  cfg["enemies"][dieb] = { "hp" => 20.0, "hp_max" => 200.0, "sp" => 0.0, "sp_max" => 0.0,
    "str" => 10.0, "str_max" => 30.0, "mg" => 1.0, "mg_max" => 1.0, "spd" => 4.0, "spd_max" => 40.0,
    "luck" => 2.0, "luck_max" => 2.0, "def" => 3.0, "def_max" => 12.0, "res" => 1.0, "res_max" => 1.0,
    "move" => 6.0, "move_max" => 6.0, "crit_rate" => 0.0, "crit_rate_max" => 0.0,
    "crit_damage" => 100.0, "crit_damage_max" => 100.0, "max_level" => 10.0,
    "exp" => 35.0, "gold" => 12.0, "size" => 2.0 }
  a = $game_actors[1]
  log("Aluxes: Str #{a.str} Mg #{a.int} Def #{a.pdef} Res #{a.mdef} Spd #{a.agi} Luck #{a.luck} CrtR #{a.crit_rate} CrtD #{a.crit_damage}")

  #=== 1 enemy values from the panel, by level ================================
  e = Game_Enemy.new(1, 0)
  check("enemy Lv1: HP 20, Str 10, Def 3 (#{e.maxhp}, #{e.str}, #{e.pdef})", e.maxhp == 20 && e.str == 10 && e.pdef == 3)
  e.level = 4
  check("enemy Lv4: HP 20+180*3/9=80, Str 16, Def 6, Spd 16 (#{e.maxhp}, #{e.str}, #{e.pdef}, #{e.agi}); HP refilled #{e.hp}", e.maxhp == 80 && e.str == 16 && e.pdef == 6 && e.agi == 16 && e.hp == 80)
  e.level = 10
  check("enemy Lv10 = max values (HP #{e.maxhp}, Str #{e.str})", e.maxhp == 200 && e.str == 30)
  e.level = 50
  check("enemy above its max level stays at max (HP #{e.maxhp})", e.maxhp == 200)
  check("enemy EXP / Gold / Size / Move from the panel (#{e.exp}, #{e.gold}, #{e.attr_size}, #{e.attr_move})", e.exp == 35 && e.gold == 12 && e.attr_size == 2 && e.attr_move == 6)
  u = Game_Enemy.new(1, 0)
  cfg["enemies"].delete(dieb)
  check("enemy not edited: Database values (HP #{u.maxhp} = #{$data_enemies[dieb].maxhp})", u.maxhp == $data_enemies[dieb].maxhp && u.exp == $data_enemies[dieb].exp)
  cfg["enemies"][dieb] = { "hp" => 20.0, "hp_max" => 200.0, "str" => 10.0, "str_max" => 30.0,
    "luck" => 2.0, "luck_max" => 2.0, "def" => 3.0, "def_max" => 12.0, "spd" => 4.0, "spd_max" => 40.0,
    "move" => 6.0, "crit_rate" => 0.0, "crit_damage" => 100.0, "max_level" => 10.0, "exp" => 35.0, "gold" => 12.0, "size" => 2.0 }
  e = Game_Enemy.new(1, 0)

  #=== 2 attack: Str - Def, hit 100 + Luck - Luck, no spread ==================
  a.crit_rate_plus = -1000                  # CrtR 0 (Luck still adds its %)
  srand(3)
  dmg = []
  200.times { e.hp = e.maxhp; e.attack_effect(a); dmg.push(e.damage) if !e.critical }   # Luck still gives a few crits
  want = [a.str - e.pdef, 0].max
  check("attack damage = Str - Def = #{want}, always (no spread, no misses at hit #{a.hit_chance_on(e)} %): #{dmg.uniq.inspect}", dmg.uniq == [want])
  check("hit chance = 100 + #{a.luck} - #{e.luck} = #{a.hit_chance_on(e)}", a.hit_chance_on(e) == 100 + a.luck - e.luck)
  e.hp = e.maxhp
  e.attack_effect(a)
  check("enemy HP after one hit = max - damage (#{e.hp})", e.hp == e.maxhp - want)
  # evasion
  cfg["enemies"][dieb]["luck"] = 40.0; cfg["enemies"][dieb]["luck_max"] = 40.0
  hc = a.hit_chance_on(e)
  miss = 0
  4000.times { e.hp = e.maxhp; e.attack_effect(a); miss += 1 if e.damage == "Miss" }
  check("Luck as evasion: hit #{hc} % -> misses #{miss * 100 / 4000} % (expected about #{100 - hc} %)", hc == 100 + a.luck - 40 && (miss * 100 / 4000 - (100 - hc)).abs <= 3)
  cfg["enemies"][dieb]["luck"] = 2.0; cfg["enemies"][dieb]["luck_max"] = 2.0
  # zero damage
  strong = Game_Enemy.new(1, 0)
  cfg["enemies"][dieb]["def"] = 99.0; cfg["enemies"][dieb]["def_max"] = 99.0
  strong.attack_effect(a)
  check("Str below Def -> 0 damage (#{strong.damage.inspect})", strong.damage == 0)
  cfg["enemies"][dieb]["def"] = 3.0; cfg["enemies"][dieb]["def_max"] = 12.0

  #=== 3 crits: CrtR + Luck, x CrtD ===========================================
  a.crit_rate_plus = 0
  check("crit chance = CrtR + Luck (#{a.crit_rate} + #{a.luck} = #{a.crit_chance})", a.crit_chance == [a.crit_rate + a.luck, 100].min)
  n = 0; tries = 4000
  tries.times { e.hp = e.maxhp; e.attack_effect(a); n += 1 if e.critical }
  check("crit rate in practice #{n * 100 / tries} % (expected #{a.crit_chance} %)", (n * 100 / tries - a.crit_chance).abs <= 3)
  a.crit_rate_plus = 1000
  e.hp = e.maxhp; e.attack_effect(a)
  check("crit damage = (Str - Def) x CrtD: #{want} x #{(100 + a.crit_damage) / 100.0} = #{e.damage}", e.critical && e.damage == (want * (100 + a.crit_damage) / 100.0).round)
  a.crit_rate_plus = 0
  check("enemies crit the same way (CrtR + Luck = #{e.crit_chance})", e.crit_chance == [e.crit_rate + e.luck, 100].min)
  check("defender's Luck does not lower crits", a.crit_chance == a.crit_chance)

  #=== 4 guard removed, turn order ============================================
  check("nobody guards", !a.guarding? && !e.guarding?)
  $game_troop.setup(1)
  sb = Scene_Battle.new
  sb.instance_eval { make_action_orders }
  order = sb.instance_variable_get(:@action_battlers)
  log("turn order: " + order.collect { |b| b.name + "(Spd #{b.agi}, Luck #{b.luck})" }.join(" > "))
  ok = true
  for i in 1...order.size
    x = order[i - 1]; y = order[i]
    ok = false if x.agi < y.agi
    ok = false if x.agi == y.agi and x.luck < y.luck
    ok = false if x.agi == y.agi and x.luck == y.luck and x.is_a?(Game_Enemy) and y.is_a?(Game_Actor)
  end
  check("turn order: Spd, then Luck, then actors first", ok)
  if defined?(BattleUI)   # script "Battle UI" has its own command window
    cmds = BattleUI::COMMANDS
    check("actor commands without Guard (Battle UI): " + cmds.inspect, !cmds.include?($data_system.words.guard) && !cmds.include?("Guard"))
  else
    sb.instance_variable_set(:@actor_command_window, Window_Command.new(160, ["Attack", "Skill", "Guard", "Item"]))
    sb.instance_variable_set(:@party_command_window, Window_PartyCommand.new)
    sb.instance_variable_set(:@actor_index, 0)
    sb.instance_eval { phase3_setup_command_window }
    cmds = sb.instance_variable_get(:@actor_command_window).instance_variable_get(:@commands)
    check("actor commands without Guard: " + cmds.inspect, cmds.size == 3 && !cmds.include?($data_system.words.guard))
    sb.instance_variable_get(:@actor_command_window).dispose
    sb.instance_variable_get(:@party_command_window).dispose
  end

  #=== 5 equipment ignored for edited actors ==================================
  d0 = a.pdef; c0 = a.crit_rate
  arm = (1...$data_armors.size).find { |i| $data_armors[i] != nil and $data_armors[i].pdef > 0 }
  a.instance_variable_set(:@armor1_id, arm) if arm
  check("armor does not change Def (#{d0} -> #{a.pdef})", a.pdef == d0)

  #=== 6 FE Tactics: same formulas, <Enemy N LvX>, size, move =================
  check("FE forecast damage = battle damage", FE_Combat.damage(a, e) == a.attack_damage_to(e))
  check("FE forecast hit = battle hit (max 100)", FE_Combat.hit(a, e) == [a.hit_chance_on(e), 100].min)
  tag = FE_Config::ENEMY_N_TAG
  r1 = ("<Enemy 1 Lv5>" =~ tag) ? [$1, $2] : nil
  r2 = ("<enemy 1 Lvl5>" =~ tag) ? [$1, $2] : nil
  r3 = ("<Enemy 2>" =~ tag) ? [$1, $2] : nil
  r4 = ("<Enemy 3 Level 12>" =~ tag) ? [$1, $2] : nil
  check("markers: <Enemy 1 Lv5> #{r1.inspect}, <enemy 1 Lvl5> #{r2.inspect}, <Enemy 2> #{r3.inspect}, <Enemy 3 Level 12> #{r4.inspect}",
    r1 == ["1", "5"] && r2 == ["1", "5"] && r3 == ["2", nil] && r4 == ["3", "12"])
  $game_map.setup(2)
  fb = Scene_FEBattle.new(1)
  list = fb.instance_eval { troop_unit(1, 4) }
  check("<Enemy 1 Lv4>: every enemy of the troop at level 4 (#{list.collect { |x| x.level }.inspect}, HP #{list.collect { |x| x.hp }.inspect})",
    list.all? { |x| x.level == 4 } && list[0].hp == 80)
  unit = Game_FEUnit.new(list, :enemy, 3, 3)
  check("FE size from the panel: #{unit.size} (big #{unit.big?})", unit.size == 2 && unit.big?)
  check("FE enemy move from the panel: #{unit.move_points}", unit.move_points == 6)
  cfg["enemies"][dieb]["size"] = 1.0
  check("size 1 -> normal unit", Game_FEUnit.new(fb.instance_eval { troop_unit(1, 1) }, :enemy, 3, 3).size == 1)
rescue Exception => ex
  log("ERROR " + ex.class.to_s + ": " + ex.message + "\n" + ex.backtrace[0, 8].join("\n"))
end
File.open("rules_log.txt", "w") { |f| f.write($log.join("\n")) }
exit
