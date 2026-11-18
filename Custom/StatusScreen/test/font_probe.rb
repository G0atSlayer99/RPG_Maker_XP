# Test script for a COPY of the project: prints how RGSS measures fonts.
log = []
begin
  b = Bitmap.new(640, 480)
  for name in ["Georgia", "Palatino Linotype", "Cambria", "Times New Roman", "Alegreya", "Book Antiqua"]
    ex = Font.respond_to?(:exist?) ? Font.exist?(name) : "?"
    for size in [15, 18]
      for bold in [false, true]
        b.font.name = name
        b.font.size = size
        b.font.bold = bold
        b.font.italic = false
        r = b.text_size("30 / 30 KP Str")
        log << sprintf("%-18s exist=%-5s size=%2d bold=%-5s  w=%3d h=%2d", name, ex.to_s, size, bold.to_s, r.width, r.height)
      end
    end
  end
  log << "default font: " + Font.default_name.inspect + " " + Font.default_size.inspect if Font.respond_to?(:default_name)
rescue Exception => e
  log << "ERROR " + e.class.to_s + ": " + e.message + "\n" + e.backtrace.join("\n")
end
File.open("render_log.txt", "w") { |f| f.write(log.join("\n")) }
exit
