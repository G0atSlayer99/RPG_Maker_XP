#==============================================================================
# ** Status Screen  (book style)
#------------------------------------------------------------------------------
#  Replaces the default Status screen with an open book:
#    left page   portrait, map sprite, level, name, class, state, KP / SP / EXP
#    right page  Werte (Str .. Move), crit rate / crit damage, Ausruestung
#  Static artwork: Graphics/Pictures/StatusBook.png and StatusBookIcons.png.
#  Everything else is drawn at runtime into one 640x480 bitmap.
#
#  Menu -> Status -> choose a character.  B: back,  L / R: previous / next.
#  Place below "Attributes", "FE Tactics" and "Windowskin", above "Main".
#  Source: RPGXP\Custom\StatusScreen\status_screen.rb (inject_script.py)
#==============================================================================

module StatusBook
  #--------------------------------------------------------------------------
  # * German names (database stays English). Missing entries show the
  #   database name.
  #--------------------------------------------------------------------------
  CLASS_NAMES = {
    "Fighter" => "Kämpfer",
    "Lancer"  => "Lanzenträger",
    "Warrior" => "Krieger",
    "Thief"   => "Dieb",
    "Hunter"  => "Jäger",
    "Gunner"  => "Schütze",
    "Cleric"  => "Kleriker",
    "Mage"    => "Magier"
  }
  STATE_NAMES = {
    "Knockout" => "K.O.",
    "Stun"     => "Betäubt",
    "Venom"    => "Vergiftet",
    "Dazzle"   => "Geblendet",
    "Mute"     => "Verstummt",
    "Confuse"  => "Verwirrt",
    "Sleep"    => "Schlaf",
    "Paralyze" => "Gelähmt",
    "Weaken"   => "Geschwächt",
    "Clumsy"   => "Ungeschickt",
    "Delay"    => "Verlangsamt",
    "Feeble"   => "Entkräftet",
    "Sharp"    => "Geschärft",
    "Barrier"  => "Barriere",
    "Resist"   => "Resistent",
    "Blink"    => "Flink"
  }
  # States shown in blue (good); every other state is red.
  GOOD_STATES = ["Sharp", "Barrier", "Resist", "Blink"]
  #--------------------------------------------------------------------------
  # * Face area of each battler graphic: "file" => [x, y, size] (pixels of
  #   the battler image). Battlers not listed use the top centre.
  #--------------------------------------------------------------------------
  FACE_RECTS = {
    "001-Fighter01" => [32,  6, 48],
    "010-Lancer02"  => [22, 32, 44],
    "013-Warrior01" => [64,  2, 46],
    "019-Thief04"   => [38,  0, 44],
    "022-Hunter03"  => [16,  6, 46],
    "023-Gunner01"  => [44, 26, 46],
    "029-Cleric05"  => [32,  8, 46],
    "038-Mage06"    => [46, 14, 46]
  }
  #--------------------------------------------------------------------------
  # * Fonts: first one installed wins
  #--------------------------------------------------------------------------
  FONTS = ["Alegreya", "Georgia", "Times New Roman"]
  # Numbers: a font with lining figures (Georgia's digits are old-style)
  NUMBER_FONTS = ["Alegreya", "Cambria", "Times New Roman"]
  # Vertical position of the baseline inside a text line, per pixel of size.
  ASCENT = 0.80
  #--------------------------------------------------------------------------
  # * Colours
  #--------------------------------------------------------------------------
  INK      = Color.new( 46,  31,  16)
  ITALIC   = Color.new( 94,  80,  62)
  FADED    = Color.new(150, 135, 115)
  RED      = Color.new(122,  31,  31)
  CREAM    = Color.new(241, 228, 195)
  BADGE_TX = Color.new(246, 236, 210)
  OK_GREEN = Color.new( 63, 106,  34)
  BAD_RED  = Color.new(160,  42,  36)
  GOOD_BLU = Color.new( 46,  74, 122)
  PILL_BG  = Color.new(239, 224, 186)
  KP_BAR   = Color.new(156,  42,  85)
  SP_BAR   = Color.new( 43,  92, 158)
  EXP_BAR  = Color.new(176, 140,  60)
  CRIT_ARC = Color.new(194,  69,  45)
  STAT_COLORS = [
    Color.new(176, 101,  42),   # Str
    Color.new(107,  63, 160),   # Mg
    Color.new( 78, 138,  43),   # Spd
    Color.new( 46, 138,  92),   # Luck
    Color.new( 46,  74, 122),   # Def
    Color.new( 42, 133, 128),   # Res
    Color.new(122,  90,  46)    # Move
  ]
  STAT_SCALE = 100
  MOVE_SCALE = 25

  #--------------------------------------------------------------------------
  def self.first_font(list)
    for name in list
      return name if !Font.respond_to?(:exist?) or Font.exist?(name)
    end
    return list[-1]
  end
  #--------------------------------------------------------------------------
  def self.font_name
    @font_name = first_font(FONTS) if @font_name == nil
    return @font_name
  end
  #--------------------------------------------------------------------------
  def self.number_font_name
    @number_font_name = first_font(NUMBER_FONTS) if @number_font_name == nil
    return @number_font_name
  end
  #--------------------------------------------------------------------------
  def self.german_class(actor)
    n = $data_classes[actor.class_id] ? $data_classes[actor.class_id].name : ""
    return CLASS_NAMES[n] || n
  end
  #--------------------------------------------------------------------------
  # * [text, colour] of the state with the highest rating, or Normal
  #--------------------------------------------------------------------------
  def self.state_info(actor)
    best = nil
    for id in actor.states
      s = $data_states[id]
      next if s == nil or s.rating < 1
      best = s if best == nil or s.rating > best.rating
    end
    return ["Normal", OK_GREEN] if best == nil
    color = GOOD_STATES.include?(best.name) ? GOOD_BLU : BAD_RED
    return [STATE_NAMES[best.name] || best.name, color]
  end
  #--------------------------------------------------------------------------
  def self.move_points(actor)
    m = actor.respond_to?(:attr_move) ? actor.attr_move : nil
    if m == nil and defined?(FE_Config)
      m = FE_Config::ACTOR_MOVE[actor.class_id] || FE_Config::DEFAULT_MOVE
    end
    return m || 0
  end
  #--------------------------------------------------------------------------
  # * 5 -> "5", 12.5 -> "12,5", 2.333 -> "2,33"
  #--------------------------------------------------------------------------
  def self.number(v)
    v = (v * 100).round / 100.0
    return v.to_i.to_s if v == v.to_i
    return sprintf("%.2f", v).sub(/0+$/, "").sub(".", ",")
  end
  #--------------------------------------------------------------------------
  # * Round face cut from the battler (FACE_RECTS), as a new bitmap of
  #   size 2 * radius with a soft circular edge; nil without a battler.
  #   The caller disposes it. Also used by the "Level Up" script.
  #--------------------------------------------------------------------------
  def self.round_face(actor, radius)
    return nil if actor.battler_name == nil or actor.battler_name == ""
    src = RPG::Cache.battler(actor.battler_name, actor.battler_hue)
    rect = FACE_RECTS[actor.battler_name]
    if rect == nil
      size = ([src.width, src.height].min * 0.42).round
      rect = [(src.width - size) / 2, 0, size]
    end
    size = [[rect[2], 8].max, [src.width, src.height].min].min
    fx = [[rect[0], 0].max, src.width - size].min
    fy = [[rect[1], 0].max, src.height - size].min
    d = radius * 2
    face = Bitmap.new(d, d)
    face.stretch_blt(Rect.new(0, 0, d, d), src, Rect.new(fx, fy, size, size))
    r = radius - 0.5
    for y in 0...d
      for x in 0...d
        dist = Math.sqrt((x + 0.5 - radius) ** 2 + (y + 0.5 - radius) ** 2)
        next if dist <= r - 1
        c = face.get_pixel(x, y)
        a = [[r - dist + 0.5, 0].max, 1].min
        c.alpha = c.alpha * a
        face.set_pixel(x, y, c)
      end
    end
    return face
  end
  #--------------------------------------------------------------------------
  # * Upper case including German umlauts (Ruby 1.8 only knows ASCII)
  #--------------------------------------------------------------------------
  def self.upcase(text)
    t = text.upcase
    t = t.gsub("ä", "Ä").gsub("ö", "Ö").gsub("ü", "Ü").gsub("ß", "SS")
    return t
  end

  #==========================================================================
  # ** StatusBook::Painter  -  draws the whole screen for one actor
  #==========================================================================
  class Painter
    attr_reader :bitmap
    #------------------------------------------------------------------------
    def initialize(bitmap)
      @b = bitmap
      @bitmap = bitmap
    end
    #------------------------------------------------------------------------
    def draw(actor)
      @b.clear
      @b.blt(0, 0, RPG::Cache.picture("StatusBook"), Rect.new(0, 0, 640, 480))
      draw_portrait(actor)
      draw_map_sprite(actor)
      draw_level(actor)
      draw_name(actor)
      draw_state(actor)
      draw_points(actor)
      draw_values(actor)
      draw_crit(actor)
      draw_equipment(actor)
    end

    #------------------------------------------------------------------------
    # * Text helpers
    #------------------------------------------------------------------------
    def font(size, bold = false, italic = false, color = StatusBook::INK, number = false)
      f = @b.font
      f.name = number ? StatusBook.number_font_name : StatusBook.font_name
      f.size = size
      f.bold = bold
      f.italic = italic
      f.color = color
    end
    #------------------------------------------------------------------------
    def width_of(text)
      return @b.text_size(text).width
    end
    #------------------------------------------------------------------------
    # Draws text with its baseline at y. align: 0 left of x, 1 centred on x,
    # 2 right of x. Returns the text width.
    #------------------------------------------------------------------------
    def text(x, base, str, align = 0)
      w = width_of(str) + 2
      h = @b.font.size + 8
      top = base - (@b.font.size * StatusBook::ASCENT).round - (h - @b.text_size(str).height) / 2
      x -= w / 2 if align == 1
      x -= w if align == 2
      @b.draw_text(x, top, w + 2, h, str)
      return w - 2
    end
    #------------------------------------------------------------------------
    # Shrinks the current font until text fits into max_width
    #------------------------------------------------------------------------
    def fit(str, max_width, min_size = 8)
      while width_of(str) > max_width and @b.font.size > min_size
        @b.font.size -= 1
      end
    end
    #------------------------------------------------------------------------
    # Shrinks down to min_size, then shortens the text with "…" if needed.
    # Returns the text to draw.
    #------------------------------------------------------------------------
    def fit_text(str, max_width, min_size = 11)
      fit(str, max_width, min_size)
      return str if width_of(str) <= max_width
      chars = str.scan(/./mu)
      while chars.size > 1
        chars.pop
        t = chars.join.rstrip + "…"
        return t if width_of(t) <= max_width
      end
      return "…"
    end
    #------------------------------------------------------------------------
    # Text with a 1 px outline
    #------------------------------------------------------------------------
    def outlined(x, base, str, outline, align = 0)
      c = @b.font.color.clone
      @b.font.color = outline
      for d in [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [-1, 1], [1, -1]]
        text(x + d[0], base + d[1], str, align)
      end
      @b.font.color = c
      return text(x, base, str, align)
    end
    #------------------------------------------------------------------------
    # Small caps: first letter big, the rest upper case and smaller
    #------------------------------------------------------------------------
    def small_caps(x, base, str, big, small, bold, color, max_width = 999)
      chars = str.scan(/./mu)
      return 0 if chars.empty?
      first = chars[0]
      rest = StatusBook.upcase(chars[1, chars.size - 1].join)
      loop do
        font(big, bold, false, color)
        w = width_of(first)
        font(small, bold, false, color)
        w += width_of(rest)
        break if w <= max_width or small <= 8
        big -= 1
        small -= 1
      end
      font(big, bold, false, color)
      w = text(x, base, first)
      font(small, bold, false, color)
      w += text(x + w, base, rest)
      return w
    end

    #------------------------------------------------------------------------
    # * Shape helpers (anti-aliased, blended over what is already drawn)
    #------------------------------------------------------------------------
    def blend(x, y, color, a)
      return if a <= 0
      a = 1.0 if a > 1
      a *= color.alpha / 255.0
      o = @b.get_pixel(x, y)
      oa = o.alpha / 255.0
      na = a + oa * (1 - a)
      return if na <= 0
      r = (color.red * a + o.red * oa * (1 - a)) / na
      g = (color.green * a + o.green * oa * (1 - a)) / na
      b = (color.blue * a + o.blue * oa * (1 - a)) / na
      @b.set_pixel(x, y, Color.new(r, g, b, na * 255))
    end
    #------------------------------------------------------------------------
    # Rounded rectangle (float edges) with fill and border
    #------------------------------------------------------------------------
    def round_rect(x0, y0, x1, y1, r, fill, border, bw = 1.2)
      for y in y0.floor..y1.ceil
        for x in x0.floor..x1.ceil
          px = x + 0.5
          py = y + 0.5
          cx = [[px, x0 + r].max, x1 - r].min
          cy = [[py, y0 + r].max, y1 - r].min
          d = Math.sqrt((px - cx) ** 2 + (py - cy) ** 2) - r
          outer = [[0.5 - d, 0].max, 1].min
          next if outer <= 0
          inner = [[0.5 - (d + bw), 0].max, 1].min
          blend(x, y, fill, inner) if fill
          blend(x, y, border, outer - inner) if border
        end
      end
    end
    #------------------------------------------------------------------------
    def circle(cx, cy, r, color)
      for y in (cy - r - 1).floor..(cy + r + 1).ceil
        for x in (cx - r - 1).floor..(cx + r + 1).ceil
          d = Math.sqrt((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2)
          blend(x, y, color, r - d + 0.5)
        end
      end
    end

    #------------------------------------------------------------------------
    # * Portrait: face cut from the battler, masked to a circle
    #------------------------------------------------------------------------
    PORTRAIT_X = 92
    PORTRAIT_Y = 90
    PORTRAIT_R = 52
    def draw_portrait(actor)
      face = StatusBook.round_face(actor, PORTRAIT_R)
      return if face == nil
      @b.blt(PORTRAIT_X - PORTRAIT_R, PORTRAIT_Y - PORTRAIT_R, face, face.rect)
      face.dispose
    end
    #------------------------------------------------------------------------
    # * Standing map sprite, facing down, 2x
    #------------------------------------------------------------------------
    def draw_map_sprite(actor)
      return if actor.character_name == nil or actor.character_name == ""
      src = RPG::Cache.character(actor.character_name, actor.character_hue)
      cw = src.width / 4
      ch = src.height / 4
      zoom = 2.0
      zoom = 96.0 / ch if ch * zoom > 96
      w = (cw * zoom).round
      h = (ch * zoom).round
      @b.stretch_blt(Rect.new(186 - w / 2, 141 - h, w, h), src, Rect.new(0, 0, cw, ch))
    end
    #------------------------------------------------------------------------
    def draw_level(actor)
      font(27, true, false, StatusBook::BADGE_TX, true)
      fit(actor.level.to_s, 44)
      text(273, 94 + (@b.font.size * 0.36).round, actor.level.to_s, 1)
      w = 0
      font(15); w += width_of("L")
      font(12); w += width_of("EVEL")
      small_caps(273 - w / 2, 139, "Level", 15, 12, false, StatusBook::INK)
    end
    #------------------------------------------------------------------------
    def draw_name(actor)
      small_caps(37, 179, actor.name, 36, 26, true, StatusBook::INK, 258)
      font(21, true, false, StatusBook::RED)
      cls = fit_text(StatusBook.german_class(actor), 258)
      text(38, 203, cls)
    end
    #------------------------------------------------------------------------
    def draw_state(actor)
      small_caps(46, 237, "Status", 16, 13, false, StatusBook::ITALIC, 50)
      info = StatusBook.state_info(actor)
      font(20, true, false, info[1])
      info[0] = fit_text(info[0], 160)
      tw = width_of(info[0])
      x0 = 110.5
      x1 = x0 + 32 + tw
      round_rect(x0, 220.5, x1, 242.5, 11, StatusBook::PILL_BG, info[1], 1.2)
      circle(x0 + 14, 231.5, 3.2, info[1])
      text(x0 + 23, 237, info[0])
    end
    #------------------------------------------------------------------------
    # * KP / SP / EXP
    #------------------------------------------------------------------------
    def label_pair(x, base, short, long)
      font(18, true)
      w = text(x, base, short)
      font(14, false, true, StatusBook::ITALIC)
      text(x + w + 5, base, long)
    end
    #------------------------------------------------------------------------
    # "30 / 30" right-aligned at x: first number bold, rest regular
    def value_pair(right, base, a, b, crisis = false)
      font(18, false, false, StatusBook::ITALIC, true)
      rest = " / " + b.to_s
      w2 = width_of(rest)
      font(18, true, false, crisis ? StatusBook::BAD_RED : StatusBook::INK, true)
      w1 = width_of(a.to_s)
      text(right - w2 - w1, base, a.to_s)
      font(18, false, false, StatusBook::ITALIC, true)
      text(right - w2, base, rest)
    end
    #------------------------------------------------------------------------
    def bar(x, y, w, h, rate, color)
      rate = [[rate, 0].max, 1].min
      fw = (w * rate).round
      @b.fill_rect(x, y, fw, h, color) if fw > 0
    end
    #------------------------------------------------------------------------
    def draw_points(actor)
      label_pair(38, 287, "KP", "Lebenspunkte")
      value_pair(298, 287, actor.hp, actor.maxhp, actor.hp == 0)
      bar(39, 295, 259, 10, actor.hp.to_f / [actor.maxhp, 1].max, StatusBook::KP_BAR)

      label_pair(38, 334, "SP", "Skillpunkte")
      value_pair(298, 334, actor.sp, actor.maxsp)
      bar(39, 342, 259, 10, actor.sp.to_f / [actor.maxsp, 1].max, StatusBook::SP_BAR)

      list = actor.instance_variable_get(:@exp_list) || []
      now = list[actor.level] || 0
      nxt = list[actor.level + 1] || 0
      font(18, true)
      w = text(38, 381, "EXP")
      long_x = 38 + w + 5
      if nxt > 0
        cur = actor.exp - now
        need = nxt - now
        num = cur.to_s + " / " + need.to_s
        font(18, false, false, StatusBook::ITALIC, true)
        tail = " bis Lv " + (actor.level + 1).to_s
        tw = width_of(tail)
        font(18, true, false, StatusBook::INK, true)
        nw = width_of(num)
        font(14, false, true, StatusBook::ITALIC)
        fit("Erfahrungspunkte", 298 - nw - tw - 8 - long_x)
        text(long_x, 381, "Erfahrungspunkte")
        font(18, true, false, StatusBook::INK, true)
        text(298 - tw - nw, 381, num)
        font(18, false, false, StatusBook::ITALIC, true)
        text(298 - tw, 381, tail)
        bar(39, 389, 259, 6, cur.to_f / [need, 1].max, StatusBook::EXP_BAR)
      else
        font(18, true)
        mw = width_of("Max. Level")
        font(14, false, true, StatusBook::ITALIC)
        fit("Erfahrungspunkte", 298 - mw - 8 - long_x)
        text(long_x, 381, "Erfahrungspunkte")
        font(18, true)
        text(298, 381, "Max. Level", 2)
        bar(39, 389, 259, 6, 1, StatusBook::EXP_BAR)
      end
    end

    #------------------------------------------------------------------------
    # * Werte
    #------------------------------------------------------------------------
    VALUES = [
      ["Str",  "Stärke"],
      ["Mg",   "Magie"],
      ["Spd",  "Geschwindigkeit"],
      ["Luck", "Glück"],
      ["Def",  "Verteidigung"],
      ["Res",  "Resistenz"],
      ["Move", "Reichweite"]
    ]
    def draw_values(actor)
      small_caps(341, 52, "Werte", 22, 16, false, StatusBook::RED)
      values = [actor.str, actor.int, actor.agi, actor.dex, actor.pdef, actor.mdef, StatusBook.move_points(actor)]
      for i in 0...VALUES.size
        y = 70 + i * 25
        base = y + 14
        font(18, true)
        text(341, base, VALUES[i][0])
        font(14, false, true, StatusBook::ITALIC)
        fit(VALUES[i][1], 474 - 387)
        text(387, base, VALUES[i][1])
        scale = i == 6 ? StatusBook::MOVE_SCALE : StatusBook::STAT_SCALE
        v = values[i]
        bar(478, y + 2, 123, 14, v.to_f / scale, StatusBook::STAT_COLORS[i])
        font(15, true, false, StatusBook::INK, true)
        outlined(482, y + 14, v.to_s, StatusBook::CREAM)
      end
    end
    #------------------------------------------------------------------------
    # * CrtR ring and CrtD multiplier
    #------------------------------------------------------------------------
    def draw_crit(actor)
      rate = actor.respond_to?(:crit_rate) ? actor.crit_rate : 0
      dmg = actor.respond_to?(:crit_damage) ? actor.crit_damage : 100
      share = [[rate / 100.0, 0].max, 1].min
      if share > 0
        share = [share, 0.012].max
        cx = 365.0
        cy = 273.0
        for y in 248..298
          for x in 340..390
            cover = 0
            for sy in [0.25, 0.75]
              for sx in [0.25, 0.75]
                dx = x + sx - cx
                dy = y + sy - cy
                d = Math.sqrt(dx * dx + dy * dy)
                next if d < 19.7 or d > 23.3
                ang = Math.atan2(dx, -dy)
                ang += Math::PI * 2 if ang < 0
                cover += 1 if ang <= share * Math::PI * 2
              end
            end
            blend(x, y, StatusBook::CRIT_ARC, cover / 4.0)
          end
        end
      end
      font(15, true, false, StatusBook::INK, true)
      t = StatusBook.number(rate) + "%"
      fit(t, 30)
      text(365, 278, t, 1)
      font(17, true)
      text(399, 270, "CrtR")
      font(13, false, true, StatusBook::ITALIC)
      text(399, 283, "Crit-Rate")

      font(17, true)
      text(483, 270, "CrtD")
      font(11, false, true, StatusBook::ITALIC)
      fit("Crit-Schaden", 60)
      text(483, 283, "Crit-Schaden")
      font(18, true, false, StatusBook::INK, true)
      m = "×" + StatusBook.number((100 + dmg) / 100.0)
      fit(m, 28)
      text(574, 278, m, 1)
    end
    #------------------------------------------------------------------------
    # * Ausruestung
    #------------------------------------------------------------------------
    def draw_equipment(actor)
      small_caps(341, 331, "Ausrüstung", 21, 15, false, StatusBook::RED)
      rows = [
        [$data_weapons[actor.weapon_id], "Waffe", 0],
        [$data_armors[actor.armor1_id], "Schild", 1],
        [$data_armors[actor.armor2_id], "Helm", 2],
        [$data_armors[actor.armor3_id], "Rüstung", 3]
      ]
      rows.push([$data_armors[actor.armor4_id], "Accessoire", 4]) if actor.armor4_id > 0
      icons = RPG::Cache.picture("StatusBookIcons")
      for i in 0...rows.size
        y = 341 + i * 24
        item = rows[i][0]
        @b.blt(341, y, icons, Rect.new(rows[i][2] * 18, 0, 18, 18), item ? 255 : 110)
        font(14, false, true, StatusBook::ITALIC)
        tw = width_of(rows[i][1])
        text(601, y + 14, rows[i][1], 2)
        if item
          font(18, true)
          text(369, y + 14, fit_text(item.name, 601 - tw - 10 - 369))
        else
          font(18, false, true, StatusBook::FADED)
          text(369, y + 14, "—")
        end
      end
    end
  end
end

#==============================================================================
# ** Scene_Status
#==============================================================================

class Scene_Status
  #--------------------------------------------------------------------------
  def initialize(actor_index = 0, equip_index = 0)
    @actor_index = actor_index
  end
  #--------------------------------------------------------------------------
  def main
    @actor = $game_party.actors[@actor_index]
    @sprite = Sprite.new
    @sprite.bitmap = Bitmap.new(640, 480)
    @painter = StatusBook::Painter.new(@sprite.bitmap)
    @painter.draw(@actor)
    Graphics.transition
    loop do
      Graphics.update
      Input.update
      update
      break if $scene != self
    end
    Graphics.freeze
    @sprite.bitmap.dispose
    @sprite.dispose
  end
  #--------------------------------------------------------------------------
  def update
    if Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      $scene = Scene_Menu.new(3)
      return
    end
    if Input.trigger?(Input::R) or Input.trigger?(Input::L)
      n = $game_party.actors.size
      return if n <= 1
      $game_system.se_play($data_system.cursor_se)
      step = Input.trigger?(Input::R) ? 1 : n - 1
      @actor_index = (@actor_index + step) % n
      @actor = $game_party.actors[@actor_index]
      @painter.draw(@actor)
      return
    end
  end
end
