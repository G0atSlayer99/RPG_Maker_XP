# Test script for a COPY of the project (replaces "Main" there): checks the
# class growth level-up rolls of the Attributes script, writes growth_log.txt.
log = []
def stats(a)
  return "Lv" + a.level.to_s + " hp" + a.maxhp.to_s + " sp" + a.maxsp.to_s + " str" + a.str.to_s +
    " mg" + a.int.to_s + " spd" + a.agi.to_s + " luck" + a.dex.to_s + " pdef" + a.pdef.to_s + " mdef" + a.mdef.to_s
end
begin
  $data_actors  = load_data("Data/Actors.rxdata")
  $data_classes = load_data("Data/Classes.rxdata")
  $data_skills  = load_data("Data/Skills.rxdata")
  $data_weapons = load_data("Data/Weapons.rxdata")
  $data_armors  = load_data("Data/Armors.rxdata")
  $data_states  = load_data("Data/States.rxdata")
  $data_system  = load_data("Data/System.rxdata")
  $game_temp = Game_Temp.new
  cfg = Attributes.config
  cfg["classes"] = {} unless cfg["classes"].is_a?(Hash)

  # 1 distribution of one roll with the defaults (KP 60/30 -> 10 % +0, 60 % +1, 30 % +2)
  srand(12345)
  n = [0, 0, 0]
  10000.times { n[Attributes.roll_growth(1, "hp")] += 1 }
  log << "KP 60/30 over 10000 rolls: +0=" + n[0].to_s + " +1=" + n[1].to_s + " +2=" + n[2].to_s
  n = [0, 0, 0]
  10000.times { n[Attributes.roll_growth(1, "mg")] += 1 }
  log << "Mg 20/0  over 10000 rolls: +0=" + n[0].to_s + " +1=" + n[1].to_s + " +2=" + n[2].to_s

  # 2 edited actor (actor 1), 10 level-ups
  a = Game_Actor.new(1)
  log << "actor1 start  " + stats(a) + "  growth=" + a.attr_growth.inspect
  a.exp += 1000
  log << "after +1000 EXP " + stats(a) + "  growth=" + a.attr_growth.inspect + " last=" + a.last_growth.inspect

  # 3 class values from the editor: class 2 Str 0/100 (always +2), Def 0/0 (never)
  cfg["classes"][2] = { "str_p1" => 0.0, "str_p2" => 100.0, "def_p1" => 0.0, "def_p2" => 0.0 }
  a.instance_variable_set(:@class_id, 2)
  before = [a.str, a.pdef]
  a.exp += 500
  log << "class 2, 5 level-ups: str " + before[0].to_s + " -> " + a.str.to_s + " (expect +10)   pdef " + before[1].to_s + " -> " + a.pdef.to_s + " (expect same)"

  # 4 caps: actor's max level value (str max 60) and global caps
  cfg["actors"][1]["hp_max"] = 20000.0
  a.level = 100
  log << "level 100: " + stats(a) + "  str<=60:" + (a.str <= 60).to_s + "  growth=" + a.attr_growth.inspect
  big = a.attr_value("hp")
  log << "hp value " + big.to_s + " (cap 10000), maxhp " + a.maxhp.to_s + " (RPG Maker cap 9999)"

  # 5 level down keeps the gains
  g = a.attr_growth["str"]
  a.level = 5
  log << "level down to 5: level " + a.level.to_s + " str gain kept " + (a.attr_growth["str"] == g).to_s

  # 6 save / load keeps the gains
  b = Marshal.load(Marshal.dump(a))
  log << "save/load: growth equal " + (b.attr_growth == a.attr_growth).to_s + "  str " + b.str.to_s + "=" + a.str.to_s

  # 7 actor not edited in the panel: Database curve, no rolls
  c = Game_Actor.new(2)
  s0 = stats(c)
  c.exp += 1000
  log << "actor2 (not edited): " + s0 + "  ->  " + stats(c) + "  growth=" + c.attr_growth.inspect

  # 8 recruit above level 1 gets its earlier level-ups
  cfg["actors"][1]["level"] = 10.0
  d = Game_Actor.new(1)
  log << "actor1 starting at Lv10: " + stats(d) + "  growth=" + d.attr_growth.inspect

  # 9 broken values in the file: p1 + p2 > 100 is trimmed to 100 %
  cfg["classes"][3] = { "hp_p1" => 80.0, "hp_p2" => 50.0 }
  log << "class 3 hp 80/50 read as " + Attributes.class_growth(3, "hp").inspect
rescue Exception => e
  log << "ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace.join("\n")
end
File.open("growth_log.txt", "w") { |f| f.write(log.join("\n")) }
exit
