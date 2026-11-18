# Test script for a COPY of the project: replaces "Main" there.
# Draws the Status screen for several cases with the real RGSS engine and
# writes each 640x480 result as raw RGB (out_<case>.rgb), then quits.
log = []
def dump_bitmap(bmp, file)
  s = ""
  for y in 0...bmp.height
    Graphics.update if y % 60 == 0
    for x in 0...bmp.width
      c = bmp.get_pixel(x, y)
      s << [c.red.to_i, c.green.to_i, c.blue.to_i].pack("C3")
    end
  end
  File.open(file, "wb") { |f| f.write(s) }
end

begin
  $data_actors  = load_data("Data/Actors.rxdata")
  $data_classes = load_data("Data/Classes.rxdata")
  $data_skills  = load_data("Data/Skills.rxdata")
  $data_items   = load_data("Data/Items.rxdata")
  $data_weapons = load_data("Data/Weapons.rxdata")
  $data_armors  = load_data("Data/Armors.rxdata")
  $data_states  = load_data("Data/States.rxdata")
  $data_system  = load_data("Data/System.rxdata")
  $game_temp    = Game_Temp.new
  $game_system  = Game_System.new
  $game_actors  = Game_Actors.new
  $game_party   = Game_Party.new
  log << "font: " + StatusBook.font_name
  bmp = Bitmap.new(640, 480)
  painter = StatusBook::Painter.new(bmp)
  cases = []

  # 1 reference actor (values of the reference picture)
  a = Game_Actor.new(1)
  a.name = "Aluxes"
  a.instance_variable_set(:@class_id, 1)
  a.instance_variable_set(:@level, 1)
  a.instance_variable_set(:@exp_list, [0, 0] + (1..99).collect { |i| i * 100 } + [0])
  a.instance_variable_set(:@exp, 0)
  vals = { "maxhp" => 30, "maxsp" => 10, "str" => 5, "int" => 2, "agi" => 5, "dex" => 3,
           "pdef" => 4, "mdef" => 2, "attr_move" => 4, "crit_rate" => 5, "crit_damage" => 100 }
  vals.each { |k, v| eval("def a.#{k}; #{v}; end") }
  a.hp = 30
  a.sp = 10
  cases << ["reference", a]

  # 2 every actor of the database as it is
  for id in 1...$data_actors.size
    cases << ["actor%d" % id, Game_Actor.new(id)]
  end

  # 3 poisoned
  a = Game_Actor.new(2)
  a.add_state(3)
  cases << ["poisoned", a]
  # 4 knocked out, 0 HP
  a = Game_Actor.new(3)
  a.hp = 0
  cases << ["ko_0hp", a]
  # 5 good state
  a = Game_Actor.new(4)
  a.add_state(14)
  cases << ["barrier", a]
  # 6 accessory equipped
  a = Game_Actor.new(5)
  a.instance_variable_set(:@armor4_id, 25)
  cases << ["accessory", a]
  # 7 long name, long item name, long class name
  a = Game_Actor.new(6)
  a.name = "Maximilian von Sturmfels"
  a.instance_variable_set(:@armor4_id, 26)
  w = $data_weapons[a.weapon_id].clone
  w.name = "Legendary Dragonslayer Greatsword of Dawn"
  $data_weapons[99] = w
  a.instance_variable_set(:@weapon_id, 99)
  cases << ["long_names", a]
  # 8 level 100
  a = Game_Actor.new(1)
  a.level = 100
  cases << ["level100", a]
  # 9 no equipment
  a = Game_Actor.new(7)
  for v in [:@weapon_id, :@armor1_id, :@armor2_id, :@armor3_id, :@armor4_id]
    a.instance_variable_set(v, 0)
  end
  cases << ["no_equipment", a]
  # 10 big crit values
  a = Game_Actor.new(8)
  a.crit_rate_plus = 57.5
  a.crit_damage_plus = 50
  cases << ["crit", a]

  for c in cases
    t = Time.now
    painter.draw(c[1])
    dump_bitmap(bmp, "out_" + c[0] + ".rgb")
    log << c[0] + ": ok (" + ((Time.now - t) * 1000).round.to_s + " ms)  " + c[1].name + " Lv" + c[1].level.to_s
  end
  # L/R in the scene
  log << "Scene_Status responds: " + Scene_Status.new(0).respond_to?(:main).to_s
rescue Exception => e
  log << "ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace.join("\n")
end
File.open("render_log.txt", "w") { |f| f.write(log.join("\n")) }
exit
