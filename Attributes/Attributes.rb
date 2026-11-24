#==============================================================================
# ** Attributes  v2.4
#------------------------------------------------------------------------------
#  Extra database attributes, edited with AttributesEditor.exe (the panel that
#  opens next to the Database window) and stored in Data/Attributes.rxdata.
#  There is nothing to edit in this script.
#
#  Actors edited in the panel (Actors page) use the panel's values instead of
#  the Database:
#    Name, Class, start Level, Max level (up to 100), EXP per level-up
#    HP -> MaxHP   SP -> MaxSP   Str -> STR   Mg -> INT   Spd -> AGI
#    Luck -> DEX   Def -> added to PDEF   Res -> added to MDEF
#    Crtr / CrtD -> Crit Rate / Crit Damage   Move -> FE Tactics move points
#  Each attribute has a level 1 value and a max level value.
#  HP, SP, Str, Mg, Spd, Luck, Def and Res grow with the class growth
#  ("Klassen-Wachstum" window, Classes tab): on every level-up one roll per
#  stat, r = rand(100): r < p2 -> +2, r < p2 + p1 -> +1, otherwise +0, with the
#  chances of the actor's current class. Value = level 1 value + all gains,
#  capped by the actor's max level value and by HP 10000, SP 1000, others 100
#  (RPG Maker XP itself still limits MaxHP / MaxSP to 9999). The gains are
#  kept in the actor (and save file); level-downs keep them.
#  Crtr, CrtD and Move stay at their level 1 value.
#  Actors not edited in the panel keep the Database values, but every actor
#  needs EXP_PER_LEVEL (100) EXP per level-up (edited ones: the panel's
#  "EXP per level-up"), up to the Database / panel max level.
#  Loading a save rebuilds every actor's EXP table from these settings and
#  caps HP / SP at their maximum, so panel changes also reach old saves.
#
#  BATTLE RULES (v2.4; every battle: default battle screen and FE Tactics)
#    Luck = DEX (actors: panel "Luck", enemies: panel or Database DEX).
#    Attack hit chance = 100 + attacker Luck - target Luck (in %); Database
#      hit / evasion rates are not used ("can't evade" states: at least 100).
#    Attack damage = attacker Str - target Def (0 or more, no random spread,
#      no elements, no Guard). Magic damage = Mg - Res (Attributes.magic_damage)
#      is ready for the skill rework; skills still use the Database formula.
#    Critical hit: chance = attacker CrtR + attacker Luck (%), damage x CrtD
#      (CrtD 100 = x2). The target's Luck does not lower it.
#    Turn order: highest Spd first; tie: higher Luck; tie: actors before
#      enemies, then party / troop order. Guard is removed from the commands.
#    Equipment is ignored for actors edited in the panel (no weapon ATK, no
#      armor Def / Res, no equipment crit bonus) until the equipment rework.
#  ENEMIES edited in the panel (Enemies page): every stat has a level 1 and a
#    max level value; at level L it is level 1 value + (max - level 1) *
#    (L - 1) / (max level - 1). The level comes from FE Tactics markers
#    (<Enemy 1 Lv5>), otherwise 1. EXP, Gold, Move and Size (1 = 1 tile,
#    2 = 2x2, 3 = 3x3 in FE Tactics) are set in the panel too.
#
#  Crit Rate   : chance (0 - 100 %) that an attack / skill is a critical hit
#  Crit Damage : extra damage of a critical hit in % (100 = double damage)
#    Actors  : panel value (or: value at level 1 + growth per level)
#              + weapon / armor bonuses + state bonuses
#    Enemies : fixed value + state bonuses
#    Skills  : can crit only if enabled for the skill; may add extra rate/damage
#
#  Skill range / area of effect are read by the FE Tactics script
#  (Attributes.get("skills", id, "range_min") etc.).
#
#  Script calls (Event command "Script..."):
#    $game_actors[1].crit_rate_plus   += 5     # permanent +5 % crit rate
#    $game_actors[1].crit_damage_plus += 25    # permanent +25 % crit damage
#    $game_actors[1].crit_rate                 # current crit rate
#    $game_actors[1].crit_damage               # current crit damage
#    $game_actors[1].attr_growth               # gains so far, e.g. {"str"=>4}
#    $game_actors[1].last_growth               # gains of the last level-up
#
#  Place this script below the default scripts and above "Main".
#  It replaces Game_Battler#attack_effect and #skill_effect.
#==============================================================================

