# Test script for a COPY of the project (replaces "Main" there): every actor
# needs 100 EXP per level-up, and loading a save rebuilds the EXP tables and
# caps HP / SP. Writes exp_log.txt.
log = []
def check(log, name, ok)
  log << (ok ? "OK    " : "FAIL  ") + name
end
begin
  $data_actors  = load_data("Data/Actors.rxdata")
  $data_classes = load_data("Data/Classes.rxdata")
  $data_skills  = load_data("Data/Skills.rxdata")
  $data_items   = load_data("Data/Items.rxdata")
  $data_weapons = load_data("Data/Weapons.rxdata")
  $data_armors  = load_data("Data/Armors.rxdata")
  $data_enemies = load_data("Data/Enemies.rxdata")
  $data_troops  = load_data("Data/Troops.rxdata")
  $data_states  = load_data("Data/States.rxdata")
  $data_animations = load_data("Data/Animations.rxdata")
  $data_tilesets = load_data("Data/Tilesets.rxdata")
  $data_common_events = load_data("Data/CommonEvents.rxdata")
  $data_system  = load_data("Data/System.rxdata")
  $game_temp = Game_Temp.new
  $game_system = Game_System.new

  # 1 new game: every actor 100 EXP per level, up to its max level
  bad = []
  for id in 1...$data_actors.size
    next if $data_actors[id] == nil
    a = Game_Actor.new(id)
    list = a.instance_variable_get(:@exp_list)
    lv = Attributes.actor_level(id)
    max = lv ? lv[1] : $data_actors[id].final_level
    per = lv ? lv[2] : 100
    ok = (2..max).all? { |l| list[l] - list[l - 1] == per } && (max >= 100 || list[max + 1].to_i == 0)
    bad.push(id.to_s + " " + a.name) if !ok or per != 100
    log << "#{id} #{a.name} edited=#{Attributes.actor_edited?(id)} max Lv #{max}: Lv2 #{list[2]}, Lv3 #{list[3]}, Lv#{max} #{list[max]}, next #{list[max + 1].inspect}"
  end
  check(log, "every actor needs 100 EXP per level-up up to its max level" + (bad.empty? ? "" : " (not: " + bad.join(", ") + ")"), bad.empty?)
  c = Game_Actor.new(3)
  c.exp += 100
  check(log, "not edited actor: +100 EXP -> Lv 2 (Lv " + c.level.to_s + ")", c.level == 2)
  c.exp += 250
  check(log, "+250 more -> Lv 4 (Lv " + c.level.to_s + ")", c.level == 4)
  c.level = 99
  check(log, "max level from the Database (Lv " + c.level.to_s + ", EXP " + c.exp.to_s + ")", c.level == $data_actors[3].final_level)

  # 2 loading the old save: EXP tables rebuilt, HP / SP capped
  if FileTest.exist?("Save1.rxdata")
    File.open("Save1.rxdata", "rb") do |f|
      Scene_Load.new.read_save_data(f)
    end
    list = $game_actors.instance_variable_get(:@data).compact
    steps_ok = list.all? { |a| l = a.instance_variable_get(:@exp_list); l[2] - l[1] == 100 && l[3] - l[2] == 100 }
    check(log, "old save: every EXP table rebuilt to 100 per level", steps_ok)
    over = list.select { |a| a.hp > a.maxhp or a.sp > a.maxsp }
    check(log, "old save: no HP / SP above maximum (" + list.collect { |a| a.name + " " + a.hp.to_s + "/" + a.maxhp.to_s }.join(", ") + ")", over.empty?)
    inside = list.all? { |a| l = a.instance_variable_get(:@exp_list); a.exp >= l[a.level].to_i && (l[a.level + 1].to_i == 0 || a.exp < l[a.level + 1]) }
    check(log, "old save: EXP inside the current level", inside)
  else
    log << "no Save1.rxdata - load test skipped"
  end
rescue Exception => e
  log << "ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace[0, 8].join("\n")
end
File.open("exp_log.txt", "w") { |f| f.write(log.join("\n")) }
exit
