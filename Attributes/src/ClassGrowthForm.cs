using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Windows.Forms;

namespace XpAttributes
{
    /// <summary>
    /// "Klassen-Wachstum": level-up chances per class. For every stat, p1 = chance of +1 and
    /// p2 = chance of +2 per level-up (one roll: r &lt; p2 → +2, r &lt; p2 + p1 → +1).
    /// Stored in Data/Attributes.rxdata, section "classes": { id => { "hp_p1" => 60.0, "hp_p2" => 30.0, ... } }.
    /// A class without stored values uses the defaults.
    /// </summary>
    public class ClassGrowthForm : Form
    {
        public class GrowthStat
        {
            public string Key, Short, Long;
            public Color Color;
            public int P1, P2;   // defaults
            public GrowthStat(string key, string s, string l, string hex, int p1, int p2)
            {
                Key = key; Short = s; Long = l; P1 = p1; P2 = p2;
                int v = Convert.ToInt32(hex, 16);
                Color = Color.FromArgb((v >> 16) & 255, (v >> 8) & 255, v & 255);
            }
        }

        public static readonly GrowthStat[] Stats =
        {
            new GrowthStat("hp",   "KP",   "Lebenspunkte",     "9C2A55", 60, 30),
            new GrowthStat("sp",   "SP",   "Skillpunkte",      "2B5C9E", 50, 10),
            new GrowthStat("str",  "Str",  "Stärke",           "B0652A", 45, 10),
            new GrowthStat("mg",   "Mg",   "Magie",            "6B3FA0", 20,  0),
            new GrowthStat("spd",  "Spd",  "Geschwindigkeit",  "4E8A2B", 40,  5),
            new GrowthStat("luck", "Luck", "Glück",            "2E8A5C", 30,  5),
            new GrowthStat("def",  "Def",  "Verteidigung",     "2E4A7A", 40, 10),
            new GrowthStat("res",  "Res",  "Resistenz",        "2A8580", 20,  0),
        };

        public const string Section = "classes";
        static readonly Color ErrorRed = Color.FromArgb(0xC4, 0x2B, 0x1C);
        static readonly Color Gray = Color.FromArgb(96, 96, 96);
        static readonly Color LineGray = Color.FromArgb(225, 225, 225);
        static readonly Color BorderGray = Color.FromArgb(204, 204, 204);
        static readonly Color NoGain = Color.FromArgb(230, 230, 230);

        // ------------------------------------------------------------------ small controls

        /// <summary>Number box 0–100 with a border that can turn red.</summary>
        class PercentBox : Panel
        {
            public readonly TextBox Box;
            bool error;
            public PercentBox()
            {
                Size = new Size(50, 24);
                BackColor = Color.White;
                Padding = new Padding(1);
                Box = new TextBox { BorderStyle = BorderStyle.None, TextAlign = HorizontalAlignment.Center, MaxLength = 4, Location = new Point(4, 4), Width = 42 };
                Controls.Add(Box);
                Box.KeyPress += (s, e) => { if (!char.IsDigit(e.KeyChar) && !char.IsControl(e.KeyChar)) e.Handled = true; };
                Click += (s, e) => Box.Focus();
            }
            public bool Error
            {
                get { return error; }
                set { if (error != value) { error = value; Invalidate(); } }
            }
            /// <summary>Whole number 0–100; empty or invalid = 0.</summary>
            public int Value
            {
                get
                {
                    int v;
                    if (!int.TryParse(Box.Text.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out v)) return 0;
                    return Math.Max(0, Math.Min(100, v));
                }
            }
            public void Normalize()
            {
                string t = Value.ToString(CultureInfo.InvariantCulture);
                if (Box.Text != t) Box.Text = t;
            }
            protected override void OnPaint(PaintEventArgs e)
            {
                base.OnPaint(e);
                Color c = error ? ErrorRed : (Box.Focused ? Color.FromArgb(0, 99, 177) : Color.FromArgb(122, 122, 122));
                using (var p = new Pen(c, error ? 2f : 1f))
                {
                    if (error) e.Graphics.DrawRectangle(p, 1, 1, Width - 2, Height - 2);
                    else e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
                }
            }
        }

