#==============================================================================
# ** Battle UI  v1.0
#------------------------------------------------------------------------------
#  Side-view battle screen for every battle (normal battles, battle tests and
#  the FE Tactics fights). Place it below "Book Menu", above "Main".
#
#  - The battleback fills the screen. Enemies stand on the left (mirrored),
#    the party on the right; lower units are drawn in front.
#  - A KP plate above every fighter (green: party, wine red: enemies).
#  - No Fight / Escape window. Every round all fighters act in turn order
#    (Spd, then Luck, then party first - script "Attributes"); when a party
#    member's turn comes, the command window opens and they act right away.
#  - Commands: Angreifen, Skill, Item, Checken (Checken: placeholder).
#  - Targeting with gold corner brackets and a preview window (KP after the
#    hit, Schaden, Treffer, Krit). Skills that hit all enemies target all of
#    them at once with one small preview window each.
#  - Only the first MAX_ACTORS party members and MAX_ENEMIES troop enemies
#    take part in a battle.
#  The preview uses the same methods as the real attack / skill (script
#  "Attributes": attack_damage_to, hit_chance_on, crit_chance,
#  skill_damage_from, skill_hit_chance, skill_crit_chance).
#==============================================================================

module BattleUI
  #--------------------------------------------------------------------------
  # * Positions: top-left corner of each KP plate. The battler's visible top
  #   is PLATE_GAP px below the plate, centred under it.
  #--------------------------------------------------------------------------
  ENEMY_POS = [[140, 120], [24, 186], [160, 272]]
  ACTOR_POS = [[400, 136], [447, 194], [539, 291], [586, 340]]  # 4th: pet (later)
  MAX_ENEMIES = 3
  MAX_ACTORS  = 3
  MIRROR_ENEMIES = true      # enemies face right
  MIRROR_ACTORS  = false     # party battlers already face left
  PLATE_W   = 100
  PLATE_H   = 28
  PLATE_GAP = 32
  #--- Command window (top right) -------------------------------------------
  COMMAND_W      = 220
  COMMAND_H      = 110
  COMMAND_MARGIN = 10
  COMMANDS  = ["Angreifen", "Skill", "Item", "Checken"]
  TURN_TEXT = "ist am Zug"
  #--- Texts ----------------------------------------------------------------
  TEXT_ATTACK      = "Angreifen"
  TEXT_SKILL       = "Skill"
  TEXT_ITEM        = "Item"
  TEXT_CHOOSE      = "Ziel wählen"
  TEXT_ALL_ENEMIES = "Ziel: alle Gegner"
  TEXT_ALL_ALLIES  = "Ziel: alle Verbündeten"
  TEXT_HP          = "KP"
  TEXT_DAMAGE      = "Schaden"
  TEXT_HIT         = "Treffer"
  TEXT_CRIT        = "Krit"
  CHECK_TITLE      = "Checken"
  CHECK_TEXT       = "Noch nicht verfügbar."
  #--- Sizes ----------------------------------------------------------------
  INFO_W  = 180      # single target preview window
  INFO_H  = 136
  SMALL_W = 124      # one per enemy (area skills)
  SMALL_H = 92
  TAIL    = 8        # length of the pointer tail
  GAP     = 12       # space between a preview window and its target
  RING_W  = 84       # gold ring at the active character's feet
  RING_H  = 18
  BRACKET_LEN  = 16  # corner brackets around targets
  BRACKET_SIZE = 3
  BRACKET_PAD  = 6
  BAR_Y   = 10       # top bar ("Angreifen · Ziel wählen")
  HUD_Z   = 150      # windows of this script (above the battle sprites)
  # FE Tactics: EXP / gold boxes after a fight (one column in the middle)
  REWARD_X    = 250
  REWARD_Y    = 110
  REWARD_STEP = 70
  #--- Fonts (first one installed is used) ----------------------------------
  HEAD_FONTS = ["IM Fell English SC", "Alegreya SC", "Georgia", "Times New Roman"]
  BODY_FONTS = ["Alegreya", "Georgia", "Times New Roman"]
  SMALL_CAPS = 0.78  # lowercase size for fake small caps (heading fonts without "SC")
  ASCENT     = 0.78
  #--- Colours --------------------------------------------------------------
  def self.rgb(hex, a = 255)
    return Color.new(hex[0, 2].hex, hex[2, 2].hex, hex[4, 2].hex, a)
  end
  GOLD        = rgb("C9A04A")
  GOLD_BRIGHT = rgb("F6D46A")
  STITCH      = rgb("8C7A3E")
  NAME_GOLD   = rgb("E8C877")
  CREAM       = rgb("F1EEDC")
  SUB_TEXT    = rgb("B9CBBF")
  GREEN_BG    = rgb("1E3A30")
  GREEN_LINE  = rgb("3E6656")
  GREEN_TRACK = rgb("0D1D17")
  GREEN_BAR   = rgb("4FA83A")
  RED_BG      = rgb("4A1A22")
  RED_LINE    = rgb("7A3A44")
  RED_TRACK   = rgb("22090E")
  RED_BAR     = rgb("D2463A")
  LOSS        = rgb("F2A79A")
  BUTTON      = rgb("2A4C3F")
  PARCHMENT   = rgb("F1E4C3")
  DARK_RED    = rgb("7A1F1F")
  DARK_TEXT   = rgb("3A2A1C")
  DARK_LABEL  = rgb("6A5640")
  AFTER_DARK  = rgb("A3222A")
  SHADOW      = Color.new(0, 0, 0, 80)

  #==========================================================================
  # * General
  #==========================================================================
  def self.on?
    return $scene.is_a?(Scene_Battle)
  end

  def self.first_font(list)
    list.each { |n| return n if Font.exist?(n) }
    return list[-1]
  end
  def self.head_font
    @head_font = first_font(HEAD_FONTS) if @head_font == nil
    return @head_font
  end
  def self.body_font
    @body_font = first_font(BODY_FONTS) if @body_font == nil
    return @body_font
  end
  # The heading font draws small caps itself ("... SC")?
  def self.real_small_caps?
    return (head_font =~ /SC$/) != nil
  end

  #==========================================================================
  # * Battler graphics: visible (non-transparent) part, cached per graphic
  #==========================================================================
  # [bitmap width, bitmap height, left, top, width, height] of the opaque part
  def self.graphic(b)
    key = b.battler_name.to_s + "/" + b.battler_hue.to_s
    @graphics = {} if @graphics == nil
    return @graphics[key] if @graphics[key] != nil
    begin
      bmp = RPG::Cache.battler(b.battler_name, b.battler_hue)
    rescue Exception
      return (@graphics[key] = [32, 32, 0, 0, 32, 32])
    end
    w = bmp.width
    h = bmp.height
    l = w; t = h; r = -1; bo = -1
    y = 0
    while y < h
      x = 0
      while x < w
        if bmp.get_pixel(x, y).alpha > 40
          l = x if x < l
          r = x if x > r
          t = y if y < t
          bo = y if y > bo
        end
        x += 2
      end
      y += 2
    end
    if r < 0
      @graphics[key] = [w, h, 0, 0, w, h]
    else
      l = [l - 1, 0].max
      t = [t - 1, 0].max
      @graphics[key] = [w, h, l, t, [r + 2, w].min - l, [bo + 2, h].min - t]
    end
    return @graphics[key]
  end

  def self.mirror?(b)
    return b.is_a?(Game_Enemy) ? MIRROR_ENEMIES : MIRROR_ACTORS
  end

  # Plate position of a battler from its slot (nil: not in the battle)
  def self.slot_pos(b)
    if b.is_a?(Game_Actor)
      i = $game_party.actors.index(b)
      return (i != nil ? ACTOR_POS[i] : nil)
    end
    i = $game_troop.enemies.index(b)
    return (i != nil ? ENEMY_POS[i] : nil)
  end

  # Sprite x (bitmap centre) so the visible part is centred under the plate
  def self.screen_x(b)
    pos = slot_pos(b)
    return nil if pos == nil
    g = graphic(b)
    off = (g[2] + g[4] / 2.0) - g[0] / 2
    off = -off if mirror?(b)
    return (pos[0] + PLATE_W / 2 - off).round
  end

  # Sprite y (bitmap bottom) so the visible top is PLATE_GAP below the plate
  def self.screen_y(b)
    pos = slot_pos(b)
    return nil if pos == nil
    g = graphic(b)
    return pos[1] + PLATE_GAP - g[3] + g[1]
  end

  # Visible part on screen: [x, y, w, h]
  def self.visible_rect(b)
    g = graphic(b)
    x0 = b.screen_x - g[0] / 2
    y0 = b.screen_y - g[1]
    x = mirror?(b) ? x0 + (g[0] - g[2] - g[4]) : x0 + g[2]
    return [x, y0 + g[3], g[4], g[5]]
  end

  def self.plate_rect(b)
    v = visible_rect(b)
    return [v[0] + v[2] / 2 - PLATE_W / 2, v[1] - PLATE_GAP, PLATE_W, PLATE_H]
  end

  #==========================================================================
  # * Preview of an attack / skill on a target (same formulas as the hit)
  #   Returns {"dmg", "hit", "crit", "hp", "after", "maxhp"} or nil.
  #==========================================================================
  def self.preview(user, target, kind, obj)
    if kind == :attack
      return nil unless user.respond_to?(:attack_damage_to)
      dmg  = user.attack_damage_to(target)
      hit  = [user.hit_chance_on(target), 100].min
      crit = dmg > 0 ? user.crit_chance : 0
    elsif kind == :skill and obj != nil
      return nil unless target.respond_to?(:skill_damage_from)
      dmg  = target.skill_damage_from(user, obj)
      hit  = target.skill_hit_chance(user, obj)
      crit = target.skill_crit_chance(user, obj)
    else
      return nil
    end
    after = [[target.hp - dmg, 0].max, target.maxhp].min
    return { "dmg" => dmg.round, "hit" => [[hit.round, 0].max, 100].min,
             "crit" => [[crit.round, 0].max, 100].min, "hp" => target.hp,
             "after" => after, "maxhp" => target.maxhp }
  end

  #==========================================================================
  # * Drawing helpers
  #==========================================================================
  def self.mix(a, b, t)
    return Color.new(a.red * (1 - t) + b.red * t, a.green * (1 - t) + b.green * t,
                     a.blue * (1 - t) + b.blue * t, a.alpha * (1 - t) + b.alpha * t)
  end

  # Rectangle with 1 px cut corners
  def self.fill_round(b, x, y, w, h, color)
    return if w <= 0 or h <= 0
    b.fill_rect(x + 1, y, w - 2, h, color)
    b.fill_rect(x, y + 1, w, h - 2, color)
  end

  def self.frame(b, x, y, w, h, color, t = 1)
    b.fill_rect(x, y, w, t, color)
    b.fill_rect(x, y + h - t, w, t, color)
    b.fill_rect(x, y, t, h, color)
    b.fill_rect(x + w - t, y, t, h, color)
  end

  # Dashed rectangle (the "stitch line")
  def self.stitch(b, x, y, w, h, color, on = 3, off = 3)
    i = 0
    while i < w
      n = [on, w - i].min
      b.fill_rect(x + i, y, n, 1, color)
      b.fill_rect(x + i, y + h - 1, n, 1, color)
      i += on + off
    end
    i = 0
    while i < h
      n = [on, h - i].min
      b.fill_rect(x, y + i, 1, n, color)
      b.fill_rect(x + w - 1, y + i, 1, n, color)
      i += on + off
    end
  end

  # Green "book" panel: shadow, gold border, green inside, dashed stitch
  def self.book_panel(b, x, y, w, h, border = 2, stitch_inset = 5)
    fill_round(b, x + 3, y + 3, w, h, SHADOW)
    fill_round(b, x, y, w, h, GOLD)
    b.fill_rect(x + border, y + border, w - border * 2, h - border * 2, GREEN_BG)
    if stitch_inset > 0
      stitch(b, x + stitch_inset, y + stitch_inset, w - stitch_inset * 2,
             h - stitch_inset * 2, STITCH)
    end
  end

  # Triangle; dir = direction the tip points (:left, :right, :up, :down)
  def self.triangle(b, dir, tx, ty, len, half, color)
    for k in 0...len
      wk = (half * k.to_f / len).round
      case dir
      when :left  then b.fill_rect(tx + k, ty - wk, 1, wk * 2 + 1, color)
      when :right then b.fill_rect(tx - k, ty - wk, 1, wk * 2 + 1, color)
      when :up    then b.fill_rect(tx - wk, ty + k, wk * 2 + 1, 1, color)
      when :down  then b.fill_rect(tx - wk, ty - k, wk * 2 + 1, 1, color)
      end
    end
  end

  #--------------------------------------------------------------------------
  # * Text
  #--------------------------------------------------------------------------
  UPPER = { "ä" => "Ä", "ö" => "Ö", "ü" => "Ü" }

  # Small caps as runs [[text, size], ...]
  def self.sc_runs(text, size)
    return [[text, size]] if real_small_caps?
    small = (size * SMALL_CAPS).round
    runs = []
    text.scan(/./mu).each do |ch|
      if ch =~ /\A[a-z]\z/
        c = ch.upcase; s = small
      elsif UPPER[ch] != nil
        c = UPPER[ch]; s = small
      elsif ch == "ß"
        c = ch; s = small
      else
        c = ch; s = size
      end
      if runs.size > 0 and runs[-1][1] == s
        runs[-1][0] += c
      else
        runs.push([c.dup, s])
      end
    end
    return runs
  end

  def self.sc_width(b, text, size, bold = false)
    b.font.name = head_font
    b.font.bold = bold
    w = 0
    sc_runs(text, size).each { |r| b.font.size = r[1]; w += b.text_size(r[0]).width }
    return w
  end

  # Small caps heading text; squeezed if wider than w
  def self.draw_sc(b, x, y, w, h, text, size, color, align = 0, bold = false)
    runs = sc_runs(text, size)
    b.font.name = head_font
    b.font.bold = bold
    b.font.italic = false
    b.font.color = color
    widths = runs.collect { |r| b.font.size = r[1]; b.text_size(r[0]).width }
    total = widths.inject(0) { |t, v| t + v }
    scale = (total > w and total > 0) ? w.to_f / total : 1.0
    tw = total * scale
    cx = x
    cx = x + (w - tw) / 2.0 if align == 1
    cx = x + w - tw if align == 2
    b.font.size = size
    bh = b.text_size("H").height
    base = y + (h - bh) / 2.0 + bh * ASCENT
    runs.each_with_index do |r, i|
      b.font.size = r[1]
      rh = b.text_size("H").height
      ty = (base - rh * ASCENT).round
      rw = widths[i] * scale
      if scale < 1.0
        b.draw_text(cx.round, ty, [rw.round, 1].max, rh, r[0])
      else
        b.draw_text(cx.round, ty, rw.round + 4, rh, r[0])
      end
      cx += rw
    end
    return tw
  end

  def self.draw_body(b, x, y, w, h, text, size, color, align = 0, bold = false)
    b.font.name = body_font
    b.font.size = size
    b.font.bold = bold
    b.font.italic = false
    b.font.color = color
    b.draw_text(x, y, w, h, text, align)
  end

  def self.body_width(b, text, size, bold = false)
    b.font.name = body_font
    b.font.size = size
    b.font.bold = bold
    return b.text_size(text).width
  end

  #--------------------------------------------------------------------------
  # * KP bar: track, remaining part, the part the hit takes away (lighter)
  #--------------------------------------------------------------------------
  def self.hp_bar(b, x, y, w, h, hp, after, maxhp, track, bar, loss = nil)
    fill_round(b, x, y, w, h, track)
    m = [maxhp, 1].max
    iw = w - 2
    cur = (iw * hp / m.to_f).round
    aft = (iw * after / m.to_f).round
    b.fill_rect(x + 1, y + 1, aft, h - 2, bar) if aft > 0
    b.fill_rect(x + 1 + aft, y + 1, cur - aft, h - 2, loss) if loss and cur > aft
  end

  #==========================================================================
  # * Bitmaps
  #==========================================================================
  def self.draw_plate(b, battler, bright)
    b.clear
    w = b.width
    h = b.height
    enemy = battler.is_a?(Game_Enemy)
    bg    = enemy ? RED_BG : GREEN_BG
    line  = enemy ? RED_LINE : GREEN_LINE
    track = enemy ? RED_TRACK : GREEN_TRACK
    bar   = enemy ? RED_BAR : GREEN_BAR
    border = bright ? GOLD_BRIGHT : GOLD
    fill_round(b, 0, 0, w, h, border)
    b.fill_rect(1, 1, w - 2, h - 2, bright ? border : mix(border, bg, 0.5))
    b.fill_rect(2, 2, w - 4, h - 4, line)
    b.fill_rect(3, 3, w - 6, h - 6, bg)
    hp = battler.hp.to_s + "/" + battler.maxhp.to_s
    hw = body_width(b, hp, 11, true)
    draw_body(b, w - 6 - hw - 2, 1, hw + 2, 16, hp, 11, CREAM, 2, true)
    draw_sc(b, 6, 1, w - 16 - hw, 16, battler.name, 12, NAME_GOLD)
    hp_bar(b, 5, 17, w - 10, 7, battler.hp, battler.hp, battler.maxhp, track, bar)
  end

  def self.ring_bitmap
    return @ring if @ring != nil and !@ring.disposed?
    w = RING_W + 4
    h = RING_H + 4
    @ring = Bitmap.new(w, h)
    cx = w / 2.0
    cy = h / 2.0
    a1 = RING_W / 2.0; b1 = RING_H / 2.0
    a2 = a1 - 2.2;     b2 = b1 - 2.2
    for y in 0...h
      for x in 0...w
        n = 0
        for sy in 0...3
          for sx in 0...3
            dx = x + (sx + 0.5) / 3 - cx
            dy = y + (sy + 0.5) / 3 - cy
            o = (dx / a1) ** 2 + (dy / b1) ** 2
            i = (dx / a2) ** 2 + (dy / b2) ** 2
            n += 1 if o <= 1.0 and i > 1.0
          end
        end
        if n > 0
          c = GOLD_BRIGHT.clone
          c.alpha = 255 * n / 9
          @ring.set_pixel(x, y, c)
        end
      end
    end
    return @ring
  end

  def self.pointer_bitmap
    return @pointer if @pointer != nil and !@pointer.disposed?
    @pointer = Bitmap.new(18, 22)
    triangle(@pointer, :right, 16, 11, 15, 10, Color.new(60, 40, 10, 200))
    triangle(@pointer, :right, 14, 11, 12, 8, GOLD_BRIGHT)
    return @pointer
  end

  def self.bracket_bitmap(w, h)
    b = Bitmap.new(w, h)
    l = [BRACKET_LEN, w / 3, h / 3].min
    t = BRACKET_SIZE
    c = GOLD_BRIGHT
    b.fill_rect(0, 0, l, t, c);         b.fill_rect(0, 0, t, l, c)
    b.fill_rect(w - l, 0, l, t, c);     b.fill_rect(w - t, 0, t, l, c)
    b.fill_rect(0, h - t, l, t, c);     b.fill_rect(0, h - l, t, l, c)
    b.fill_rect(w - l, h - t, l, t, c); b.fill_rect(w - t, h - l, t, l, c)
    return b
  end

  # Top bar ("Angreifen · Ziel wählen")
  def self.bar_bitmap(text)
    tmp = Bitmap.new(32, 32)
    tw = sc_width(tmp, text, 17)
    tmp.dispose
    w = tw + 48
    h = 36
    b = Bitmap.new(w + 4, h + 4)
    book_panel(b, 0, 0, w, h)
    draw_sc(b, 0, 1, w, h - 2, text, 17, NAME_GOLD, 1)
    return b
  end

  # Tail (pointer) of a preview window; m = margin around the panel
  def self.draw_tail(b, side, pos, m, w, h)
    case side
    when :right   # window right of its target: tail on the left edge
      triangle(b, :left, m - TAIL, m + pos, TAIL + 1, 7, GOLD)
    when :left
      triangle(b, :right, m + w + TAIL - 1, m + pos, TAIL + 1, 7, GOLD)
    when :above   # window above its target: tail at the bottom, pointing down
      triangle(b, :down, m + pos, m + h + TAIL - 1, TAIL + 1, 7, GOLD)
    when :below
      triangle(b, :up, m + pos, m - TAIL, TAIL + 1, 7, GOLD)
    end
  end

  # Big preview window (single target)
  def self.info_bitmap(target, pv, side, pos)
    m = TAIL + 2
    w = INFO_W
    h = INFO_H
    b = Bitmap.new(w + m * 2 + 3, h + m * 2 + 3)
    book_panel(b, m, m, w, h)
    draw_tail(b, side, pos, m, w, h)
    x = m
    y = m
    # bookmark ribbon
    rx = x + w - 34
    for i in 0...14
      notch = 6 - (i - 6.5).abs.round
      notch = 0 if notch < 0
      b.fill_rect(rx + i, y - 1, 1, 28 - notch, DARK_RED)
    end
    draw_sc(b, x + 14, y + 10, w - 56, 24, target.name, 18, NAME_GOLD)
    b.fill_rect(x + 14, y + 36, w - 28, 1, GOLD)
    # KP  cur -> after
    draw_sc(b, x + 14, y + 42, 40, 22, TEXT_HP, 15, CREAM)
    a = pv["after"].to_s
    aw = body_width(b, a, 17, true)
    right = x + w - 14
    draw_body(b, right - aw - 2, y + 41, aw + 2, 24, a, 17, LOSS, 2, true)
    arw = 10
    draw_arrow(b, right - aw - arw - 6, y + 54, arw, SUB_TEXT)
    c = pv["hp"].to_s
    cw = body_width(b, c, 17, true)
    draw_body(b, right - aw - arw - cw - 14, y + 41, cw + 2, 24, c, 17, CREAM, 2, true)
    hp_bar(b, x + 14, y + 66, w - 28, 9, pv["hp"], pv["after"], pv["maxhp"],
           RED_TRACK, RED_BAR, LOSS)
    # Schaden / Treffer / Krit
    labels = [TEXT_DAMAGE, TEXT_HIT, TEXT_CRIT]
    values = [pv["dmg"].to_s, pv["hit"].to_s + " %", pv["crit"].to_s + " %"]
    bw = (w - 28 - 8) / 3
    for i in 0...3
      bx = x + 14 + i * (bw + 4)
      by = y + 82
      fill_round(b, bx, by, bw, 42, GREEN_LINE)
      b.fill_rect(bx + 1, by + 1, bw - 2, 40, BUTTON)
      draw_sc(b, bx + 2, by + 3, bw - 4, 14, labels[i], 11, SUB_TEXT, 1)
      draw_body(b, bx + 2, by + 17, bw - 4, 22, values[i], 17, CREAM, 1, true)
    end
    return b
  end

  # Small preview window (area skills)
  def self.small_bitmap(target, pv, side, pos)
    m = TAIL + 2
    w = SMALL_W
    h = SMALL_H
    b = Bitmap.new(w + m * 2 + 3, h + m * 2 + 3)
    book_panel(b, m, m, w, h, 2, 0)
    frame(b, m + 3, m + 3, w - 6, h - 6, mix(GOLD, GREEN_BG, 0.35))
    draw_tail(b, side, pos, m, w, h)
    x = m
    y = m
    # name between two thin gold lines
    nw = draw_sc(b, x + 8, y + 5, w - 16, 18, target.name, 14, NAME_GOLD, 1)
    lw = ((w - 16 - nw) / 2.0 - 6).floor
    if lw > 4
      b.fill_rect(x + 8, y + 14, lw, 1, GOLD)
      b.fill_rect(x + w - 8 - lw, y + 14, lw, 1, GOLD)
    end
    # parchment panel
    px = x + 7; py = y + 25; pw = w - 14; ph = h - 32
    b.fill_rect(px, py, pw, ph, GOLD)
    b.fill_rect(px + 1, py + 1, pw - 2, ph - 2, PARCHMENT)
    draw_sc(b, px + 6, py + 3, 30, 16, TEXT_HP, 12, DARK_TEXT)
    right = px + pw - 6
    a = pv["after"].to_s
    aw = body_width(b, a, 13, true)
    draw_body(b, right - aw - 2, py + 2, aw + 2, 18, a, 13, AFTER_DARK, 2, true)
    arw = 8
    draw_arrow(b, right - aw - arw - 5, py + 12, arw, DARK_LABEL)
    c = pv["hp"].to_s
    cw = body_width(b, c, 13, true)
    draw_body(b, right - aw - arw - cw - 10, py + 2, cw + 2, 18, c, 13, DARK_TEXT, 2, true)
    hp_bar(b, px + 6, py + 21, pw - 12, 6, pv["hp"], pv["after"], pv["maxhp"],
           mix(RED_TRACK, DARK_TEXT, 0.3), RED_BAR, LOSS)
    labels = [TEXT_DAMAGE, TEXT_HIT, TEXT_CRIT]
    values = [pv["dmg"].to_s, pv["hit"].to_s + "%", pv["crit"].to_s + "%"]
    cw3 = (pw - 8) / 3
    for i in 0...3
      cx = px + 4 + i * cw3
      draw_sc(b, cx, py + 29, cw3, 12, labels[i], 9, DARK_LABEL, 1)
      draw_body(b, cx, py + 40, cw3, 18, values[i], 14, DARK_TEXT, 1, true)
    end
    return b
  end

  # Small arrow "->" (fonts may lack the glyph)
  def self.draw_arrow(b, x, cy, w, color)
    b.fill_rect(x, cy, w - 3, 1, color)
    triangle(b, :right, x + w - 1, cy, 4, 3, color)
  end

  def self.overlap(a, b)
    w = [a[0] + a[2], b[0] + b[2]].min - [a[0], b[0]].max
    h = [a[1] + a[3], b[1] + b[3]].min - [a[1], b[1]].max
    return (w > 0 and h > 0) ? w * h : 0
  end

  #==========================================================================
  # ** BattleUI::CommandPanel - Angreifen / Skill / Item / Checken (2 x 2)
  #     Stands in for @actor_command_window (active, visible, index, update).
  #==========================================================================
  class CommandPanel < Sprite
    attr_reader   :index, :active
    attr_accessor :back_opacity
    def initialize(viewport)
      super(viewport)
      self.bitmap = Bitmap.new(COMMAND_W + 4, COMMAND_H + 4)
      self.x = 640 - COMMAND_MARGIN - COMMAND_W
      self.y = COMMAND_MARGIN
      self.visible = false
      @index = 0
      @active = false
      @actor = nil
    end
    def setup(actor)
      @actor = actor
      refresh
    end
    def active=(v);   @active = v;                   end
    def index=(i);    @index = i; refresh;            end
    def dispose
      return if disposed?
      self.bitmap.dispose
      super
    end
    def update
      super
      return unless @active and self.visible
      i = @index
      i ^= 1 if Input.repeat?(Input::LEFT) or Input.repeat?(Input::RIGHT)
      i ^= 2 if Input.repeat?(Input::UP) or Input.repeat?(Input::DOWN)
      if i != @index
        $game_system.se_play($data_system.cursor_se)
        self.index = i
      end
    end
    def refresh
      b = self.bitmap
      b.clear
      w = COMMAND_W
      h = COMMAND_H
      BattleUI.book_panel(b, 0, 0, w, h)
      name = @actor != nil ? @actor.name : ""
      tw = BattleUI.body_width(b, TURN_TEXT, 14)
      BattleUI.draw_body(b, w - 14 - tw - 2, 7, tw + 2, 24, TURN_TEXT, 14, SUB_TEXT, 2)
      BattleUI.draw_sc(b, 14, 7, w - 34 - tw, 24, name, 17, NAME_GOLD)
      bw = (w - 24 - 4) / 2
      bh = 30
      for i in 0...4
        bx = 12 + (i % 2) * (bw + 4)
        by = 36 + (i / 2) * (bh + 4)
        if i == @index
          BattleUI.fill_round(b, bx, by, bw, bh, GOLD)
          b.fill_rect(bx + 2, by + 2, bw - 4, bh - 4, PARCHMENT)
          BattleUI.triangle(b, :right, bx + 13, by + bh / 2, 7, 4, DARK_RED)
          BattleUI.draw_sc(b, bx + 16, by + 1, bw - 20, bh - 2, COMMANDS[i], 16, DARK_RED, 1)
        else
          BattleUI.fill_round(b, bx, by, bw, bh, GREEN_LINE)
          b.fill_rect(bx + 1, by + 1, bw - 2, bh - 2, BUTTON)
          BattleUI.draw_sc(b, bx + 4, by + 1, bw - 8, bh - 2, COMMANDS[i], 16, CREAM, 1)
        end
      end
    end
  end

  #==========================================================================
  # ** BattleUI::Targeter - target choice (stands in for Arrow_Enemy /
  #     Arrow_Actor: index, update, dispose)
  #     side: :enemy / :actor, all: every valid target at once
  #==========================================================================
  class Targeter
    attr_reader :index, :all
    def initialize(hud, side, all, user, kind, obj)
      @hud  = hud
      @side = side
      @all  = all
      @user = user
      @kind = kind
      @obj  = obj
      @index = 0
      @index = (step_from(-1, 1) || 0)
      refresh
    end
    def list
      return (@side == :enemy ? $game_troop.enemies : $game_party.actors)
    end
    def valid?(b)
      return false if b == nil
      return (@side == :enemy ? b.exist? : !b.hidden)
    end
    def step_from(i, d)
      n = list.size
      n.times do
        i = (i + d) % n
        return i if valid?(list[i])
      end
      return nil
    end
    def index=(i)
      @index = i if valid?(list[i])
      refresh
    end
    def help_window=(w)
    end
    def targets
      return list.select { |b| valid?(b) } if @all
      return [list[@index]].compact
    end
    def title
      head = TEXT_ITEM
      head = TEXT_ATTACK if @kind == :attack
      head = TEXT_SKILL if @kind == :skill
      tail = TEXT_CHOOSE
      tail = (@side == :enemy ? TEXT_ALL_ENEMIES : TEXT_ALL_ALLIES) if @all
      return head + " · " + tail
    end
    def update
      return if @all
      d = 0
      d = 1 if Input.repeat?(Input::DOWN) or Input.repeat?(Input::RIGHT)
      d = -1 if Input.repeat?(Input::UP) or Input.repeat?(Input::LEFT)
      return if d == 0
      i = step_from(@index, d)
      if i != nil and i != @index
        $game_system.se_play($data_system.cursor_se)
        @index = i
        refresh
      end
    end
    def refresh
      preview = (@side == :enemy) ? @kind : nil
      @hud.show_targets(targets, title, preview, @user, @obj, @all)
    end
    def dispose
      @hud.clear_targets
    end
  end

  #==========================================================================
  # ** BattleUI::Hud - plates, ring, pointer, command panel, targeting
  #     Owned by Spriteset_Battle (updated and disposed with it).
  #==========================================================================
  class Hud
    attr_reader   :command, :targets, :info_sprites, :active_battler
    def initialize(spriteset)
      @ss = spriteset
      @vp1 = spriteset.viewport1
      @vp = Viewport.new(0, 0, 640, 480)
      @vp.z = HUD_Z
      @plates = {}
      @ring = Sprite.new(@vp1)
      @ring.bitmap = BattleUI.ring_bitmap
      @ring.visible = false
      @pointer = Sprite.new(@vp1)
      @pointer.bitmap = BattleUI.pointer_bitmap
      @pointer.z = 3000
      @pointer.visible = false
      @command = CommandPanel.new(@vp)
      @bar = Sprite.new(@vp)
      @bar.visible = false
      @brackets = []
      @info_sprites = []
      @targets = []
      @placeholder = nil
      @active_battler = nil
      @t = 0
    end

    def active_battler=(b)
      @active_battler = b
      update_active
      update_plates_now
    end

    def battlers
      return $game_party.actors[0, ACTOR_POS.size] + $game_troop.enemies
    end

    def dispose
      clear_targets
      close_placeholder
      @plates.each_value { |s| s.bitmap.dispose; s.dispose }
      @plates.clear
      @ring.dispose
      @pointer.dispose
      @command.dispose
      @bar.bitmap.dispose if @bar.bitmap != nil
      @bar.dispose
      @vp.dispose
    end

    #--- Frame update ---------------------------------------------------------
    def update
      @t += 1
      list = battlers
      @plates.keys.each do |b|
        next if list.include?(b)
        @plates[b].bitmap.dispose
        @plates[b].dispose
        @plates.delete(b)
      end
      list.each { |b| update_plate(b) }
      update_active
      a = 200 + (55 * Math.sin(@t / 8.0)).abs.round
      @brackets.each { |x| x[1].opacity = a }
    end

    def update_plate(b)
      return if BattleUI.slot_pos(b) == nil
      s = @plates[b]
      if s == nil
        s = Sprite.new(@vp1)
        s.bitmap = Bitmap.new(PLATE_W, PLATE_H)
        @plates[b] = s
      end
      bright = (b == @active_battler or @targets.include?(b))
      key = [b.name, b.hp, b.maxhp, bright]
      if s.instance_variable_get(:@bui_key) != key
        s.instance_variable_set(:@bui_key, key)
        BattleUI.draw_plate(s.bitmap, b, bright)
      end
      r = BattleUI.plate_rect(b)
      s.x = r[0]
      s.y = r[1]
      s.z = b.screen_y * 4 + 1
      if b.is_a?(Game_Enemy)
        sp = @ss.battler_sprite(b)
        s.visible = (!b.hidden and sp != nil and sp.visible)
        s.opacity = (sp != nil and b.dead?) ? sp.opacity : 255
      else
        s.visible = true
        s.opacity = b.dead? ? 150 : 255
      end
    end

    def update_active
      b = @active_battler
      if b == nil or BattleUI.slot_pos(b) == nil
        @ring.visible = false
        @pointer.visible = false
        return
      end
      v = BattleUI.visible_rect(b)
      @ring.visible = true
      @ring.x = v[0] + v[2] / 2 - @ring.bitmap.width / 2
      @ring.y = v[1] + v[3] - @ring.bitmap.height / 2 - 3
      @ring.z = b.screen_y * 4 - 1
      @pointer.visible = true
      @pointer.x = v[0] - @pointer.bitmap.width - 4 + (Math.sin(@t / 6.0) * 3).round
      @pointer.y = v[1] + v[3] / 2 - @pointer.bitmap.height / 2
    end

    #--- Targeting ------------------------------------------------------------
    # list: targeted battlers; kind :attack / :skill shows preview windows
    def show_targets(list, title, kind, user, obj, all)
      clear_targets
      @targets = list
      @bar.bitmap = BattleUI.bar_bitmap(title)
      @bar.x = 320 - (@bar.bitmap.width - 4) / 2
      @bar.y = BAR_Y
      @bar.visible = true
      list.each do |b|
        v = BattleUI.visible_rect(b)
        p = BRACKET_PAD
        s = Sprite.new(@vp)
        s.bitmap = BattleUI.bracket_bitmap(v[2] + p * 2, v[3] + p * 2)
        s.x = v[0] - p
        s.y = v[1] - p
        @brackets.push([b, s])
      end
      return unless kind == :attack or kind == :skill
      placed = []
      list.each do |b|
        pv = BattleUI.preview(user, b, kind, obj)
        next if pv == nil
        w = all ? SMALL_W : INFO_W
        h = all ? SMALL_H : INFO_H
        pos = place(b, w, h, placed, user)
        placed.push([pos[0], pos[1], w, h])
        if all
          bmp = BattleUI.small_bitmap(b, pv, pos[2], pos[3])
        else
          bmp = BattleUI.info_bitmap(b, pv, pos[2], pos[3])
        end
        s = Sprite.new(@vp)
        s.bitmap = bmp
        s.x = pos[0] - TAIL - 2
        s.y = pos[1] - TAIL - 2
        s.z = 10
        @info_sprites.push(s)
      end
      update_plates_now
    end

    def update_plates_now
      battlers.each { |b| update_plate(b) }
    end

    def clear_targets
      @brackets.each { |x| x[1].bitmap.dispose; x[1].dispose }
      @brackets = []
      @info_sprites.each { |s| s.bitmap.dispose; s.dispose }
      @info_sprites = []
      @targets = []
      if @bar.bitmap != nil
        @bar.bitmap.dispose
        @bar.bitmap = nil
      end
      @bar.visible = false
    end

    # Where a preview window goes: [x, y, side, tail position along the edge]
    # Tries right, above, left, below of the target and takes the place that
    # covers the least (party, active character, other windows weigh most).
    def place(target, w, h, placed, user)
      v = BattleUI.visible_rect(target)
      pr = BattleUI.plate_rect(target)
      cx = v[0] + v[2] / 2
      cy = v[1] + v[3] / 2
      top = [pr[1], v[1]].min
      cands = [
        [:right, v[0] + v[2] + GAP, cy - h / 2],
        [:right, v[0] + v[2] + GAP, v[1]],
        [:right, v[0] + v[2] + GAP, v[1] + v[3] - h],
        [:above, cx - w / 2, top - GAP - h],
        [:left,  v[0] - GAP - w, cy - h / 2],
        [:left,  v[0] - GAP - w, v[1]],
        [:below, cx - w / 2, v[1] + v[3] + GAP]
      ]
      avoid = []
      battlers.each do |b|
        next if BattleUI.slot_pos(b) == nil
        next if b.is_a?(Game_Enemy) and !b.exist?
        wt = b.is_a?(Game_Actor) ? 4 : 1
        wt = 20 if b == user or b == @active_battler
        wt = 3 if b == target
        avoid.push([BattleUI.visible_rect(b), wt])
        avoid.push([BattleUI.plate_rect(b), wt + 1])
      end
      if @bar.visible and @bar.bitmap != nil
        avoid.push([[@bar.x, @bar.y, @bar.bitmap.width, @bar.bitmap.height], 10])
      end
      placed.each { |r| avoid.push([[r[0] - 4, r[1] - 4, r[2] + 8, r[3] + 8], 30]) }
      best = nil
      best_score = nil
      cands.each do |c|
        x = [[c[1], 4].max, 636 - w].min
        y = [[c[2], 4].max, 474 - h].min
        # the tail must still face the target
        next if c[0] == :right and x < v[0] + v[2]
        next if c[0] == :left and x + w > v[0]
        next if c[0] == :above and y + h > top
        next if c[0] == :below and y < v[1] + v[3]
        r = [x, y, w, h]
        score = 0
        avoid.each { |a| score += BattleUI.overlap(r, a[0]) * a[1] }
        if best_score == nil or score < best_score
          best = [x, y, c[0]]
          best_score = score
        end
      end
      if best == nil
        best = [[[cx + GAP, 4].max, 636 - w].min, [[cy - h / 2, 4].max, 474 - h].min, :right]
      end
      x = best[0]
      y = best[1]
      if best[2] == :right or best[2] == :left
        pos = [[cy - y, 14].max, h - 14].min
      else
        pos = [[cx - x, 14].max, w - 14].min
      end
      return [x, y, best[2], pos]
    end

    #--- "Checken" placeholder ----------------------------------------------
    def open_placeholder
      close_placeholder
      w = 300
      h = 96
      s = Sprite.new(@vp)
      s.bitmap = Bitmap.new(w + 4, h + 4)
      BattleUI.book_panel(s.bitmap, 0, 0, w, h)
      BattleUI.draw_sc(s.bitmap, 0, 14, w, 26, CHECK_TITLE, 19, NAME_GOLD, 1)
      s.bitmap.fill_rect(30, 44, w - 60, 1, GOLD)
      BattleUI.draw_body(s.bitmap, 0, 52, w, 24, CHECK_TEXT, 15, CREAM, 1)
      s.x = 320 - w / 2
      s.y = 240 - h / 2
      s.z = 50
      @placeholder = s
    end
    def placeholder?
      return @placeholder != nil
    end
    def close_placeholder
      return if @placeholder == nil
      @placeholder.bitmap.dispose
      @placeholder.dispose
      @placeholder = nil
    end
  end
