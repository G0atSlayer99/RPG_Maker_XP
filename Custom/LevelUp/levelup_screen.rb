#==============================================================================
# ** Level Up  (Fire Emblem style level-up screen)
#------------------------------------------------------------------------------
#  Shows a level-up screen on the map for every level an actor gains:
#    darkened map, the actor's walk sprite on a highlighted tile, a
#    "Level Up!" sign above it and a parchment window with face, name, class,
#    "Lv a -> b" and the 8 stats. Rising stats count up one after another
#    (+1 green, +2 blue). All stats start faded; a rising stat turns dark on
#    its turn, stats without a gain stay faded and are skipped.
#    Then "Skip" appears; C or A closes the screen.
#  Several levels from one EXP change -> one screen per level.
#  Several actors -> one after another (queue). Afterwards the game continues.
#
#  Only actors edited in the Attributes panel (class growth) get the screen.
#  The values are the real class growth rolls of the "Attributes" script:
#  roll_growth is split into single levels and every level is logged in
#  $game_temp.levelup_queue as
#    { "actor" => id, "from" => 3, "to" => 4,
#      "old" => [KP, SP, Str, Mg, Spd, Luck, Def, Res] before the roll,
#      "new" => [...] after the roll, "growth" => {"str" => 1, ...} }
#  ($game_actors[id].last_growth is still the sum of the last EXP change.)
#
#  When: Change EXP / Change Level (event commands) and battle EXP; the
#  screen opens on the map before the next event command runs.
#
#  Needs "Attributes" and "Status Screen" (fonts, colours, round face).
#  Place below "Status Screen", above "Main".
#  Source: RPGXP\Custom\LevelUp\levelup_screen.rb (inject with
#  RPGXP\Custom\StatusScreen\inject_script.py --name "Level Up").
#==============================================================================

