#==============================================================================
# ** FE Tactics for RPG Maker XP (RGSS1)  -  v1.0  (core loop)
#------------------------------------------------------------------------------
#  Fire Emblem-style grid combat that plays out directly on your map.
#
#  INSTALL
#    Script Editor (F11) -> right-click "Main" -> Insert -> name it
#    "FE Tactics" -> paste this whole file. It must sit ABOVE Main.
#
#  MAP SETUP
#    1. Build the battlefield as a normal map.
#    2. Create an event named  <start>  on every tile where a party member
#       may deploy. Party order is matched to <start> events by event ID.
#    3. Create an event named  <enemy>  on every tile where a troop member
#       spawns. Troop member order is matched to <enemy> events by event ID.
#       Marker events can be completely blank (no graphic, no commands).
#    4. Big enemies (Gold = BIG_ENEMY_GOLD) cover BIG_ENEMY_ZOOM x
#       BIG_ENEMY_ZOOM tiles. Their <enemy> marker is the TOP-LEFT tile of
#       that square; keep the rest of the square free and walkable.
#
#  START A BATTLE  (event command "Script", on the battle map)
#       fe_battle(3)          # fight Troop 3, losing = Game Over
#       fe_battle(3, true)    # losing allowed (check RESULT_VARIABLE after)
#
#  CONTROLS
#    Arrows ......... move cursor
#    C (Enter/Space)  select unit / confirm
#    B (Esc/X) ...... cancel; after moving, undo the move
#    A (Shift) ...... jump to the next unit that hasn't acted
#    C on an enemy .. toggle that enemy's move + attack range
#    C on empty tile  map menu (End Turn)
#
#  STACKS & COMBAT (v2.0, Bahamut Lagoon style)
#    Every unit on the map is a STACK of STACK_SIZE battlers:
#      party member -> the actor itself + (STACK_SIZE - 1) temporary copies
#      troop member -> STACK_SIZE copies of that enemy
#    Each member has its own HP/SP/states for the whole map battle. The map
#    HP bar is the average HP % of all members (dead ones count as 0 %).
#    Hover a stack to see its members. A stack falls when all members fall.
#    After the map battle only the real actor is kept; the copies vanish.
#
#    "Attack" opens the default RMXP battle screen: the player stack vs the
#    enemy stack. Both sides always fight, whoever started it. You pick
#    commands for your members; turn order is RMXP's speed order. After
#    BATTLE_ROUNDS rounds (or when one side is wiped out) it returns to the
#    map. No escape, no EXP/gold/drops, troop battle events don't run.
#    States marked "release at end of battle" are removed after each fight.
#
#  MAGIC (v1.1)
#    After moving, choose "Magic" to cast any skill the unit knows (actors:
#    learned skills; enemies: skills in their database action list).
#    The first living member casts and pays the SP. Map spells hit EVERY
#    living member of the target stack (damage and healing alike), without
#    opening the battle screen and without a counterattack.
#    Spells use RMXP's skill formula (power, atk_f, int_f, ...).
#    Negative power heals. Skill states are applied (poison, sleep, buffs...):
#      - stat changes from states work automatically
#      - slip damage (poison) only hurts in the battle screen
#      - a stack whose living members all "Can't Move" skips its map turn
#      - "Can't Use Magic" disables skills whose atk_f is 0
#      - states wear off per the database release settings
#    Scope:  one enemy / one ally / user = single target
#            all enemies / all allies = everyone on that side within
#            AREA_RADIUS tiles of the chosen target
#            (scopes that revive fallen allies are not usable on the map)
#
#  RANGE & AREA OF EFFECT (v1.3, needs the "Attributes" script)
#    Set per skill in the Attributes panel next to the Database (Skills tab):
#      Custom range ... min/max tiles; overrides SKILL_RANGE / SPELL_RANGE
#      Targeting ...... Default       = scope rules above
#                       Single target = one unit, even for "All" scopes
#                       Area of effect = the player moves a cursor to any
#                         tile in range; every unit in the area around it
#                         is hit (square / diamond / cross, radius 1 = 3x3).
#                         Friendly fire: hits every unit in the area, else
#                         only the skill's side (foes for damage spells).
#      Critical hits .. map spells can crit like in the battle screen.
#    Without the Attributes script everything works as before.
#
#  ITEMS (v1.2)
#    After moving, choose "Item" to use a consumable from the party bag
#    (shared, RMXP-style). Only items the party owns and whose occasion is
#    "Always" or "Only in battle" are listed. HP/SP recovery (rate + fixed),
#    states, element rates, hit rate and stat-boost parameters all follow the
#    database; consumable items are removed from the bag. Like spells, an
#    item affects every living member of the target stack. Common events and
#    revive-type scopes are not used on the map. Enemies don't use items.
#      one ally / all allies / user -> ally items, reach ITEM_ALLY_RANGE
#      one enemy / all enemies      -> thrown items, reach ITEM_FOE_RANGE
#
#  FORMULAS
#    Weapon fights use the default RMXP battle system as-is. FE_Combat only
#    holds RMXP's formulas without variance, used for map spells/items and
#    for the enemy AI's estimates.
#==============================================================================

module FE_Config
  #--- Movement ---------------------------------------------------------------
  DEFAULT_MOVE = 5
  ACTOR_MOVE   = {}     # { class_id => move }        e.g. { 1 => 5, 4 => 7 }
  ENEMY_MOVE   = {}     # { enemy_id => move }        e.g. { 2 => 4 }
  TERRAIN_COST = {}     # { terrain_tag => move cost } e.g. { 1 => 2 } forest
  #--- Attack range [min, max] in tiles ---------------------------------------
  DEFAULT_RANGE = [1, 1]
  WEAPON_RANGE  = {}    # { weapon_id => [min, max] } e.g. { 17 => [2, 2] } bow
  ENEMY_RANGE   = {}    # { enemy_id  => [min, max] } e.g. { 5 => [1, 2] }
  #--- Enemy map graphics -----------------------------------------------------
  ENEMY_CHARSET = {}    # { enemy_id => ["Character file", hue] }
  DEFAULT_ENEMY_CHARSET = ["001-Fighter01", 180]
  BIG_ENEMY_GOLD = 1    # enemies whose database Gold is exactly this are big
  BIG_ENEMY_ZOOM = 2    # whole number: sprite scale AND footprint (2 = 2x2 tiles)
  #--- Enemy AI -----------------------------------------------------------------
  #  :charge  attack if it can, otherwise march toward the nearest target
  #  :guard   attack anything reachable this turn, otherwise stay put
  #  :hold    never moves, only attacks what is already in range
  DEFAULT_AI = :charge
  ENEMY_AI   = {}       # { enemy_id => :guard }
  #--- Stacks & battle screen ---------------------------------------------------
  STACK_SIZE    = 3     # battlers per map unit (max 4: the battle screen shows 4)
  BATTLE_ROUNDS = 1     # rounds per fight in the battle screen
  #--- Magic --------------------------------------------------------------------
  SPELL_RANGE   = [1, 2]  # default range of spells that target foes
  SUPPORT_RANGE = [0, 1]  # default range of spells that target allies (0 = self)
  SKILL_RANGE   = {}      # { skill_id => [min, max] }  e.g. { 7 => [1, 3] }
  AREA_RADIUS   = 1       # radius of "all enemies"/"all allies" skills
  ENEMY_MAGIC   = true    # enemies use the skills in their action list
  #--- Items ----------------------------------------------------------------------
  ITEM_ALLY_RANGE = [0, 1]  # potions etc.: self (0) or an adjacent ally (1)
  ITEM_FOE_RANGE  = [1, 2]  # items that target enemies (bombs, ...)
  ITEM_RANGE      = {}      # { item_id => [min, max] }
  #--- Battle rules -----------------------------------------------------------
  LORD_ACTOR_ID   = nil   # battle is lost if this actor falls (nil = off)
  REVIVE_AFTER    = true  # fallen actors return with 1 HP after the battle
  RESULT_VARIABLE = 0     # variable set to 0 = victory, 2 = defeat (0 = off)
  AUTO_END_TURN   = true  # end player phase when every unit has acted
  PLAY_BATTLE_BGM = true  # play the database battle BGM during the fight
  SHOW_HP_BARS    = true  # small HP bar above every unit on the map
  UNIT_SPEED      = 5     # unit walking speed on the map (1-6)
  #--- Event name tags --------------------------------------------------------
  START_TAG = "<start>"
  ENEMY_TAG = "<enemy>"
  #--- Text -------------------------------------------------------------------
  TEXT_ATTACK   = "Attack"
  TEXT_MAGIC    = "Magic"
  TEXT_ITEM     = "Item"
  TEXT_WAIT     = "Wait"
  TEXT_END_TURN = "End Turn"
  TEXT_CANCEL   = "Cancel"
  TEXT_PLAYER   = "Player Phase"
  TEXT_ENEMY    = "Enemy Phase"
  TEXT_VICTORY  = "Victory!"
  TEXT_DEFEAT   = "Defeat..."
end

#==============================================================================
# ** FE_Combat - combat math (edit here to change formulas)
#==============================================================================
module FE_Combat
  module_function
  def damage(a, b)
    power = [a.atk - b.pdef / 2, 0].max
    dmg = power * (20 + a.str) / 20
    dmg = dmg * b.elements_correct(a.element_set) / 100
    return [dmg, 0].max
  end
  def hit(a, b)
    return 100 if b.cant_evade?
    eva = 8 * b.agi / [a.dex, 1].max + b.eva
    return [[a.hit * (100 - eva) / 100, 0].max, 100].min
  end
  # RMXP skill formula without random variance. Negative result = healing.
  def skill_damage(a, b, s)
    power = s.power + a.atk * s.atk_f / 100
    if power > 0
      power -= b.pdef * s.pdef_f / 200
      power -= b.mdef * s.mdef_f / 200
      power = [power, 0].max
    end
    rate = 20
    rate += a.str * s.str_f / 100
    rate += a.dex * s.dex_f / 100
    rate += a.agi * s.agi_f / 100
    rate += a.int * s.int_f / 100
    dmg = power * rate / 20
    return dmg * b.elements_correct(s.element_set) / 100
  end
  def skill_hit(a, b, s)
    h = s.hit
    h = h * a.hit / 100 if s.atk_f > 0
    if skill_damage(a, b, s) >= 0 and !b.cant_evade?
      eva = 8 * b.agi / [a.dex, 1].max + b.eva
      h = h * (100 - eva * s.eva_f / 100) / 100
    end
    return [[h, 0].max, 100].min
  end