end

#==============================================================================
# ** Battler positions in battle (slots of BattleUI)
#==============================================================================
class Game_Actor
  alias battle_ui_screen_x screen_x
  alias battle_ui_screen_y screen_y
  alias battle_ui_screen_z screen_z
  def screen_x
    v = BattleUI.on? ? BattleUI.screen_x(self) : nil
    return (v != nil ? v : battle_ui_screen_x)
  end
  def screen_y
    v = BattleUI.on? ? BattleUI.screen_y(self) : nil
    return (v != nil ? v : battle_ui_screen_y)
  end
  def screen_z
    v = BattleUI.on? ? BattleUI.screen_y(self) : nil
    return (v != nil ? v * 4 : battle_ui_screen_z)
  end
end

class Game_Enemy
  alias battle_ui_screen_x screen_x
  alias battle_ui_screen_y screen_y
  alias battle_ui_screen_z screen_z
  def screen_x
    v = BattleUI.on? ? BattleUI.screen_x(self) : nil
    return (v != nil ? v : battle_ui_screen_x)
  end
  def screen_y
    v = BattleUI.on? ? BattleUI.screen_y(self) : nil
    return (v != nil ? v : battle_ui_screen_y)
  end
  def screen_z
    v = BattleUI.on? ? BattleUI.screen_y(self) : nil
    return (v != nil ? v * 4 : battle_ui_screen_z)
  end
