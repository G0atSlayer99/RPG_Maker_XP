#==============================================================================
# ** Book Menu  (main menu as an open leather book)
#------------------------------------------------------------------------------
#  Replaces the default main menu (Scene_Menu):
#    left page   Menü: Inventar, Einheiten, Begleiter, Status, Options,
#                Speichern, Spiel Verlassen; Spielzeit and money boxes
#    right page  Gruppen: the party in groups of up to 3 characters plus one
#                Begleiter slot. The first character of a group is its leader.
#  Einheiten, Begleiter and Options open an empty placeholder window for now.
#
#  Groups are kept in Game_Party (saved with the game) and follow the party:
#  new party members take the first free character spot, removed ones leave.
#  A new group starts only when the previous one has 3 characters.
#  The party limit of 4 is raised to MAX_PARTY (Game_Party#add_actor).
#  Battles are not changed.
#
#  Controls: Up/Down in the menu, C confirm, B close. Right (or "Status")
#  moves into the groups: Left/Right along a row, Up/Down between rows,
#  Left from a leader goes back to the menu. C on a character opens the
#  Status screen; B there returns to the menu on the same character.
#
#  Needs "Status Screen" (fonts, colours, text helpers).
#  Place below "Status Screen" (and "Level Up"), above "Main".
#  Source: RPGXP\Custom\BookMenu\book_menu.rb (inject with
#  RPGXP\Custom\StatusScreen\inject_script.py --name "Book Menu").
#==============================================================================