end

module FE_Combat
  module_function
  # RMXP item formula (no variance). Positive = recovery, negative = damage.
  def item_hp(b, it)
    r = b.maxhp * it.recover_hp_rate / 100 + it.recover_hp
    if r < 0
      r += b.pdef * it.pdef_f / 20
      r += b.mdef * it.mdef_f / 20
      r = [r, 0].min
    end
    return r * b.elements_correct(it.element_set) / 100
  end
  def item_sp(b, it)
    r = b.maxsp * it.recover_sp_rate / 100 + it.recover_sp
    return r * b.elements_correct(it.element_set) / 100
  end
end

#==============================================================================
# ** FE_Spell - which skills work on the map, and how they target
#==============================================================================
module FE_Spell
  module_function
  def offensive?(s); return (s.scope == 1 or s.scope == 2);                   end
  def support?(s);   return (s.scope == 3 or s.scope == 4 or s.scope == 7);   end
  # Value set in the Attributes panel (nil = not set or no Attributes script).
  def attr_value(s, key)
    return nil unless defined?(Attributes) and s.is_a?(RPG::Skill)
    return Attributes.get("skills", s.id, key)
  end
  # Classic area: "All ..." scope around the chosen unit (no targeting set).
  def area?(s)
    return false if attr_value(s, "aoe") != nil
    return (s.scope == 2 or s.scope == 4)
  end
  # Tile-aimed area of effect: [radius, shape, friendly_fire] or nil.
  # shape: 0 square, 1 diamond, 2 cross
  def aoe(s)
    return nil unless attr_value(s, "aoe") == true
    return [[attr_value(s, "aoe_radius").to_i, 0].max,
            attr_value(s, "aoe_shape").to_i, attr_value(s, "friendly_fire") == true]
  end
  def in_area?(cx, cy, tx, ty, a)
    dx = (tx - cx).abs
    dy = (ty - cy).abs
    return dx + dy <= a[0] if a[1] == 1
    return ((dx == 0 or dy == 0) and dx + dy <= a[0]) if a[1] == 2
    return (dx <= a[0] and dy <= a[0])
  end
  def area_tiles(cx, cy, a)
    list = []
    for x in (cx - a[0])..(cx + a[0])
      for y in (cy - a[0])..(cy + a[0])
        list.push([x, y]) if in_area?(cx, cy, x, y, a)
      end
    end
    return list
  end
  # Steps the area reaches past its center (for the danger zone display).
  def area_reach(a)
    return (a[1] == 0) ? a[0] * 2 : a[0]
  end
  def map_usable?(s)
    return false unless offensive?(s) or support?(s)
    return (s.occasion == 0 or s.occasion == 1)
  end
end

#==============================================================================
# ** FE_Grid - footprint geometry (units are n x n squares, (x, y) = top-left)
#==============================================================================
module FE_Grid
  module_function
  # Tiles covered by an n x n unit whose top-left tile is (x, y).
  def tiles(x, y, n)
    list = []
    for i in 0...n
      for j in 0...n
        list.push([x + i, y + j])
      end
    end
    return list
  end
  # [closest, farthest] tile-to-tile distance between two squares.
  def span(ax, ay, an, bx, by, bn)
    ax2 = ax + an - 1; ay2 = ay + an - 1
    bx2 = bx + bn - 1; by2 = by + bn - 1
    near = [bx - ax2, ax - bx2, 0].max + [by - ay2, ay - by2, 0].max
    far  = [ax2 - bx, bx2 - ax].max + [ay2 - by, by2 - ay].max
    return [near, far]
  end
  # True if any tile of square A is within range [min, max] of any tile of B.
  def in_reach?(ax, ay, an, bx, by, bn, rng)
    s = span(ax, ay, an, bx, by, bn)
    return (s[0] <= rng[1] and s[1] >= rng[0])
  end
end

#==============================================================================
# ** FE_Draw - small drawing helpers
#==============================================================================
module FE_Draw
  module_function
  def team_color(unit)
    return unit.player? ? Color.new(140, 190, 255) : Color.new(255, 130, 130)
  end
  def draw_bar(bmp, x, y, w, cur, max, h = 6, col = nil)
    bmp.fill_rect(x, y, w, h, Color.new(0, 0, 0, 180))
    return if max <= 0
    fw = (w - 2) * cur / max
    col ||= (cur * 4 <= max) ? Color.new(255, 96, 64) : Color.new(96, 224, 96)
    bmp.fill_rect(x + 1, y + 1, fw, h - 2, col) if fw > 0
  end
end

#==============================================================================
# ** Small hooks into default classes
#==============================================================================
class Game_Event < Game_Character
  def fe_name
    return @event.name
  end
end

class Spriteset_Map
  attr_reader :viewport1, :viewport2, :viewport3
end

# Lets the battle screen use a stack's members as the party / the troop.
class Game_Party
  def fe_actors=(list)
    @actors = list
  end
end

class Game_Troop
  attr_accessor :fe_stack
  alias fe_tactics_setup setup
  def setup(troop_id)
    if @fe_stack != nil
      @enemies = @fe_stack
      return
    end
    fe_tactics_setup(troop_id)
  end
  def fe_release
    @fe_stack = nil
    @enemies = []
  end
end

# One enemy inside a stack. Copies of the same troop member share the
# database position, so the battle screen gives each its own slot and index.
class Game_FEEnemy < Game_Enemy
  attr_accessor :fe_index, :fe_x, :fe_y
  def index;    return @fe_index;      end
  def screen_x; return @fe_x || super; end
  def screen_y; return @fe_y || super; end
end

#==============================================================================
# ** Scene_FESkirmish - default RMXP battle screen for one map fight
#     Runs nested inside Scene_FEBattle; when it finishes, control goes
#     straight back to the map. No party command (Fight/Escape), no troop
#     battle events, no victory rewards, no game over.
#==============================================================================
class Scene_FESkirmish < Scene_Battle
  def initialize(map_scene)
    @fe_map_scene = map_scene
    @fe_done = false
  end

  def setup_battle_event
  end

  # Start of every turn: stop after BATTLE_ROUNDS, otherwise skip straight
  # to the actor commands.
  def start_phase2
    if $game_temp.battle_turn >= FE_Config::BATTLE_ROUNDS
      fe_finish
      return
    end
    super
    if @phase == 2
      @party_command_window.active = false
      @party_command_window.visible = false
      start_phase3
    end
  end

  def judge
    if $game_party.all_dead? or $game_troop.enemies.find { |e| e.exist? } == nil
      fe_finish
      return true
    end
    return false
  end

  def start_phase5
    fe_finish
  end

  def battle_end(result)
    fe_finish
  end

  def fe_finish
    return if @fe_done
    @fe_done = true
    $game_temp.in_battle = false
    $game_temp.battle_main_phase = false
    ($game_party.actors + $game_troop.enemies).each do |b|
      b.current_action.clear
      b.blink = false
      b.remove_states_battle
    end
    $scene = @fe_map_scene
  end
end

class Interpreter
  # Script call:  fe_battle(troop_id)  or  fe_battle(troop_id, true)
  def fe_battle(troop_id, can_lose = false)
    $scene = Scene_FEBattle.new(troop_id, can_lose)
    @wait_count = 1   # make the event pause until the battle is over
    return true
  end
end

