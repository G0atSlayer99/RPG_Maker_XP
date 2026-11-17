using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Windows.Forms;

namespace XpAttributes
{
    public enum PanelMode { None, Actors, Enemies, Weapons, Armors, States, Skills, Settings, NoProject }

    /// <summary>Small level graph in the style of the Database parameter curves.</summary>
    public class GraphBox : Control
    {
        public string Title = "";
        public Color Fill = Color.OrangeRed;
        public double Base, Growth;
        public int MinLevel = 1, MaxLevel = 99;
        public double MaxValue = 100;
        public Func<double, double> Clamp = v => v;
        readonly ToolTip tip = new ToolTip();
        int lastLevel = -1;

        public GraphBox()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        public double ValueAt(int level) { return Clamp(Base + Growth * (level - 1)); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Color.White);
            int w = Width - 1, h = Height - 1;
            int n = Math.Max(MaxLevel - MinLevel, 1);
            var pts = new List<PointF> { new PointF(0, h) };
            for (int lv = MinLevel; lv <= MaxLevel; lv++)
            {
                float x = (float)(lv - MinLevel) * w / n;
                double v = Math.Max(0, Math.Min(MaxValue, ValueAt(lv)));
                pts.Add(new PointF(x, (float)(h - v / MaxValue * h)));
            }
            pts.Add(new PointF(w, h));
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var b = new SolidBrush(Fill)) g.FillPolygon(b, pts.ToArray());
            g.SmoothingMode = SmoothingMode.None;
            using (var p = new Pen(Color.FromArgb(160, 160, 160))) g.DrawRectangle(p, 0, 0, w, h);
            g.DrawString(Title, Font, Brushes.Black, 3, 2);
            string scale = PanelForm.Pct(MaxValue);
            var sz = g.MeasureString(scale, Font);
            g.DrawString(scale, Font, Brushes.Gray, w - sz.Width - 2, 2);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int n = Math.Max(MaxLevel - MinLevel, 1);
            int lv = MinLevel + (int)Math.Round((double)e.X / Math.Max(Width - 1, 1) * n);
            lv = Math.Max(MinLevel, Math.Min(MaxLevel, lv));
            if (lv != lastLevel)
            {
                lastLevel = lv;
                tip.SetToolTip(this, "Lv " + lv + ": " + PanelForm.Pct(ValueAt(lv)));
            }
            base.OnMouseMove(e);
        }
    }

    /// <summary>Grid preview of a skill's area of effect (center tile marked).</summary>
    public class AreaPreview : Control
    {
        public int Radius = 1;
        public int Shape;          // 0 square, 1 diamond, 2 cross
        public bool Active = true;

        public AreaPreview()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        public static bool Inside(int dx, int dy, int r, int shape)
        {
            dx = Math.Abs(dx);
            dy = Math.Abs(dy);
            if (shape == 1) return dx + dy <= r;
            if (shape == 2) return (dx == 0 || dy == 0) && dx + dy <= r;
            return Math.Max(dx, dy) <= r;
        }

        public static int Count(int r, int shape)
        {
            int n = 0;
            for (int x = -r; x <= r; x++)
                for (int y = -r; y <= r; y++)
                    if (Inside(x, y, r, shape)) n++;
            return n;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Color.FromArgb(70, 110, 60));
            int cells = Math.Max(2 * Radius + 3, 5);
            int cell = Math.Max(3, Math.Min(Width, Height) / cells);
            int ox = (Width - cell * cells) / 2, oy = (Height - cell * cells) / 2;
            int c = cells / 2;
            using (var area = new SolidBrush(Active ? Color.FromArgb(255, 170, 40) : Color.FromArgb(150, 150, 150)))
            using (var center = new SolidBrush(Active ? Color.FromArgb(220, 60, 30) : Color.FromArgb(110, 110, 110)))
            using (var grid = new Pen(Color.FromArgb(60, 0, 0, 0)))
            {
                for (int x = 0; x < cells; x++)
                    for (int y = 0; y < cells; y++)
                    {
                        var r = new Rectangle(ox + x * cell, oy + y * cell, cell, cell);
                        if (x == c && y == c) g.FillRectangle(center, r);
                        else if (Inside(x - c, y - c, Radius, Shape)) g.FillRectangle(area, r);
                        g.DrawRectangle(grid, r);
                    }
            }
        }
    }

    public class PanelForm : Form
    {
        readonly Controller ctl;
        readonly Label lblTitle, lblKind, lblFooter;
        readonly LinkLabel lnkScript;
        readonly Panel content;
        readonly Dictionary<PanelMode, Panel> pages = new Dictionary<PanelMode, Panel>();

        // Actor page
        NumericUpDown aRate, aRateGrowth, aDmg, aDmgGrowth;
        GraphBox gRate, gDmg;
        Label aRateInfo, aDmgInfo, aDefault;
        // Enemy page
        NumericUpDown eRate, eDmg;
        Label eDefault;
        // Weapon / armor / state page
        GroupBox bGroup;
        NumericUpDown bRate, bDmg;
        Label bHelp;
        // Skill page
        CheckBox sCan, sRangeCustom, sFriendly;
        NumericUpDown sRate, sDmg, sRangeMin, sRangeMax, sRadius;
        ComboBox sTargeting, sShape;
        Label sAreaHint, sAreaSize;
        AreaPreview sPreview;
        // Settings page
        NumericUpDown dARate, dARateGrowth, dADmg, dADmgGrowth, dERate, dEDmg, maxDmg;
        CheckBox showStatus;
        TextBox rateName, dmgName;
        Label scriptState;

        PanelMode mode = PanelMode.None;
        int entryId;
        bool loading;
        public bool Docked;

        public PanelMode Mode { get { return mode; } }

        public const string AppTitle = "Attributes";

        public PanelForm(Controller controller)
        {
            ctl = controller;
            Text = AppTitle;
            Font = new Font("Segoe UI", 9f);
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(316, 600);
            BackColor = SystemColors.Control;

            lblTitle = new Label { Location = new Point(8, 6), Size = new Size(296, 22), Font = new Font("Segoe UI", 11f, FontStyle.Bold), AutoEllipsis = true, Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            lblKind = new Label { Location = new Point(9, 28), Size = new Size(296, 18), ForeColor = Color.DimGray, Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            content = new Panel { Location = new Point(0, 50), Size = new Size(316, 490), Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom, AutoScroll = true };
            lnkScript = new LinkLabel { Location = new Point(8, 544), Size = new Size(300, 34), Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom, LinkColor = Color.FromArgb(180, 60, 0), Visible = false };
            lnkScript.LinkClicked += (s, e) => ctl.InstallScript();
            lblFooter = new Label { Location = new Point(8, 580), Size = new Size(300, 18), Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom, ForeColor = Color.DimGray, AutoEllipsis = true };
            Controls.AddRange(new Control[] { lblTitle, lblKind, content, lnkScript, lblFooter });

            BuildActorPage();
            BuildEnemyPage();
            BuildBonusPage();
            BuildSkillPage();
            BuildSettingsPage();
            BuildNoProjectPage();
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing && !ctl.Quitting)
            {
                e.Cancel = true;
                Flush();
                Hide();
                ctl.PanelClosedByUser();
                return;
            }
            base.OnFormClosing(e);
        }

        // ------------------------------------------------------------------ helpers

        public static string Pct(double v)
        {
            return Math.Round(v, 2).ToString("0.##", CultureInfo.CurrentCulture) + " %";
        }

        static void SetNum(NumericUpDown n, double v)
        {
            decimal d = (decimal)Math.Round(v, n.DecimalPlaces);
            if (d < n.Minimum) d = n.Minimum;
            if (d > n.Maximum) d = n.Maximum;
            n.Value = d;
        }

        static double V(NumericUpDown n) { return (double)n.Value; }

        NumericUpDown Row(Control parent, string label, int y, decimal min, decimal max, int decimals, string suffix, int labelWidth, EventHandler changed)
        {
            parent.Controls.Add(new Label { Text = label, Location = new Point(10, y + 3), Size = new Size(labelWidth, 18) });
            var n = new NumericUpDown
            {
                Location = new Point(10 + labelWidth, y),
                Width = 76,
                Minimum = min,
                Maximum = max,
                DecimalPlaces = decimals,
                Increment = decimals > 0 ? 0.1m : 1m,
                TextAlign = HorizontalAlignment.Right
            };
            n.ValueChanged += changed;
            parent.Controls.Add(n);
            parent.Controls.Add(new Label { Text = suffix, Location = new Point(10 + labelWidth + 80, y + 3), AutoSize = true, ForeColor = Color.DimGray });
            return n;
        }

        Panel NewPage(PanelMode m, int height)
        {
            var p = new Panel { Location = new Point(0, 0), Size = new Size(300, height), Visible = false };
            content.Controls.Add(p);
            pages[m] = p;
            return p;
        }

        static Label Help(Control parent, string text, int y, int height)
        {
            var l = new Label { Text = text, Location = new Point(10, y), Size = new Size(280, height), ForeColor = Color.DimGray };
            parent.Controls.Add(l);
            return l;
        }

        // ------------------------------------------------------------------ pages

        void BuildActorPage()
        {
            var p = NewPage(PanelMode.Actors, 450);
            EventHandler ch = (s, e) => OnEntryEdited();

            var g1 = new GroupBox { Text = "Crit Rate  (chance, 0 – 100 %)", Location = new Point(8, 0), Size = new Size(284, 184) };
            aRate = Row(g1, "At level 1", 22, 0, 100, 1, "%", 90, ch);
            aRateGrowth = Row(g1, "Per level", 50, -100, 100, 2, "% / level", 90, ch);
            gRate = new GraphBox { Title = "Crit Rate", Fill = Color.FromArgb(232, 96, 60), Location = new Point(10, 80), Size = new Size(264, 76), MaxValue = 100 };
            gRate.Clamp = v => Math.Max(0, Math.Min(100, v));
            g1.Controls.Add(gRate);
            aRateInfo = new Label { Location = new Point(10, 160), Size = new Size(264, 18), ForeColor = Color.DimGray };
            g1.Controls.Add(aRateInfo);

            var g2 = new GroupBox { Text = "Crit Damage  (+% damage, 100 % = ×2)", Location = new Point(8, 192), Size = new Size(284, 184) };
            aDmg = Row(g2, "At level 1", 22, 0, 10000, 1, "%", 90, ch);
            aDmgGrowth = Row(g2, "Per level", 50, -1000, 1000, 2, "% / level", 90, ch);
            gDmg = new GraphBox { Title = "Crit Damage", Fill = Color.FromArgb(214, 160, 32), Location = new Point(10, 80), Size = new Size(264, 76) };
            gDmg.Clamp = v => ClampDamage(v);
            g2.Controls.Add(gDmg);
            aDmgInfo = new Label { Location = new Point(10, 160), Size = new Size(264, 18), ForeColor = Color.DimGray };
            g2.Controls.Add(aDmgInfo);

            aDefault = Help(p, "", 382, 34);
            var reset = new Button { Text = "Reset to defaults", Location = new Point(8, 418), Size = new Size(130, 25) };
            reset.Click += (s, e) => ResetCrit();
            p.Controls.AddRange(new Control[] { g1, g2, reset });
        }

        void BuildEnemyPage()
        {
            var p = NewPage(PanelMode.Enemies, 200);
            EventHandler ch = (s, e) => OnEntryEdited();
            var g = new GroupBox { Text = "Critical hits", Location = new Point(8, 0), Size = new Size(284, 84) };
            eRate = Row(g, "Crit Rate", 22, 0, 100, 1, "%", 100, ch);
            eDmg = Row(g, "Crit Damage", 50, 0, 10000, 1, "%  (100 = ×2)", 100, ch);
            p.Controls.Add(g);
            eDefault = Help(p, "", 92, 34);
            var reset = new Button { Text = "Reset to defaults", Location = new Point(8, 128), Size = new Size(130, 25) };
            reset.Click += (s, e) => ResetCrit();
            p.Controls.Add(reset);
            Help(p, "States can add more while they are active.", 162, 34);
        }

        void BuildBonusPage()
        {
            var p = NewPage(PanelMode.Weapons, 160);
            pages[PanelMode.Armors] = p;
            pages[PanelMode.States] = p;
            EventHandler ch = (s, e) => OnEntryEdited();
            bGroup = new GroupBox { Text = "Critical hits", Location = new Point(8, 0), Size = new Size(284, 84) };
            bRate = Row(bGroup, "Crit Rate", 22, -100, 100, 1, "%", 100, ch);
            bDmg = Row(bGroup, "Crit Damage", 50, -10000, 10000, 1, "%", 100, ch);
            p.Controls.Add(bGroup);
            bHelp = Help(p, "", 92, 60);
        }

        void BuildSkillPage()
        {
            var p = NewPage(PanelMode.Skills, 560);
            EventHandler ch = (s, e) => OnEntryEdited();

            // Critical hits
            var g1 = new GroupBox { Text = "Critical hits", Location = new Point(8, 0), Size = new Size(284, 110) };
            sCan = new CheckBox { Text = "This skill can land critical hits", Location = new Point(10, 20), Size = new Size(260, 22) };
            sCan.CheckedChanged += ch;
            g1.Controls.Add(sCan);
            sRate = Row(g1, "Extra Crit Rate", 48, -100, 100, 1, "%", 110, ch);
            sDmg = Row(g1, "Extra Crit Dmg", 76, -10000, 10000, 1, "%", 110, ch);

            // Range
            var g2 = new GroupBox { Text = "Range  (FE Tactics, in tiles)", Location = new Point(8, 116), Size = new Size(284, 104) };
            sRangeCustom = new CheckBox { Text = "Custom range", Location = new Point(10, 20), Size = new Size(260, 22) };
            sRangeCustom.CheckedChanged += ch;
            g2.Controls.Add(sRangeCustom);
            sRangeMin = Row(g2, "Min", 46, 0, 99, 0, "0 = can target own tile", 40, ch);
            sRangeMax = Row(g2, "Max", 72, 0, 99, 0, "tiles", 40, ch);

            // Area of effect
            var g3 = new GroupBox { Text = "Targeting  (FE Tactics)", Location = new Point(8, 226), Size = new Size(284, 290) };
            sTargeting = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(10, 20), Width = 264 };
            sTargeting.Items.AddRange(new object[] { "Default (from the skill's scope)", "Single target", "Area of effect" });
            sTargeting.SelectedIndexChanged += ch;
            g3.Controls.Add(sTargeting);
            sAreaHint = new Label { Location = new Point(10, 48), Size = new Size(264, 32), ForeColor = Color.DimGray };
            g3.Controls.Add(sAreaHint);
            sRadius = Row(g3, "Radius", 84, 0, 10, 0, "", 60, ch);
            sAreaSize = new Label { Location = new Point(150, 87), Size = new Size(124, 18), ForeColor = Color.DimGray };
            g3.Controls.Add(sAreaSize);
            g3.Controls.Add(new Label { Text = "Shape", Location = new Point(10, 115), Size = new Size(60, 18) });
            sShape = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(70, 112), Width = 100 };
            sShape.Items.AddRange(new object[] { "Square", "Diamond", "Cross" });
            sShape.SelectedIndexChanged += ch;
            g3.Controls.Add(sShape);
            sFriendly = new CheckBox { Text = "Friendly fire (hits everyone in the area)", Location = new Point(10, 140), Size = new Size(264, 22) };
            sFriendly.CheckedChanged += ch;
            g3.Controls.Add(sFriendly);
            sPreview = new AreaPreview { Location = new Point(10, 168), Size = new Size(110, 110) };
            g3.Controls.Add(sPreview);
            g3.Controls.Add(new Label
            {
                Text = "The player aims the center with a free cursor within the skill's range. Every unit standing in the area is hit.",
                Location = new Point(128, 168), Size = new Size(148, 110), ForeColor = Color.DimGray
            });

            p.Controls.AddRange(new Control[] { g1, g2, g3 });
            Help(p, "Range and targeting are used by the FE Tactics map battles. Critical hits work in every battle.", 522, 36);
        }

        void BuildSettingsPage()
        {
            var p = NewPage(PanelMode.Settings, 450);
            EventHandler ch = (s, e) => OnSettingsEdited();

            var g1 = new GroupBox { Text = "Crit defaults for actors not edited yet", Location = new Point(8, 0), Size = new Size(284, 130) };
            dARate = Row(g1, "Crit Rate Lv 1", 22, 0, 100, 1, "%", 110, ch);
            dARateGrowth = Row(g1, "  per level", 48, -100, 100, 2, "%", 110, ch);
            dADmg = Row(g1, "Crit Damage Lv 1", 74, 0, 10000, 1, "%", 110, ch);
            dADmgGrowth = Row(g1, "  per level", 100, -1000, 1000, 2, "%", 110, ch);

            var g2 = new GroupBox { Text = "Crit defaults for enemies not edited yet", Location = new Point(8, 136), Size = new Size(284, 78) };
            dERate = Row(g2, "Crit Rate", 22, 0, 100, 1, "%", 110, ch);
            dEDmg = Row(g2, "Crit Damage", 48, 0, 10000, 1, "%", 110, ch);

            var g3 = new GroupBox { Text = "Limit", Location = new Point(8, 220), Size = new Size(284, 52) };
            maxDmg = Row(g3, "Max Crit Damage", 20, 0, 100000, 0, "%  (0 = none)", 110, ch);

            var g4 = new GroupBox { Text = "Status screen (in-game menu)", Location = new Point(8, 278), Size = new Size(284, 100) };
            showStatus = new CheckBox { Text = "Show Crit Rate / Crit Damage", Location = new Point(10, 20), Size = new Size(260, 22) };
            showStatus.CheckedChanged += ch;
            g4.Controls.Add(showStatus);
            g4.Controls.Add(new Label { Text = "Rate label", Location = new Point(10, 49), Size = new Size(100, 18) });
            rateName = new TextBox { Location = new Point(120, 46), Width = 150 };
            rateName.TextChanged += ch;
            g4.Controls.Add(rateName);
            g4.Controls.Add(new Label { Text = "Damage label", Location = new Point(10, 75), Size = new Size(100, 18) });
            dmgName = new TextBox { Location = new Point(120, 72), Width = 150 };
            dmgName.TextChanged += ch;
            g4.Controls.Add(dmgName);

            var g5 = new GroupBox { Text = "Game script", Location = new Point(8, 384), Size = new Size(284, 60) };
            scriptState = new Label { Location = new Point(10, 18), Size = new Size(150, 36) };
            var install = new Button { Text = "Install / Update", Location = new Point(166, 15), Size = new Size(110, 24) };
            install.Click += (s, e) => ctl.InstallScript();
            var copy = new LinkLabel { Text = "Copy to clipboard", Location = new Point(166, 41), AutoSize = true };
            copy.LinkClicked += (s, e) => ctl.CopyScript();
            g5.Controls.AddRange(new Control[] { scriptState, install, copy });

            p.Controls.AddRange(new Control[] { g1, g2, g3, g4, g5 });
        }

        void BuildNoProjectPage()
        {
            var p = NewPage(PanelMode.NoProject, 100);
            Help(p, "Couldn't tell which project RPG Maker XP has open.", 4, 36);
            var b = new Button { Text = "Choose project folder...", Location = new Point(8, 44), Size = new Size(170, 26) };
            b.Click += (s, e) => ctl.ChooseProject();
            p.Controls.Add(b);
        }

        // ------------------------------------------------------------------ state

        static string SectionOf(PanelMode m)
        {
            switch (m)
            {
                case PanelMode.Actors: return "actors";
                case PanelMode.Enemies: return "enemies";
                case PanelMode.Weapons: return "weapons";
                case PanelMode.Armors: return "armors";
                case PanelMode.States: return "states";
                case PanelMode.Skills: return "skills";
            }
            return null;
        }

        static string KindText(PanelMode m)
        {
            switch (m)
            {
                case PanelMode.Actors: return "Actor – attributes";
                case PanelMode.Enemies: return "Enemy – attributes";
                case PanelMode.Weapons: return "Weapon – attributes";
                case PanelMode.Armors: return "Armor – attributes";
                case PanelMode.States: return "State – attributes";
                case PanelMode.Skills: return "Skill – attributes";
                case PanelMode.Settings: return "Attributes – settings";
            }
            return "";
        }

        /// <summary>Commits values that are typed but not yet confirmed.</summary>
        public void Flush()
        {
            Panel p;
            if (mode == PanelMode.None || !pages.TryGetValue(mode, out p)) return;
            FlushIn(p);
        }

        static void FlushIn(Control c)
        {
            foreach (Control k in c.Controls)
            {
                var n = k as NumericUpDown;
                if (n != null) { var unused = n.Value; }
                else FlushIn(k);
            }
        }

        public void ShowEntry(PanelMode m, int id, string title, bool force)
        {
            if (!force && m == mode && id == entryId)
            {
                if (lblTitle.Text != title) lblTitle.Text = title;
                return;
            }
            Flush();
            mode = m;
            entryId = id;
            lblTitle.Text = title;
            lblKind.Text = KindText(m);
            foreach (var kv in pages) kv.Value.Visible = false;
            Panel page;
            if (pages.TryGetValue(m, out page)) page.Visible = true;
            content.AutoScrollPosition = new Point(0, 0);
            LoadValues();
        }

        public void SetFooter(string text) { lblFooter.Text = text; }

        public void SetScriptState(ScriptInstaller.State st)
        {
            string msg = null;
            switch (st)
            {
                case ScriptInstaller.State.Installed:
                    scriptState.Text = "Installed in this project.";
                    scriptState.ForeColor = Color.DarkGreen;
                    break;
                case ScriptInstaller.State.Outdated:
                    scriptState.Text = "Installed, but outdated.";
                    scriptState.ForeColor = Color.FromArgb(180, 60, 0);
                    msg = "The Attributes game script in this project is outdated. Click to update.";
                    break;
                case ScriptInstaller.State.NotInstalled:
                    scriptState.Text = "Not installed yet.";
                    scriptState.ForeColor = Color.FromArgb(180, 60, 0);
                    msg = "The Attributes game script isn't installed in this project yet, so these values do nothing in-game. Click to install.";
                    break;
                default:
                    scriptState.Text = "Unknown.";
                    scriptState.ForeColor = Color.DimGray;
                    break;
            }
            lnkScript.Text = msg ?? "";
            lnkScript.Visible = msg != null;
        }

        double ClampDamage(double v)
        {
            v = Math.Max(0, v);
            var p = ctl.Project;
            if (p != null && p.Config.MaxCritDamage > 0) v = Math.Min(v, p.Config.MaxCritDamage);
            return v;
        }

        static string ScopeName(int scope)
        {
            string[] names = { "None", "One Enemy", "All Enemies", "One Ally", "All Allies", "One Ally (HP 0)", "All Allies (HP 0)", "The User" };
            return scope >= 0 && scope < names.Length ? names[scope] : "?";
        }

        void LoadValues()
        {
            var p = ctl.Project;
            if (p == null) return;
            var c = p.Config;
            loading = true;
            try
            {
                string sec = SectionOf(mode);
                switch (mode)
                {
                    case PanelMode.Actors:
                        {
                            bool def = !c.Has(sec, entryId, "crit_rate");
                            var d = c.ActorDefault;
                            SetNum(aRate, c.D(sec, entryId, "crit_rate", d[0]));
                            SetNum(aRateGrowth, c.D(sec, entryId, "crit_rate_growth", d[1]));
                            SetNum(aDmg, c.D(sec, entryId, "crit_damage", d[2]));
                            SetNum(aDmgGrowth, c.D(sec, entryId, "crit_damage_growth", d[3]));
                            var e = p.Find("actors", entryId);
                            int max = e != null ? Math.Max(e.FinalLevel, 2) : 99;
                            gRate.MaxLevel = max;
                            gDmg.MaxLevel = max;
                            ShowDefaultHint(aDefault, def);
                            UpdateActorGraphs();
                            break;
                        }
                    case PanelMode.Enemies:
                        {
                            bool def = !c.Has(sec, entryId, "crit_rate");
                            SetNum(eRate, c.D(sec, entryId, "crit_rate", c.EnemyDefault[0]));
                            SetNum(eDmg, c.D(sec, entryId, "crit_damage", c.EnemyDefault[1]));
                            ShowDefaultHint(eDefault, def);
                            break;
                        }
                    case PanelMode.Weapons:
                    case PanelMode.Armors:
                    case PanelMode.States:
                        {
                            SetNum(bRate, c.D(sec, entryId, "crit_rate", 0));
                            SetNum(bDmg, c.D(sec, entryId, "crit_damage", 0));
                            bGroup.Text = mode == PanelMode.States ? "Critical hits – bonus while active" : "Critical hits – bonus while equipped";
                            bHelp.Text = mode == PanelMode.States
                                ? "Added to the Crit Rate / Crit Damage of anyone (actor or enemy) who has this state. Negative values lower them."
                                : "Added to the actor's Crit Rate / Crit Damage while equipped. Negative values lower them.";
                            break;
                        }
                    case PanelMode.Skills:
                        {
                            sCan.Checked = c.B(sec, entryId, "can_crit", false);
                            SetNum(sRate, c.D(sec, entryId, "crit_rate", 0));
                            SetNum(sDmg, c.D(sec, entryId, "crit_damage", 0));
                            sRangeCustom.Checked = c.B(sec, entryId, "range_custom", false);
                            SetNum(sRangeMin, c.D(sec, entryId, "range_min", 1));
                            SetNum(sRangeMax, c.D(sec, entryId, "range_max", 2));
                            if (!c.Has(sec, entryId, "aoe")) sTargeting.SelectedIndex = 0;
                            else sTargeting.SelectedIndex = c.B(sec, entryId, "aoe", false) ? 2 : 1;
                            SetNum(sRadius, c.D(sec, entryId, "aoe_radius", 1));
                            sShape.SelectedIndex = Math.Max(0, Math.Min(2, (int)c.D(sec, entryId, "aoe_shape", 0)));
                            sFriendly.Checked = c.B(sec, entryId, "friendly_fire", false);
                            UpdateSkillControls();
                            break;
                        }
                    case PanelMode.Settings:
                        {
                            SetNum(dARate, c.ActorDefault[0]); SetNum(dARateGrowth, c.ActorDefault[1]);
                            SetNum(dADmg, c.ActorDefault[2]); SetNum(dADmgGrowth, c.ActorDefault[3]);
                            SetNum(dERate, c.EnemyDefault[0]); SetNum(dEDmg, c.EnemyDefault[1]);
                            SetNum(maxDmg, c.MaxCritDamage);
                            showStatus.Checked = c.ShowInStatus;
                            rateName.Text = c.RateName;
                            dmgName.Text = c.DamageName;
                            break;
                        }
                }
            }
            finally { loading = false; }
        }

        static void ShowDefaultHint(Label l, bool isDefault)
        {
            l.Text = isDefault ? "Not edited yet – uses the defaults from the System tab." : "Edited.";
        }

        void UpdateActorGraphs()
        {
            gRate.Base = V(aRate); gRate.Growth = V(aRateGrowth);
            gDmg.Base = V(aDmg); gDmg.Growth = V(aDmgGrowth);
            double top = Math.Max(gDmg.ValueAt(1), gDmg.ValueAt(gDmg.MaxLevel));
            gDmg.MaxValue = Math.Max(200, Math.Ceiling(top / 100.0) * 100);
            gRate.Invalidate();
            gDmg.Invalidate();
            int max = gRate.MaxLevel;
            aRateInfo.Text = "Lv 1: " + Pct(gRate.ValueAt(1)) + "     Lv " + max + ": " + Pct(gRate.ValueAt(max));
            aDmgInfo.Text = "Lv 1: +" + Pct(gDmg.ValueAt(1)) + "     Lv " + max + ": +" + Pct(gDmg.ValueAt(max));
        }

        void UpdateSkillControls()
        {
            sRate.Enabled = sDmg.Enabled = sCan.Checked;
            sRangeMin.Enabled = sRangeMax.Enabled = sRangeCustom.Checked;
            bool area = sTargeting.SelectedIndex == 2;
            sRadius.Enabled = sShape.Enabled = sFriendly.Enabled = area;
            int r = (int)sRadius.Value, shape = Math.Max(0, sShape.SelectedIndex);
            sAreaSize.Text = shape == 0 ? (2 * r + 1) + " × " + (2 * r + 1) + " tiles" : AreaPreview.Count(r, shape) + " tiles";
            sPreview.Radius = r;
            sPreview.Shape = shape;
            sPreview.Active = area;
            sPreview.Invalidate();
            var e = ctl.Project != null ? ctl.Project.Find("skills", entryId) : null;
            string scope = e != null ? ScopeName(e.Scope) : "?";
            switch (sTargeting.SelectedIndex)
            {
                case 0:
                    sAreaHint.Text = "Scope is \"" + scope + "\"" + (e != null && (e.Scope == 2 || e.Scope == 4)
                        ? ": hits that side around the chosen unit (FE Tactics AREA_RADIUS)."
                        : ": one unit.");
                    break;
                case 1:
                    sAreaHint.Text = "Hits one unit, even if the scope is \"All\".";
                    break;
                default:
                    sAreaHint.Text = "Hits " + (sFriendly.Checked ? "every unit" : "every target of the skill's side") + " in the area.";
                    break;
            }
            if (!sRangeCustom.Checked) sRangeMin.Enabled = sRangeMax.Enabled = false;
        }

        void OnEntryEdited()
        {
            if (loading) return;
            var p = ctl.Project;
            string sec = SectionOf(mode);
            if (p == null || sec == null) return;
            var c = p.Config;
            switch (mode)
            {
                case PanelMode.Actors:
                    c.Set(sec, entryId, "crit_rate", V(aRate));
                    c.Set(sec, entryId, "crit_rate_growth", V(aRateGrowth));
                    c.Set(sec, entryId, "crit_damage", V(aDmg));
                    c.Set(sec, entryId, "crit_damage_growth", V(aDmgGrowth));
                    UpdateActorGraphs();
                    ShowDefaultHint(aDefault, false);
                    break;
                case PanelMode.Enemies:
                    c.Set(sec, entryId, "crit_rate", V(eRate));
                    c.Set(sec, entryId, "crit_damage", V(eDmg));
                    ShowDefaultHint(eDefault, false);
                    break;
                case PanelMode.Skills:
                    if (sRangeMax.Value < sRangeMin.Value)
                    {
                        loading = true;
                        sRangeMax.Value = sRangeMin.Value;
                        loading = false;
                    }
                    c.Set(sec, entryId, "can_crit", sCan.Checked);
                    c.Set(sec, entryId, "crit_rate", V(sRate));
                    c.Set(sec, entryId, "crit_damage", V(sDmg));
                    c.Set(sec, entryId, "range_custom", sRangeCustom.Checked);
                    c.Set(sec, entryId, "range_min", V(sRangeMin));
                    c.Set(sec, entryId, "range_max", V(sRangeMax));
                    if (sTargeting.SelectedIndex <= 0) c.Remove(sec, entryId, "aoe");
                    else c.Set(sec, entryId, "aoe", sTargeting.SelectedIndex == 2);
                    c.Set(sec, entryId, "aoe_radius", V(sRadius));
                    c.Set(sec, entryId, "aoe_shape", (double)Math.Max(0, sShape.SelectedIndex));
                    c.Set(sec, entryId, "friendly_fire", sFriendly.Checked);
                    UpdateSkillControls();
                    break;
                default:
                    c.Set(sec, entryId, "crit_rate", V(bRate));
                    c.Set(sec, entryId, "crit_damage", V(bDmg));
                    break;
            }
            ctl.ScheduleSave();
        }

        void ResetCrit()
        {
            var p = ctl.Project;
            string sec = SectionOf(mode);
            if (p == null || sec == null) return;
            p.Config.Remove(sec, entryId, "crit_rate", "crit_rate_growth", "crit_damage", "crit_damage_growth");
            LoadValues();
            ctl.ScheduleSave();
        }

        void OnSettingsEdited()
        {
            if (loading) return;
            var p = ctl.Project;
            if (p == null) return;
            var c = p.Config;
            c.ActorDefault = new[] { V(dARate), V(dARateGrowth), V(dADmg), V(dADmgGrowth) };
            c.EnemyDefault = new[] { V(dERate), V(dEDmg) };
            c.MaxCritDamage = V(maxDmg);
            c.ShowInStatus = showStatus.Checked;
            c.RateName = rateName.Text;
            c.DamageName = dmgName.Text;
            ctl.ScheduleSave();
        }
    }
}