module LevelUp
  #--------------------------------------------------------------------------
  # * Keys that close the screen once "Skip" is shown
  #   Input::C = Enter / Space / C,  Input::A = Shift / Z
  #--------------------------------------------------------------------------
  SKIP_KEYS = [Input::C, Input::A]
  #--------------------------------------------------------------------------
  # * Sounds: [file, volume, pitch]  (RTP Audio/SE and Audio/ME)
  #   FANFARE_KIND "me" pauses the map music while it plays (RPG Maker
  #   resumes it); use "se" with an SE file to keep the music running.
  #--------------------------------------------------------------------------
  FANFARE_KIND = "me"
  FANFARE      = ["007-Fanfare01", 100, 100]
  SE_PLUS1     = ["032-Switch01", 80, 120]
  SE_PLUS2     = ["105-Heal01",   80, 130]
  SE_SKIP      = nil        # nil = the database decision sound
  #--------------------------------------------------------------------------
  # * Timing in frames (40 frames = 1 second)
  #--------------------------------------------------------------------------
  FADE_IN     = 8     # map darkens, window appears
  INTRO_HOLD  = 14    # old values shown before the level-up moment
  POP         = 18    # pop: small -> slightly too big -> normal (0.45 s)
  AFTER_LEVEL = 10    # pause after the level pop
  VALUE_AT    = 5     # flash frame on which value, +1/+2 and sound change
  FLASH       = 16    # length of the gold row flash
  STAT_GAP    = 4     # pause after a stat's pop before the next stat
  SKIP_DELAY  = 16    # pause after the last stat before "Skip" (0.4 s)
  SKIP_FADE   = 8     # "Skip" fades in; keys count after this
  PULSE       = 60    # one pulse of the "Skip" text and frame (1.5 s)
  #--------------------------------------------------------------------------
  # * Colours
  #--------------------------------------------------------------------------
  PARCH      = Color.new(241, 228, 195)
  LEATHER    = Color.new( 74,  46,  27)
  GOLD       = Color.new(184, 145,  63)
  SHADOW     = Color.new( 30,  18,   8, 150)
  RED        = Color.new(122,  31,  31)
  INK        = Color.new( 46,  31,  16)
  INK2       = Color.new(106,  79,  44)
  MUTED      = Color.new(138, 115,  80)
  BOX_BORDER = Color.new(184, 152,  99)
  BOX_BG     = Color.new(232, 216, 178)
  DOTS       = Color.new(201, 174, 118)
  RING       = Color.new(122,  90,  46)
  DIM        = Color.new( 14,   9,   5, 115)
  TILE_FILL  = Color.new(241, 228, 195, 110)
  TILE_LINE  = Color.new(255, 248, 220, 230)
  FLASH_GOLD = Color.new(255, 222, 130)
  OUTLINE    = Color.new( 28,  18,   8)
  PLUS1_TEXT = Color.new( 91, 209,  62)
  PLUS1_ARR  = Color.new( 61, 170,  46)
  PLUS2_TEXT = Color.new(111, 168, 255)
  PLUS2_ARR  = Color.new( 46, 111, 224)
  SKIP_GLOW  = Color.new(232, 195,  90)     # Skip frame: gold -> white
  WHITE      = Color.new(255, 255, 255)
  #--------------------------------------------------------------------------
  # * Stats: label, in the order of LevelUp.values and of the animation
  #--------------------------------------------------------------------------
  LABELS = ["KP", "SP", "Str", "Mg", "Spd", "Luck", "Def", "Res"]
  #--------------------------------------------------------------------------
  # * Layout
  #--------------------------------------------------------------------------
  WIN_W  = 608
  WIN_H  = 208        # 480 - 16 - 208 = 256: the player's tile ends there
  FACE_R = 46
  COL_X  = [178, 398]       # stat columns inside the window
  ROW_Y  = 12
  ROW_H  = 46
  COL_W  = 200
  SKIP_W = 96
  SKIP_H = 36
  Z      = 7000

  #--------------------------------------------------------------------------
  # * Queue / debug trace (tests set @trace = [])
  #--------------------------------------------------------------------------
  def self.queue
    return $game_temp.levelup_queue
  end
  def self.pending?
    return ($game_temp != nil and !queue.empty?)
  end
  def self.trace
    return @trace
  end
  def self.trace=(list)
    @trace = list
  end
  def self.log(text)
    @trace.push(text) if @trace != nil
  end
  #--------------------------------------------------------------------------
  # * The values the Status screen shows
  #--------------------------------------------------------------------------
  def self.values(a)
    return [a.maxhp, a.maxsp, a.str, a.int, a.agi, a.dex, a.pdef, a.mdef]
  end
  #--------------------------------------------------------------------------
  # * May the screen open now? (on the map, nothing else going on)
  #--------------------------------------------------------------------------
  def self.ready?
    return false unless pending?
    return false if $game_temp.message_window_showing
    return false if $game_temp.player_transferring
    return false if $game_temp.transition_processing
    return true
  end
  #--------------------------------------------------------------------------
  # * Shows every queued level-up, then clears the key that closed it
  #--------------------------------------------------------------------------
  def self.run(spriteset = nil)
    while pending?
      e = queue.shift
      actor = $game_actors[e["actor"]]
      next if actor == nil
      log("open actor " + e["actor"].to_s + " Lv " + e["from"].to_s + "->" + e["to"].to_s)
      screen = Screen.new(actor, e)
      until screen.done?
        Graphics.update
        Input.update
        spriteset.update if spriteset != nil
        screen.update
      end
      screen.dispose
      log("close actor " + e["actor"].to_s)
    end
    Input.update
  end
  #--------------------------------------------------------------------------
  # * Sounds
  #--------------------------------------------------------------------------
  def self.play(data, kind = "se")
    return if data == nil
    a = RPG::AudioFile.new(data[0], data[1], data[2])
    if kind == "me"
      $game_system.me_play(a)
    else
      $game_system.se_play(a)
    end
  end

  #==========================================================================
  # ** Drawing helpers
  #==========================================================================
  # Rounded rectangle, filled; corners anti-aliased and blended
  def self.rounded_fill(b, x, y, w, h, r, c)
    return if w <= 0 or h <= 0
    r = [r, w / 2, h / 2].min
    b.fill_rect(x + r, y, w - 2 * r, h, c)
    b.fill_rect(x, y + r, r, h - 2 * r, c)
    b.fill_rect(x + w - r, y + r, r, h - 2 * r, c)
    return if r <= 0
    p = StatusBook::Painter.new(b)
    for py in 0...r
      for px in 0...r
        d = Math.sqrt((r - px - 0.5) ** 2 + (r - py - 0.5) ** 2)
        a = r - d + 0.5
        next if a <= 0
        a = 1.0 if a > 1
        p.blend(x + px, y + py, c, a)
        p.blend(x + w - 1 - px, y + py, c, a)
        p.blend(x + px, y + h - 1 - py, c, a)
        p.blend(x + w - 1 - px, y + h - 1 - py, c, a)
      end
    end
  end
  # Parchment box: hard shadow, leather border, gold inner line
  def self.frame(b, x, y, w, h, r, border, shadow)
    rounded_fill(b, x + shadow, y + shadow, w, h, r, SHADOW) if shadow > 0
    rounded_fill(b, x, y, w, h, r, LEATHER)
    rounded_fill(b, x + border, y + border, w - 2 * border, h - 2 * border, r - border + 2, PARCH)
    g = border + 2
    rounded_fill(b, x + g, y + g, w - 2 * g, h - 2 * g, [r - g + 2, 2].max, GOLD)
    rounded_fill(b, x + g + 1, y + g + 1, w - 2 * g - 2, h - 2 * g - 2, [r - g + 1, 1].max, PARCH)
  end
  # Rounded outline of width bw along the bitmap's edge
  def self.ring(b, r, bw, c)
    w = b.width
    h = b.height
    for y in 0...h
      for x in 0...w
        px = x + 0.5
        py = y + 0.5
        cx = [[px, r].max, w - r].min
        cy = [[py, r].max, h - r].min
        d = r - Math.sqrt((px - cx) ** 2 + (py - cy) ** 2)   # > 0 inside
        a = [[d + 0.5, 0].max, 1].min - [[d - bw + 0.5, 0].max, 1].min
        next if a <= 0
        b.set_pixel(x, y, Color.new(c.red, c.green, c.blue, 255 * a))
      end
    end
  end
  # Up arrow (13 x 14) with a 1 px outline, as a new 15 x 16 bitmap
  def self.arrow_bitmap(color)
    inside = lambda do |x, y|
      next false if x < 0 or y < 0 or x > 12 or y > 13
      next (x - 6).abs <= y if y <= 5
      next (x >= 4 and x <= 8)
    end
    b = Bitmap.new(15, 16)
    for y in -1..14
      for x in -1..13
        if inside.call(x, y)
          b.set_pixel(x + 1, y + 1, color)
        else
          n = false
          for d in [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [-1, 1], [1, -1]]
            n = true if inside.call(x + d[0], y + d[1])
          end
          b.set_pixel(x + 1, y + 1, OUTLINE) if n
        end
      end
    end
    return b
  end
  # Small right arrow for "Lv a -> b"
  def self.draw_right_arrow(b, x, y, c)
    b.fill_rect(x, y - 1, 10, 2, c)
    for i in 0..3
      b.fill_rect(x + 9 - i, y - 1 - i, 1, 2 + 2 * i, c)
    end
  end
  # Small caps for every word, centred on cx
  def self.caps_words(p, cx, base, str, big, small, color)
    words = str.split(" ")
    p.font(small, true)
    space = p.width_of(" ")
    w = 0
    words.each { |x| w += caps_width(p, x, big, small, true) }
    w += space * (words.size - 1)
    x = cx - w / 2
    for word in words
      x += p.small_caps(x, base, word, big, small, true, color) + space
    end
  end
  # Width of small caps text (same rule as Painter#small_caps)
  def self.caps_width(p, str, big, small, bold)
    chars = str.scan(/./mu)
    return 0 if chars.empty?
    p.font(big, bold)
    w = p.width_of(chars[0])
    p.font(small, bold)
    w += p.width_of(StatusBook.upcase(chars[1, chars.size - 1].join))
    return w
  end

  #==========================================================================
  # ** LevelUp::Screen - one level of one actor
  #==========================================================================
  class Screen
    attr_reader :sprites, :phase, :gains
    #------------------------------------------------------------------------
    def initialize(actor, entry)
      @actor = actor
      @from = entry["from"]
      @to = entry["to"]
      @old = entry["old"]
      @new = entry["new"]
      @gains = []
      for i in 0...8
        @gains.push([@new[i] - @old[i], 0].max)
      end
      @sprites = []
      @bitmaps = []
      @base = []
      layout
      create_map_part
      create_window
      create_rows
      create_level
      create_sign
      create_skip
      @phase = :intro
      @t = 0
      update_fade
    end
    #------------------------------------------------------------------------
    def done?
      return @phase == :done
    end
    #------------------------------------------------------------------------
    def dispose
      for s in @sprites
        s.dispose
      end
      for b in @bitmaps
        b.dispose
      end
      @sprites = []
      @bitmaps = []
    end
    #------------------------------------------------------------------------
    # * Positions: player tile, window bottom (or top if the tile is under it)
    #------------------------------------------------------------------------
    def layout
      @px = $game_player.screen_x
      @py = $game_player.screen_y
      @win_x = 16
      bottom_y = 480 - 16 - WIN_H
      @top = (@py - 32 > bottom_y - 8)    # tile (mostly) under the window
      @win_y = @top ? 16 : bottom_y
      @skip_x = @win_x + WIN_W - SKIP_W
      @skip_y = @top ? @win_y + WIN_H + 8 : @win_y - 8 - SKIP_H
    end
    #------------------------------------------------------------------------
    def new_bitmap(w, h)
      b = Bitmap.new(w, h)
      @bitmaps.push(b)
      return b
    end
    #------------------------------------------------------------------------
    def new_sprite(bitmap, x, y, z, base_opacity = nil)
      s = Sprite.new
      s.bitmap = bitmap
      s.x = x
      s.y = y
      s.z = Z + z
      @sprites.push(s)
      if base_opacity != nil
        @base.push([s, base_opacity])
        s.opacity = 0
      end
      return s
    end
    #------------------------------------------------------------------------
    def painter(b)
      return StatusBook::Painter.new(b)
    end
    #------------------------------------------------------------------------
    # * Dark overlay, highlighted tile, walk sprite
    #------------------------------------------------------------------------
    def create_map_part
      b = new_bitmap(640, 480)
      b.fill_rect(b.rect, DIM)
      new_sprite(b, 0, 0, 0, 255)
      b = new_bitmap(32, 32)
      b.fill_rect(b.rect, TILE_LINE)
      b.fill_rect(1, 1, 30, 30, Color.new(0, 0, 0, 0))
      b.fill_rect(1, 1, 30, 30, TILE_FILL)
      new_sprite(b, @px - 16, @py - 32, 1, 255)
      @char_h = 48
      name = @actor.character_name
      if name != nil and name != ""
        src = RPG::Cache.character(name, @actor.character_hue)
        cw = src.width / 4
        ch = src.height / 4
        @char_h = ch
        s = new_sprite(src, @px, @py, 2, 255)
        s.src_rect.set(0, 0, cw, ch)
        s.ox = cw / 2
        s.oy = ch
      end
    end
    #------------------------------------------------------------------------
    # * Bottom window: frame, face, name, class, level box, divider, dots
    #------------------------------------------------------------------------
    def create_window
      b = new_bitmap(WIN_W + 4, WIN_H + 4)
      LevelUp.frame(b, 0, 0, WIN_W, WIN_H, 12, 4, 4)
      p = painter(b)
      # face with brown ring and thin gold outer ring
      cx = 83
      cy = 61
      p.circle(cx, cy, 50.5, GOLD)
      p.circle(cx, cy, 49.0, RING)
      p.circle(cx, cy, FACE_R, PARCH)
      face = StatusBook.round_face(@actor, FACE_R)
      if face != nil
        b.blt(cx - FACE_R, cy - FACE_R, face, face.rect)
        face.dispose
      end
      # name (small caps) and class
      name = @actor.name
      w = [LevelUp.caps_width(p, name, 24, 18, true), 144].min
      p.small_caps(cx - w / 2, 136, name, 24, 18, true, INK, 144)
      p.font(16, true, false, RED)
      cls = p.fit_text(StatusBook.german_class(@actor), 144)
      p.text(cx, 156, cls, 1)
      # level box
      @box_x = cx - 60
      @box_y = 166
      LevelUp.rounded_fill(b, @box_x, @box_y, 120, 30, 4, BOX_BORDER)
      LevelUp.rounded_fill(b, @box_x + 1, @box_y + 1, 118, 28, 3, BOX_BG)
      p.font(15, true, false, INK2)
      p.text(@box_x + 9, @box_y + 20, "Lv")
      # divider
      b.fill_rect(166, 16, 1, WIN_H - 32, BOX_BORDER)
      # dotted lines between the stat rows
      for col in 0...2
        for row in 1...4
          y = ROW_Y + row * ROW_H
          x = COL_X[col]
          while x < COL_X[col] + COL_W
            b.set_pixel(x, y, DOTS)
            x += 3
          end
        end
      end
      new_sprite(b, @win_x, @win_y, 10, 255)
    end
    #------------------------------------------------------------------------
    # * Stat rows: flash, label + value, +1/+2 with arrow
    #------------------------------------------------------------------------
    def row_pos(i)
      return [@win_x + COL_X[i / 4], @win_y + ROW_Y + (i % 4) * ROW_H]
    end
    #------------------------------------------------------------------------
    def create_rows
      @flash = []
      @rows = []
      @gain_sprites = []
      fb = new_bitmap(COL_W, ROW_H - 8)
      LevelUp.rounded_fill(fb, 0, 0, COL_W, ROW_H - 8, 6, FLASH_GOLD)
      for i in 0...8
        pos = row_pos(i)
        f = new_sprite(fb, pos[0], pos[1] + 4, 11)
        f.opacity = 0
        @flash.push(f)
        rb = new_bitmap(COL_W, ROW_H)
        @rows.push(new_sprite(rb, pos[0], pos[1], 12, 128))   # all faded: no spoilers
        draw_row(i, @old[i])
        g = gain_sprite(@gains[i])
        if g != nil
          g.x += pos[0] + 116
          g.y = pos[1] + ROW_H / 2
          g.visible = false
        end
        @gain_sprites.push(g)
      end
    end
    #------------------------------------------------------------------------
    def draw_row(i, value)
      b = @rows[i].bitmap
      b.clear
      p = painter(b)
      p.font(17, true, false, INK)
      p.text(6, 30, LABELS[i])
      p.font(20, true, false, INK, true)
      p.text(108, 31, value.to_s, 2)
    end
    #------------------------------------------------------------------------
    def gain_sprite(gain)
      return nil if gain <= 0
      text_c = gain == 1 ? PLUS1_TEXT : PLUS2_TEXT
      arr_c  = gain == 1 ? PLUS1_ARR : PLUS2_ARR
      b = new_bitmap(80, 32)
      p = painter(b)
      p.font(18, true, false, text_c, true)
      w = p.outlined(2, 23, "+" + gain.to_s, OUTLINE)
      a = LevelUp.arrow_bitmap(arr_c)
      b.blt(2 + w + 4, 8, a, a.rect)
      a.dispose
      used = 2 + w + 4 + 15
      s = new_sprite(b, 0, 0, 13)
      s.ox = used / 2
      s.oy = 16
      s.x = used / 2
      return s
    end
    #------------------------------------------------------------------------
    # * "Lv a -> b": old part hidden until the level-up moment
    #------------------------------------------------------------------------
    def create_level
      b = new_bitmap(44, 30)
      p = painter(b)
      p.font(16, true, false, MUTED, true)
      w = p.text(0, 21, @from.to_s)
      LevelUp.draw_right_arrow(b, w + 6, 15, MUTED)
      @lv_old = new_sprite(b, @win_x + @box_x + 30, @win_y + @box_y, 14)
      @lv_old.visible = false
      b = new_bitmap(48, 30)
      @lv_new = new_sprite(b, @win_x + @box_x + 90, @win_y + @box_y + 15, 14, 255)
      @lv_new.ox = 24
      @lv_new.oy = 15
      draw_level_number(@from)
    end
    #------------------------------------------------------------------------
    def draw_level_number(lv)
      b = @lv_new.bitmap
      b.clear
      p = painter(b)
      p.font(22, true, false, RED, true)
      p.text(24, 23, lv.to_s, 1)
    end
    #------------------------------------------------------------------------
    # * "Level Up!" sign above the walk sprite (below it if the window is on top)
    #------------------------------------------------------------------------
    def create_sign
      b = new_bitmap(183, 47)
      LevelUp.frame(b, 0, 0, 180, 44, 7, 3, 3)
      p = painter(b)
      LevelUp.caps_words(p, 90, 31, "Level Up!", 26, 20, RED)
      y = @py - @char_h - 4 - 22
      if @top and y - 22 < @win_y + WIN_H + 4
        y = @py + 8 + 22
      end
      y = [[y, 26].max, 480 - 26].min
      x = [[@px, 16 + 90].max, 640 - 16 - 90].min
      @sign = new_sprite(b, x, y, 20)
      @sign.ox = 90
      @sign.oy = 22
      @sign.visible = false
    end
    #------------------------------------------------------------------------
    # * "Skip" window with its pulsing frame
    #------------------------------------------------------------------------
    def create_skip
      @skip = []
      b = new_bitmap(SKIP_W + 12, SKIP_H + 12)
      LevelUp.ring(b, 9, 3, SKIP_GLOW)
      @glow_gold = new_sprite(b, @skip_x - 6, @skip_y - 6, 30)
      b = new_bitmap(SKIP_W + 12, SKIP_H + 12)
      LevelUp.ring(b, 9, 3, WHITE)
      @glow_white = new_sprite(b, @skip_x - 6, @skip_y - 6, 31)
      b = new_bitmap(SKIP_W + 3, SKIP_H + 3)
      LevelUp.frame(b, 0, 0, SKIP_W, SKIP_H, 6, 3, 3)
      @skip_win = new_sprite(b, @skip_x, @skip_y, 32)
      @skip_red = new_sprite(skip_text(RED), @skip_x, @skip_y, 33)
      @skip_white = new_sprite(skip_text(WHITE, LEATHER), @skip_x, @skip_y, 34)
      @skip = [@glow_gold, @glow_white, @skip_win, @skip_red, @skip_white]
      for s in @skip
        s.visible = false
      end
    end
    #------------------------------------------------------------------------
    def skip_text(color, outline = nil)
      b = new_bitmap(SKIP_W, SKIP_H)
      p = painter(b)
      w = LevelUp.caps_width(p, "Skip", 22, 17, true)
      x = (SKIP_W - w) / 2
      if outline
        for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]
          p.small_caps(x + d[0], 25 + d[1], "Skip", 22, 17, true, outline)
        end
      end
      p.small_caps(x, 25, "Skip", 22, 17, true, color)
      return b
    end

    #------------------------------------------------------------------------
    # * Animation
    #------------------------------------------------------------------------
    def pop_zoom(f)
      return 1.0 if f >= POP - 1
      up = 10
      if f < up
        x = (f + 1).to_f / up
        return 0.3 + 0.85 * (1 - (1 - x) ** 2)
      end
      return 1.15 - 0.15 * (f - up + 1).to_f / (POP - 1 - up)
    end
    #------------------------------------------------------------------------
    def pop(sprite, f)
      z = pop_zoom(f)
      sprite.zoom_x = z
      sprite.zoom_y = z
      sprite.opacity = f < 4 ? 255 * (f + 1) / 4 : 255
    end
    #------------------------------------------------------------------------
    def update_fade
      k = [@t.to_f / FADE_IN, 1.0].min
      for e in @base
        e[0].opacity = (e[1] * k).to_i
      end
    end
    #------------------------------------------------------------------------
    def update
      case @phase
      when :intro
        update_fade
        start_level if @t >= FADE_IN + INTRO_HOLD
      when :level
        pop(@sign, @t)
        pop(@lv_new, @t)
        next_stat(0) if @t >= POP + AFTER_LEVEL
      when :stat
        update_stat
      when :wait
        show_skip if @t >= SKIP_DELAY
      when :skip
        update_skip
      end
      @t += 1
    end
    #------------------------------------------------------------------------
    def start_level
      @phase = :level
      @t = 0
      @sign.visible = true
      @lv_old.visible = true
      draw_level_number(@to)
      LevelUp.play(FANFARE, FANFARE_KIND)
      LevelUp.log("level " + @from.to_s + "->" + @to.to_s)
      pop(@sign, 0)
      pop(@lv_new, 0)
    end
    #------------------------------------------------------------------------
    def next_stat(i)
      while i < 8 and @gains[i] <= 0
        LevelUp.log("skip " + LABELS[i])
        i += 1
      end
      @t = -1
      if i >= 8
        @phase = :wait
        LevelUp.log("stats done")
      else
        @stat = i
        @phase = :stat
      end
    end
    #------------------------------------------------------------------------
    def update_stat
      i = @stat
      t = @t
      if t <= VALUE_AT
        @flash[i].opacity = 200 * t / VALUE_AT
      else
        @flash[i].opacity = [200 - 200 * (t - VALUE_AT) / (FLASH - VALUE_AT), 0].max
      end
      if t == VALUE_AT
        draw_row(i, @new[i])
        @rows[i].opacity = 255             # darkens only on its turn
        @gain_sprites[i].visible = true
        LevelUp.play(@gains[i] >= 2 ? SE_PLUS2 : SE_PLUS1)
        LevelUp.log("stat " + LABELS[i] + " " + @old[i].to_s + "->" + @new[i].to_s + " +" + @gains[i].to_s)
      end
      pop(@gain_sprites[i], t - VALUE_AT) if t >= VALUE_AT
      next_stat(i + 1) if t >= VALUE_AT + POP + STAT_GAP
    end
    #------------------------------------------------------------------------
    def show_skip
      @phase = :skip
      @t = 0
      for s in @skip
        s.visible = true
      end
      update_skip
      LevelUp.log("skip shown")
    end
    #------------------------------------------------------------------------
    def update_skip
      fade = [(@t + 1).to_f / SKIP_FADE, 1.0].min
      k = (1 - Math.cos(2 * Math::PI * @t / PULSE)) / 2
      glow = (160 + 95 * k) * fade
      @glow_gold.opacity = glow.to_i
      @glow_white.opacity = (glow * k).to_i
      @skip_win.opacity = (255 * fade).to_i
      @skip_red.opacity = (255 * fade).to_i
      @skip_white.opacity = (255 * fade * k).to_i
      return if @t < SKIP_FADE
      for key in SKIP_KEYS
        if Input.trigger?(key)
          if SE_SKIP == nil
            $game_system.se_play($data_system.decision_se)
          else
            LevelUp.play(SE_SKIP)
          end
          LevelUp.log("closed by key " + key.to_s)
          @phase = :done
          return
        end
      end
    end
  end