#==============================================================================
# ** Game_FEUnit - one unit standing on the battle map
#==============================================================================
class Game_FEUnit < Game_Character
  attr_reader   :members, :team, :size
  attr_accessor :acted, :sprite, :hp_bar
  attr_writer   :opacity, :direction

  # members: the battlers in this stack (Game_Actor or Game_FEEnemy).
  def initialize(members, team, x, y)
    super()
    @members = members
    battler  = members[0]
    @team    = team
    @acted   = false
    @sprite  = nil
    @path    = []
    @through = true
    @move_speed = FE_Config::UNIT_SPEED
    @step_anime = true
    if actor?
      @character_name = battler.character_name
      @character_hue  = battler.character_hue
    else
      @character_name = battler.battler_name
      @character_hue  = battler.battler_hue
    end
    @size = big? ? [FE_Config::BIG_ENEMY_ZOOM.to_i, 1].max : 1
    moveto(x, y)
    @direction = player? ? 8 : 2
  end

  #--- Stack -----------------------------------------------------------------
  # Stand-in for the whole stack (name, move, range, map spells): the first
  # living member, or the first member if all are down.
  def battler
    return (@members.find { |m| !m.dead? } || @members[0])
  end

  def alive_members; return @members.select { |m| !m.dead? };          end
  def total_hp;      return @members.inject(0) { |t, m| t + m.hp };    end

  # Average HP % over all members (fallen members count as 0 %).
  def hp_rate
    sum = 0
    @members.each { |m| sum += m.hp * 100 / [m.maxhp, 1].max }
    return sum / [@members.size, 1].max
  end

  # True if every living member is under a "Can't Move" state.
  def stuck?
    list = alive_members
    return (!list.empty? and list.find { |m| m.restriction != 4 } == nil)
  end

  def actor?;  return @members[0].is_a?(Game_Actor);       end
  def player?; return @team == :player;                    end
  def dead?;   return @members.find { |m| !m.dead? } == nil; end
  def idle=(b); @step_anime = b;                           end

  # Enemies with exactly BIG_ENEMY_GOLD gold in the database are big.
  def big?
    return (!actor? and battler.gold == FE_Config::BIG_ENEMY_GOLD)
  end

  # Tiles this unit covers when its top-left tile is (x, y).
  def tiles(x = @x, y = @y)
    return FE_Grid.tiles(x, y, @size)
  end

  def covers?(tx, ty)
    return (tx >= @x and ty >= @y and tx < @x + @size and ty < @y + @size)
  end

  # Draw the sprite centred on its footprint, feet on the bottom row.
  def screen_x;              return super + (@size - 1) * 16;       end
  def screen_y;              return super + (@size - 1) * 32;       end
  def screen_z(height = 0);  return super(height) + (@size - 1) * 32; end

  def move_points
    if actor?
      return FE_Config::ACTOR_MOVE[battler.class_id] || FE_Config::DEFAULT_MOVE
    end
    return FE_Config::ENEMY_MOVE[battler.id] || FE_Config::DEFAULT_MOVE
  end

  def range
    if actor?
      return FE_Config::WEAPON_RANGE[battler.weapon_id] || FE_Config::DEFAULT_RANGE
    end
    return FE_Config::ENEMY_RANGE[battler.id] || FE_Config::DEFAULT_RANGE
  end

  # Could this unit, standing on (fx, fy), hit unit t standing on (tx, ty)?
  def can_attack_from?(fx, fy, t, tx = t.x, ty = t.y)
    return FE_Grid.in_reach?(fx, fy, @size, tx, ty, t.size, range)
  end

  #--- Magic ------------------------------------------------------------------
  # Map-usable skills this unit knows (RPG::Skill objects).
  def skills
    if actor?
      ids = battler.skills
    elsif FE_Config::ENEMY_MAGIC
      ids = []
      $data_enemies[battler.id].actions.each do |a|
        ids.push(a.skill_id) if a.kind == 1 and !ids.include?(a.skill_id)
      end
    else
      ids = []
    end
    list = []
    ids.each do |i|
      s = $data_skills[i]
      list.push(s) if s != nil and FE_Spell.map_usable?(s)
    end
    return list
  end

  def can_cast?(s)
    return false if dead? or s.sp_cost > battler.sp
    return false if s.atk_f == 0 and battler.restriction == 1   # silenced
    return true
  end

  def castable_skills
    return skills.select { |s| can_cast?(s) }
  end

  # Range of a skill OR an item.
  def skill_range(s)
    return [0, 0] if s.scope == 7
    if s.is_a?(RPG::Item)
      r = FE_Config::ITEM_RANGE[s.id]
      return r if r != nil
      return FE_Spell.offensive?(s) ? FE_Config::ITEM_FOE_RANGE : FE_Config::ITEM_ALLY_RANGE
    end
    if FE_Spell.attr_value(s, "range_custom") == true
      return [FE_Spell.attr_value(s, "range_min").to_i, FE_Spell.attr_value(s, "range_max").to_i]
    end
    r = FE_Config::SKILL_RANGE[s.id]
    return r if r != nil
    return FE_Spell.offensive?(s) ? FE_Config::SPELL_RANGE : FE_Config::SUPPORT_RANGE
  end

  # Widest reach over weapon + castable offensive spells (for range display/AI).
  def threat_range
    r = range.dup
    castable_skills.each do |s|
      next unless FE_Spell.offensive?(s)
      sr = skill_range(s)
      a = FE_Spell.aoe(s)
      if a != nil
        n = FE_Spell.area_reach(a)
        sr = [[sr[0] - n, 0].max, sr[1] + n]
      end
      r[0] = sr[0] if sr[0] < r[0]
      r[1] = sr[1] if sr[1] > r[1]
    end
    return r
  end

  def follow_path(path)
    @path = path.dup
  end

  def busy?
    return (moving? or !@path.empty?)
  end

  def face(tx, ty)
    dx = tx - @x
    dy = ty - @y
    if dx.abs > dy.abs
      @direction = dx > 0 ? 6 : 4
    elsif dy != 0
      @direction = dy > 0 ? 2 : 8
    end
  end

  def update
    super
    if !moving? and !@path.empty?
      step = @path.shift
      face(step[0], step[1])
      @x = step[0]
      @y = step[1]
      increase_steps
    end
  end
end

#==============================================================================
# ** Windows
#==============================================================================
# Stack overview: name, level, average HP, then one row per member.
class Window_FEInfo < Window_Base
  def initialize
    super(0, 0, 288, 32 + 26 * 4)
    self.contents = Bitmap.new(width - 32, height - 32)
    self.z = 300
    self.back_opacity = 200
    self.visible = false
    @unit = nil
    @sig = nil
  end
  def unit=(u)
    sig = (u == nil) ? nil : u.members.collect { |m| [m.hp, m.sp, m.maxhp] }
    return if u == @unit and sig == @sig
    @unit = u
    @sig = sig
    refresh
  end
  def refresh
    self.visible = (@unit != nil)
    return if @unit == nil
    list = @unit.members
    h = 32 + 26 * (list.size + 1)
    if self.height != h
      self.height = h
      self.contents.dispose
      self.contents = Bitmap.new(width - 32, height - 32)
    end
    c = self.contents
    c.clear
    b = @unit.battler
    c.font.color = FE_Draw.team_color(@unit)
    c.draw_text(0, 0, 160, 26, b.name)
    c.font.color = normal_color
    lv = @unit.actor? ? "Lv " + b.level.to_s + "   " : ""
    c.draw_text(0, 0, 256, 26, lv + @unit.hp_rate.to_s + "%", 2)
    list.each_with_index do |m, i|
      y = 26 * (i + 1)
      c.font.color = m.dead? ? disabled_color : normal_color
      c.draw_text(0, y, 96, 26, m.name)
      FE_Draw.draw_bar(c, 100, y + 7, 64, m.hp, m.maxhp, 6)
      if m.maxsp > 0
        FE_Draw.draw_bar(c, 100, y + 14, 64, m.sp, m.maxsp, 4, Color.new(96, 160, 255))
      end
      c.draw_text(168, y, 88, 26, m.hp.to_s + "/" + m.maxhp.to_s, 2)
    end
  end
end

class Window_FEForecast < Window_Base
  def initialize
    super(0, 0, 288, 32 + 26 * 5)
    self.contents = Bitmap.new(width - 32, height - 32)
    self.z = 300
    self.back_opacity = 220
    self.visible = false
  end

  def resize(w, rows)
    h = 32 + 26 * rows
    return if self.width == w and self.height == h
    self.width = w
    self.height = h
    self.contents.dispose
    self.contents = Bitmap.new(w - 32, h - 32)
  end

  # Weapon attack: both stacks side by side (the fight itself happens in
  # the battle screen).
  def set(a, b)
    n = [a.members.size, b.members.size].max
    resize(352, n + 1)
    c = self.contents
    c.clear
    [[a, 0], [b, 164]].each do |pair|
      u = pair[0]
      x = pair[1]
      c.font.color = FE_Draw.team_color(u)
      c.draw_text(x, 0, 104, 26, u.battler.name)
      c.font.color = normal_color
      c.draw_text(x, 0, 156, 26, u.hp_rate.to_s + "%", 2)
      u.members.each_with_index do |m, i|
        y = 26 * (i + 1)
        c.font.color = m.dead? ? disabled_color : normal_color
        c.draw_text(x, y, 84, 26, m.name)
        c.draw_text(x + 84, y, 72, 26, m.hp.to_s + "/" + m.maxhp.to_s, 2)
      end
    end
    self.visible = true
  end

  # Spell forecast. Values are per member; the spell hits every living
  # member of the target stack.
  # count: number of stacks an area-of-effect skill hits (nil = not tile-aimed)
  def set_skill(a, b, s, count = nil)
    ab = a.battler
    bb = b.battler
    d = FE_Combat.skill_damage(ab, bb, s)
    if s.power == 0
      eff = ["Effect", "Status"]
    elsif d < 0
      eff = ["Heal/unit", [-d, bb.maxhp - bb.hp].min.to_s]
    else
      eff = ["Dmg/unit", d.to_s]
    end
    eff[1] += " (area)" if FE_Spell.area?(s)
    rows = [
      ["HP %", a.hp_rate.to_s, b.hp_rate.to_s],
      [eff[0], eff[1], ""],
      ["Hit",  FE_Combat.skill_hit(ab, bb, s).to_s, ""]
    ]
    rows.push(["Units hit", count.to_s, ""]) if count != nil
    draw_rows(a, b, s.name + "   SP " + s.sp_cost.to_s, rows)
  end

  # Item forecast (per member, like spells).
  def set_item(a, b, it)
    bb = b.battler
    hp = FE_Combat.item_hp(bb, it)
    sp = FE_Combat.item_sp(bb, it)
    if hp > 0
      eff = ["Heal/unit", [hp, bb.maxhp - bb.hp].min.to_s]
    elsif hp < 0
      eff = ["Dmg/unit", (-hp).to_s]
    elsif sp > 0
      eff = ["SP/unit", "+" + [sp, bb.maxsp - bb.sp].min.to_s]
    else
      eff = ["Effect", "Status"]
    end
    eff[1] += " (area)" if FE_Spell.area?(it)
    draw_rows(a, b, it.name + "   x" + $game_party.item_number(it.id).to_s, [
      ["HP %", a.hp_rate.to_s, b.hp_rate.to_s],
      [eff[0], eff[1], ""],
      ["Hit",  it.hit.to_s, ""]
    ])
  end

  def draw_rows(a, b, s, rows)
    resize(288, rows.size + 1 + (s != nil ? 1 : 0))
    c = self.contents
    c.clear
    c.font.color = FE_Draw.team_color(a)
    c.draw_text(0, 0, 124, 26, a.battler.name)
    c.font.color = FE_Draw.team_color(b)
    c.draw_text(132, 0, 124, 26, b.battler.name, 2)
    rows.each_with_index do |r, i|
      y = 26 * (i + 1)
      c.font.color = normal_color
      c.draw_text(0, y, 80, 26, r[1], 1)
      c.font.color = system_color
      c.draw_text(80, y, 96, 26, r[0], 1)
      c.font.color = normal_color
      c.draw_text(176, y, 80, 26, r[2], 1)
    end
    if s != nil
      c.font.color = system_color
      c.draw_text(0, 26 * (rows.size + 1), 256, 26, s, 1)
    end
    self.visible = true
  end
end

# Bottom bar while a map spell/item resolves: stack name + average HP.
class Window_FECombat < Window_Base
  def initialize
    super(0, 384, 640, 96)
    self.contents = Bitmap.new(width - 32, height - 32)
    self.z = 300
    self.back_opacity = 220
    self.visible = false
  end
  def setup(a, b)
    if a == b
      @l = a; @r = nil
    elsif a.player? or !b.player?
      @l = a; @r = b
    else
      @l = b; @r = a
    end
    refresh
    self.visible = true
  end
  def refresh
    c = self.contents
    c.clear
    [[@l, 0], [@r, 320]].each do |pair|
      u = pair[0]
      x = pair[1]
      next if u == nil
      c.font.color = FE_Draw.team_color(u)
      c.draw_text(x, 0, 288, 28, u.battler.name)
      c.font.color = normal_color
      c.draw_text(x, 0, 288, 28, u.alive_members.size.to_s + "/" +
                  u.members.size.to_s + "   " + u.hp_rate.to_s + "%", 2)
      FE_Draw.draw_bar(c, x, 36, 288, u.hp_rate, 100, 10)
    end
  end