end

# FE Tactics enemies keep their own place only outside the slots
if defined?(Game_FEEnemy)
  class Game_FEEnemy
    def screen_x
      v = BattleUI.on? ? BattleUI.screen_x(self) : nil
      return v if v != nil
      return (@fe_x || super)
    end
    def screen_y
      v = BattleUI.on? ? BattleUI.screen_y(self) : nil
      return v if v != nil
      return (@fe_y || super)
    end
  end
end

#==============================================================================
# ** Only the first MAX_ACTORS / MAX_ENEMIES take part in a battle
#==============================================================================
class Game_Party
  def battle_ui_actors=(list)
    @actors = list
  end
end

class Game_Troop
  alias battle_ui_setup setup
  def setup(troop_id)
    battle_ui_setup(troop_id)
    @enemies = @enemies[0, BattleUI::MAX_ENEMIES] if @enemies.size > BattleUI::MAX_ENEMIES
  end
end

#==============================================================================
# ** Sprite_Battler - mirrored enemies
#==============================================================================
class Sprite_Battler
  alias battle_ui_update update
  def update
    battle_ui_update
    return if @battler == nil
    self.mirror = BattleUI.mirror?(@battler) if BattleUI.on?
  end
end

#==============================================================================
# ** Spriteset_Battle - full screen battleback, all battlers in one viewport
#    (depth sorted by foot height), BattleUI::Hud
#==============================================================================
class Spriteset_Battle
  attr_reader :viewport1, :viewport2, :hud
  def initialize
    @viewport1 = Viewport.new(0, 0, 640, 480)
    @viewport2 = Viewport.new(0, 0, 640, 480)
    @viewport3 = Viewport.new(0, 0, 640, 480)
    @viewport4 = Viewport.new(0, 0, 640, 480)
    @viewport2.z = 101
    @viewport3.z = 200
    @viewport4.z = 5000
    @battleback_sprite = Sprite.new(@viewport1)
    @battleback_sprite.z = -100
    @enemy_sprites = []
    for enemy in $game_troop.enemies.reverse
      @enemy_sprites.push(Sprite_Battler.new(@viewport1, enemy))
    end
    @actor_sprites = []
    BattleUI::ACTOR_POS.size.times do
      @actor_sprites.push(Sprite_Battler.new(@viewport1))
    end
    @weather = RPG::Weather.new(@viewport1)
    @picture_sprites = []
    for i in 51..100
      @picture_sprites.push(Sprite_Picture.new(@viewport3,
        $game_screen.pictures[i]))
    end
    @timer_sprite = Sprite_Timer.new
    @hud = BattleUI::Hud.new(self)
    update
  end

  def battler_sprite(b)
    (@enemy_sprites + @actor_sprites).each { |s| return s if s.battler == b }
    return nil
  end

  def dispose
    @hud.dispose
    if @battleback_sprite.bitmap != nil
      @battleback_sprite.bitmap.dispose
    end
    @battleback_sprite.dispose
    for sprite in @enemy_sprites + @actor_sprites
      sprite.dispose
    end
    @weather.dispose
    for sprite in @picture_sprites
      sprite.dispose
    end
    @timer_sprite.dispose
    @viewport1.dispose
    @viewport2.dispose
    @viewport3.dispose
    @viewport4.dispose
  end

  def effect?
    for sprite in @enemy_sprites + @actor_sprites
      return true if sprite.effect?
    end
    return false
  end

  def update
    @actor_sprites.each_with_index do |s, i|
      s.battler = (i < BattleUI::MAX_ACTORS ? $game_party.actors[i] : nil)
    end
    if @battleback_name != $game_temp.battleback_name
      @battleback_name = $game_temp.battleback_name
      if @battleback_sprite.bitmap != nil
        @battleback_sprite.bitmap.dispose
      end
      bmp = RPG::Cache.battleback(@battleback_name)
      @battleback_sprite.bitmap = bmp
      zoom = [640.0 / bmp.width, 480.0 / bmp.height].max
      @battleback_sprite.src_rect.set(0, 0, bmp.width, bmp.height)
      @battleback_sprite.ox = bmp.width / 2
      @battleback_sprite.oy = bmp.height / 2
      @battleback_sprite.x = 320
      @battleback_sprite.y = 240
      @battleback_sprite.zoom_x = zoom
      @battleback_sprite.zoom_y = zoom
    end
    for sprite in @enemy_sprites + @actor_sprites
      sprite.update
    end
    @hud.update
    @weather.type = $game_screen.weather_type
    @weather.max = $game_screen.weather_max
    @weather.update
    for sprite in @picture_sprites
      sprite.update
    end
    @timer_sprite.update
    @viewport1.tone = $game_screen.tone
    @viewport1.ox = $game_screen.shake
    @viewport4.color = $game_screen.flash_color
    @viewport1.update
    @viewport2.update
    @viewport4.update
  end
