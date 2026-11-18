// Generates the static artwork of the book-style Status screen:
//   StatusBook.png       640x480 RGBA  cover, pages, spine, ribbon, rings, badge, boxes, bar frames, dividers
//   StatusBookIcons.png  90x18   RGBA  equipment icons: weapon, shield, helmet, body armor, accessory
// Everything is drawn 4x larger and scaled down for smooth edges.
// Build + run: make_statusbook.bat <output folder>
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

static class MakeStatusBook
{
    const int SS = 4;   // supersampling

    static Color C(string hex)
    {
        int v = Convert.ToInt32(hex.TrimStart('#'), 16);
        return Color.FromArgb(255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    }

    static readonly Color Cover = C("4A2E1B"), Stitch = C("A57B4A"), Page = C("F1E4C3"), PageShade = C("C9BB9D"),
        Spine = C("3A2412"), Ribbon = C("7A1F1F"), RibbonDark = C("651818"), Gold = C("C9A86A"), Brown = C("7B5B2F"),
        PortraitFill = C("DBC699"), Line = C("B89863"), Ink = C("2E1F10"), BarBg = C("E2D1A8"), Box = C("E8D8B2"),
        Ochre = C("A07A2A"), PillFill = C("EFE0BA"), Underline = C("7A5A2E");

    static GraphicsPath Round(float x0, float y0, float x1, float y1, float r)
    {
        var p = new GraphicsPath();
        float d = r * 2;
        p.AddArc(x0, y0, d, d, 180, 90);
        p.AddArc(x1 - d, y0, d, d, 270, 90);
        p.AddArc(x1 - d, y1 - d, d, d, 0, 90);
        p.AddArc(x0, y1 - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    static void Circle(Graphics g, Pen pen, Brush fill, float cx, float cy, float r)
    {
        if (fill != null) g.FillEllipse(fill, cx - r, cy - r, 2 * r, 2 * r);
        if (pen != null) g.DrawEllipse(pen, cx - r, cy - r, 2 * r, 2 * r);
    }

    static Bitmap Canvas(int w, int h, out Graphics g)
    {
        var bmp = new Bitmap(w * SS, h * SS, PixelFormat.Format32bppArgb);
        g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.ScaleTransform(SS, SS);
        g.Clear(Color.Transparent);
        return bmp;
    }

    static void SaveScaled(Bitmap big, int w, int h, string path)
    {
        using (var small = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(small))
        {
            g.Clear(Color.Transparent);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.CompositingMode = CompositingMode.SourceCopy;
            using (var ia = new ImageAttributes())
            {
                ia.SetWrapMode(WrapMode.TileFlipXY);
                g.DrawImage(big, new Rectangle(0, 0, w, h), 0, 0, big.Width, big.Height, GraphicsUnit.Pixel, ia);
            }
            small.Save(path, ImageFormat.Png);
        }
    }

    static void Book(string path)
    {
        Graphics g;
        var bmp = Canvas(640, 480, out g);
        using (g)
        {
            // Cover with stitching
            using (var b = new SolidBrush(Cover)) g.FillRectangle(b, 0, 0, 640, 480);
            using (var pen = new Pen(Stitch, 1.6f) { DashPattern = new float[] { 3.5f, 2.5f } })
                g.DrawRectangle(pen, 11, 11, 618, 458);

            // Pages: rounded outer corners, shading toward the spine
            using (var path2 = Round(20, 20, 620, 460, 6))
            using (var b = new SolidBrush(Page)) g.FillPath(b, path2);
            using (var lg = new LinearGradientBrush(new RectangleF(296, 20, 22, 440), Color.FromArgb(0, PageShade), PageShade, 0f))
                g.FillRectangle(lg, 296, 20, 22, 440);
            using (var lg = new LinearGradientBrush(new RectangleF(322, 20, 14, 440), PageShade, Color.FromArgb(0, PageShade), 0f))
                g.FillRectangle(lg, 322, 20, 14, 440);
            using (var lg = new LinearGradientBrush(new RectangleF(20, 20, 5, 440), Color.FromArgb(90, PageShade), Color.FromArgb(0, PageShade), 0f))
                g.FillRectangle(lg, 20, 20, 5, 440);
            using (var lg = new LinearGradientBrush(new RectangleF(614, 20, 6, 440), Color.FromArgb(0, PageShade), Color.FromArgb(110, PageShade), 0f))
                g.FillRectangle(lg, 614, 20, 6, 440);
            using (var b = new SolidBrush(Spine)) g.FillRectangle(b, 318, 20, 4, 440);

            // Ribbon bookmark with a notch
            var rib = new[] { new PointF(570, 8), new PointF(588, 8), new PointF(588, 63), new PointF(579, 55), new PointF(570, 63) };
            using (var b = new SolidBrush(Ribbon)) g.FillPolygon(b, rib);
            using (var b = new SolidBrush(RibbonDark)) g.FillPolygon(b, new[] { new PointF(579, 8), new PointF(588, 8), new PointF(588, 63), new PointF(579, 55) });
            using (var b = new SolidBrush(Color.FromArgb(90, 0, 0, 0))) g.FillRectangle(b, 570, 8, 18, 12);

            // Portrait rings (the face is drawn inside at runtime)
            using (var pen = new Pen(Gold, 1.1f)) Circle(g, pen, null, 92, 90, 57);
            using (var b = new SolidBrush(PortraitFill)) Circle(g, null, b, 92, 90, 53.5f);
            using (var pen = new Pen(Brown, 3.2f)) Circle(g, pen, null, 92, 90, 53.5f);

            // Line under the map sprite
            using (var pen = new Pen(Underline, 2f)) g.DrawLine(pen, 158, 142.5f, 214, 142.5f);

            // Level badge
            using (var pen = new Pen(Ribbon, 1.3f)) Circle(g, pen, null, 273, 94, 29);
            using (var b = new SolidBrush(Ribbon)) Circle(g, null, b, 273, 94, 26);

            // Status box (the state pill is drawn at runtime)
            using (var p = Round(38.5f, 214.5f, 297.5f, 247.5f, 4))
            {
                using (var b = new SolidBrush(Box)) g.FillPath(b, p);
                using (var pen = new Pen(Gold, 1f)) g.DrawPath(pen, p);
            }
            using (var pen = new Pen(Line, 1f)) g.DrawLine(pen, 100.5f, 220, 100.5f, 242);

            // Dividers
            using (var pen = new Pen(Line, 1f))
            {
                g.DrawLine(pen, 38, 258.5f, 298, 258.5f);
                g.DrawLine(pen, 341, 59.5f, 602, 59.5f);
                g.DrawLine(pen, 341, 305.5f, 602, 305.5f);
            }

            // KP / SP / EXP bar frames
            using (var b = new SolidBrush(BarBg))
            using (var pen = new Pen(Ink, 1.2f))
            {
                foreach (var r in new[] { new RectangleF(38.5f, 294.5f, 259, 11), new RectangleF(38.5f, 341.5f, 259, 11), new RectangleF(38.5f, 388.5f, 259, 7) })
                {
                    g.FillRectangle(b, r);
                    g.DrawRectangle(pen, r.X, r.Y, r.Width, r.Height);
                }
                // Attribute bar frames (Str .. Move)
                for (int i = 0; i < 7; i++)
                {
                    float y = 70.5f + i * 25;
                    using (var p = Round(477.5f, y, 601.5f, y + 16, 2))
                    {
                        g.FillPath(b, p);
                        g.DrawPath(pen, p);
                    }
                }
            }

            // Crit rate ring (the red share is drawn at runtime)
            using (var pen = new Pen(Ink, 1.2f))
            {
                Circle(g, pen, null, 365, 273, 24);
                Circle(g, pen, null, 365, 273, 19);
            }

            // Crit damage box with the multiplier pill
            using (var p = Round(474.5f, 252.5f, 601.5f, 291.5f, 4))
            {
                using (var b = new SolidBrush(Box)) g.FillPath(b, p);
                using (var pen = new Pen(Gold, 1f)) g.DrawPath(pen, p);
            }
            using (var pen = new Pen(Line, 1f)) g.DrawLine(pen, 546.5f, 258, 546.5f, 286);
            using (var p = Round(555.5f, 260.5f, 592.5f, 283.5f, 11.5f))
            {
                using (var b = new SolidBrush(PillFill)) g.FillPath(b, p);
                using (var pen = new Pen(Ochre, 1.2f)) g.DrawPath(pen, p);
            }
        }
        SaveScaled(bmp, 640, 480, path);
        bmp.Dispose();
    }

    static void Icons(string path)
    {
        Graphics g;
        var bmp = Canvas(90, 18, out g);
        using (g)
        using (var pen = new Pen(C("3A2A18"), 1.05f) { LineJoin = LineJoin.Round, StartCap = LineCap.Round, EndCap = LineCap.Round })
        {
            // 0 weapon: thin sword, blade from top-left to bottom-right, cross guard
            g.DrawPolygon(pen, new[] { new PointF(2.5f, 4), new PointF(4, 2.5f), new PointF(11, 9.5f), new PointF(9.5f, 11) });
            g.DrawLine(pen, 8.5f, 13.5f, 13.5f, 8.5f);
            g.DrawLine(pen, 11.5f, 11.5f, 15, 15);
            // 1 shield
            g.TranslateTransform(18, 0);
            using (var p = new GraphicsPath())
            {
                p.AddLine(3, 3.5f, 9, 2);
                p.AddLine(9, 2, 15, 3.5f);
                p.AddBezier(15, 3.5f, 15, 10, 12.8f, 13.8f, 9, 16);
                p.AddBezier(9, 16, 5.2f, 13.8f, 3, 10, 3, 3.5f);
                p.CloseFigure();
                g.DrawPath(pen, p);
            }
            // 2 helmet: dome with a rim
            g.TranslateTransform(18, 0);
            using (var p = new GraphicsPath())
            {
                p.AddLine(3, 15, 3, 9.5f);
                p.AddArc(3, 3.5f, 12, 12, 180, 180);
                p.AddLine(15, 9.5f, 15, 15);
                p.CloseFigure();
                g.DrawPath(pen, p);
            }
            g.DrawLine(pen, 3, 12.5f, 15, 12.5f);
            // 3 body armor: shirt
            g.TranslateTransform(18, 0);
            g.DrawPolygon(pen, new[] {
                new PointF(6.5f, 2.5f), new PointF(2.5f, 4.5f), new PointF(3.2f, 8), new PointF(5, 7.5f), new PointF(5, 15.5f),
                new PointF(13, 15.5f), new PointF(13, 7.5f), new PointF(14.8f, 8), new PointF(15.5f, 4.5f), new PointF(11.5f, 2.5f) });
            g.DrawArc(pen, 6.5f, 0, 5, 5, 20, 140);
            // 4 accessory: ring with a gem
            g.TranslateTransform(18, 0);
            g.DrawEllipse(pen, 3.5f, 7, 11, 9);
            g.DrawPolygon(pen, new[] { new PointF(9, 2), new PointF(11.5f, 4.5f), new PointF(9, 7), new PointF(6.5f, 4.5f) });
        }
        SaveScaled(bmp, 90, 18, path);
        bmp.Dispose();
    }

    static int Main(string[] args)
    {
        string dir = args.Length > 0 ? args[0] : ".";
        Book(System.IO.Path.Combine(dir, "StatusBook.png"));
        Icons(System.IO.Path.Combine(dir, "StatusBookIcons.png"));
        Console.WriteLine("written to " + dir);
        return 0;
    }
}