module Attributes
  CONFIG_FILE = "Data/Attributes.rxdata"
  OLD_FILE    = "Data/CritConfig.rxdata"     # v1 ("Crit Stats") file
  # Key order of the v1 file, which stored arrays instead of hashes.
  OLD_KEYS = {
    "actors"  => ["crit_rate", "crit_rate_growth", "crit_damage", "crit_damage_growth"],
    "enemies" => ["crit_rate", "crit_damage"],
    "weapons" => ["crit_rate", "crit_damage"],
    "armors"  => ["crit_rate", "crit_damage"],
    "states"  => ["crit_rate", "crit_damage"],
    "skills"  => ["can_crit", "crit_rate", "crit_damage"]
  }
  #--------------------------------------------------------------------------
  # * Configuration (loaded once)
  #--------------------------------------------------------------------------
  def self.config
    if @config == nil
      @config = load_file(CONFIG_FILE)
      @config = convert_old(load_file(OLD_FILE)) if @config == nil
      @config = {} if @config == nil
    end
    return @config
  end
  #--------------------------------------------------------------------------
  def self.load_file(file)
    begin
      data = load_data(file)
      return data.is_a?(Hash) ? data : nil
    rescue
      return nil
    end
  end
  #--------------------------------------------------------------------------
  def self.convert_old(old)
    return nil if old == nil
    result = { "settings" => old["settings"] }
    OLD_KEYS.each do |name, keys|
      section = {}
      (old[name] || {}).each do |id, values|
        next unless values.is_a?(Array)
        entry = {}
        keys.each_with_index { |k, i| entry[k] = values[i] }
        section[id] = entry
      end
      result[name] = section
    end
    return result
  end
  #--------------------------------------------------------------------------
  def self.section(name)
    s = config[name]
    return s.is_a?(Hash) ? s : {}
  end
  #--------------------------------------------------------------------------
  def self.setting(key, default)
    s = section("settings")
    return s.has_key?(key) ? s[key] : default
  end
  #--------------------------------------------------------------------------
  # * Attribute of one database entry, e.g. get("skills", 7, "range_max")
  #   Returns default if it was never set in the editor.
  #--------------------------------------------------------------------------
  def self.get(name, id, key, default = nil)
    e = section(name)[id]
    return default unless e.is_a?(Hash) and e.has_key?(key)
    return e[key]
  end
  #--------------------------------------------------------------------------
  def self.set?(name, id, key)
    e = section(name)[id]
    return (e.is_a?(Hash) and e.has_key?(key))
  end
  #--------------------------------------------------------------------------
  # * [rate at Lv1, rate per level, damage at Lv1, damage per level]
  #--------------------------------------------------------------------------
  def self.actor_crit(id)
    d = setting("actor_default", [5.0, 0.0, 100.0, 0.0])
    return d unless set?("actors", id, "crit_rate")
    return [get("actors", id, "crit_rate", d[0]), get("actors", id, "crit_rate_growth", d[1]),
            get("actors", id, "crit_damage", d[2]), get("actors", id, "crit_damage_growth", d[3])]
  end
  #--------------------------------------------------------------------------
  # * Actor attributes from the Actors page
  #--------------------------------------------------------------------------
  MAX_LEVEL = 100
  EXP_PER_LEVEL = 100   # EXP per level-up for actors not edited in the panel
  def self.actor_edited?(id)
    return set?("actors", id, "hp")
  end
  #--------------------------------------------------------------------------
  # * [start level, max level, EXP per level-up], nil if not edited
  #--------------------------------------------------------------------------
  def self.actor_level(id)
    return nil unless actor_edited?(id)
    max = [[get("actors", id, "max_level", 99).to_i, 1].max, MAX_LEVEL].min
    lv  = [[get("actors", id, "level", 1).to_i, 1].max, max].min
    exp = [get("actors", id, "exp_per_level", 100).to_i, 1].max
    return [lv, max, exp]
  end
  #--------------------------------------------------------------------------
  # * [value at level 1, value at max level], nil if not edited
  #   key: "hp", "sp", "str", "mg", "crit_rate", "crit_damage", "spd",
  #        "luck", "def", "res", "move"
  #--------------------------------------------------------------------------
  def self.actor_stat(id, key)
    return nil unless actor_edited?(id)
    v = get("actors", id, key, 0).to_i
    return [v, [get("actors", id, key + "_max", v).to_i, v].max]
  end
  #--------------------------------------------------------------------------
  # * Value of an attribute at a level, nil if not edited.
  #   The level-up system will fill in the levels between; for now:
  #   level 1 value below the max level, max level value at the max level.
  #--------------------------------------------------------------------------
  def self.actor_value(id, key, level)
    s = actor_stat(id, key)
    return nil if s == nil
    return s[0]
  end
  #--------------------------------------------------------------------------
  # * Class growth (Klassen-Wachstum)
  #--------------------------------------------------------------------------
  GROWTH_KEYS = ["hp", "sp", "str", "mg", "spd", "luck", "def", "res"]
  GROWTH_DEFAULT = {
    "hp" => [60, 30], "sp" => [50, 10], "str" => [45, 10], "mg" => [20, 0],
    "spd" => [40, 5], "luck" => [30, 5], "def" => [40, 10], "res" => [20, 0]
  }
  GROWTH_CAP = {
    "hp" => 10000, "sp" => 1000, "str" => 100, "mg" => 100,
    "spd" => 100, "luck" => 100, "def" => 100, "res" => 100
  }
  #--------------------------------------------------------------------------
  # * [+1 chance, +2 chance] in % of a class for a stat
  #--------------------------------------------------------------------------
  def self.class_growth(class_id, key)
    d = GROWTH_DEFAULT[key] || [0, 0]
    p2 = [[get("classes", class_id, key + "_p2", d[1]).to_i, 0].max, 100].min
    p1 = [[get("classes", class_id, key + "_p1", d[0]).to_i, 0].max, 100 - p2].min
    return [p1, p2]
  end
  #--------------------------------------------------------------------------
  # * One level-up roll: 0, 1 or 2
  #--------------------------------------------------------------------------
  def self.roll_growth(class_id, key)
    g = class_growth(class_id, key)
    r = rand(100)
    return 2 if r < g[1]
    return 1 if r < g[1] + g[0]
    return 0
  end
  #--------------------------------------------------------------------------
  # * Enemies edited in the panel
  #--------------------------------------------------------------------------
  ENEMY_KEYS = ["hp", "sp", "str", "mg", "spd", "luck", "def", "res", "move",
                "crit_rate", "crit_damage"]
  def self.enemy_edited?(id)
    return set?("enemies", id, "hp")
  end
  def self.enemy_max_level(id)
    return [[get("enemies", id, "max_level", 1).to_i, 1].max, MAX_LEVEL].min
  end
  # Stat of an edited enemy at a level (nil if the enemy is not edited)
  def self.enemy_value(id, key, level)
    return nil unless enemy_edited?(id)
    v1 = get("enemies", id, key, 0).to_i
    top = get("enemies", id, key + "_max", v1).to_i
    ml = enemy_max_level(id)
    return v1 if ml <= 1
    l = [[level.to_i, 1].max, ml].min
    return v1 + (top - v1) * (l - 1) / (ml - 1)
  end
  # FE Tactics size in tiles (1 = 1x1, 2 = 2x2, 3 = 3x3)
  def self.enemy_size(id)
    return [[get("enemies", id, "size", 1).to_i, 1].max, 3].min
  end
  #--------------------------------------------------------------------------
  # * [rate, damage]
  #--------------------------------------------------------------------------
  def self.enemy_crit(id)
    d = setting("enemy_default", [5.0, 100.0])
    return d unless set?("enemies", id, "crit_rate")
    return [get("enemies", id, "crit_rate", d[0]), get("enemies", id, "crit_damage", d[1])]
  end
  #--------------------------------------------------------------------------
  # * [rate bonus, damage bonus]  name: "weapons", "armors" or "states"
  #--------------------------------------------------------------------------
  def self.crit_bonus(name, id)
    return [get(name, id, "crit_rate", 0), get(name, id, "crit_damage", 0)]
  end
  #--------------------------------------------------------------------------
  # * [can crit, extra rate, extra damage]
  #--------------------------------------------------------------------------
  def self.skill_crit(id)
    return [get("skills", id, "can_crit", false) == true,
            get("skills", id, "crit_rate", 0), get("skills", id, "crit_damage", 0)]
  end
  #--------------------------------------------------------------------------
  def self.clamp_damage(value)
    value = [value, 0].max
    limit = setting("max_crit_damage", 0.0).to_f
    value = [value, limit].min if limit > 0
    return value
  end
  #--------------------------------------------------------------------------
  def self.format(value, sign = false)
    v = (value * 10).round / 10.0
    text = (v == v.to_i) ? v.to_i.to_s : v.to_s
    text = "+" + text if sign and v > 0
    return text + "%"
  end
