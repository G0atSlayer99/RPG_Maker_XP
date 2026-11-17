#==============================================================================
# ** Attributes  v2.0
#------------------------------------------------------------------------------
#  Extra database attributes, edited with AttributesEditor.exe (the panel that
#  opens next to the Database window) and stored in Data/Attributes.rxdata.
#  There is nothing to edit in this script.
#
#  Crit Rate   : chance (0 - 100 %) that an attack / skill is a critical hit
#  Crit Damage : extra damage of a critical hit in % (100 = double damage)
#    Actors  : value at level 1 + growth per level
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
  # * Roll for a critical hit
  #--------------------------------------------------------------------------
  def critical_hit?(extra_rate = 0)
    rate = [[crit_rate + extra_rate, 0].max, 100].min
    return rand * 100 < rate
  end
  #--------------------------------------------------------------------------
  # * Apply crit damage to a damage value
  #--------------------------------------------------------------------------
  def apply_crit_damage(damage, extra_damage = 0)
    bonus = Attributes.clamp_damage(crit_damage + extra_damage)
    return (damage * (100 + bonus) / 100.0).round
  end
  #--------------------------------------------------------------------------
  # * Applying Normal Attack Effects (default code, new critical hit)
  #--------------------------------------------------------------------------
  def attack_effect(attacker)
    self.critical = false
    hit_result = (rand(100) < attacker.hit)
    if hit_result == true
      atk = [attacker.atk - self.pdef / 2, 0].max
      self.damage = atk * (20 + attacker.str) / 20
      self.damage *= elements_correct(attacker.element_set)
      self.damage /= 100
      if self.damage > 0
        if attacker.critical_hit?
          self.damage = attacker.apply_crit_damage(self.damage)
          self.critical = true
        end
        if self.guarding?
          self.damage /= 2
        end
      end
      if self.damage.abs > 0
        amp = [self.damage.abs * 15 / 100, 1].max
        self.damage += rand(amp+1) + rand(amp+1) - amp
      end
      eva = 8 * self.agi / attacker.dex + self.eva
      hit = self.damage < 0 ? 100 : 100 - eva
      hit = self.cant_evade? ? 100 : hit
      hit_result = (rand(100) < hit)
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
  #--------------------------------------------------------------------------
  def base_crit_rate
    v = Attributes.actor_crit(@actor_id)
    n = v[0] + v[1] * (@level - 1)
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
  #--------------------------------------------------------------------------
  def base_crit_rate
    return Attributes.enemy_crit(@enemy_id)[0]
  end
  #--------------------------------------------------------------------------
  def base_crit_damage
    return Attributes.enemy_crit(@enemy_id)[1]
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