end

#==============================================================================
# ** Game_Temp - the queue (not saved)
#==============================================================================
class Game_Temp
  def levelup_queue
    @levelup_queue = [] if @levelup_queue == nil
    return @levelup_queue
  end
end

#==============================================================================
# ** Game_Actor - log every single level of the class growth rolls
#==============================================================================
class Game_Actor < Game_Battler
  unless method_defined?(:levelup_roll_growth)
    alias levelup_roll_growth roll_growth
    alias levelup_set_exp     exp=
  end
  #--------------------------------------------------------------------------
  def exp=(exp)
    @levelup_logging = true
    begin
      levelup_set_exp(exp)
    ensure
      @levelup_logging = false
    end
  end
  #--------------------------------------------------------------------------
  # * Rolls level by level; old values = before that level's roll
  #--------------------------------------------------------------------------
  def roll_growth(levels)
    if !@levelup_logging or levels < 1 or !Attributes.actor_edited?(@actor_id)
      return levelup_roll_growth(levels)
    end
    first = @level - levels
    total = {}
    for k in 0...levels
      old = LevelUp.values(self)
      levelup_roll_growth(1)
      last_growth.each { |key, v| total[key] = total[key].to_i + v }
      LevelUp.queue.push({ "actor" => @actor_id, "from" => first + k,
        "to" => first + k + 1, "old" => old, "new" => LevelUp.values(self),
        "growth" => last_growth.dup })
    end
    @last_growth = total
  end
end

#==============================================================================
# ** Interpreter - Change EXP / Change Level wait one frame for the screen
#==============================================================================
class Interpreter
  unless method_defined?(:levelup_command_315)
    alias levelup_command_315 command_315
    alias levelup_command_316 command_316
  end
  def command_315
    r = levelup_command_315
    @wait_count = 1 if LevelUp.pending? and $scene.is_a?(Scene_Map)
    return r
  end
  def command_316
    r = levelup_command_316
    @wait_count = 1 if LevelUp.pending? and $scene.is_a?(Scene_Map)
    return r
  end
end

#==============================================================================
# ** Scene_Map - open the queued level-up screens
#==============================================================================
class Scene_Map
  unless method_defined?(:levelup_update)
    alias levelup_update update
  end
  def update
    LevelUp.run(@spriteset) if LevelUp.ready?
    levelup_update
  end
end