end

#==============================================================================
# ** Game_Battler
#==============================================================================

class Game_Battler
  attr_writer :crit_rate_plus
  attr_writer :crit_damage_plus
  #--------------------------------------------------------------------------
  def crit_rate_plus
    return @crit_rate_plus || 0
  end
  #--------------------------------------------------------------------------
  def crit_damage_plus
    return @crit_damage_plus || 0
  end
  #--------------------------------------------------------------------------
  def base_crit_rate
    return 0
  end
  #--------------------------------------------------------------------------
  def base_crit_damage
    return 100
  end
  #--------------------------------------------------------------------------
  # * Crit Rate in % (0 - 100)
  #--------------------------------------------------------------------------
  def crit_rate
    n = base_crit_rate + crit_rate_plus
    for i in @states
      n += Attributes.crit_bonus("states", i)[0]
    end
    return [[n, 0].max, 100].min
  end
  #--------------------------------------------------------------------------
  # * Crit Damage in % (extra damage, 100 = double damage)
  #--------------------------------------------------------------------------
  def crit_damage
    n = base_crit_damage + crit_damage_plus
    for i in @states
      n += Attributes.crit_bonus("states", i)[1]
    end
    return Attributes.clamp_damage(n)
  end
  #--------------------------------------------------------------------------
  # * Luck (= DEX)
  #--------------------------------------------------------------------------
  def luck
    return dex
  end
  #--------------------------------------------------------------------------
  # * Crit chance in % = CrtR + Luck (the target does not lower it)
  #--------------------------------------------------------------------------
  def crit_chance(extra_rate = 0)
    return [[crit_rate + luck + extra_rate, 0].max, 100].min
  end
  #--------------------------------------------------------------------------
  # * Roll for a critical hit
  #--------------------------------------------------------------------------
  def critical_hit?(extra_rate = 0)
    return rand * 100 < crit_chance(extra_rate)
  end
  #--------------------------------------------------------------------------
  # * Attack hit chance in % on target = 100 + own Luck - target Luck
  #--------------------------------------------------------------------------
  def hit_chance_on(target)
    h = 100 + luck - target.luck
    h = [h, 100].max if target.cant_evade?
    return [h, 0].max
  end
  #--------------------------------------------------------------------------
  # * Attack damage on target = Str - Def (0 or more)
  #--------------------------------------------------------------------------
  def attack_damage_to(target)
    return [str - target.pdef, 0].max
  end
  #--------------------------------------------------------------------------
  # * Magic damage on target = Mg - Res (0 or more; for the skill rework)
  #--------------------------------------------------------------------------
  def magic_damage_to(target)
    return [int - target.mdef, 0].max
  end
  #--------------------------------------------------------------------------
  # * Guard is removed from battles
  #--------------------------------------------------------------------------
  def guarding?
    return false
  end
  #--------------------------------------------------------------------------
  # * Turn order value: Spd (no random part)
  #--------------------------------------------------------------------------
  def make_action_speed
    @current_action.speed = agi
  end
  #--------------------------------------------------------------------------
  # * Apply crit damage to a damage value
  #--------------------------------------------------------------------------
  def apply_crit_damage(damage, extra_damage = 0)
    bonus = Attributes.clamp_damage(crit_damage + extra_damage)
    return (damage * (100 + bonus) / 100.0).round
  end
  #--------------------------------------------------------------------------
  # * Normal attack (v2.4 rules): hit = 100 + Luck - target Luck,
  #   damage = Str - Def, crit = CrtR + Luck -> damage x CrtD
  #--------------------------------------------------------------------------
  def attack_effect(attacker)
    self.critical = false
    hit_result = (rand(100) < attacker.hit_chance_on(self))
    if hit_result == true
      self.damage = attacker.attack_damage_to(self)
      if self.damage > 0 and attacker.critical_hit?
        self.damage = attacker.apply_crit_damage(self.damage)
        self.critical = true
      end
    end
    if hit_result == true
      remove_states_shock
      self.hp -= self.damage
      @state_changed = false
      states_plus(attacker.plus_state_set)
      states_minus(attacker.minus_state_set)
    else
      self.damage = "Miss"
      self.critical = false
    end
    return true
  end
  #--------------------------------------------------------------------------
  # * Apply Skill Effects (default code, skills can now crit)
  #--------------------------------------------------------------------------
  def skill_effect(user, skill)
    self.critical = false
    if ((skill.scope == 3 or skill.scope == 4) and self.hp == 0) or
       ((skill.scope == 5 or skill.scope == 6) and self.hp >= 1)
      return false
    end
    effective = false
    effective |= skill.common_event_id > 0
    hit = skill.hit
    if skill.atk_f > 0
      hit *= user.hit / 100
    end
    hit_result = (rand(100) < hit)
    effective |= hit < 100
    if hit_result == true
      power = skill.power + user.atk * skill.atk_f / 100
      if power > 0
        power -= self.pdef * skill.pdef_f / 200
        power -= self.mdef * skill.mdef_f / 200
        power = [power, 0].max
      end
      rate = 20
      rate += (user.str * skill.str_f / 100)
      rate += (user.dex * skill.dex_f / 100)
      rate += (user.agi * skill.agi_f / 100)
      rate += (user.int * skill.int_f / 100)
      self.damage = power * rate / 20
      self.damage *= elements_correct(skill.element_set)
      self.damage /= 100
      if self.damage > 0
        crit = Attributes.skill_crit(skill.id)
        if crit[0] and user.critical_hit?(crit[1])
          self.damage = user.apply_crit_damage(self.damage, crit[2])
          self.critical = true
        end
        if self.guarding?
          self.damage /= 2
        end
      end
      if skill.variance > 0 and self.damage.abs > 0
        amp = [self.damage.abs * skill.variance / 100, 1].max
        self.damage += rand(amp+1) + rand(amp+1) - amp
      end
      eva = 8 * self.agi / user.dex + self.eva
      hit = self.damage < 0 ? 100 : 100 - eva * skill.eva_f / 100
      hit = self.cant_evade? ? 100 : hit
      hit_result = (rand(100) < hit)
      effective |= hit < 100
    end
    if hit_result == true
      if skill.power != 0 and skill.atk_f > 0
        remove_states_shock
        effective = true
      end
      last_hp = self.hp
      self.hp -= self.damage
      effective |= self.hp != last_hp
      @state_changed = false
      effective |= states_plus(skill.plus_state_set)
      effective |= states_minus(skill.minus_state_set)
      if skill.power == 0
        self.damage = ""
        unless @state_changed
          self.damage = "Miss"
        end
        self.critical = false
      end
    else
      self.damage = "Miss"
      self.critical = false
    end
    unless $game_temp.in_battle
      self.damage = nil
    end
    return effective
  end