end

#==============================================================================
# ** Scene_Battle - new flow and windows
#==============================================================================
class Scene_Battle
  #--------------------------------------------------------------------------
  # * Only the first MAX_ACTORS party members fight
  #--------------------------------------------------------------------------
  alias battle_ui_main main
  def main
    full = nil
    if $game_party.actors.size > BattleUI::MAX_ACTORS
      full = $game_party.actors.dup
      $game_party.battle_ui_actors = full[0, BattleUI::MAX_ACTORS]
    end
    battle_ui_main
    if full != nil
      now = $game_party.actors
      extra = now - full
      $game_party.battle_ui_actors = full + extra
    end
  end
  #--------------------------------------------------------------------------
  # * Start: replace the command window, hide the old windows
  #--------------------------------------------------------------------------
  alias battle_ui_start_phase1 start_phase1
  def start_phase1
    @hud = @spriteset.hud
    if @actor_command_window != @hud.command
      @actor_command_window.dispose
      @actor_command_window = @hud.command
    end
    @party_command_window.active = false
    @party_command_window.visible = false
    @status_window.visible = false
    battle_ui_start_phase1
  end
  #--------------------------------------------------------------------------
  # * Start of a round: no Fight / Escape window, straight to the actions
  #--------------------------------------------------------------------------
  def start_phase2
    @phase = 2
    @actor_index = -1
    @active_battler = nil
    @party_command_window.active = false
    @party_command_window.visible = false
    @actor_command_window.active = false
    @actor_command_window.visible = false
    $game_party.clear_actions
    start_phase4
  end
  #--------------------------------------------------------------------------
  # * Next fighter in turn order. A party member chooses a command now.
  #--------------------------------------------------------------------------
  def update_phase4_step1
    @help_window.visible = false
    return if judge
    if $game_temp.forcing_battler == nil
      setup_battle_event
      return if $game_system.battle_interpreter.running?
    end
    if $game_temp.forcing_battler != nil
      @action_battlers.delete($game_temp.forcing_battler)
      @action_battlers.unshift($game_temp.forcing_battler)
    end
    if @action_battlers.size == 0
      start_phase2
      return
    end
    @animation1_id = 0
    @animation2_id = 0
    @common_event_id = 0
    @active_battler = @action_battlers.shift
    return if @active_battler.index == nil
    if @active_battler.hp > 0 and @active_battler.slip_damage?
      @active_battler.slip_damage_effect
      @active_battler.damage_pop = true
    end
    @active_battler.remove_states_auto
    @status_window.refresh
    if @active_battler.is_a?(Game_Actor) and @active_battler.inputable? and
       !@active_battler.current_action.forcing
      bui_start_input
      return
    end
    @phase4_step = 2
  end

  def bui_start_input
    @phase = 3
    @actor_index = $game_party.actors.index(@active_battler)
    @active_battler.current_action.clear
    @hud.active_battler = @active_battler
    phase3_setup_command_window
  end
  #--------------------------------------------------------------------------
  # * Command window
  #--------------------------------------------------------------------------
  def phase3_setup_command_window
    @party_command_window.active = false
    @party_command_window.visible = false
    @actor_command_window.setup(@active_battler)
    @actor_command_window.index = 0
    @actor_command_window.active = true
    @actor_command_window.visible = true
  end

  # Command chosen: the character acts right away
  def phase3_next_actor
    @actor_command_window.active = false
    @actor_command_window.visible = false
    @hud.active_battler = nil
    @phase = 4
    @phase4_step = 2
  end

  # No going back to an earlier character (they have already acted)
  def phase3_prior_actor
  end

  def update_phase3
    if @hud.placeholder?
      if Input.trigger?(Input::B) or Input.trigger?(Input::C)
        $game_system.se_play($data_system.cancel_se)
        @hud.close_placeholder
        @actor_command_window.active = true
        @actor_command_window.visible = true
      end
      return
    end
    if @enemy_arrow != nil
      update_phase3_enemy_select
    elsif @actor_arrow != nil
      update_phase3_actor_select
    elsif @skill_window != nil
      update_phase3_skill_select
    elsif @item_window != nil
      update_phase3_item_select
    elsif @actor_command_window.active
      update_phase3_basic_command
    end
  end

  def update_phase3_basic_command
    return unless Input.trigger?(Input::C)
    $game_system.se_play($data_system.decision_se)
    case @actor_command_window.index
    when 0  # Angreifen
      @active_battler.current_action.kind = 0
      @active_battler.current_action.basic = 0
      start_enemy_select
    when 1  # Skill
      @active_battler.current_action.kind = 1
      start_skill_select
    when 2  # Item
      @active_battler.current_action.kind = 2
      start_item_select
    when 3  # Checken (placeholder)
      @actor_command_window.active = false
      @hud.open_placeholder
    end
  end
  #--------------------------------------------------------------------------
  # * Skill / item lists: area targets get a confirm step
  #--------------------------------------------------------------------------
  def update_phase3_skill_select
    @skill_window.visible = true
    @skill_window.update
    if Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      end_skill_select
      return
    end
    if Input.trigger?(Input::C)
      @skill = @skill_window.skill
      if @skill == nil or not @active_battler.skill_can_use?(@skill.id)
        $game_system.se_play($data_system.buzzer_se)
        return
      end
      $game_system.se_play($data_system.decision_se)
      @active_battler.current_action.skill_id = @skill.id
      @skill_window.visible = false
      bui_choose_target(@skill.scope, :skill)
    end
  end

  def update_phase3_item_select
    @item_window.visible = true
    @item_window.update
    if Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      end_item_select
      return
    end
    if Input.trigger?(Input::C)
      @item = @item_window.item
      unless @item.is_a?(RPG::Item) and $game_party.item_can_use?(@item.id)
        $game_system.se_play($data_system.buzzer_se)
        return
      end
      $game_system.se_play($data_system.decision_se)
      @active_battler.current_action.item_id = @item.id
      @item_window.visible = false
      bui_choose_target(@item.scope, :item)
    end
  end

  def bui_choose_target(scope, kind)
    case scope
    when 1    then start_enemy_select
    when 2    then bui_start_area(:enemy)
    when 3, 5 then start_actor_select
    when 4    then bui_start_area(:actor)
    else
      end_skill_select if @skill_window != nil
      end_item_select if @item_window != nil
      phase3_next_actor
    end
  end
  #--------------------------------------------------------------------------
  # * Targets
  #--------------------------------------------------------------------------
  def bui_action
    a = @active_battler.current_action
    return [:skill, $data_skills[a.skill_id]] if a.kind == 1
    return [:item, $data_items[a.item_id]] if a.kind == 2
    return [:attack, nil]
  end

  def start_enemy_select
    k = bui_action
    @enemy_arrow = BattleUI::Targeter.new(@hud, :enemy, false, @active_battler, k[0], k[1])
    @actor_command_window.active = false
    @actor_command_window.visible = false
  end

  def start_actor_select
    k = bui_action
    @actor_arrow = BattleUI::Targeter.new(@hud, :actor, false, @active_battler, k[0], k[1])
    @actor_arrow.index = @actor_index
    @actor_command_window.active = false
    @actor_command_window.visible = false
  end

  def bui_start_area(side)
    k = bui_action
    t = BattleUI::Targeter.new(@hud, side, true, @active_battler, k[0], k[1])
    if side == :enemy
      @enemy_arrow = t
    else
      @actor_arrow = t
    end
    @actor_command_window.active = false
    @actor_command_window.visible = false
  end

  def end_actor_select
    @actor_arrow.dispose
    @actor_arrow = nil
    if @actor_command_window.index == 0
      @actor_command_window.active = true
      @actor_command_window.visible = true
    end
  end
end