end

# Spell / item list: icon, name, right-hand text (SP cost or count).
class Window_FEList < Window_Selectable
  def initialize(list, enabled, right_texts)
    @data = list
    @enabled = enabled
    @right = right_texts
    rows = [[@data.size, 1].max, 7].min
    super(0, 0, 320, rows * 32 + 32)
    @item_max = @data.size
    self.contents = Bitmap.new(width - 32, [@item_max, 1].max * 32)
    self.z = 320
    self.back_opacity = 220
    refresh
    self.index = 0
  end
  def current
    return @data[self.index]
  end
  def enabled?(i)
    return @enabled[i]
  end
  def refresh
    self.contents.clear
    for i in 0...@item_max
      s = @data[i]
      y = i * 32
      op = @enabled[i] ? 255 : 128
      self.contents.font.color = @enabled[i] ? normal_color : disabled_color
      icon = RPG::Cache.icon(s.icon_name)
      self.contents.blt(4, y + 4, icon, Rect.new(0, 0, 24, 24), op)
      self.contents.draw_text(32, y, 200, 32, s.name)
      self.contents.draw_text(232, y, 56, 32, @right[i], 2)
    end
  end
  def update_help
    @help_window.set_text(current == nil ? "" : current.description)
  end
end

#==============================================================================
# ** Scene_FEBattle
#==============================================================================
class Scene_FEBattle
  # [direction, dx, dy]; index i <-> bit (1 << i) in the passage table
  DIRS = [[2, 0, 1], [4, -1, 0], [6, 1, 0], [8, 0, -1]]

  def initialize(troop_id, can_lose = false)
    @troop_id = troop_id
    @can_lose = can_lose
  end

  #--------------------------------------------------------------------------
  # * Main
  #--------------------------------------------------------------------------
  def main
    @saved_dx = $game_map.display_x
    @saved_dy = $game_map.display_y
    @player_was_transparent = $game_player.transparent
    $game_player.transparent = true
    @map_bgm = $game_system.playing_bgm
    @units  = []
    @turn   = 0
    @ended  = false
    @state  = :busy
    @sel    = nil
    @shown_enemy = nil
    @spriteset = Spriteset_Map.new
    create_graphics
    build_grid
    ok = deploy
    @cam_x = $game_map.display_x
    @cam_y = $game_map.display_y
    if ok
      $game_system.se_play($data_system.battle_start_se)
      $game_system.bgm_play($game_system.battle_bgm) if FE_Config::PLAY_BATTLE_BGM
    end
    Graphics.transition(20)
    if !ok
      restore_and_leave(nil)
    elsif !check_battle_end
      start_player_phase
    end
    while $scene == self
      update_basic
      update_input unless @ended
    end
    Graphics.freeze
    dispose_graphics
  end

  #--------------------------------------------------------------------------
  # * Setup
  #--------------------------------------------------------------------------
  def create_graphics
    vp = @spriteset.viewport1
    @bmp_move = Bitmap.new(32, 32)
    @bmp_move.fill_rect(0, 0, 32, 32, Color.new(120, 170, 255, 200))
    @bmp_move.fill_rect(1, 1, 30, 30, Color.new(60, 120, 255, 130))
    @bmp_atk = Bitmap.new(32, 32)
    @bmp_atk.fill_rect(0, 0, 32, 32, Color.new(255, 140, 140, 200))
    @bmp_atk.fill_rect(1, 1, 30, 30, Color.new(255, 60, 60, 120))
    @bmp_heal = Bitmap.new(32, 32)
    @bmp_heal.fill_rect(0, 0, 32, 32, Color.new(140, 255, 160, 200))
    @bmp_heal.fill_rect(1, 1, 30, 30, Color.new(60, 220, 100, 120))
    @bmp_area = Bitmap.new(32, 32)
    @bmp_area.fill_rect(0, 0, 32, 32, Color.new(255, 230, 140, 230))
    @bmp_area.fill_rect(2, 2, 28, 28, Color.new(255, 160, 30, 180))
    @tile_pool  = []
    @tile_pos   = []
    @tile_count = 0
    @cursor = Sprite.new(vp)
    @cursor.bitmap = Bitmap.new(32, 32)
    white = Color.new(255, 255, 255)
    @cursor.bitmap.fill_rect(0, 0, 32, 3, white)
    @cursor.bitmap.fill_rect(0, 29, 32, 3, white)
    @cursor.bitmap.fill_rect(0, 0, 3, 32, white)
    @cursor.bitmap.fill_rect(29, 0, 3, 32, white)
    @cursor.z = 999
    @cx = 0
    @cy = 0
    @frame = 0
    @info_window     = Window_FEInfo.new
    @forecast_window = Window_FEForecast.new
    @combat_window   = Window_FECombat.new
    @command_window  = nil
    @list_window    = nil
    @help_window     = Window_Help.new
    @help_window.y   = 416
    @help_window.z   = 320
    @help_window.visible = false
  end

  # Pre-compute which steps are legal so path searches stay fast.
  def build_grid
    w = $game_map.width
    h = $game_map.height
    @pass = Table.new(w, h)
    @cost = Table.new(w, h)
    blocked = {}
    $game_map.events.values.each do |ev|
      next if marker?(ev) or ev.through
      next if ev.character_name == "" and ev.tile_id == 0
      blocked[[ev.x, ev.y]] = true
    end
    for x in 0...w
      for y in 0...h
        @cost[x, y] = [FE_Config::TERRAIN_COST[$game_map.terrain_tag(x, y)] || 1, 1].max
        bits = 0
        DIRS.each_with_index do |d, i|
          nx = x + d[1]
          ny = y + d[2]
          next unless $game_map.valid?(nx, ny)
          next if blocked[[nx, ny]]
          next unless $game_map.passable?(x, y, d[0])
          next unless $game_map.passable?(nx, ny, 10 - d[0])
          bits |= (1 << i)
        end
        @pass[x, y] = bits
      end
    end
  end

  def marker?(ev)
    n = ev.fe_name
    return (n.include?(FE_Config::START_TAG) or n.include?(FE_Config::ENEMY_TAG))
  end

  def deploy
    starts = []
    spawns = []
    $game_map.events.values.sort_by { |e| e.id }.each do |ev|
      n = ev.fe_name
      starts.push(ev) if n.include?(FE_Config::START_TAG)
      spawns.push(ev) if n.include?(FE_Config::ENEMY_TAG)
    end
    if starts.empty?
      print("FE Tactics: this map has no events named " + FE_Config::START_TAG)
      return false
    end
    i = 0
    @lord_deployed = false
    $game_party.actors.each do |actor|
      next if actor.dead?
      break if i >= starts.size
      add_unit(Game_FEUnit.new(actor_stack(actor), :player, starts[i].x, starts[i].y))
      @lord_deployed = true if actor.id == FE_Config::LORD_ACTOR_ID
      i += 1
    end
    troop = $data_troops[@troop_id]
    if troop == nil
      print("FE Tactics: Troop " + @troop_id.to_s + " does not exist")
      return false
    end
    j = 0
    troop.members.each_index do |k|
      next if troop.members[k].hidden
      if j >= spawns.size
        print("FE Tactics: not enough " + FE_Config::ENEMY_TAG + " events for Troop " + @troop_id.to_s) if $DEBUG
        break
      end
      unit = Game_FEUnit.new(enemy_stack(k), :enemy, spawns[j].x, spawns[j].y)
      if unit.size > 1   # keep a big unit's whole square on the map
        unit.moveto([unit.x, $game_map.width - unit.size].min,
                    [unit.y, $game_map.height - unit.size].min)
      end
      add_unit(unit)
      j += 1
    end
    return true
  end

  # The real actor plus temporary copies (deep copies: own HP/SP/states).
  # Later this is where a stack's makeup gets defined.
  def actor_stack(actor)
    list = [actor]
    (FE_Config::STACK_SIZE - 1).times { list.push(Marshal.load(Marshal.dump(actor))) }
    return list
  end

  def enemy_stack(member_index)
    list = []
    FE_Config::STACK_SIZE.times { list.push(Game_FEEnemy.new(@troop_id, member_index)) }
    return list
  end

  def add_unit(u)
    u.sprite = Sprite_Character.new(@spriteset.viewport1, u)
    if u.size > 1
      u.sprite.zoom_x = u.size
      u.sprite.zoom_y = u.size
    end
    u.sprite.update
    if FE_Config::SHOW_HP_BARS
      u.hp_bar = Sprite.new(@spriteset.viewport1)
      u.hp_bar.bitmap = Bitmap.new(28, 6)
      u.hp_bar.z = 998
      @bar_hp ||= {}
      @bar_hp[u] = -1
    end
    @units.push(u)
  end

  # Redraw a unit's overhead HP bar when its HP changes; keep it on its head.
  def update_hp_bar(u)
    bar = u.hp_bar
    return if bar == nil
    rate = u.hp_rate
    if @bar_hp[u] != rate
      @bar_hp[u] = rate
      bmp = bar.bitmap
      bmp.clear
      bmp.fill_rect(0, 0, 28, 6, u.player? ? Color.new(40, 80, 200) : Color.new(200, 40, 40))
      FE_Draw.draw_bar(bmp, 1, 1, 26, rate, 100, 4)
    end
    h = (u.sprite.src_rect.height * u.sprite.zoom_y).to_i
    h = 48 if h <= 0
    bar.x = u.screen_x - 14
    bar.y = u.screen_y - h - 4
    bar.opacity = u.opacity
    bar.visible = u.sprite.visible
  end

  #--------------------------------------------------------------------------
  # * Frame update (called every frame, including inside blocking waits)
  #--------------------------------------------------------------------------
  def update_basic
    Graphics.update
    Input.update
    @frame += 1
    update_camera
    @spriteset.update
    @units.each do |u|
      u.update
      u.sprite.update
      update_hp_bar(u)
    end
    update_tiles
    @cursor.x = tile_sx(@cx)
    @cursor.y = tile_sy(@cy)
    @cursor.opacity = 160 + (@frame % 40 < 20 ? @frame % 20 : 20 - @frame % 20) * 4
    @command_window.update if @command_window != nil
    @list_window.update if @list_window != nil
  end

  def wait(frames)
    frames.times { update_basic }
  end

  def wait_effects(unit)
    update_basic
    update_basic while unit.sprite.effect?
  end

  def wait_unit(u)
    while u.busy?
      camera_follow(u.x, u.y)
      update_basic
    end
  end

  def wait_camera
    update_basic while $game_map.display_x != @cam_x or $game_map.display_y != @cam_y
  end

  #--------------------------------------------------------------------------
  # * Camera & cursor
  #--------------------------------------------------------------------------
  def tile_sx(x); return (x * 128 - $game_map.display_x + 3) / 4; end
  def tile_sy(y); return (y * 128 - $game_map.display_y + 3) / 4; end

  def cam_clamp(x, y)
    mx = [($game_map.width - 20) * 128, 0].max
    my = [($game_map.height - 15) * 128, 0].max
    @cam_x = [[x * 128, 0].max, mx].min
    @cam_y = [[y * 128, 0].max, my].min
  end

  def camera_follow(x, y)
    m = 3
    left = @cam_x / 128
    top  = @cam_y / 128
    left = x - m      if x < left + m
    left = x - 19 + m if x > left + 19 - m
    top  = y - m      if y < top + m
    top  = y - 14 + m if y > top + 14 - m
    cam_clamp(left, top)
  end

  def center_camera(x, y)
    cam_clamp(x - 9, y - 7)
  end

  def update_camera
    $game_map.display_x = approach($game_map.display_x, @cam_x, 64)
    $game_map.display_y = approach($game_map.display_y, @cam_y, 64)
  end

  def approach(v, t, s)
    return v < t ? [v + s, t].min : [v - s, t].max
  end

  def set_cursor(x, y)
    @cx = x
    @cy = y
    camera_follow(x, y)
    refresh_info
  end

  def refresh_info
    if @state == :free or @state == :move
      @info_window.unit = unit_at(@cx, @cy)
      @info_window.x = tile_sx(@cx) < 320 ? 640 - @info_window.width : 0
    else
      @info_window.unit = nil
    end
  end

  def cursor_input
    dx = 0
    dy = 0
    dy =  1 if Input.repeat?(Input::DOWN)
    dy = -1 if Input.repeat?(Input::UP)
    dx = -1 if Input.repeat?(Input::LEFT)
    dx =  1 if Input.repeat?(Input::RIGHT)
    return if dx == 0 and dy == 0
    nx = [[@cx + dx, 0].max, $game_map.width - 1].min
    ny = [[@cy + dy, 0].max, $game_map.height - 1].min
    set_cursor(nx, ny) if nx != @cx or ny != @cy
  end

  #--------------------------------------------------------------------------
  # * Range highlight tiles
  #--------------------------------------------------------------------------
  def show_tiles(move_keys, atk_keys)
    clear_tiles
    move_keys.each { |k| add_tile(k, @bmp_move) }
    atk_keys.each  { |k| add_tile(k, @bmp_atk) }
  end

  def add_tile(key, bmp)
    s = @tile_pool[@tile_count]
    if s == nil
      s = Sprite.new(@spriteset.viewport1)
      s.z = 1
      @tile_pool[@tile_count] = s
    end
    s.bitmap = bmp
    s.visible = true
    @tile_pos[@tile_count] = key
    @tile_count += 1
  end

  def clear_tiles
    @tile_pool.each { |s| s.visible = false }
    @tile_count = 0
  end

  def update_tiles
    op = 170 + (@frame % 60 < 30 ? @frame % 30 : 30 - @frame % 30) * 2
    for i in 0...@tile_count
      s = @tile_pool[i]
      s.x = tile_sx(@tile_pos[i][0])
      s.y = tile_sy(@tile_pos[i][1])
      s.opacity = op
    end
  end

  #--------------------------------------------------------------------------
  # * Grid queries   (a unit's position (x, y) is the top-left of its square)
  #--------------------------------------------------------------------------
  def unit_at(x, y)
    return @units.find { |u| u.covers?(x, y) }
  end

  def units_of(team)
    return @units.select { |u| u.team == team }
  end

  # { tile => unit } for every tile covered by a unit other than `unit`.
  def occupancy(unit)
    occ = {}
    @units.each do |o|
      next if o == unit
      o.tiles.each { |t| occ[t] = o }
    end
    return occ
  end

  # Tiles an n x n square at (x, y) enters when stepping in DIRS[i],
  # or nil if any part of its leading edge is blocked.
  def step_tiles(x, y, n, i)
    d = DIRS[i]
    entered = []
    for j in 0...n
      if d[1] != 0
        ox = d[1] > 0 ? x + n - 1 : x
        oy = y + j
      else
        ox = x + j
        oy = d[2] > 0 ? y + n - 1 : y
      end
      return nil if @pass[ox, oy] & (1 << i) == 0
      entered.push([ox + d[1], oy + d[2]])
    end
    return entered
  end

  # Cheapest-path search (Dijkstra with bucket queue).
  # Returns [cost hash, previous-step hash, occupancy hash]; keys are [x, y]
  # (top-left tiles). Units may walk through allies but not through foes.
  def search(unit, max)
    occ = occupancy(unit)
    n = unit.size
    start = [unit.x, unit.y]
    best = { start => 0 }
    prev = {}
    buckets = [[start]]
    c = 0
    while c < buckets.size
      list = buckets[c]
      if list != nil
        list.each do |cur|
          next if best[cur] != c
          DIRS.each_with_index do |d, i|
            entered = step_tiles(cur[0], cur[1], n, i)
            next if entered == nil
            next if entered.find { |t| o = occ[t]; o != nil and o.team != unit.team } != nil
            key = [cur[0] + d[1], cur[1] + d[2]]
            nc = c + entered.collect { |t| @cost[t[0], t[1]] }.max
            next if nc > max
            old = best[key]
            if old == nil or nc < old
              best[key] = nc
              prev[key] = cur
              (buckets[nc] ||= []).push(key)
            end
          end
        end
      end
      c += 1
    end
    return [best, prev, occ]
  end

  # Can the unit stop with its top-left tile on k (no other unit in the way)?
  def free_at?(unit, k, occ)
    return unit.tiles(k[0], k[1]).find { |t| occ[t] != nil } == nil
  end

  # Positions the unit can end its move on.
  def dest_keys(unit, best, occ)
    return best.keys.select { |k| free_at?(unit, k, occ) }
  end

  # Every tile covered by the unit standing on any of the given positions.
  def footprint(unit, keys)
    set = {}
    keys.each { |k| unit.tiles(k[0], k[1]).each { |t| set[t] = true } }
    return set
  end

  # Tiles hittable from any of the given standing positions, minus `exclude`.
  def attack_keys(unit, stands, exclude, rng = nil)
    rng ||= unit.range
    n = unit.size
    rmax = rng[1]
    set = {}
    stands.each do |k|
      for tx in (k[0] - rmax)..(k[0] + n - 1 + rmax)
        for ty in (k[1] - rmax)..(k[1] + n - 1 + rmax)
          key = [tx, ty]
          next if set[key] or exclude[key]
          next unless $game_map.valid?(tx, ty)
          inside = (tx >= k[0] and ty >= k[1] and tx < k[0] + n and ty < k[1] + n)
          next if inside and rng[0] > 0
          set[key] = true if FE_Grid.in_reach?(k[0], k[1], n, tx, ty, 1, rng)
        end
      end
    end
    return set.keys
  end

  def targets_from(unit, x, y)
    return @units.select { |o| o.team != unit.team and unit.can_attack_from?(x, y, o) }
  end

  def build_path(prev, start, goal)
    path = []
    cur = goal
    while cur != start
      path.unshift(cur)
      cur = prev[cur]
      return [] if cur == nil
    end
    return path
  end

  # Show a unit's full danger zone (blue = move, red = attack).
  def show_range(unit)
    r = search(unit, unit.move_points)
    best = r[0]
    stands = dest_keys(unit, best, r[2])
    moves = footprint(unit, best.keys)
    show_tiles(moves.keys, attack_keys(unit, stands, moves, unit.threat_range))
  end

  # Units the skill could affect if cast from tile k (targets, not victims).
  def skill_targets(u, s, k)
    rng = u.skill_range(s)
    list = []
    @units.each do |t|
      if s.scope == 7
        next if t != u
      elsif FE_Spell.offensive?(s)
        next if t.team == u.team
      else
        next if t.team != u.team
      end
      if t == u
        ok = (rng[0] == 0)
      else
        ok = FE_Grid.in_reach?(k[0], k[1], u.size, t.x, t.y, t.size, rng)
      end
      list.push(t) if ok
    end
    return list
  end

  # True if v is on the side the skill is meant for (foes for damage spells).
  def right_side?(u, s, v)
    return FE_Spell.offensive?(s) ? (v.team != u.team) : (v.team == u.team)
  end

  # Everyone hit by an area-of-effect skill centered on tile c (caster on k).
  def area_victims(u, s, c, k = nil)
    k ||= [u.x, u.y]
    a = FE_Spell.aoe(s)
    list = []
    @units.each do |v|
      next unless a[2] or right_side?(u, s, v)
      p = (v == u) ? k : [v.x, v.y]
      hit = v.tiles(p[0], p[1]).find { |t| FE_Spell.in_area?(c[0], c[1], t[0], t[1], a) }
      list.push(v) if hit != nil
    end
    return list
  end

  # Area-of-effect choices from tile k: [[center, victims], ...], only centers
  # in range that hit at least one unit of the skill's side.
  def area_options(u, s, k)
    a = FE_Spell.aoe(s)
    valid = {}
    attack_keys(u, [k], {}, u.skill_range(s)).each { |c| valid[c] = true }
    seen = {}
    list = []
    @units.each do |t|
      next unless right_side?(u, s, t)
      p = (t == u) ? k : [t.x, t.y]
      t.tiles(p[0], p[1]).each do |tt|
        FE_Spell.area_tiles(tt[0], tt[1], a).each do |c|   # areas are symmetric
          next if seen[c] or !valid[c]
          seen[c] = true
          v = area_victims(u, s, c, k)
          list.push([c, v]) if v.find { |x| right_side?(u, s, x) } != nil
        end
      end
    end
    return list
  end

  # Everyone actually hit when the skill lands on `primary` (caster on k).
  def skill_victims(u, s, primary, k = nil)
    k ||= [u.x, u.y]
    return [primary] unless FE_Spell.area?(s)
    c = (primary == u) ? k : [primary.x, primary.y]
    rad = FE_Config::AREA_RADIUS
    list = []
    @units.each do |v|
      next if v.team != primary.team
      p = (v == u) ? k : [v.x, v.y]
      list.push(v) if FE_Grid.span(p[0], p[1], v.size, c[0], c[1], primary.size)[0] <= rad
    end
    return list
  end

  #--------------------------------------------------------------------------
  # * Phases
  #--------------------------------------------------------------------------
  def start_player_phase
    @turn += 1
    @units.each do |u|
      u.acted = false
      u.idle = true
      u.sprite.tone = Tone.new(0, 0, 0, 0)
    end
    show_banner("Turn " + @turn.to_s + "  -  " + FE_Config::TEXT_PLAYER, Color.new(120, 170, 255))
    process_states(:player)
    return if @ended
    first = ready_units[0]
    if first != nil
      center_camera(first.x, first.y)
      @state = :free
      set_cursor(first.x, first.y)
    else
      @state = :free
    end
  end

  def ready_units
    return @units.select { |u| u.player? and !u.acted }
  end

  def end_player_phase
    close_command
    clear_tiles
    @shown_enemy = nil
    @state = :busy
    refresh_info
    run_enemy_phase
    return if @ended
    start_player_phase
  end

  def run_enemy_phase
    show_banner(FE_Config::TEXT_ENEMY, Color.new(255, 120, 120))
    process_states(:enemy)
    return if @ended
    units_of(:enemy).each do |e|
      next unless @units.include?(e)
      next if e.acted                     # asleep / paralyzed
      enemy_act(e)
      return if check_battle_end
    end
  end

  # Start of a side's phase: states wear off (no slip damage on the map),
  # stacks that can't move skip their turn.
  def process_states(team)
    units_of(team).each do |u|
      u.alive_members.each { |m| m.remove_states_auto }
      stuck = u.stuck?
      u.acted = stuck
      u.idle = !stuck
      u.sprite.tone = stuck ? Tone.new(0, 0, 0, 255) : Tone.new(0, 0, 0, 0)
    end
  end

  #--------------------------------------------------------------------------
  # * Player input
  #--------------------------------------------------------------------------
  def update_input
    case @state
    when :free   then input_free
    when :move   then input_move
    when :action then input_action
    when :list   then input_list
    when :target then input_target
    when :area   then input_area
    when :menu   then input_menu
    end
  end

  def input_free
    if FE_Config::AUTO_END_TURN and ready_units.empty?
      wait(10)
      end_player_phase
      return
    end
    cursor_input
    if Input.trigger?(Input::A)
      list = ready_units
      return if list.empty?
      cur = unit_at(@cx, @cy)
      idx = list.index(cur)
      nxt = list[idx == nil ? 0 : (idx + 1) % list.size]
      $game_system.se_play($data_system.cursor_se)
      set_cursor(nxt.x, nxt.y)
    elsif Input.trigger?(Input::C)
      u = unit_at(@cx, @cy)
      if u != nil and u.player? and !u.acted
        $game_system.se_play($data_system.decision_se)
        @shown_enemy = nil
        select_unit(u)
      elsif u != nil and !u.player?
        $game_system.se_play($data_system.decision_se)
        if @shown_enemy == u
          @shown_enemy = nil
          clear_tiles
        else
          @shown_enemy = u
          show_range(u)
        end
      else
        open_map_menu
      end
    elsif Input.trigger?(Input::B) and @shown_enemy != nil
      $game_system.se_play($data_system.cancel_se)
      @shown_enemy = nil
      clear_tiles
    end
  end

  def select_unit(u)
    @sel = u
    r = search(u, u.move_points)
    @best = r[0]
    @prev = r[1]
    @dests = {}
    dest_keys(u, @best, r[2]).each { |k| @dests[k] = true }
    moves = footprint(u, @best.keys)
    show_tiles(moves.keys, attack_keys(u, @dests.keys, moves, u.threat_range))
    @state = :move
  end

  def input_move
    cursor_input
    if Input.trigger?(Input::C)
      key = [@cx, @cy]
      unless @dests[key]
        $game_system.se_play($data_system.buzzer_se)
        return
      end
      $game_system.se_play($data_system.decision_se)
      @orig = [@sel.x, @sel.y, @sel.direction]
      clear_tiles
      @state = :busy
      refresh_info
      @sel.follow_path(build_path(@prev, [@sel.x, @sel.y], key))
      wait_unit(@sel)
      open_action_menu
    elsif Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      clear_tiles
      @state = :free
      set_cursor(@sel.x, @sel.y)
      @sel = nil
    end
  end

  def open_action_menu
    @targets = targets_from(@sel, @sel.x, @sel.y)
    open_command([FE_Config::TEXT_ATTACK, FE_Config::TEXT_MAGIC,
                  FE_Config::TEXT_ITEM, FE_Config::TEXT_WAIT])
    @command_window.disable_item(0) if @targets.empty?
    @command_window.disable_item(1) unless magic_available?(@sel)
    @command_window.disable_item(2) unless items_available?(@sel)
    @state = :action
  end

  def skill_enabled?(u, s)
    return false unless u.can_cast?(s)
    return !area_options(u, s, [u.x, u.y]).empty? if FE_Spell.aoe(s)
    return !skill_targets(u, s, [u.x, u.y]).empty?
  end

  def magic_available?(u)
    return (u.skills.find { |s| skill_enabled?(u, s) } != nil)
  end

  #--- Items (shared party bag; player units only) ---------------------------
  def battle_items
    list = []
    for i in 1...$data_items.size
      it = $data_items[i]
      next if it == nil or $game_party.item_number(i) <= 0
      list.push(it) if FE_Spell.map_usable?(it)
    end
    return list
  end

  def item_enabled?(u, it)
    return false if !u.player? or $game_party.item_number(it.id) <= 0
    return !skill_targets(u, it, [u.x, u.y]).empty?
  end

  def items_available?(u)
    return (battle_items.find { |it| item_enabled?(u, it) } != nil)
  end

  def input_action
    if Input.trigger?(Input::C)
      case @command_window.index
      when 0
        if @targets.empty?
          $game_system.se_play($data_system.buzzer_se)
          return
        end
        $game_system.se_play($data_system.decision_se)
        hide_command
        @cur_abil = nil
        show_tiles([], attack_keys(@sel, [[@sel.x, @sel.y]], {}))
        @target_index = 0
        @state = :target
        refresh_target
      when 1, 2
        mode = (@command_window.index == 1) ? :skill : :item
        ok = (mode == :skill) ? magic_available?(@sel) : items_available?(@sel)
        unless ok
          $game_system.se_play($data_system.buzzer_se)
          return
        end
        $game_system.se_play($data_system.decision_se)
        hide_command
        open_list(mode)
      else
        $game_system.se_play($data_system.decision_se)
        close_command
        finish_unit(@sel)
      end
    elsif Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      close_command
      @sel.moveto(@orig[0], @orig[1])
      @sel.direction = @orig[2]
      @state = :free
      set_cursor(@sel.x, @sel.y)
      select_unit(@sel)
    end
  end

  def hide_command
    @command_window.visible = false
    @command_window.active = false
  end

  def show_command
    @command_window.visible = true
    @command_window.active = true
  end

  #--- Spell / item list -------------------------------------------------------
  def open_list(mode)
    close_list
    if mode == :skill
      list = @sel.skills
      enabled = list.collect { |s| skill_enabled?(@sel, s) }
      right = list.collect { |s| s.sp_cost.to_s }
    else
      list = battle_items
      enabled = list.collect { |it| item_enabled?(@sel, it) }
      right = list.collect { |it| "x" + $game_party.item_number(it.id).to_s }
    end
    @list_window = Window_FEList.new(list, enabled, right)
    @list_window.x = tile_sx(@sel.x) < 320 ? 640 - 320 - 16 : 16
    @list_window.y = 16
    @help_window.visible = true
    @list_window.help_window = @help_window
    @state = :list
  end

  def close_list
    @list_window.dispose if @list_window != nil
    @list_window = nil
    @help_window.visible = false
  end

  def input_list
    if Input.trigger?(Input::C)
      i = @list_window.index
      unless @list_window.enabled?(i)
        $game_system.se_play($data_system.buzzer_se)
        return
      end
      $game_system.se_play($data_system.decision_se)
      @cur_abil = @list_window.current
      @list_window.visible = false
      @list_window.active = false
      @help_window.visible = false
      if FE_Spell.aoe(@cur_abil)
        start_area_target
        return
      end
      @targets = skill_targets(@sel, @cur_abil, [@sel.x, @sel.y])
      keys = attack_keys(@sel, [[@sel.x, @sel.y]], {}, @sel.skill_range(@cur_abil))
      if FE_Spell.offensive?(@cur_abil)
        show_tiles([], keys)
      else
        clear_tiles
        keys.each { |k| add_tile(k, @bmp_heal) }
      end
      @target_index = 0
      @state = :target
      refresh_target
    elsif Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      close_list
      show_command
      @state = :action
    end
  end

  #--- Target selection (weapon, spell or item) ---------------------------------
  def refresh_target
    t = @targets[@target_index]
    @cx = t.x
    @cy = t.y
    camera_follow(t.x, t.y)
    @sel.face(t.x, t.y) if t != @sel
    if @cur_abil == nil
      @forecast_window.set(@sel, t)
    elsif @cur_abil.is_a?(RPG::Item)
      @forecast_window.set_item(@sel, t, @cur_abil)
    else
      @forecast_window.set_skill(@sel, t, @cur_abil)
    end
    @forecast_window.x = tile_sx(t.x) < 320 ? 640 - @forecast_window.width : 0
  end

  def input_target
    step = 0
    step =  1 if Input.repeat?(Input::RIGHT) or Input.repeat?(Input::DOWN)
    step = -1 if Input.repeat?(Input::LEFT)  or Input.repeat?(Input::UP)
    if step != 0 and @targets.size > 1
      $game_system.se_play($data_system.cursor_se)
      @target_index = (@target_index + step) % @targets.size
      refresh_target
    end
    if Input.trigger?(Input::C)
      $game_system.se_play($data_system.decision_se)
      @forecast_window.visible = false
      clear_tiles
      close_command
      close_list
      @state = :busy
      unit = @sel
      if @cur_abil == nil
        run_combat(unit, @targets[@target_index])
      else
        run_ability(unit, @cur_abil, @targets[@target_index])
      end
      finish_unit(unit)
    elsif Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      @forecast_window.visible = false
      clear_tiles
      @cx = @sel.x
      @cy = @sel.y
      if @cur_abil == nil
        show_command
        @state = :action
      else
        @list_window.visible = true
        @list_window.active = true
        @help_window.visible = true
        @state = :list
      end
    end
  end

  #--- Area-of-effect aiming (free cursor inside the skill's range) ----------
  def start_area_target
    s = @cur_abil
    @area = FE_Spell.aoe(s)
    @area_keys = {}
    attack_keys(@sel, [[@sel.x, @sel.y]], {}, @sel.skill_range(s)).each { |k| @area_keys[k] = true }
    best = nil
    area_options(@sel, s, [@sel.x, @sel.y]).each do |o|
      n = o[1].select { |v| right_side?(@sel, s, v) }.size
      best = [o[0], n] if best == nil or n > best[1]
    end
    c = (best != nil) ? best[0] : [@sel.x, @sel.y]
    @cx = c[0]
    @cy = c[1]
    camera_follow(@cx, @cy)
    @state = :area
    refresh_area
  end

  def refresh_area
    s = @cur_abil
    clear_tiles
    bmp = FE_Spell.offensive?(s) ? @bmp_atk : @bmp_heal
    @area_keys.keys.each { |k| add_tile(k, bmp) }
    @area_victims = []
    if @area_keys[[@cx, @cy]]
      FE_Spell.area_tiles(@cx, @cy, @area).each do |k|
        add_tile(k, @bmp_area) if $game_map.valid?(k[0], k[1])
      end
      @area_victims = area_victims(@sel, s, [@cx, @cy])
    end
    main = @area_victims.find { |v| right_side?(@sel, s, v) }
    if main != nil
      @sel.face(@cx, @cy) if @cx != @sel.x or @cy != @sel.y
      @forecast_window.set_skill(@sel, main, s, @area_victims.size)
      @forecast_window.x = tile_sx(@cx) < 320 ? 640 - @forecast_window.width : 0
    else
      @forecast_window.visible = false
    end
  end

  def input_area
    ox = @cx
    oy = @cy
    cursor_input
    refresh_area if @cx != ox or @cy != oy
    if Input.trigger?(Input::C)
      if @area_victims.find { |v| right_side?(@sel, @cur_abil, v) } == nil
        $game_system.se_play($data_system.buzzer_se)
        return
      end
      $game_system.se_play($data_system.decision_se)
      @forecast_window.visible = false
      clear_tiles
      close_command
      close_list
      @state = :busy
      unit = @sel
      run_ability(unit, @cur_abil, nil, [@cx, @cy])
      finish_unit(unit)
    elsif Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      @forecast_window.visible = false
      clear_tiles
      @cx = @sel.x
      @cy = @sel.y
      @list_window.visible = true
      @list_window.active = true
      @help_window.visible = true
      @state = :list
    end
  end

  def finish_unit(u)
    @sel = nil
    clear_tiles
    return if check_battle_end
    if @units.include?(u)
      u.acted = true
      u.idle = false
      u.sprite.tone = Tone.new(0, 0, 0, 255)
    end
    @state = :free
    set_cursor(@cx, @cy)
    @info_window.refresh
  end

  def open_map_menu
    $game_system.se_play($data_system.decision_se)
    open_command([FE_Config::TEXT_END_TURN, FE_Config::TEXT_CANCEL])
    @state = :menu
    refresh_info
  end

  def input_menu
    if Input.trigger?(Input::C)
      $game_system.se_play($data_system.decision_se)
      if @command_window.index == 0
        end_player_phase
      else
        close_command
        @state = :free
        refresh_info
      end
    elsif Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      close_command
      @state = :free
      refresh_info
    end
  end

  def open_command(items)
    close_command
    @command_window = Window_Command.new(160, items)
    @command_window.z = 310
    @command_window.back_opacity = 220
    @command_window.x = tile_sx(@cx) < 320 ? 640 - 160 - 16 : 16
    @command_window.y = 16
    @state = :busy
    refresh_info
  end

  def close_command
    @command_window.dispose if @command_window != nil
    @command_window = nil
  end

  #--------------------------------------------------------------------------
  # * Enemy AI
  #--------------------------------------------------------------------------
  def enemy_act(u)
    ai = FE_Config::ENEMY_AI[u.battler.id] || FE_Config::DEFAULT_AI
    @cx = u.x
    @cy = u.y
    center_camera(u.x, u.y)
    wait_camera
    wait(6)
    start = [u.x, u.y]
    mp = (ai == :hold) ? 0 : u.move_points
    r = search(u, mp)
    best = r[0]
    prev = r[1]
    occ  = r[2]
    plan = best_action(u, dest_keys(u, best, occ), best)
    if plan != nil
      move_along(u, build_path(prev, start, plan[0]))
      if plan[2] == nil
        run_combat(u, plan[1])
      elsif plan[1].is_a?(Array)            # area of effect: plan[1] = center tile
        run_ability(u, plan[2], nil, plan[1])
      else
        run_ability(u, plan[2], plan[1])
      end
    elsif ai == :charge
      move_along(u, approach_path(u, mp))
    end
    wait(6)
  end

  def move_along(u, path)
    return if path.empty?
    u.follow_path(path)
    wait_unit(u)
    @cx = u.x
    @cy = u.y
    wait(6)
  end

  # Pick the [tile, target] pair with the best score, or nil.
  # Pick the best [tile, target, skill-or-nil] plan, or nil.
  def best_action(u, stands, best)
    pick = nil
    top = nil
    skills = u.castable_skills
    stands.each do |k|
      @units.each do |t|
        if t.team != u.team and u.can_attack_from?(k[0], k[1], t)
          sc = attack_score(u, t, k) - best[k] * 0.01
          if top == nil or sc > top
            top = sc
            pick = [k, t, nil]
          end
        end
      end
      skills.each do |s|
        if FE_Spell.aoe(s)
          area_options(u, s, k).each do |o|
            sc = skill_score(u, s, nil, k, o[1])
            next if sc <= 0
            sc -= best[k] * 0.01 + s.sp_cost * 0.05
            if top == nil or sc > top
              top = sc
              pick = [k, o[0], s]
            end
          end
          next
        end
        skill_targets(u, s, k).each do |t|
          sc = skill_score(u, s, t, k)
          next if sc <= 0
          sc -= best[k] * 0.01 + s.sp_cost * 0.05
          if top == nil or sc > top
            top = sc
            pick = [k, t, s]
          end
        end
      end
    end
    return pick
  end

  # Expected value of casting s on t from tile k (<= 0 means pointless).
  # Map spells hit every living member of each victim stack.
  # victims: precomputed list (area of effect); units on the wrong side
  # (friendly fire) count against the plan.
  def skill_score(u, s, t, k, victims = nil)
    a = u.battler
    score = 0.0
    victims ||= skill_victims(u, s, t, k)
    victims.each do |v|
      wiped = true
      gain = 0.0
      v.alive_members.each do |b|
        d = FE_Combat.skill_damage(a, b, s)
        h = FE_Combat.skill_hit(a, b, s) / 100.0
        if FE_Spell.offensive?(s)
          gain += [d, b.hp].min * h if d > 0
          gain += 15 * h if s.power != 0 and d >= b.hp
          wiped = false unless s.power != 0 and d >= b.hp
          gain += 4 * h if (s.plus_state_set - b.states).size > 0
        else
          gain += [-d, b.maxhp - b.hp].min * h * 1.2 if d < 0
          gain += 4 * h if (s.minus_state_set & b.states).size > 0
          gain += 3 * h if s.power == 0 and (s.plus_state_set - b.states).size > 0
        end
      end
      gain += 50 if FE_Spell.offensive?(s) and wiped
      score += right_side?(u, s, v) ? gain : -1.5 * gain
    end
    return score
  end

  # Rough value of a battle-screen fight: one round in which every living
  # member of both stacks acts (estimated with RMXP's formula, no variance).
  def attack_score(u, t, k)
    a = u.battler
    d = t.battler
    mine   = u.alive_members.size * FE_Combat.damage(a, d) * FE_Combat.hit(a, d) / 100.0
    theirs = t.alive_members.size * FE_Combat.damage(d, a) * FE_Combat.hit(d, a) / 100.0
    score = [mine, t.total_hp].min
    score += 50 if mine >= t.total_hp
    score -= theirs / 2
    return score
  end

  # Path toward the closest tile from which some foe could be attacked,
  # cut off at the unit's move limit.
  def approach_path(u, mp)
    r = search(u, $game_map.width * $game_map.height * 4)
    best = r[0]
    prev = r[1]
    occ  = r[2]
    rng = u.threat_range
    rmax = rng[1]
    n = u.size
    goal = nil
    @units.each do |t|
      next if t.team == u.team
      for x in (t.x - rmax - n + 1)..(t.x + t.size - 1 + rmax)
        for y in (t.y - rmax - n + 1)..(t.y + t.size - 1 + rmax)
          k = [x, y]
          next if best[k] == nil or !free_at?(u, k, occ)
          next unless FE_Grid.in_reach?(x, y, n, t.x, t.y, t.size, rng)
          goal = k if goal == nil or best[k] < best[goal]
        end
      end
    end
    if goal == nil
      # Nobody reachable: just get as close as possible in a straight line.
      foes = @units.select { |o| o.team != u.team }
      return [] if foes.empty?
      near = best.keys.select { |k| best[k] <= mp and free_at?(u, k, occ) }
      goal = near.sort_by { |k|
        foes.collect { |f| FE_Grid.span(k[0], k[1], n, f.x, f.y, f.size)[0] }.min * 1000 + best[k]
      }[0]
      return [] if goal == nil
    end
    path = build_path(prev, [u.x, u.y], goal)
    stop = nil
    path.each_with_index do |k, i|
      break if best[k] > mp
      stop = i if free_at?(u, k, occ)
    end
    return stop == nil ? [] : path[0..stop]
  end

  #--------------------------------------------------------------------------
  # * Combat
  #--------------------------------------------------------------------------
  def run_combat(a, b)
    @cx = b.x
    @cy = b.y
    a.face(b.x, b.y)
    b.face(a.x, a.y)
    wait(10)
    if a.player?
      run_skirmish(a, b)
    else
      run_skirmish(b, a)
    end
    wait(10)
    [a, b].each { |u| kill_unit(u) if u.dead? and @units.include?(u) }
  end

  # One fight in the default RMXP battle screen: the player stack is the
  # party, the enemy stack is the troop. Runs nested, then the map resumes.
  def run_skirmish(pl, foe)
    enemies = foe.alive_members
    enemies.each_with_index do |e, i|
      e.fe_index = i
      e.fe_x = 640 * (i + 1) / (enemies.size + 1)
      e.fe_y = 280 - (i % 2) * 40
    end
    party = $game_party.actors
    $game_party.fe_actors = pl.members
    $game_troop.fe_stack = enemies
    $game_temp.battle_troop_id = @troop_id
    $game_temp.battle_can_escape = false
    $game_temp.battle_can_lose = true
    $game_temp.battle_proc = nil
    $game_system.se_play($data_system.battle_start_se)
    Graphics.freeze
    shown = set_map_visible(false)
    battle = Scene_FESkirmish.new(self)
    $scene = battle
    battle.main
    $game_party.fe_actors = party
    $game_troop.fe_release
    set_map_visible(true, shown)
    Graphics.transition(20)
  end

  # Hide / show everything the map scene draws (the battle screen draws on
  # top of the same screen). Returns the windows that were visible.
  def set_map_visible(on, shown = nil)
    wins = [@info_window, @forecast_window, @combat_window, @help_window,
            @command_window, @list_window].compact
    if on
      shown.each { |w| w.visible = true unless w.disposed? }
    else
      shown = wins.select { |w| w.visible }
      wins.each { |w| w.visible = false }
    end
    [@spriteset.viewport1, @spriteset.viewport2, @spriteset.viewport3].each do |v|
      v.visible = on
    end
    return shown
  end

  # Cast a spell or use an item (s = RPG::Skill or RPG::Item).
  # It affects every living member of each target stack.
  # center: tile an area-of-effect skill is aimed at (then primary may be nil).
  def run_ability(caster, s, primary, center = nil)
    if center != nil
      victims = area_victims(caster, s, center)
      primary = victims.find { |v| right_side?(caster, s, v) } || victims[0] || caster
      @cx = center[0]
      @cy = center[1]
      caster.face(center[0], center[1]) if center != [caster.x, caster.y]
      FE_Spell.area_tiles(center[0], center[1], FE_Spell.aoe(s)).each do |k|
        add_tile(k, @bmp_area) if $game_map.valid?(k[0], k[1])
      end
    else
      victims = skill_victims(caster, s, primary)
      @cx = primary.x
      @cy = primary.y
      caster.face(primary.x, primary.y) if primary != caster
    end
    primary.face(caster.x, caster.y) if primary != caster and primary.team != caster.team
    @combat_window.setup(caster, primary)
    item = s.is_a?(RPG::Item)
    if item
      $game_party.lose_item(s.id, 1) if s.consumable
    else
      caster.battler.sp -= s.sp_cost
    end
    @help_window.set_text(s.name, 1)
    @help_window.y = 0
    @help_window.visible = true
    wait(10)
    caster.sprite.flash(Color.new(255, 255, 255, 160), 8)
    if s.animation1_id > 0
      caster.animation_id = s.animation1_id
      wait_effects(caster)
    else
      wait(8)
    end
    if s.animation2_id > 0
      victims.each { |v| v.animation_id = s.animation2_id }
      update_basic
      update_basic while victims.find { |v| v.sprite.effect? } != nil
    end
    victims.each { |v| item ? apply_item(v, s) : apply_skill(caster, v, s) }
    clear_tiles if center != nil
    update_basic
    update_basic while victims.find { |v| v.sprite.effect? } != nil
    @combat_window.refresh
    @help_window.visible = false
    @help_window.y = 416
    wait(16)
    ([caster] + victims).uniq.each { |v| kill_unit(v) if v.dead? and @units.include?(v) }
    @combat_window.visible = false
  end

  # Skill on every living member of stack v; pops the stack's total.
  def apply_skill(caster, v, s)
    a = caster.battler
    total = 0
    hit = false
    changed = false
    crit = false
    # Critical hits from the Attributes script (skills marked "can crit").
    sc = (defined?(Attributes) and a.respond_to?(:critical_hit?)) ? Attributes.skill_crit(s.id) : [false]
    v.alive_members.each do |b|
      next unless rand(100) < FE_Combat.skill_hit(a, b, s)
      hit = true
      before = b.states.dup
      old = b.hp
      dmg = FE_Combat.skill_damage(a, b, s)
      if dmg > 0 and sc[0] and a.critical_hit?(sc[1])
        dmg = a.apply_crit_damage(dmg, sc[2])
        crit = true
      end
      b.hp -= dmg
      total += old - b.hp
      b.states_plus(s.plus_state_set)
      b.states_minus(s.minus_state_set)
      changed = true if b.states != before
    end
    if hit and s.power != 0
      v.sprite.damage(total, crit)
    elsif hit and changed
      v.sprite.damage("", false)
    else
      v.sprite.damage("Miss", false)
    end
    mark_stuck(v)
  end

  # Item on every living member of stack v; pops the stack's total.
  def apply_item(v, it)
    hit = false
    changed = false
    hp_total = 0
    sp_total = 0
    v.alive_members.each do |b|
      next unless rand(100) < it.hit
      hit = true
      before = b.states.dup
      old_hp = b.hp
      old_sp = b.sp
      b.hp += FE_Combat.item_hp(b, it)
      b.sp += FE_Combat.item_sp(b, it)
      hp_total += b.hp - old_hp
      sp_total += b.sp - old_sp
      b.states_plus(it.plus_state_set)
      b.states_minus(it.minus_state_set)
      n = it.parameter_points
      case it.parameter_type
      when 1 then b.maxhp += n
      when 2 then b.maxsp += n
      when 3 then b.str += n
      when 4 then b.dex += n
      when 5 then b.agi += n
      when 6 then b.int += n
      end
      changed = true if b.states != before or it.parameter_type != 0
    end
    if !hit
      v.sprite.damage("Miss", false)
    elsif hp_total != 0
      v.sprite.damage(-hp_total, false)
    elsif sp_total != 0
      v.sprite.damage(-sp_total, false)
    elsif changed
      v.sprite.damage("", false)
    else
      v.sprite.damage("Miss", false)
    end
    mark_stuck(v)
  end

  # A stack whose living members all can't move loses its turn.
  def mark_stuck(v)
    return unless v.stuck?
    v.acted = true
    v.idle = false
    v.sprite.tone = Tone.new(0, 0, 0, 255)
  end

  def kill_unit(u)
    se = u.player? ? $data_system.actor_collapse_se : $data_system.enemy_collapse_se
    $game_system.se_play(se)
    u.sprite.flash(Color.new(255, 255, 255, 255), 12)
    for i in 1..24
      u.opacity = 255 - i * 10
      update_basic
    end
    u.opacity = 0
    @units.delete(u)
    u.sprite.dispose
    dispose_hp_bar(u)
    @shown_enemy = nil if @shown_enemy == u
  end

  #--------------------------------------------------------------------------
  # * Victory / defeat
  #--------------------------------------------------------------------------
  def check_battle_end
    return true if @ended
    if units_of(:enemy).empty?
      end_battle(0)
    elsif units_of(:player).empty?
      end_battle(2)
    elsif @lord_deployed and
          @units.find { |u| u.player? and u.battler.id == FE_Config::LORD_ACTOR_ID } == nil
      end_battle(2)
    end
    return @ended
  end

  def end_battle(result)
    @ended = true
    close_command
    clear_tiles
    @state = :busy
    refresh_info
    @forecast_window.visible = false
    if result == 0
      $game_system.me_play($game_system.battle_end_me)
      show_banner(FE_Config::TEXT_VICTORY, Color.new(255, 230, 120))
    else
      show_banner(FE_Config::TEXT_DEFEAT, Color.new(180, 180, 180))
    end
    wait(30)
    restore_and_leave(result)
  end

  def restore_and_leave(result)
    @ended = true
    if result != nil and FE_Config::RESULT_VARIABLE > 0
      $game_variables[FE_Config::RESULT_VARIABLE] = result
      $game_map.need_refresh = true
    end
    $game_party.actors.each { |a| a.remove_states_battle }
    if FE_Config::REVIVE_AFTER
      $game_party.actors.each { |a| a.hp = 1 if a.dead? }
    end
    $game_player.transparent = @player_was_transparent
    $game_map.display_x = @saved_dx
    $game_map.display_y = @saved_dy
    $game_system.bgm_play(@map_bgm) if FE_Config::PLAY_BATTLE_BGM
    if result == 2 and !@can_lose
      $scene = Scene_Gameover.new
    else
      $scene = Scene_Map.new
    end
  end

  #--------------------------------------------------------------------------
  # * Phase banner
  #--------------------------------------------------------------------------
  def show_banner(text, color)
    s = Sprite.new
    s.bitmap = Bitmap.new(640, 72)
    s.bitmap.fill_rect(0, 0, 640, 72, Color.new(0, 0, 0, 160))
    s.bitmap.fill_rect(0, 0, 640, 2, color)
    s.bitmap.fill_rect(0, 70, 640, 2, color)
    s.bitmap.font.size = 32
    s.bitmap.font.color = color
    s.bitmap.draw_text(0, 0, 640, 72, text, 1)
    s.y = 204
    s.z = 600
    s.opacity = 0
    12.times { s.opacity += 22; update_basic }
    s.opacity = 255
    wait(45)
    12.times { s.opacity -= 22; update_basic }
    s.bitmap.dispose
    s.dispose
  end

  #--------------------------------------------------------------------------
  # * Dispose
  #--------------------------------------------------------------------------
  def dispose_hp_bar(u)
    return if u.hp_bar == nil
    u.hp_bar.bitmap.dispose
    u.hp_bar.dispose
    u.hp_bar = nil
  end

  def dispose_graphics
    close_command
    close_list
    @units.each do |u|
      u.sprite.dispose
      dispose_hp_bar(u)
    end
    @tile_pool.each { |s| s.dispose }
    @cursor.bitmap.dispose
    @cursor.dispose
    @bmp_move.dispose
    @bmp_atk.dispose
    @bmp_heal.dispose
    @bmp_area.dispose
    @help_window.dispose
    @info_window.dispose
    @forecast_window.dispose
    @combat_window.dispose
    @spriteset.dispose
  end
end