end

#==============================================================================
# ** Game_Actor
#==============================================================================

class Game_Actor < Game_Battler
  unless method_defined?(:attributes_setup)
    alias attributes_setup         setup
    alias attributes_make_exp_list make_exp_list
    alias attributes_set_level     level=
    alias attributes_set_exp       exp=
    alias attributes_base_maxhp    base_maxhp
    alias attributes_base_maxsp    base_maxsp
    alias attributes_base_str      base_str
    alias attributes_base_dex      base_dex
    alias attributes_base_agi      base_agi
    alias attributes_base_int      base_int
    alias attributes_base_pdef     base_pdef
    alias attributes_base_mdef     base_mdef
  end
  #--------------------------------------------------------------------------
  # * Panel value of an attribute at the current level (nil = not edited)
  #--------------------------------------------------------------------------
  def attr_value(key)
    v = Attributes.actor_value(@actor_id, key, @level)
    return nil if v == nil
    return v unless Attributes::GROWTH_KEYS.include?(key)
    return [v + attr_growth[key].to_i, growth_cap(key)].min
  end
  #--------------------------------------------------------------------------
  # * Gains from class growth so far / of the last level-up
  #--------------------------------------------------------------------------
  def attr_growth
    @attr_growth = {} if @attr_growth == nil
    return @attr_growth
  end
  #--------------------------------------------------------------------------
  def last_growth
    @last_growth = {} if @last_growth == nil
    return @last_growth
  end
  #--------------------------------------------------------------------------
  # * Highest value of a stat: the actor's max level value and the global cap
  #--------------------------------------------------------------------------
  def growth_cap(key)
    s = Attributes.actor_stat(@actor_id, key)
    cap = Attributes::GROWTH_CAP[key] || 100
    cap = [cap, s[1]].min if s != nil
    return cap
  end
  #--------------------------------------------------------------------------
  # * Rolls the class growth for a number of level-ups
  #--------------------------------------------------------------------------
  def roll_growth(levels)
    return if levels < 1 or !Attributes.actor_edited?(@actor_id)
    @last_growth = {}
    levels.times do
      for key in Attributes::GROWTH_KEYS
        base = Attributes.actor_value(@actor_id, key, @level)
        have = base + attr_growth[key].to_i
        gain = [Attributes.roll_growth(@class_id, key), growth_cap(key) - have].min
        next if gain <= 0
        attr_growth[key] = attr_growth[key].to_i + gain
        @last_growth[key] = @last_growth[key].to_i + gain
      end
    end
  end
  #--------------------------------------------------------------------------
  # * EXP change: roll the growth for every level gained
  #--------------------------------------------------------------------------
  def exp=(exp)
    old = @level
    attributes_set_exp(exp)
    roll_growth(@level - old) if old != nil and @level > old
  end
  #--------------------------------------------------------------------------
  # * Move points for FE Tactics (nil = not edited)
  #--------------------------------------------------------------------------
  def attr_move
    return attr_value("move")
  end
  #--------------------------------------------------------------------------
  # * Setup: name, class and start level from the panel
  #--------------------------------------------------------------------------
  def setup(actor_id)
    attributes_setup(actor_id)
    lv = Attributes.actor_level(actor_id)
    return if lv == nil
    name = Attributes.get("actors", actor_id, "name")
    @name = name if name.is_a?(String)
    class_id = Attributes.get("actors", actor_id, "class_id")
    @class_id = class_id.to_i if class_id != nil and $data_classes[class_id.to_i] != nil
    @level = lv[0]
    make_exp_list
    @exp = @exp_list[@level]
    @attr_growth = {}
    roll_growth(@level - 1)   # recruits above level 1 get their earlier level-ups
    @skills = []
    for i in 1..@level
      for j in $data_classes[@class_id].learnings
        learn_skill(j.skill_id) if j.level == i
      end
    end
    @hp = maxhp
    @sp = maxsp
  end
  #--------------------------------------------------------------------------
  # * EXP list: the same EXP for every level-up, up to the max level
  #--------------------------------------------------------------------------
  def make_exp_list
    attributes_make_exp_list
    lv = Attributes.actor_level(@actor_id)
    if lv == nil   # not edited: EXP_PER_LEVEL each, up to the Database max level
      lv = [1, $data_actors[@actor_id].final_level, Attributes::EXP_PER_LEVEL]
    end
    @exp_list[1] = 0
    for i in 2..(Attributes::MAX_LEVEL + 1)
      @exp_list[i] = i <= lv[1] ? (i - 1) * lv[2] : 0
    end
  end
  #--------------------------------------------------------------------------
  # * After loading a save: EXP table from the current settings, EXP inside
  #   the current level, HP / SP not above their maximum
  #--------------------------------------------------------------------------
  def attributes_refresh_after_load
    make_exp_list
    low = @exp_list[@level] || 0
    nxt = @exp_list[@level + 1].to_i
    @exp = [@exp, low].max
    @exp = [@exp, nxt - 1].min if nxt > 0
    @hp = [@hp, maxhp].min
    @sp = [@sp, maxsp].min
  end
  #--------------------------------------------------------------------------
  def level=(level)
    lv = Attributes.actor_level(@actor_id)
    return attributes_set_level(level) if lv == nil
    level = [[level, lv[1]].min, 1].max
    self.exp = @exp_list[level]
  end
  #--------------------------------------------------------------------------
  def base_maxhp
    v = attr_value("hp")
    return v != nil ? v : attributes_base_maxhp
  end
  #--------------------------------------------------------------------------
  def base_maxsp
    v = attr_value("sp")
    return v != nil ? v : attributes_base_maxsp
  end
  #--------------------------------------------------------------------------
  def base_str
    v = attr_value("str")
    return v != nil ? v : attributes_base_str
  end
  #--------------------------------------------------------------------------
  def base_int
    v = attr_value("mg")
    return v != nil ? v : attributes_base_int
  end
  #--------------------------------------------------------------------------
  def base_agi
    v = attr_value("spd")
    return v != nil ? v : attributes_base_agi
  end
  #--------------------------------------------------------------------------
  def base_dex
    v = attr_value("luck")
    return v != nil ? v : attributes_base_dex
  end
  #--------------------------------------------------------------------------
  def base_pdef
    v = attr_value("def")                   # edited: panel Def only, no armor
    return v != nil ? v : attributes_base_pdef
  end
  #--------------------------------------------------------------------------
  def base_mdef
    v = attr_value("res")                   # edited: panel Res only, no armor
    return v != nil ? v : attributes_base_mdef
  end
  #--------------------------------------------------------------------------
  def base_crit_rate
    v = Attributes.actor_crit(@actor_id)
    n = v[0] + v[1] * (@level - 1)
    p = attr_value("crit_rate")
    return p if p != nil                    # edited: no equipment bonus
    n += Attributes.crit_bonus("weapons", @weapon_id)[0]
    for id in [@armor1_id, @armor2_id, @armor3_id, @armor4_id]
      n += Attributes.crit_bonus("armors", id)[0]
    end
    return n
  end
  #--------------------------------------------------------------------------
  def base_crit_damage
    v = Attributes.actor_crit(@actor_id)
    n = v[2] + v[3] * (@level - 1)
    p = attr_value("crit_damage")
    return p if p != nil                    # edited: no equipment bonus
    n += Attributes.crit_bonus("weapons", @weapon_id)[1]
    for id in [@armor1_id, @armor2_id, @armor3_id, @armor4_id]
      n += Attributes.crit_bonus("armors", id)[1]
    end
    return n
  end