        /// <summary>Bar split into +2 share, +1 share (45 % opacity) and no gain.</summary>
        class GrowthBar : Control
        {
            public Color StatColor;
            public int P1, P2;
            public GrowthBar() { DoubleBuffered = true; SetStyle(ControlStyles.ResizeRedraw, true); }
            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.Clear(Color.White);
                int w = Width - 1, h = Height - 1;
                using (var b = new SolidBrush(NoGain)) g.FillRectangle(b, 0, 0, w, h);
                int p2 = Math.Max(0, Math.Min(100, P2));
                int p1 = Math.Max(0, Math.Min(100 - p2, P1));
                int x2 = (int)Math.Round(w * p2 / 100.0);
                int x1 = (int)Math.Round(w * (p1 + p2) / 100.0);
                using (var b = new SolidBrush(StatColor)) g.FillRectangle(b, 0, 0, x2, h);
                using (var b = new SolidBrush(Color.FromArgb(115, StatColor))) g.FillRectangle(b, x2, 0, x1 - x2, h);
                using (var p = new Pen(BorderGray)) g.DrawRectangle(p, 0, 0, w, h);
            }
        }

        class ClassItem
        {
            public int Id;
            public string Name;
            public override string ToString() { return Id.ToString("000") + ": " + Name; }
        }

        class Row
        {
            public GrowthStat Stat;
            public PercentBox P1, P2;
            public GrowthBar Bar;
            public Label Avg;
        }

        // ------------------------------------------------------------------ form

        readonly Controller ctl;
        readonly ListBox list;
        readonly Label header;
        readonly List<Row> rows = new List<Row>();
        bool loading;
        int classId = -1;
        public bool Docked;

