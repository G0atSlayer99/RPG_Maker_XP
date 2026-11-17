using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace XpAttributes
{
    /// <summary>Runs in the tray, follows RPG Maker XP's Database window and docks the panel next to it.</summary>
    public class Controller : ApplicationContext
    {
        public Project Project;
        public bool Quitting;
        public static bool TestMode;   // --selftest: no tray icon, no launching, nothing remembered
        readonly PanelForm panel;
        readonly NotifyIcon tray;
        readonly System.Windows.Forms.Timer tick, saveTimer;
        IntPtr db = IntPtr.Zero;
        int dbPid;
        bool seenEditor, hiddenByUser, standalone;
        DateTime lastSeen = DateTime.Now;
        string lastStatus = "";

        static string SettingsDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "XpAttributes"); }
        }
        static string LastProjectFile { get { return Path.Combine(SettingsDir, "last_project.txt"); } }
        // Written by the earlier "Crit Stats" version.
        static string OldLastProjectFile
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CritStatsXP", "last_project.txt"); }
        }

        public Controller(string[] args)
        {
            panel = new PanelForm(this);
            panel.Icon = MakeIcon();
            var unused = panel.Handle;

            var menu = new ContextMenuStrip();
            menu.Items.Add(new ToolStripMenuItem("Attributes for RPG Maker XP") { Enabled = false });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Settings...", null, (s, e) => ShowSettingsStandalone());
            menu.Items.Add("Install / update game script...", null, (s, e) => InstallScript());
            menu.Items.Add("Copy game script to clipboard", null, (s, e) => CopyScript());
            menu.Items.Add("Choose project folder...", null, (s, e) => ChooseProject());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, (s, e) => Quit());
            tray = new NotifyIcon { Icon = panel.Icon, Text = "Attributes – opens with the RPG Maker XP Database", ContextMenuStrip = menu, Visible = true };
            tray.DoubleClick += (s, e) => ShowSettingsStandalone();
            if (TestMode)
            {
                tray.Visible = false;
                saveTimer = new System.Windows.Forms.Timer();
                tick = new System.Windows.Forms.Timer();
                return;
            }

            try
            {
                string file = File.Exists(LastProjectFile) ? LastProjectFile : OldLastProjectFile;
                if (File.Exists(file))
                {
                    string last = File.ReadAllText(file).Trim();
                    if (Project.IsProjectDir(last)) OpenProject(last);
                }
            }
            catch { }

            LaunchEditor(args);

            saveTimer = new System.Windows.Forms.Timer { Interval = 400 };
            saveTimer.Tick += (s, e) => { saveTimer.Stop(); SaveNow(); };
            tick = new System.Windows.Forms.Timer { Interval = 150 };
            tick.Tick += (s, e) => Tick();
            tick.Start();
        }

        static Icon MakeIcon()
        {
            var bmp = new Bitmap(32, 32);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using (var b = new SolidBrush(Color.FromArgb(220, 70, 40))) g.FillEllipse(b, 1, 1, 30, 30);
                using (var f = new Font("Segoe UI", 15f, FontStyle.Bold, GraphicsUnit.Pixel))
                using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                    g.DrawString("A", f, Brushes.White, new RectangleF(0, 1, 32, 32), sf);
            }
            return Icon.FromHandle(bmp.GetHicon());
        }

        /// <summary>Starts RPG Maker XP: either the command passed by Steam (%command%) or RPGXP.exe next to this tool.</summary>
        void LaunchEditor(string[] args)
        {
            try
            {
                if (args.Length > 0 && args[0].EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(args[0]))
                {
                    var psi = new ProcessStartInfo(args[0], string.Join(" ", args.Skip(1).Select(Quote).ToArray()))
                    {
                        UseShellExecute = false,
                        WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(args[0]))
                    };
                    Process.Start(psi);
                    return;
                }
                if (args.Contains("--no-launch") || Process.GetProcessesByName("RPGXP").Length > 0) return;
                string here = Path.GetDirectoryName(Application.ExecutablePath);
                foreach (string dir in new[] { Path.GetDirectoryName(here), here })
                {
                    string exe = dir == null ? null : Path.Combine(dir, "RPGXP.exe");
                    if (exe != null && File.Exists(exe))
                    {
                        Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = dir, UseShellExecute = false });
                        return;
                    }
                }
            }
            catch (Exception ex)
            {
                tray.ShowBalloonTip(5000, PanelForm.AppTitle, "Couldn't start RPG Maker XP: " + ex.Message, ToolTipIcon.Warning);
            }
        }

        static string Quote(string a) { return a.Contains(" ") && !a.StartsWith("\"") ? "\"" + a + "\"" : a; }

        // ------------------------------------------------------------------ project

        public void OpenProject(string dir)
        {
            SaveNow();
            try
            {
                Project = new Project(dir);
                if (!TestMode)
                {
                    Directory.CreateDirectory(SettingsDir);
                    File.WriteAllText(LastProjectFile, Project.Dir);
                }
                RefreshScriptState();
                SetStatus("Project: " + Project.Name);
            }
            catch (Exception ex)
            {
                Project = null;
                MessageBox.Show("Couldn't open the project:\n" + ex.Message, PanelForm.AppTitle, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        public void ChooseProject()
        {
            using (var d = new OpenFileDialog { Title = "Select your project's Game.rxproj", Filter = "RPG Maker XP project (Game.rxproj)|*.rxproj", CheckFileExists = true })
            {
                if (Project != null) d.InitialDirectory = Project.Dir;
                if (d.ShowDialog(panel.Visible ? panel : null) != DialogResult.OK) return;
                OpenProject(Path.GetDirectoryName(d.FileName));
                panel.ShowEntry(PanelMode.None, -1, "", true);
                if (db == IntPtr.Zero && Project != null) ShowSettingsStandalone();
            }
        }

        void RefreshScriptState()
        {
            if (Project != null) panel.SetScriptState(ScriptInstaller.Check(Project));
        }

        void SetStatus(string s)
        {
            if (s == lastStatus) return;
            lastStatus = s;
            panel.SetFooter(s);
        }

        public void ScheduleSave()
        {
            saveTimer.Stop();
            saveTimer.Start();
            SetStatus("Project: " + (Project != null ? Project.Name : "?") + "  ·  saving...");
        }

        void SaveNow()
        {
            if (saveTimer != null) saveTimer.Stop();
            if (Project == null) return;
            try
            {
                Project.SaveConfig();
                SetStatus("Project: " + Project.Name + "  ·  saved");
            }
            catch (Exception ex)
            {
                SetStatus("Couldn't save: " + ex.Message);
            }
        }

        // ------------------------------------------------------------------ script

        static bool EditorRunning() { return Process.GetProcessesByName("RPGXP").Length > 0; }

        public void CopyScript()
        {
            Clipboard.SetText(ScriptInstaller.ScriptText());
            MessageBox.Show(
                "The game script is on the clipboard.\n\nIn RPG Maker XP: open the Script Editor (F11), right-click \"Main\" → Insert, " +
                "name the new entry \"" + ScriptInstaller.ScriptName + "\", paste the script into it, press OK and save the project.",
                PanelForm.AppTitle, MessageBoxButtons.OK, MessageBoxIcon.Information);
            RefreshScriptState();
        }

        public void InstallScript()
        {
            if (Project == null)
            {
                MessageBox.Show("No project yet. Open the Database in RPG Maker XP once, or choose the project folder from the tray menu.",
                    PanelForm.AppTitle, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (EditorRunning())
            {
                var r = MessageBox.Show(
                    "RPG Maker XP is open. It keeps its own copy of the scripts and would undo an automatic install the next time you save.\n\n" +
                    "Yes: copy the script to the clipboard so you can paste it into the Script Editor yourself.\n" +
                    "No: do nothing (close RPG Maker XP, then use \"Install / update game script\" from the tray icon).",
                    PanelForm.AppTitle, MessageBoxButtons.YesNo, MessageBoxIcon.Information);
                if (r == DialogResult.Yes) CopyScript();
                return;
            }
            try
            {
                string backup = ScriptInstaller.Install(Project);
                RefreshScriptState();
                MessageBox.Show("Installed \"" + ScriptInstaller.ScriptName + "\" above Main in\n" + Project.ScriptsPath +
                    "\n\nBackup of the old script file:\n" + backup, PanelForm.AppTitle, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Install failed:\n" + ex.Message, PanelForm.AppTitle, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        // ------------------------------------------------------------------ following the Database window

        static PanelMode ModeForTab(int tab)
        {
            // Actors, Classes, Skills, Items, Weapons, Armors, Enemies, Troops, States, Animations, Tilesets, Common Events, System
            switch (tab)
            {
                case 0: return PanelMode.Actors;
                case 2: return PanelMode.Skills;
                case 4: return PanelMode.Weapons;
                case 5: return PanelMode.Armors;
                case 6: return PanelMode.Enemies;
                case 8: return PanelMode.States;
                case 12: return PanelMode.Settings;
            }
            return PanelMode.None;
        }

        static string SectionFor(PanelMode m)
        {
            switch (m)
            {
                case PanelMode.Actors: return "actors";
                case PanelMode.Skills: return "skills";
                case PanelMode.Weapons: return "weapons";
                case PanelMode.Armors: return "armors";
                case PanelMode.Enemies: return "enemies";
                case PanelMode.States: return "states";
            }
            return null;
        }

        void Tick()
        {
            var procs = Process.GetProcessesByName("RPGXP");
            int[] pids = procs.Select(p => p.Id).ToArray();
            foreach (var p in procs) p.Dispose();

            if (pids.Length > 0) { seenEditor = true; lastSeen = DateTime.Now; }
            else if (seenEditor && !standalone && (DateTime.Now - lastSeen).TotalSeconds > 8) { Quit(); return; }

            int pid;
            IntPtr h;
            if (Win32.Alive(db)) { h = db; pid = dbPid; }
            else h = Win32.FindDatabase(pids, out pid);

            if (h == IntPtr.Zero)
            {
                if (db != IntPtr.Zero) DatabaseClosed();
                return;
            }
            if (h != db) DatabaseOpened(h, pid);
            standalone = false;

            PanelMode mode = ModeForTab(Win32.GetTabIndex(h));
            if (mode == PanelMode.None || hiddenByUser)
            {
                HidePanel();
                return;
            }

            if (Project == null)
            {
                panel.ShowEntry(PanelMode.NoProject, 0, PanelForm.AppTitle, false);
            }
            else if (mode == PanelMode.Settings)
            {
                panel.ShowEntry(PanelMode.Settings, 0, "Attributes – " + Project.Name, false);
            }
            else
            {
                IntPtr list = Win32.GetVisibleEntryList(h);
                int sel = Win32.GetSelection(list);
                if (sel < 0) { HidePanel(); return; }
                int id = sel + 1;
                string title = Win32.GetItemText(list, sel);
                if (string.IsNullOrEmpty(title))
                {
                    var e = Project.Find(SectionFor(mode), id);
                    title = id.ToString("000") + ": " + (e != null ? e.Name : "");
                }
                panel.ShowEntry(mode, id, title, false);
            }
            DockTo(h);
        }

        void DatabaseOpened(IntPtr h, int pid)
        {
            db = h;
            dbPid = pid;
            hiddenByUser = false;
            string cwd = Win32.GetProcessCurrentDirectory(pid);
            if (Project.IsProjectDir(cwd))
            {
                if (Project == null || !Project.IsSameDir(cwd)) OpenProject(cwd);
                else Project.ReloadNames();
            }
            else if (Project != null) Project.ReloadNames();
            RefreshScriptState();
            panel.ShowEntry(PanelMode.None, -1, "", true);
        }

        void DatabaseClosed()
        {
            db = IntPtr.Zero;
            panel.Flush();
            SaveNow();
            HidePanel();
        }

        void HidePanel()
        {
            if (panel.Visible && panel.Docked)
            {
                panel.Flush();
                panel.Hide();
            }
        }

        public void PanelClosedByUser()
        {
            if (db != IntPtr.Zero) hiddenByUser = true;
            SaveNow();
        }

        void DockTo(IntPtr h)
        {
            Rectangle f = Win32.GetFrame(h);
            int width = panel.Width;
            var screen = Screen.FromRectangle(f).WorkingArea;
            int x = f.Right - 1;
            if (x + width > screen.Right) x = Math.Max(screen.Left, f.Left - width + 1);
            var target = new Rectangle(x, f.Top, width, Math.Max(f.Height, 420));
            if (panel.Bounds != target) panel.Bounds = target;

            IntPtr fg = Win32.GetForegroundWindow();
            bool active = fg == h || fg == panel.Handle || (fg != IntPtr.Zero && Win32.ProcessOf(fg) == dbPid) || Form.ActiveForm == panel;
            if (panel.TopMost != active) panel.TopMost = active;
            if (!panel.Visible)
            {
                panel.Docked = true;
                panel.Show();
            }
        }

        void ShowSettingsStandalone()
        {
            if (Project == null) { ChooseProject(); if (Project == null) return; }
            if (db != IntPtr.Zero) { hiddenByUser = false; return; }
            standalone = true;
            panel.Docked = false;
            panel.ShowEntry(PanelMode.Settings, 0, "Attributes – " + Project.Name, true);
            RefreshScriptState();
            var wa = Screen.PrimaryScreen.WorkingArea;
            panel.Bounds = new Rectangle(wa.Left + (wa.Width - panel.Width) / 2, wa.Top + (wa.Height - 640) / 2, panel.Width, 640);
            panel.TopMost = false;
            panel.Show();
            panel.Activate();
        }

        public void Quit()
        {
            if (Quitting) return;
            Quitting = true;
            tick.Stop();
            panel.Flush();
            SaveNow();
            tray.Visible = false;
            tray.Dispose();
            panel.Close();
            ExitThread();
        }
    }

    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (args.Length > 0 && args[0] == "--selftest") return SelfTest.Run(args);

            bool created;
            using (var mutex = new Mutex(true, "XpAttributes_SingleInstance", out created))
            {
                if (!created)
                {
                    // Already running: still start the editor if Steam asked us to.
                    if (args.Length > 0 && args[0].EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(args[0]))
                        Process.Start(new ProcessStartInfo(args[0], string.Join(" ", args.Skip(1).ToArray())) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(Path.GetFullPath(args[0])) });
                    return 0;
                }
                Application.Run(new Controller(args));
            }
            return 0;
        }
    }

    /// <summary>Command-line checks used during development: --selftest &lt;projectDir&gt; &lt;outDir&gt;</summary>
    static class SelfTest
    {
        public static int Run(string[] args)
        {
            string dir = args[1], outDir = args[2];
            Controller.TestMode = true;
            var log = new StringBuilder();
            try
            {
                var p = new Project(dir);
                foreach (string s in AttrConfig.Sections)
                {
                    var l = p.List(s);
                    log.AppendLine(s + ": " + l.Count + (l.Count > 0 ? "  first=" + l[0].Id + ":" + l[0].Name + " final=" + l[0].FinalLevel : ""));
                }
                log.AppendLine("loaded (migrated) actor1 crit_rate=" + p.Config.D("actors", 1, "crit_rate", -1) + " skill7 can_crit=" + p.Config.B("skills", 7, "can_crit", false) + " rate_name=" + p.Config.RateName);
                log.AppendLine("script before: " + ScriptInstaller.Check(p));
                // Extra test values for the in-game test (args[4] = "aoe").
                if (args.Length > 4 && args[4] == "aoe")
                {
                    var c = p.Config;
                    c.Set("skills", 7, "range_custom", true); c.Set("skills", 7, "range_min", 2); c.Set("skills", 7, "range_max", 4);
                    c.Set("skills", 7, "aoe", true); c.Set("skills", 7, "aoe_radius", 1); c.Set("skills", 7, "aoe_shape", 0);
                    c.Set("skills", 8, "aoe", true); c.Set("skills", 8, "aoe_radius", 2); c.Set("skills", 8, "aoe_shape", 1);
                    c.Set("skills", 8, "friendly_fire", true);
                    c.Set("skills", 9, "aoe", false);
                }
                p.SaveConfig();
                var again = AttrConfig.Load(p.DataDir);
                log.AppendLine("reload actor1 crit_rate_growth=" + again.D("actors", 1, "crit_rate_growth", -1) +
                    " skill7 aoe=" + again.B("skills", 7, "aoe", false) + " r=" + again.D("skills", 7, "aoe_radius", -1) +
                    " range=" + again.D("skills", 7, "range_min", -1) + "-" + again.D("skills", 7, "range_max", -1));
                if (args.Length > 3 && args[3] == "install")
                {
                    ScriptInstaller.Install(p);
                    log.AppendLine("script after: " + ScriptInstaller.Check(p));
                }
                log.AppendLine("cwd of this process: " + Win32.GetProcessCurrentDirectory(Process.GetCurrentProcess().Id));

                // Render each page to PNG for a visual check.
                var ctl = new SnapshotController(p);
                foreach (var m in new[] { PanelMode.Actors, PanelMode.Enemies, PanelMode.Weapons, PanelMode.Skills, PanelMode.Settings })
                {
                    var f = ctl.Panel;
                    f.ShowEntry(m, m == PanelMode.Skills ? 7 : 1, "001: " + (p.Find("actors", 1) != null ? p.Find("actors", 1).Name : "?"), true);
                    f.SetScriptState(ScriptInstaller.Check(p));
                    f.SetFooter("Project: " + p.Name + "  ·  saved");
                    f.Size = new Size(f.Width, m == PanelMode.Actors ? 1640 : 640);
                    f.StartPosition = FormStartPosition.Manual;
                    f.Location = new Point(-3000, -3000);
                    f.Show();
                    Application.DoEvents();
                    using (var bmp = new Bitmap(f.Width, f.Height))
                    {
                        f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height));
                        bmp.Save(Path.Combine(outDir, "panel_" + m + ".png"));
                    }
                }

                // Actors page: edit through the controls, then check what was stored.
                {
                    var f = ctl.Panel;
                    var flags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance;
                    Func<string, object> get = n => typeof(PanelForm).GetField(n, flags).GetValue(f);
                    f.ShowEntry(PanelMode.Actors, 2, "002", true);
                    log.AppendLine("actor2 unedited: " + ((Label)get("aDefault")).Text);
                    var rows = (System.Collections.IList)get("aStats");
                    var hp = rows[0];
                    var lv1 = (NumericUpDown)hp.GetType().GetField("Lv1").GetValue(hp);
                    var max = (NumericUpDown)hp.GetType().GetField("Max").GetValue(hp);
                    log.AppendLine("actor2 hp defaults lv1=" + lv1.Value + " max=" + max.Value);
                    lv1.Value = Math.Min(lv1.Maximum, max.Value + 50);
                    log.AppendLine("lv1 above max -> lv1=" + lv1.Value + " max=" + max.Value);
                    max.Value = 20;
                    log.AppendLine("max lowered to 20 -> lv1=" + lv1.Value + " max=" + max.Value);
                    var level = (NumericUpDown)get("aLevel");
                    var maxLevel = (NumericUpDown)get("aMaxLevel");
                    maxLevel.Value = 100; level.Value = 100; maxLevel.Value = 50;
                    log.AppendLine("level=" + level.Value + " max level=" + maxLevel.Value);
                    ((TextBox)get("aName")).Text = "Renamed";
                    var cls = (ComboBox)get("aClass");
                    log.AppendLine("classes: " + cls.Items.Count + " selected=" + cls.SelectedItem);
                    cls.SelectedIndex = cls.Items.Count - 1;
                    p.SaveConfig();
                    var c2 = AttrConfig.Load(p.DataDir);
                    var sb = new StringBuilder("stored actor2:");
                    foreach (var kv in c2.Data["actors"][2]) sb.Append(" " + kv.Key + "=" + kv.Value);
                    log.AppendLine(sb.ToString());
                    ((Button)((Panel)get("content")).Controls.OfType<Panel>().First(x => x.Visible).Controls.OfType<Button>().First()).PerformClick();
                    log.AppendLine("after reset: has actor2=" + p.Config.Data["actors"].ContainsKey(2) + " status=" + ((Label)get("aDefault")).Text + " hp lv1=" + lv1.Value + " name=" + ((TextBox)get("aName")).Text);
                }
            }
            catch (Exception ex) { log.AppendLine("ERROR " + ex); }
            File.WriteAllText(Path.Combine(outDir, "selftest.txt"), log.ToString());
            return 0;
        }

        class SnapshotController : Controller
        {
            public PanelForm Panel;
            public SnapshotController(Project p) : base(new string[0])
            {
                Project = p;
                Panel = (PanelForm)typeof(Controller).GetField("panel", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).GetValue(this);
            }
        }
    }
}