end

#==============================================================================
# ** Game_Enemy
#==============================================================================

class Game_Enemy < Game_Battler
  unless method_defined?(:attributes_enemy_maxhp)
    alias attributes_enemy_maxhp base_maxhp
    alias attributes_enemy_maxsp base_maxsp
    alias attributes_enemy_str   base_str
    alias attributes_enemy_int   base_int
    alias attributes_enemy_agi   base_agi
    alias attributes_enemy_dex   base_dex
    alias attributes_enemy_pdef  base_pdef
    alias attributes_enemy_mdef  base_mdef
    alias attributes_enemy_exp   exp
    alias attributes_enemy_gold  gold
  end
  #--------------------------------------------------------------------------
  # * Level (FE Tactics markers <Enemy 1 Lv5>; otherwise 1). Setting it
  #   refills HP / SP to the new maximum.
  #--------------------------------------------------------------------------
  def level
    return @level || 1
  end
  def level=(lv)
    @level = [[lv.to_i, 1].max, Attributes::MAX_LEVEL].min
    @hp = maxhp
    @sp = maxsp
  end
  #--------------------------------------------------------------------------
  def enemy_attr(key)
    return Attributes.enemy_value(@enemy_id, key, level)
  end
  def base_maxhp; v = enemy_attr("hp");   return v != nil ? v : attributes_enemy_maxhp; end
  def base_maxsp; v = enemy_attr("sp");   return v != nil ? v : attributes_enemy_maxsp; end
  def base_str;   v = enemy_attr("str");  return v != nil ? v : attributes_enemy_str;   end
  def base_int;   v = enemy_attr("mg");   return v != nil ? v : attributes_enemy_int;   end
  def base_agi;   v = enemy_attr("spd");  return v != nil ? v : attributes_enemy_agi;   end
  def base_dex;   v = enemy_attr("luck"); return v != nil ? v : attributes_enemy_dex;   end
  def base_pdef;  v = enemy_attr("def");  return v != nil ? v : attributes_enemy_pdef;  end
  def base_mdef;  v = enemy_attr("res");  return v != nil ? v : attributes_enemy_mdef;  end
  #--------------------------------------------------------------------------
  # * Rewards: panel values for edited enemies
  #--------------------------------------------------------------------------
  def exp
    return attributes_enemy_exp unless Attributes.enemy_edited?(@enemy_id)
    return Attributes.get("enemies", @enemy_id, "exp", 0).to_i
  end
  def gold
    return attributes_enemy_gold unless Attributes.enemy_edited?(@enemy_id)
    return Attributes.get("enemies", @enemy_id, "gold", 0).to_i
  end
  # FE Tactics: move points (nil = not edited) and size in tiles
  def attr_move
    return enemy_attr("move")
  end
  def attr_size
    return Attributes.enemy_size(@enemy_id)
  end
  #--------------------------------------------------------------------------
  def base_crit_rate
    v = enemy_attr("crit_rate")
    return v != nil ? v : Attributes.enemy_crit(@enemy_id)[0]
  end
  #--------------------------------------------------------------------------
  def base_crit_damage
    v = enemy_attr("crit_damage")
    return v != nil ? v : Attributes.enemy_crit(@enemy_id)[1]
  end