module BookMenu
  #--------------------------------------------------------------------------
  # * Settings
  #--------------------------------------------------------------------------
  MAX_PARTY   = 12     # highest party size (default RPG Maker XP: 4)
  GROUP_SIZE  = 3      # characters per group (plus one Begleiter slot)
  MIN_ROWS    = 4      # empty groups are added until this many rows exist
  ENTRIES     = ["Inventar", "Einheiten", "Begleiter", "Status", "Options",
                 "Speichern", "Spiel Verlassen"]
  # default menu index (used by other screens) -> entry of this menu
  OLD_INDEX   = { 0 => 0, 1 => 0, 2 => 0, 3 => 3, 4 => 5, 5 => 6 }
  #--------------------------------------------------------------------------
  # * Colours
  #--------------------------------------------------------------------------
  LEATHER  = Color.new( 74,  46,  27)
  STITCH   = Color.new(165, 123,  74)
  PARCH    = Color.new(241, 228, 195)
  SPINE    = Color.new( 58,  36,  18)
  RED      = Color.new(122,  31,  31)
  INK      = Color.new( 46,  31,  16)
  INK2     = Color.new(106,  79,  44)
  GOLD     = Color.new(138, 106,  18)
  LINE     = Color.new(184, 152,  99)
  LINE2    = Color.new(201, 174, 118)
  SEL_BG   = Color.new(227, 210, 168)
  BOX_BG   = Color.new(232, 216, 178)
  BASE     = Color.new(201, 162,  58)
  BASE_RIM = Color.new(150, 112,  30)
  SEAL_GRAY = Color.new(160, 148, 128)
  SHADE    = Color.new( 40,  25,  10)
  #--------------------------------------------------------------------------
  # * Layout
  #--------------------------------------------------------------------------
  LEFT_X   = 34                  # left page content
  LEFT_W   = 152
  ENTRY_Y  = 72
  ENTRY_H  = 34
  LIST_X   = 222                 # right page content
  LIST_R   = 602
  LIST_TOP = 62
  LIST_BOT = 426
  GROUP_H  = 112                 # row heights
  EMPTY_H  = 64
  SEAL_X   = 241
  SLOT_X   = [312, 396, 480, 562]
  FOOT_Y   = 74                  # feet of the walk sprites inside a row
  NAME_Y   = 96                  # name baseline inside a row
  Z        = 100

  #==========================================================================
  # * Drawing helpers
  #==========================================================================
  def self.painter(b)
    return StatusBook::Painter.new(b)
  end
  # filled rounded rectangle, anti-aliased corners
  def self.rounded_fill(b, x, y, w, h, r, c)
    return if w <= 0 or h <= 0
    r = [r, w / 2, h / 2].min
    b.fill_rect(x + r, y, w - 2 * r, h, c)
    b.fill_rect(x, y + r, r, h - 2 * r, c)
    b.fill_rect(x + w - r, y + r, r, h - 2 * r, c)
    return if r <= 0
    p = painter(b)
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
  # framed box: border colour, then fill inset by 1
  def self.box(b, x, y, w, h, r, fill, border)
    rounded_fill(b, x, y, w, h, r, border)
    rounded_fill(b, x + 1, y + 1, w - 2, h - 2, [r - 1, 0].max, fill)
  end
  # point s pixels along a rounded rectangle path (top-left of a t x t dot)
  def self.path_point(x, y, w, h, r, s)
    segs = [w - 2 * r, Math::PI * r / 2, h - 2 * r, Math::PI * r / 2,
            w - 2 * r, Math::PI * r / 2, h - 2 * r, Math::PI * r / 2]
    i = 0
    while i < 8 and s > segs[i]
      s -= segs[i]
      i += 1
    end
    i = 7 if i > 7
    a = r > 0 ? s / r.to_f : 0
    case i
    when 0 then return [x + r + s, y]
    when 1 then return [x + w - r + r * Math.sin(a), y + r - r * Math.cos(a)]
    when 2 then return [x + w, y + r + s]
    when 3 then return [x + w - r + r * Math.cos(a), y + h - r + r * Math.sin(a)]
    when 4 then return [x + w - r - s, y + h]
    when 5 then return [x + r - r * Math.sin(a), y + h - r + r * Math.cos(a)]
    when 6 then return [x, y + h - r - s]
    else        return [x + r - r * Math.cos(a), y + r - r * Math.sin(a)]
    end
  end
  # dashed rounded rectangle outline, line width t
  def self.dashed_rect(b, x, y, w, h, r, c, t = 2, dash = 6, gap = 4)
    w -= t
    h -= t
    total = 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Math::PI * r
    s = 0.0
    while s < total
      if s % (dash + gap) < dash
        pt = path_point(x, y, w, h, r, s)
        b.fill_rect(pt[0].round, pt[1].round, t, t, c)
      end
      s += 0.5
    end
  end
  # dashed circle outline
  def self.dashed_circle(b, cx, cy, r, c, t = 2, dash = 5, gap = 4)
    total = 2 * Math::PI * r
    s = 0.0
    while s < total
      if s % (dash + gap) < dash
        a = s / r
        b.fill_rect((cx + r * Math.cos(a) - t / 2.0).round, (cy + r * Math.sin(a) - t / 2.0).round, t, t, c)
      end
      s += 0.5
    end
  end
  # filled ellipse; soft = alpha fades towards the edge
  def self.ellipse(b, cx, cy, rx, ry, c, soft = false)
    p = painter(b)
    for y in (cy - ry - 1).floor..(cy + ry + 1).ceil
      for x in (cx - rx - 1).floor..(cx + rx + 1).ceil
        d = Math.sqrt(((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2)
        next if d >= 1.0 + 1.0 / ry
        a = soft ? (1 - d) * 1.4 : (1 - d) * ry + 0.5
        a = [[a, 0].max, 1].min
        p.blend(x, y, c, a)
      end
    end
  end
  # paw: pad and four toes
  def self.paw(b, cx, cy, c)
    ellipse(b, cx, cy + 3, 5.5, 4.5, c)
    ellipse(b, cx - 6, cy - 3, 2.2, 2.6, c)
    ellipse(b, cx - 2.2, cy - 6.5, 2.2, 2.6, c)
    ellipse(b, cx + 2.2, cy - 6.5, 2.2, 2.6, c)
    ellipse(b, cx + 6, cy - 3, 2.2, 2.6, c)
  end
  # small padlock, top-left at x, y (11 x 13)
  def self.lock(b, x, y, c)
    p = painter(b)
    for yy in 0..7
      for xx in 0..10
        d = Math.sqrt((xx + 0.5 - 5.5) ** 2 + (yy + 0.5 - 6.0) ** 2)
        a = [[1.0 - (d - 4.0).abs, 0].max, 1].min
        p.blend(x + xx, y + yy, c, a) if yy < 6
      end
    end
    b.fill_rect(x + 1, y + 6, 1, 1, c)
    b.fill_rect(x + 9, y + 6, 1, 1, c)
    rounded_fill(b, x, y + 6, 11, 7, 1, c)
  end
  # small down chevron, top-left at x, y (9 x 5)
  def self.chevron(b, x, y, c)
    for i in 0..4
      b.fill_rect(x + i, y + i, 2, 1, c)
      b.fill_rect(x + 8 - i, y + i, 2, 1, c)
    end
  end
  # right-pointing triangle, top-left at x, y (6 x 9)
  def self.triangle(b, x, y, c)
    for i in 0..4
      b.fill_rect(x + i, y + i, 1, 9 - 2 * i, c)
    end
  end
  # small caps with a big first letter in every word, left at x
  def self.caps_words(p, x, base, str, big, small, color)
    p.font(small)
    space = p.width_of(" ")
    for word in str.split(" ")
      x += p.small_caps(x, base, word, big, small, false, color) + space
    end
  end
  # 1 -> "I", 4 -> "IV" ...
  def self.roman(n)
    s = ""
    [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"],
     [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]].each do |v|
      while n >= v[0]
        s += v[1]
        n -= v[0]
      end
    end
    return s
  end
  # play time hh:mm:ss
  def self.play_time
    t = Graphics.frame_count / Graphics.frame_rate
    return sprintf("%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
  end
end

#==============================================================================
# ** Game_Party - groups and a bigger party
#==============================================================================
class Game_Party
  #--------------------------------------------------------------------------
  # * Add Actor (limit BookMenu::MAX_PARTY instead of 4)
  #--------------------------------------------------------------------------
  def add_actor(actor_id)
    actor = $game_actors[actor_id]
    if @actors.size < BookMenu::MAX_PARTY and not @actors.include?(actor)
      @actors.push(actor)
      $game_player.refresh
    end
  end
  #--------------------------------------------------------------------------
  # * Groups: [[actor_id, ...] (up to GROUP_SIZE), ...], matched to the party
  #--------------------------------------------------------------------------
  def menu_groups
    @menu_groups = [] if @menu_groups == nil
    ids = @actors.collect { |a| a.id }
    # drop actors that left the party, close the gaps
    @menu_groups.each { |g| g.delete_if { |id| !ids.include?(id) } }
    # newcomers take the first free character spot
    for id in ids
      next if @menu_groups.find { |g| g.include?(id) } != nil
      g = @menu_groups.find { |x| x.size < BookMenu::GROUP_SIZE }
      if g == nil
        g = []
        @menu_groups.push(g)
      end
      g.push(id)
    end
    @menu_groups.pop while !@menu_groups.empty? and @menu_groups[-1].empty?
    return @menu_groups
  end
  #--------------------------------------------------------------------------
  # * Begleiter of a group (none yet)
  #--------------------------------------------------------------------------
  def menu_companion(group_index)
    return nil
  end
end

#==============================================================================
# ** Window_Target - scrolls when the party has more than 4 members
#==============================================================================
class Window_Target < Window_Selectable
  alias bookmenu_refresh refresh
  def refresh
    h = [height - 32, $game_party.actors.size * 116 - 20].max
    if self.contents.height != h
      self.contents.dispose
      self.contents = Bitmap.new(width - 32, h)
    end
    bookmenu_refresh
  end
  alias bookmenu_update_cursor_rect update_cursor_rect
  def update_cursor_rect
    bookmenu_update_cursor_rect
    if @index >= 0
      top = @index * 116
      self.oy = top if top < self.oy
      self.oy = top + 96 - (height - 32) if top + 96 > self.oy + height - 32
    elsif @index == -1
      self.oy = 0
    end
  end
end

#==============================================================================
# ** Scene_Status - B returns to the menu on the same character
#==============================================================================
class Scene_Status
  alias bookmenu_update update
  def update
    bookmenu_update
    if $scene.is_a?(Scene_Menu) and $scene.respond_to?(:focus_actor) and @actor != nil
      $scene.focus_actor(@actor.id)
    end
  end
end

#==============================================================================
# ** Scene_Menu - the book
#==============================================================================
class Scene_Menu
  include BookMenu
  attr_reader :sprites, :focus, :row, :col, :top, :rows, :placeholder
  attr_reader :index
  #--------------------------------------------------------------------------
  # * menu_index: index of the default menu (0 Item ... 5 End), as the
  #   other screens use it
  #--------------------------------------------------------------------------
  def initialize(menu_index = 0)
    @index = OLD_INDEX[menu_index] || 0
    @focus_actor_id = nil
  end
  #--------------------------------------------------------------------------
  def focus_actor(actor_id)
    @focus_actor_id = actor_id
  end
  #--------------------------------------------------------------------------
  def main
    create
    Graphics.transition
    loop do
      Graphics.update
      Input.update
      update
      break if $scene != self
    end
    Graphics.freeze
    dispose
  end
  #--------------------------------------------------------------------------
  def create
    @sprites = []
    @bitmaps = []
    @row_sprites = []
    @focus = :left
    @row = 0
    @col = 0
    @want_col = 0
    @top = 0
    @frame = 0
    @placeholder = nil
    build_rows
    @book = new_sprite(draw_book, 0, 0, 0)
    @menu_layer = new_sprite(new_bitmap(640, 480), 0, 0, 1)
    @info_layer = new_sprite(new_bitmap(640, 480), 0, 0, 1)
    @list_layer = new_sprite(new_bitmap(640, 480), 0, 0, 2)
    @cursor = new_sprite(nil, 0, 0, 5)
    @cursor.visible = false
    @shown_time = nil
    @shown_gold = nil
    if @focus_actor_id != nil and find_actor(@focus_actor_id)
      @focus = :groups
    end
    scroll_to_row
    draw_menu
    draw_info
    draw_list
    update_cursor
  end
  #--------------------------------------------------------------------------
  def dispose
    close_placeholder
    @cursor.bitmap.dispose if @cursor.bitmap != nil
    for s in @sprites + @row_sprites
      s.dispose
    end
    for b in @bitmaps
      b.dispose
    end
  end
  #--------------------------------------------------------------------------
  def new_bitmap(w, h)
    b = Bitmap.new(w, h)
    @bitmaps.push(b)
    return b
  end
  #--------------------------------------------------------------------------
  def new_sprite(bitmap, x, y, z)
    s = Sprite.new
    s.bitmap = bitmap
    s.x = x
    s.y = y
    s.z = Z + z
    @sprites.push(s)
    return s
  end

  #--------------------------------------------------------------------------
  # * Rows: one per group, then empty groups
  #   { "type" => :group / :empty, "n" => number, "ids" => [...],
  #     "active" => empty row can be chosen }
  #--------------------------------------------------------------------------
  def build_rows
    @rows = []
    groups = $game_party.menu_groups
    groups.each_with_index do |g, i|
      @rows.push({ "type" => :group, "n" => i + 1, "ids" => g.dup })
    end
    prev_full = (groups.empty? or groups[-1].size >= GROUP_SIZE)
    loop do
      @rows.push({ "type" => :empty, "n" => @rows.size + 1, "active" => prev_full })
      prev_full = false
      break if @rows.size >= MIN_ROWS
    end
  end
  #--------------------------------------------------------------------------
  def row_h(i)
    return @rows[i]["type"] == :group ? GROUP_H : EMPTY_H
  end
  #--------------------------------------------------------------------------
  # * Last row that fits completely when the list starts at @top
  #--------------------------------------------------------------------------
  def last_visible
    y = LIST_TOP
    i = @top
    while i < @rows.size and y + row_h(i) <= LIST_BOT
      y += row_h(i)
      i += 1
    end
    return [i - 1, @top].max
  end
  #--------------------------------------------------------------------------
  def row_y(i)
    y = LIST_TOP
    for k in @top...i
      y += row_h(k)
    end
    return y
  end
  #--------------------------------------------------------------------------
  def scroll_to_row
    @top = @row if @row < @top
    @top += 1 while @row > last_visible and @top < @row
  end
  #--------------------------------------------------------------------------
  def find_actor(actor_id)
    @rows.each_with_index do |r, i|
      next if r["type"] != :group
      k = r["ids"].index(actor_id)
      if k != nil
        @row = i
        @col = k
        @want_col = k
        return true
      end
    end
    return false
  end

  #--------------------------------------------------------------------------
  # * Static book: leather, stitching, pages, spine, ribbon, headings
  #--------------------------------------------------------------------------
  def draw_book
    b = new_bitmap(640, 480)
    b.fill_rect(b.rect, LEATHER)
    BookMenu.dashed_rect(b, 8, 8, 624, 464, 12, STITCH, 2, 7, 5)
    BookMenu.rounded_fill(b, 20, 20, 182, 440, 5, PARCH)
    BookMenu.rounded_fill(b, 200, 20, 420, 440, 5, PARCH)
    # soft shade on both pages next to the spine
    p = BookMenu.painter(b)
    for i in 0...10
      a = 0.22 * (10 - i) / 10.0
      for y in 20...460
        p.blend(198 - i, y, SHADE, a)
        p.blend(203 + i, y, SHADE, a)
      end
    end
    b.fill_rect(199, 20, 4, 440, SPINE)
    # ribbon bookmark
    b.fill_rect(570, 8, 18, 56, RED)
    b.fill_rect(570, 8, 2, 56, Color.new(150, 50, 45))
    for i in 0...9                                    # V notch at the bottom
      b.fill_rect(579 - i, 55 + i, 2 * i, 1, PARCH)
    end
    p = BookMenu.painter(b)
    p.small_caps(LEFT_X, 52, "Menü", 20, 15, false, RED)
    b.fill_rect(LEFT_X, 60, LEFT_W, 1, LINE)
    p.small_caps(LIST_X, 52, "Gruppen", 20, 15, false, RED)
    b.fill_rect(LIST_X, 60, LIST_R - LIST_X - 20, 1, LINE)
    # Spielzeit and money boxes
    BookMenu.box(b, LEFT_X, 340, LEFT_W, 58, 4, BOX_BG, LINE)
    p.small_caps(LEFT_X + 10, 360, "Spielzeit", 15, 12, false, RED)
    BookMenu.box(b, LEFT_X, 406, LEFT_W, 38, 4, BOX_BG, LINE)
    return b
  end
  #--------------------------------------------------------------------------
  # * Menu entries
  #--------------------------------------------------------------------------
  def draw_menu
    b = @menu_layer.bitmap
    b.clear
    p = BookMenu.painter(b)
    for i in 0...ENTRIES.size
      y = ENTRY_Y + i * ENTRY_H
      if i == @index
        BookMenu.box(b, LEFT_X, y, LEFT_W, ENTRY_H - 4, 3, SEL_BG, LINE)
        BookMenu.triangle(b, LEFT_X + 8, y + 10, RED) if @focus == :left
      end
      BookMenu.caps_words(p, LEFT_X + 24, y + 21, ENTRIES[i], 18, 14, INK)
    end
  end
  #--------------------------------------------------------------------------
  # * Play time and money (redrawn when they change)
  #--------------------------------------------------------------------------
  def draw_info
    time = BookMenu.play_time
    gold = $game_party.gold
    return if time == @shown_time and gold == @shown_gold
    @shown_time = time
    @shown_gold = gold
    b = @info_layer.bitmap
    b.clear
    p = BookMenu.painter(b)
    p.font(18, true, false, INK, true)
    p.text(LEFT_X + LEFT_W - 10, 388, time, 2)
    p.font(18, true, false, GOLD)
    w = p.text(LEFT_X + LEFT_W - 10, 431, "G", 2)
    p.font(18, true, false, INK, true)
    p.text(LEFT_X + LEFT_W - 10 - w - 6, 431, gold.to_s, 2)
  end
  #--------------------------------------------------------------------------
  # * Group list (visible rows) and the walk sprites
  #--------------------------------------------------------------------------
  def draw_list
    b = @list_layer.bitmap
    b.clear
    for s in @row_sprites
      s.dispose
    end
    @row_sprites = []
    last = last_visible
    for i in @top..last
      y = row_y(i)
      r = @rows[i]
      if r["type"] == :group
        draw_group_row(b, r, y)
      else
        draw_empty_row(b, r, y)
      end
      b.fill_rect(LIST_X, y + row_h(i) - 1, LIST_R - LIST_X, 1, LINE2)
    end
    if last < @rows.size - 1
      p = BookMenu.painter(b)
      p.font(13, false, true, INK2)
      w = p.width_of("weitere Gruppen")
      x = (LIST_X + LIST_R) / 2 - (w + 14) / 2
      BookMenu.chevron(b, x, 437, INK)
      p.text(x + 14, 445, "weitere Gruppen")
    end
  end
  #--------------------------------------------------------------------------
  def draw_seal(b, n, cy, color)
    BookMenu.ellipse(b, SEAL_X, cy, 18, 18, color)
    p = BookMenu.painter(b)
    for yy in (cy - 17)..(cy + 17)
      for xx in (SEAL_X - 17)..(SEAL_X + 17)
        d = Math.sqrt((xx + 0.5 - SEAL_X) ** 2 + (yy + 0.5 - cy) ** 2)
        a = 1.0 - (d - 15.0).abs
        p.blend(xx, yy, PARCH, a * 0.9) if a > 0
      end
    end
    p.font(n > 3 ? 13 : 15, true, false, PARCH)
    p.fit(BookMenu.roman(n), 24, 9)
    p.text(SEAL_X, cy + 5, BookMenu.roman(n), 1)
  end
  #--------------------------------------------------------------------------
  def draw_group_row(b, r, y)
    draw_seal(b, r["n"], y + 50, RED)
    p = BookMenu.painter(b)
    for k in 0...GROUP_SIZE
      cx = SLOT_X[k]
      id = r["ids"][k]
      if id == nil
        BookMenu.dashed_rect(b, cx - 22, y + 30, 44, 44, 6, LINE, 2, 5, 4)
        p.font(22, false, false, INK2)
        p.text(cx, y + 59, "+", 1)
        p.font(12, false, true, INK2)
        p.text(cx, y + NAME_Y, "Freier Platz", 1)
        next
      end
      actor = $game_actors[id]
      leader = (k == 0)
      if leader
        BookMenu.ellipse(b, cx, y + FOOT_Y, 24, 6, BASE_RIM)
        BookMenu.ellipse(b, cx, y + FOOT_Y - 1, 22, 4.5, BASE)
      else
        BookMenu.ellipse(b, cx, y + FOOT_Y, 17, 4.5, SHADE, true)
      end
      add_walker(actor, cx, y + FOOT_Y + (leader ? 1 : 2), leader ? 1.5 : 1.25)
      p.font(13, true, false, leader ? RED : INK)
      name = p.fit_text(actor.name, 80, 10)
      p.text(cx, y + NAME_Y, name, 1)
      if leader
        p.font(11, false, true, RED)
        p.text(cx, y + NAME_Y + 12, "Anführer", 1)
      end
    end
    # Begleiter slot
    cx = SLOT_X[3]
    BookMenu.dashed_circle(b, cx, y + 50, 21, LINE, 2, 5, 4)
    BookMenu.paw(b, cx, y + 51, Color.new(LINE2.red, LINE2.green, LINE2.blue, 200))
    p.font(12, false, true, INK2)
    p.text(cx, y + NAME_Y, "Begleiter", 1)
  end
  #--------------------------------------------------------------------------
  def draw_empty_row(b, r, y)
    t = Bitmap.new(LIST_R - LIST_X, EMPTY_H)
    ox = LIST_X
    # draw at list coordinates shifted by -ox
    BookMenu.ellipse(t, SEAL_X - ox, 32, 18, 18, SEAL_GRAY)
    p = BookMenu.painter(t)
    for yy in 15..49
      for xx in (SEAL_X - ox - 17)..(SEAL_X - ox + 17)
        d = Math.sqrt((xx + 0.5 - (SEAL_X - ox)) ** 2 + (yy + 0.5 - 32) ** 2)
        a = 1.0 - (d - 15.0).abs
        p.blend(xx, yy, PARCH, a * 0.9) if a > 0
      end
    end
    p.font(r["n"] > 3 ? 13 : 15, true, false, PARCH)
    p.fit(BookMenu.roman(r["n"]), 24, 9)
    p.text(SEAL_X - ox, 37, BookMenu.roman(r["n"]), 1)
    bx = 268 - ox
    BookMenu.dashed_rect(t, bx, 10, LIST_R - 268, 44, 8, LINE, 2, 6, 4)
    p.font(15, false, true, INK2)
    w = p.width_of("Leere Gruppe")
    cx = bx + (LIST_R - 268) / 2
    tx = cx - (w + 20) / 2
    if r["active"]
      p.font(18, false, false, INK2)
      p.text(tx, 38, "+")
    else
      BookMenu.lock(t, tx, 25, INK2)
    end
    p.font(15, false, true, INK2)
    p.text(tx + 20, 37, "Leere Gruppe")
    b.blt(ox, y, t, t.rect, r["active"] ? 255 : 120)
    t.dispose
  end
  #--------------------------------------------------------------------------
  # * Walk sprite (standing, facing down), feet at x, y
  #--------------------------------------------------------------------------
  def add_walker(actor, x, y, zoom)
    name = actor.character_name
    return if name == nil or name == ""
    src = RPG::Cache.character(name, actor.character_hue)
    cw = src.width / 4
    ch = src.height / 4
    zoom = [zoom, (FOOT_Y - 4).to_f / ch, 78.0 / cw].min   # stay inside the row and slot
    s = Sprite.new
    s.bitmap = src
    s.src_rect.set(0, 0, cw, ch)
    s.ox = cw / 2
    s.oy = ch
    s.x = x
    s.y = y
    s.zoom_x = zoom
    s.zoom_y = zoom
    s.z = Z + 3
    @row_sprites.push(s)
  end

  #--------------------------------------------------------------------------
  # * Cursor frame around the hovered slot (groups focus)
  #--------------------------------------------------------------------------
  def cursor_rect
    y = row_y(@row)
    if @rows[@row]["type"] == :empty
      return [264, y + 6, LIST_R - 264 + 4, 52]
    end
    cx = SLOT_X[@col]
    return [cx - 40, y + 4, 80, GROUP_H - 8]
  end
  #--------------------------------------------------------------------------
  def update_cursor
    if @focus != :groups
      @cursor.visible = false
      return
    end
    r = cursor_rect
    key = r.join(",")
    if key != @cursor_key
      @cursor_key = key
      @cursor.bitmap.dispose if @cursor.bitmap != nil
      b = Bitmap.new(r[2], r[3])
      BookMenu.rounded_fill(b, 0, 0, r[2], r[3], 7, RED)
      BookMenu.rounded_fill(b, 2, 2, r[2] - 4, r[3] - 4, 5, Color.new(184, 145, 63))
      BookMenu.rounded_fill(b, 3, 3, r[2] - 6, r[3] - 6, 4, Color.new(0, 0, 0, 0))
      b.fill_rect(5, 3, r[2] - 10, r[3] - 6, Color.new(0, 0, 0, 0))
      b.fill_rect(3, 5, r[2] - 6, r[3] - 10, Color.new(0, 0, 0, 0))
      @cursor.bitmap = b
      @cursor.x = r[0]
      @cursor.y = r[1]
    end
    @cursor.visible = true
  end

  #--------------------------------------------------------------------------
  # * Placeholder window (Einheiten, Begleiter, Options)
  #--------------------------------------------------------------------------
  def open_placeholder
    @placeholder = Window_Base.new(120, 120, 400, 240)
    @placeholder.z = Z + 50
  end
  #--------------------------------------------------------------------------
  def close_placeholder
    return if @placeholder == nil
    @placeholder.dispose
    @placeholder = nil
  end

  #--------------------------------------------------------------------------
  # * Frame update
  #--------------------------------------------------------------------------
  def update
    @frame += 1
    draw_info
    if @cursor.visible
      k = (1 - Math.cos(2 * Math::PI * @frame / 60.0)) / 2
      @cursor.opacity = (190 + 65 * k).to_i
    end
    if @placeholder != nil
      @placeholder.update
      if Input.trigger?(Input::B)
        $game_system.se_play($data_system.cancel_se)
        close_placeholder
      end
      return
    end
    if @focus == :left
      update_left
    else
      update_groups
    end
  end
  #--------------------------------------------------------------------------
  def set_focus(f)
    @focus = f
    draw_menu
    update_cursor
  end
  #--------------------------------------------------------------------------
  def first_character?
    return (@rows[0] != nil and @rows[0]["type"] == :group)
  end
  #--------------------------------------------------------------------------
  def enter_groups
    @row = 0
    @col = 0
    @want_col = 0
    scroll_to_row
    draw_list
    set_focus(:groups)
  end
  #--------------------------------------------------------------------------
  def update_left
    if Input.repeat?(Input::DOWN) or Input.repeat?(Input::UP)
      $game_system.se_play($data_system.cursor_se)
      d = Input.repeat?(Input::DOWN) ? 1 : ENTRIES.size - 1
      @index = (@index + d) % ENTRIES.size
      draw_menu
      return
    end
    if Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      $scene = Scene_Map.new
      return
    end
    if Input.trigger?(Input::RIGHT)
      if first_character?
        $game_system.se_play($data_system.cursor_se)
        enter_groups
      else
        $game_system.se_play($data_system.buzzer_se)
      end
      return
    end
    if Input.trigger?(Input::C)
      case @index
      when 0   # Inventar
        if $game_party.actors.size == 0
          $game_system.se_play($data_system.buzzer_se)
          return
        end
        $game_system.se_play($data_system.decision_se)
        $scene = Scene_Item.new
      when 1, 2, 4   # Einheiten, Begleiter, Options
        $game_system.se_play($data_system.decision_se)
        open_placeholder
      when 3   # Status
        if !first_character?
          $game_system.se_play($data_system.buzzer_se)
          return
        end
        $game_system.se_play($data_system.decision_se)
        enter_groups
      when 5   # Speichern
        if $game_system.save_disabled
          $game_system.se_play($data_system.buzzer_se)
          return
        end
        $game_system.se_play($data_system.decision_se)
        $scene = Scene_Save.new
      when 6   # Spiel Verlassen
        $game_system.se_play($data_system.decision_se)
        $scene = Scene_End.new
      end
    end
  end
  #--------------------------------------------------------------------------
  def move_to(row, col)
    @row = row
    @col = @rows[row]["type"] == :empty ? 0 : col
    old_top = @top
    scroll_to_row
    draw_list if @top != old_top
    update_cursor
  end
  #--------------------------------------------------------------------------
  def update_groups
    if Input.trigger?(Input::B)
      $game_system.se_play($data_system.cancel_se)
      set_focus(:left)
      return
    end
    if Input.repeat?(Input::LEFT)
      if @col == 0
        $game_system.se_play($data_system.cursor_se)
        set_focus(:left)
      else
        $game_system.se_play($data_system.cursor_se)
        @want_col = @col - 1
        move_to(@row, @col - 1)
      end
      return
    end
    if Input.repeat?(Input::RIGHT)
      if @rows[@row]["type"] == :group and @col < 3
        $game_system.se_play($data_system.cursor_se)
        @want_col = @col + 1
        move_to(@row, @col + 1)
      end
      return
    end
    if Input.repeat?(Input::DOWN)
      if @row < @rows.size - 1
        $game_system.se_play($data_system.cursor_se)
        move_to(@row + 1, @want_col)
      end
      return
    end
    if Input.repeat?(Input::UP)
      if @row > 0
        $game_system.se_play($data_system.cursor_se)
        move_to(@row - 1, @want_col)
      end
      return
    end
    if Input.trigger?(Input::C)
      r = @rows[@row]
      if r["type"] == :empty
        if r["active"]
          $game_system.se_play($data_system.decision_se)
          open_placeholder
        else
          $game_system.se_play($data_system.buzzer_se)
        end
      elsif @col == 3
        $game_system.se_play($data_system.decision_se)
        open_placeholder
      elsif r["ids"][@col] == nil
        $game_system.se_play($data_system.buzzer_se)
      else
        $game_system.se_play($data_system.decision_se)
        actor = $game_actors[r["ids"][@col]]
        $scene = Scene_Status.new($game_party.actors.index(actor))
      end
    end
  end
end