        public ClassGrowthForm(Controller controller)
        {
            ctl = controller;
            Text = "Klassen-Wachstum";
            Font = new Font("Segoe UI", 9f);
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(720, 540);
            BackColor = Color.FromArgb(240, 240, 240);
            DoubleBuffered = true;

            // Title strip
            var top = new Panel { Location = new Point(0, 0), Size = new Size(720, 37), BackColor = Color.White };
            top.Paint += (s, e) => { using (var p = new Pen(BorderGray)) e.Graphics.DrawLine(p, 0, 36, 720, 36); };
            top.Controls.Add(new Label { Text = "Klassen-Wachstum", Font = new Font("Segoe UI", 10f), Location = new Point(13, 9), AutoSize = true });
            top.Controls.Add(new Label { Text = "Level-Up-Chancen pro Wert", ForeColor = Gray, TextAlign = ContentAlignment.MiddleRight, Location = new Point(420, 9), Size = new Size(287, 20) });
            Controls.Add(top);

            // Class list
            Controls.Add(new Label { Text = "Klasse wählen", Font = new Font("Segoe UI", 9f, FontStyle.Bold), Location = new Point(12, 50), AutoSize = true });
            list = new ListBox
            {
                Location = new Point(13, 70), Size = new Size(160, 457), IntegralHeight = false,
                DrawMode = DrawMode.OwnerDrawFixed, ItemHeight = 22, BorderStyle = BorderStyle.FixedSingle
            };
            list.DrawItem += DrawClassItem;
            list.SelectedIndexChanged += (s, e) => { var c = list.SelectedItem as ClassItem; if (c != null) LoadClass(c.Id); };
            Controls.Add(list);

            // Content panel
            var content = new Panel { Location = new Point(186, 48), Size = new Size(521, 479), BackColor = Color.White };
            content.Paint += (s, e) =>
            {
                using (var p = new Pen(BorderGray)) e.Graphics.DrawRectangle(p, 0, 0, content.Width - 1, content.Height - 1);
                using (var p = new Pen(LineGray))
                {
                    e.Graphics.DrawLine(p, 14, 72, 507, 72);
                    for (int i = 1; i <= Stats.Length; i++) e.Graphics.DrawLine(p, 14, 72 + i * 43, 507, 72 + i * 43);
                }
                DrawLegend(e.Graphics);
            };
            Controls.Add(content);

            header = new Label { Location = new Point(13, 18), Size = new Size(390, 22), Font = new Font("Segoe UI", 10f), UseMnemonic = false };
            header.Paint += PaintHeader;
            content.Controls.Add(header);
            var reset = new Button { Text = "Zurücksetzen", Location = new Point(413, 15), Size = new Size(92, 25), FlatStyle = FlatStyle.System };
            reset.Click += (s, e) => ResetClass();
            content.Controls.Add(reset);

            Label h;
            content.Controls.Add(h = new Label { Text = "Wert", Location = new Point(14, 51), AutoSize = true, ForeColor = Color.FromArgb(64, 64, 64) });
            content.Controls.Add(new Label { Text = "+1 Chance", Location = new Point(133, 51), AutoSize = true, ForeColor = h.ForeColor });
            content.Controls.Add(new Label { Text = "+2 Chance", Location = new Point(217, 51), AutoSize = true, ForeColor = h.ForeColor });
            content.Controls.Add(new Label { Text = "Verteilung", Location = new Point(301, 51), AutoSize = true, ForeColor = h.ForeColor });
            content.Controls.Add(new Label { Text = "Ø / Lv", Location = new Point(430, 51), Size = new Size(77, 18), TextAlign = ContentAlignment.TopRight, ForeColor = h.ForeColor });

            var bold = new Font("Segoe UI", 9.75f, FontStyle.Bold);
            var small = new Font("Segoe UI", 8.25f);
            for (int i = 0; i < Stats.Length; i++)
            {
                var st = Stats[i];
                int y = 72 + i * 43;   // row top
                int cy = y + 22;       // row centre
                var r = new Row { Stat = st };
                var shortLbl = new Label { Text = st.Short, Font = bold, Location = new Point(13, cy - 9), AutoSize = true };
                content.Controls.Add(shortLbl);
                int sw = TextRenderer.MeasureText(st.Short, bold).Width;
                content.Controls.Add(new Label { Text = st.Long == "Geschwindigkeit" ? "Geschw." : st.Long == "Verteidigung" ? "Verteid." : st.Long,
                    Font = small, ForeColor = Gray, Location = new Point(13 + sw - 4, cy - 6), AutoSize = true });
                r.P1 = new PercentBox { Location = new Point(134, cy - 12) };
                r.P2 = new PercentBox { Location = new Point(218, cy - 12) };
                content.Controls.Add(r.P1);
                content.Controls.Add(r.P2);
                content.Controls.Add(new Label { Text = "%", Location = new Point(187, cy - 8), AutoSize = true, ForeColor = Gray });
                content.Controls.Add(new Label { Text = "%", Location = new Point(271, cy - 8), AutoSize = true, ForeColor = Gray });
                r.Bar = new GrowthBar { StatColor = st.Color, Location = new Point(302, cy - 7), Size = new Size(130, 13) };
                content.Controls.Add(r.Bar);
                r.Avg = new Label { Font = new Font("Segoe UI", 9f, FontStyle.Bold), Location = new Point(430, cy - 9), Size = new Size(77, 18), TextAlign = ContentAlignment.MiddleRight };
                content.Controls.Add(r.Avg);
                var row = r;
                foreach (var pb in new[] { r.P1, r.P2 })
                {
                    var box = pb;
                    box.Box.TextChanged += (s, e) => OnEdited(row);
                    box.Box.Leave += (s, e) => { box.Normalize(); box.Invalidate(); };
                    box.Box.Enter += (s, e) => { box.Invalidate(); box.Box.SelectAll(); };
                }
                rows.Add(r);
            }
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing && !ctl.Quitting)
            {
                e.Cancel = true;
                Hide();
                ctl.PanelClosedByUser();
                return;
            }
            base.OnFormClosing(e);
        }

        // ------------------------------------------------------------------ drawing

        void DrawClassItem(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            bool sel = (e.State & DrawItemState.Selected) != 0;
            using (var b = new SolidBrush(sel ? Color.FromArgb(0, 99, 177) : Color.White)) e.Graphics.FillRectangle(b, e.Bounds);
            var r = new Rectangle(e.Bounds.X + 5, e.Bounds.Y, e.Bounds.Width - 6, e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics, list.Items[e.Index].ToString(), list.Font, r, sel ? Color.White : Color.Black,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
        }

        void PaintHeader(object sender, PaintEventArgs e)
        {
            var c = list.SelectedItem as ClassItem;
            e.Graphics.Clear(Color.White);
            if (c == null) return;
            using (var bold = new Font(header.Font, FontStyle.Bold))
            {
                string a = c.Id.ToString("000") + ": " + c.Name;
                var flags = TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
                int w = TextRenderer.MeasureText(e.Graphics, a, bold, new Size(999, 30), flags).Width;
                TextRenderer.DrawText(e.Graphics, a, bold, new Point(0, 2), Color.Black, flags);
                TextRenderer.DrawText(e.Graphics, " – Wachstum pro Level-Up", header.Font, new Point(w, 2), Color.FromArgb(64, 64, 64), flags);
            }
        }

        void DrawLegend(Graphics g)
        {
            int y = 444;
            var f = new Font("Segoe UI", 8.25f);
            using (var b = new SolidBrush(Color.FromArgb(85, 85, 85))) g.FillRectangle(b, 14, y, 11, 11);
            TextRenderer.DrawText(g, "+2", f, new Point(30, y - 2), Gray);
            using (var b = new SolidBrush(Color.FromArgb(170, 170, 170))) g.FillRectangle(b, 59, y, 11, 11);
            TextRenderer.DrawText(g, "+1", f, new Point(75, y - 2), Gray);
            using (var b = new SolidBrush(NoGain)) g.FillRectangle(b, 105, y, 11, 11);
            TextRenderer.DrawText(g, "kein\nAnstieg", f, new Rectangle(121, y - 8, 60, 34), Gray, TextFormatFlags.WordBreak);
            TextRenderer.DrawText(g, "Pro Level-Up ein Wurf · +1 und +2 zusammen max. 100 %", f, new Rectangle(201, y - 8, 306, 34), Gray, TextFormatFlags.WordBreak);
            f.Dispose();
        }

        // ------------------------------------------------------------------ data

        /// <summary>Fills the class list from Classes.rxdata and selects a class (keeps the current one if id &lt; 1).</summary>
        public void ShowClasses(int selectId)
        {
            var p = ctl.Project;
            if (p == null) return;
            if (selectId < 1) selectId = classId;
            var classes = p.List("classes");
            bool same = classes.Count == list.Items.Count;
            for (int i = 0; same && i < classes.Count; i++)
            {
                var it = (ClassItem)list.Items[i];
                same = it.Id == classes[i].Id && it.Name == classes[i].Name;
            }
            if (!same)
            {
                list.BeginUpdate();
                list.Items.Clear();
                foreach (var c in classes) list.Items.Add(new ClassItem { Id = c.Id, Name = c.Name });
                list.EndUpdate();
            }
            int index = 0;
            for (int i = 0; i < list.Items.Count; i++) if (((ClassItem)list.Items[i]).Id == selectId) index = i;
            if (list.Items.Count == 0) return;
            if (list.SelectedIndex != index) list.SelectedIndex = index;
            else if (!same || classId != selectId) LoadClass(((ClassItem)list.Items[index]).Id);
        }

        public static int Stored(AttrConfig c, int id, GrowthStat s, int which)
        {
            double def = which == 1 ? s.P1 : s.P2;
            return (int)Math.Max(0, Math.Min(100, Math.Round(c.D(Section, id, s.Key + (which == 1 ? "_p1" : "_p2"), def))));
        }

        void LoadClass(int id)
        {
            var p = ctl.Project;
            if (p == null) return;
            classId = id;
            loading = true;
            try
            {
                foreach (var r in rows)
                {
                    r.P1.Box.Text = Stored(p.Config, id, r.Stat, 1).ToString(CultureInfo.InvariantCulture);
                    r.P2.Box.Text = Stored(p.Config, id, r.Stat, 2).ToString(CultureInfo.InvariantCulture);
                    UpdateRow(r);
                }
            }
            finally { loading = false; }
            header.Invalidate();
        }

        /// <summary>Updates bar / average / red borders. Returns true if the row is valid (p1 + p2 ≤ 100).</summary>
        bool UpdateRow(Row r)
        {
            int p1 = r.P1.Value, p2 = r.P2.Value;
            bool ok = p1 + p2 <= 100;
            r.P1.Error = r.P2.Error = !ok;
            r.Bar.P1 = p1;
            r.Bar.P2 = p2;
            r.Bar.Invalidate();
            if (ok)
            {
                r.Avg.ForeColor = Color.Black;
                r.Avg.Text = "+" + ((p1 + 2 * p2) / 100.0).ToString("0.00", CultureInfo.GetCultureInfo("de-DE"));
            }
            else
            {
                r.Avg.ForeColor = ErrorRed;
                r.Avg.Text = "> 100 %";
            }
            return ok;
        }

        void OnEdited(Row r)
        {
            if (loading) return;
            bool ok = UpdateRow(r);
            var p = ctl.Project;
            if (p == null || classId < 1 || !ok) return;   // rows over 100 % are not saved
            p.Config.Set(Section, classId, r.Stat.Key + "_p1", r.P1.Value);
            p.Config.Set(Section, classId, r.Stat.Key + "_p2", r.P2.Value);
            ctl.ScheduleSave();
        }

        void ResetClass()
        {
            var p = ctl.Project;
            if (p == null || classId < 1) return;
            p.Config.Clear(Section, classId);
            LoadClass(classId);
            ctl.ScheduleSave();
        }

        /// <summary>Puts invalid rows back to their last saved values (used when the window hides).</summary>
        public void DiscardInvalid()
        {
            bool any = false;
            foreach (var r in rows) if (r.P1.Error) any = true;
            if (any && classId > 0) LoadClass(classId);
        }

        /// <summary>For the self-test: types into a field.</summary>
        public void TestSet(int row, int which, string text)
        {
            (which == 1 ? rows[row].P1 : rows[row].P2).Box.Text = text;
        }
        public string TestAvg(int row) { return rows[row].Avg.Text; }
        public bool TestError(int row) { return rows[row].P1.Error; }
    }
}