end

#==============================================================================
# ** Scene_Battle - turn order by Spd / Luck, no Guard command
#==============================================================================
class Scene_Battle
  #--------------------------------------------------------------------------
  # * Turn order: Spd, then Luck, then actors before enemies, then the
  #   party / troop order
  #--------------------------------------------------------------------------
  def make_action_orders
    list = []
    $game_party.actors.each_with_index { |a, i| list.push([a, 0, i]) }
    $game_troop.enemies.each_with_index { |e, i| list.push([e, 1, i]) }
    list.each { |x| x[0].make_action_speed }
    list = list.sort_by { |x| [-x[0].agi, -x[0].luck, x[1], x[2]] }
    @action_battlers = list.collect { |x| x[0] }
  end
  #--------------------------------------------------------------------------
  # * Actor commands without Guard: Attack, Skill, Item
  #--------------------------------------------------------------------------
  unless method_defined?(:attributes_phase3_setup_command_window)
    alias attributes_phase3_setup_command_window phase3_setup_command_window
  end
  def phase3_setup_command_window
    if @actor_command_window.instance_variable_get(:@commands).size == 4
      w = @actor_command_window
      @actor_command_window = Window_Command.new(160, [$data_system.words.attack,
        $data_system.words.skill, $data_system.words.item])
      @actor_command_window.y = w.y
      @actor_command_window.z = w.z
      @actor_command_window.back_opacity = w.back_opacity
      @actor_command_window.active = false
      @actor_command_window.visible = false
      w.dispose
    end
    attributes_phase3_setup_command_window
  end
  #--------------------------------------------------------------------------
  def update_phase3_basic_command
    if Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      phase3_prior_actor
      return
    end
    if Input.trigger?(Input::C)
      case @actor_command_window.index
      when 0  # attack
        $game_system.se_play($data_system.decision_se)
        @active_battler.current_action.kind = 0
        @active_battler.current_action.basic = 0
        start_enemy_select
      when 1  # skill
        $game_system.se_play($data_system.decision_se)
        @active_battler.current_action.kind = 1
        start_skill_select
      when 2  # item
        $game_system.se_play($data_system.decision_se)
        @active_battler.current_action.kind = 2
        start_item_select
      end
      return
    end
  end
end

#==============================================================================
# ** Window_Status  (shows the crit stats in the menu's Status screen)
#==============================================================================

class Window_Status < Window_Base
  unless method_defined?(:attributes_refresh)
    alias attributes_refresh refresh
  end
  #--------------------------------------------------------------------------
  def refresh
    attributes_refresh
    return unless Attributes.setting("show_in_status", true)
    self.contents.font.color = system_color
    self.contents.draw_text(320, 106, 124, 32, Attributes.setting("rate_name", "Crit Rate"))
    self.contents.draw_text(320, 130, 124, 32, Attributes.setting("damage_name", "Crit Damage"))
    self.contents.font.color = normal_color
    self.contents.draw_text(404, 106, 80, 32, Attributes.format(@actor.crit_rate), 2)
    self.contents.draw_text(404, 130, 80, 32, Attributes.format(@actor.crit_damage, true), 2)
  end
end

#==============================================================================
# ** Game_Character  (FE Tactics move points)
#------------------------------------------------------------------------------
#  FE Tactics is placed below this script, so its Game_FEUnit#move_points is
#  wrapped the moment it is defined: actors edited in the panel use their Move
#  value, everyone else keeps the FE Tactics settings.
#==============================================================================

class Game_Character
  def self.method_added(name)
    super
    return unless name == :move_points and self.name == "Game_FEUnit"
    return if @attributes_patching
    @attributes_patching = true
    alias_method :attributes_move_points, :move_points
    define_method(:move_points) do
      m = nil
      if actor? and battler.respond_to?(:attr_move)
        m = battler.attr_move
      end
      m != nil ? m : attributes_move_points
    end
    @attributes_patching = false
  end
end

#==============================================================================
# ** Scene_Load - refresh every actor after loading a save
#==============================================================================
class Scene_Load
  alias attributes_read_save_data read_save_data
  def read_save_data(file)
    attributes_read_save_data(file)
    list = $game_actors.instance_variable_get(:@data) || []
    list.each { |a| a.attributes_refresh_after_load if a != nil }
  end
end
