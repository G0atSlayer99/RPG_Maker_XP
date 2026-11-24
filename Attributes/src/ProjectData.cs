using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;

namespace XpAttributes
{
    public class DbEntry
    {
        public int Id;
        public string Name = "";
        public int InitialLevel = 1;
        public int FinalLevel = 99;
        public int Scope;
        public int ClassId = 1;
        // Actors: Database parameter curves (Table 6 x 100: MaxHP, MaxSP, STR, DEX, AGI, INT per level).
        public int ParamX;
        public short[] Params;
        // Enemies: Database values ("maxhp", "maxsp", "str", "dex", "agi", "int", "pdef", "mdef", "exp", "gold").
        public Dictionary<string, int> Fields = new Dictionary<string, int>();
        public int Field(string key, int fallback) { int v; return Fields.TryGetValue(key, out v) ? v : fallback; }

        /// <summary>Database parameter (0 MaxHP, 1 MaxSP, 2 STR, 3 DEX, 4 AGI, 5 INT) at a level, or -1 if unknown.</summary>
        public int Param(int kind, int level)
        {
            if (Params == null || ParamX <= 0) return -1;
            level = Math.Max(1, Math.Min(level, 99));
            int i = kind + level * ParamX;
            return i >= 0 && i < Params.Length ? Params[i] : -1;
        }
    }

    /// <summary>
    /// Attributes stored in Data/Attributes.rxdata:
    ///   { "version" => 2, "actors" => { id => { "crit_rate" => 5.0, ... } }, ..., "settings" => { ... } }
    /// Values are Floats or true/false. A missing key means "not set" (the game uses its default).
    /// </summary>
    public class AttrConfig
    {
        public const string FileName = "Attributes.rxdata";
        public const string OldFileName = "CritConfig.rxdata";
        // "classes": level-up growth per class, { id => { "hp_p1" => 60.0, "hp_p2" => 30.0, ... } } (see ClassGrowthForm)
        public static readonly string[] Sections = { "actors", "enemies", "weapons", "armors", "states", "skills", "classes" };

        static readonly Dictionary<string, string[]> OldKeys = new Dictionary<string, string[]>
        {
            { "actors",  new[] { "crit_rate", "crit_rate_growth", "crit_damage", "crit_damage_growth" } },
            { "enemies", new[] { "crit_rate", "crit_damage" } },
            { "weapons", new[] { "crit_rate", "crit_damage" } },
            { "armors",  new[] { "crit_rate", "crit_damage" } },
            { "states",  new[] { "crit_rate", "crit_damage" } },
            { "skills",  new[] { "can_crit", "crit_rate", "crit_damage" } },
        };
        static readonly HashSet<string> BoolKeys = new HashSet<string> { "can_crit", "range_custom", "aoe", "friendly_fire" };
        static readonly HashSet<string> StringKeys = new HashSet<string> { "name" };

        public readonly Dictionary<string, Dictionary<int, Dictionary<string, object>>> Data =
            new Dictionary<string, Dictionary<int, Dictionary<string, object>>>();
        public double[] ActorDefault = { 5, 0, 100, 0 };   // crit rate Lv1, rate/level, damage Lv1, damage/level
        public double[] EnemyDefault = { 5, 100 };         // crit rate, crit damage
        public bool ShowInStatus = true;
        public string RateName = "Crit Rate";
        public string DamageName = "Crit Damage";
        public double MaxCritDamage = 0;                   // 0 = no limit

        public AttrConfig()
        {
            foreach (string s in Sections) Data[s] = new Dictionary<int, Dictionary<string, object>>();
        }

        // ---------------------------------------------------------------- access

        public bool Has(string section, int id, string key)
        {
            Dictionary<string, object> e;
            return Data[section].TryGetValue(id, out e) && e.ContainsKey(key);
        }

        public double D(string section, int id, string key, double def)
        {
            Dictionary<string, object> e;
            object v;
            if (!Data[section].TryGetValue(id, out e) || !e.TryGetValue(key, out v)) return def;
            if (v is bool) return (bool)v ? 1 : 0;
            return Convert.ToDouble(v);
        }

        public bool B(string section, int id, string key, bool def)
        {
            Dictionary<string, object> e;
            object v;
            if (!Data[section].TryGetValue(id, out e) || !e.TryGetValue(key, out v)) return def;
            if (v is bool) return (bool)v;
            return Convert.ToDouble(v) != 0;
        }

        public string S(string section, int id, string key, string def)
        {
            Dictionary<string, object> e;
            object v;
            if (!Data[section].TryGetValue(id, out e) || !e.TryGetValue(key, out v) || v == null) return def;
            return v.ToString();
        }

        public void Set(string section, int id, string key, object value)
        {
            Dictionary<string, object> e;
            if (!Data[section].TryGetValue(id, out e)) Data[section][id] = e = new Dictionary<string, object>();
            e[key] = value is bool || value is string ? value : (object)Convert.ToDouble(value);
        }

        /// <summary>Removes every value of one entry.</summary>
        public void Clear(string section, int id) { Data[section].Remove(id); }

        public void Remove(string section, int id, params string[] keys)
        {
            Dictionary<string, object> e;
            if (!Data[section].TryGetValue(id, out e)) return;
            foreach (string k in keys) e.Remove(k);
            if (e.Count == 0) Data[section].Remove(id);
        }

        // ---------------------------------------------------------------- load / save

        static double Num(object o)
        {
            if (o is bool) return (bool)o ? 1 : 0;
            if (RHash.IsNumber(o)) return Convert.ToDouble(o);
            return 0;
        }

        static double[] Nums(object o, int width)
        {
            var list = o as List<object>;
            if (list == null || list.Count < width) return null;
            var r = new double[width];
            for (int i = 0; i < width; i++) r[i] = Num(list[i]);
            return r;
        }

        static object Value(string key, object o)
        {
            if (BoolKeys.Contains(key)) return o is bool ? (bool)o : Num(o) != 0;
            if (StringKeys.Contains(key)) return o.ToString();
            return Num(o);
        }

        /// <summary>Loads Attributes.rxdata, or converts the old CritConfig.rxdata if that is all there is.</summary>
        public static AttrConfig Load(string dataDir)
        {
            var c = new AttrConfig();
            string path = Path.Combine(dataDir, FileName);
            string old = Path.Combine(dataDir, OldFileName);
            RHash root = null;
            if (File.Exists(path)) root = MarshalReader.LoadFile(path) as RHash;
            else if (File.Exists(old)) root = MarshalReader.LoadFile(old) as RHash;
            if (root == null) return c;

            foreach (string s in Sections)
            {
                var h = root.Get(s) as RHash;
                if (h == null) continue;
                foreach (var p in h.Pairs)
                {
                    if (!RHash.IsNumber(p.Key)) continue;
                    int id = Convert.ToInt32(p.Key);
                    var entry = new Dictionary<string, object>();
                    var eh = p.Value as RHash;
                    var arr = p.Value as List<object>;
                    if (eh != null)
                    {
                        foreach (var kv in eh.Pairs)
                            if (kv.Key != null && kv.Value != null) entry[kv.Key.ToString()] = Value(kv.Key.ToString(), kv.Value);
                    }
                    else if (arr != null && OldKeys.ContainsKey(s))   // v1 format
                    {
                        string[] keys = OldKeys[s];
                        for (int i = 0; i < keys.Length && i < arr.Count; i++) entry[keys[i]] = Value(keys[i], arr[i]);
                    }
                    if (entry.Count > 0) c.Data[s][id] = entry;
                }
            }
            var st = root.Get("settings") as RHash;
            if (st != null)
            {
                c.ActorDefault = Nums(st.Get("actor_default"), 4) ?? c.ActorDefault;
                c.EnemyDefault = Nums(st.Get("enemy_default"), 2) ?? c.EnemyDefault;
                object o = st.Get("show_in_status");
                if (o is bool) c.ShowInStatus = (bool)o;
                o = st.Get("rate_name");
                if (o != null) c.RateName = o.ToString();
                o = st.Get("damage_name");
                if (o != null) c.DamageName = o.ToString();
                c.MaxCritDamage = Num(st.Get("max_crit_damage"));
            }
            return c;
        }

        static List<object> ToList(double[] v)
        {
            var l = new List<object>();
            foreach (double d in v) l.Add(d);
            return l;
        }

        public void Save(string dataDir)
        {
            var root = new RHash();
            root.Add("version", 2L);
            foreach (string s in Sections)
            {
                var h = new RHash();
                var ids = new List<int>(Data[s].Keys);
                ids.Sort();
                foreach (int id in ids)
                {
                    var eh = new RHash();
                    var keys = new List<string>(Data[s][id].Keys);
                    keys.Sort(StringComparer.Ordinal);
                    foreach (string k in keys) eh.Add(k, Data[s][id][k]);
                    h.Add((long)id, eh);
                }
                root.Add(s, h);
            }
            var st = new RHash();
            st.Add("actor_default", ToList(ActorDefault));
            st.Add("enemy_default", ToList(EnemyDefault));
            st.Add("show_in_status", ShowInStatus);
            st.Add("rate_name", RateName);
            st.Add("damage_name", DamageName);
            st.Add("max_crit_damage", MaxCritDamage);
            root.Add("settings", st);

            string path = Path.Combine(dataDir, FileName);
            string tmp = path + ".tmp";
            File.WriteAllBytes(tmp, MarshalWriter.Dump(root));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
    }

    /// <summary>An RPG Maker XP project folder.</summary>
    public class Project
    {
        public readonly string Dir;
        public AttrConfig Config;
        readonly Dictionary<string, List<DbEntry>> lists = new Dictionary<string, List<DbEntry>>();

        static readonly Dictionary<string, string> Files = new Dictionary<string, string>
        {
            { "actors", "Actors.rxdata" }, { "enemies", "Enemies.rxdata" }, { "weapons", "Weapons.rxdata" },
            { "armors", "Armors.rxdata" }, { "states", "States.rxdata" }, { "skills", "Skills.rxdata" },
            { "classes", "Classes.rxdata" }
        };

        public Project(string dir)
        {
            Dir = Path.GetFullPath(dir.TrimEnd('\\', '/'));
            Config = AttrConfig.Load(DataDir);
            ReloadNames();
        }

        public string Name { get { return Path.GetFileName(Dir); } }
        public string DataDir { get { return Path.Combine(Dir, "Data"); } }
        public string ScriptsPath { get { return Path.Combine(DataDir, "Scripts.rxdata"); } }

        public static bool IsProjectDir(string dir)
        {
            if (string.IsNullOrEmpty(dir)) return false;
            try
            {
                return File.Exists(Path.Combine(dir, "Game.rxproj")) && Directory.Exists(Path.Combine(dir, "Data"));
            }
            catch { return false; }
        }

        public bool IsSameDir(string dir)
        {
            try { return string.Equals(Path.GetFullPath(dir.TrimEnd('\\', '/')), Dir, StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }

        static int Int(object o, int def) { return RHash.IsNumber(o) ? Convert.ToInt32(o) : def; }

        public void ReloadNames()
        {
            foreach (var f in Files)
            {
                try
                {
                    var arr = MarshalReader.LoadFile(Path.Combine(DataDir, f.Value)) as List<object>;
                    if (arr == null) continue;
                    var list = new List<DbEntry>();
                    for (int i = 1; i < arr.Count; i++)
                    {
                        var o = arr[i] as RObject;
                        if (o == null) continue;
                        var e = new DbEntry { Id = i, Name = o["@name"] != null ? o["@name"].ToString() : "" };
                        e.InitialLevel = Int(o["@initial_level"], 1);
                        e.FinalLevel = Int(o["@final_level"], 99);
                        e.Scope = Int(o["@scope"], 0);
                        e.ClassId = Int(o["@class_id"], 1);
                        foreach (var k in new[] { "maxhp", "maxsp", "str", "dex", "agi", "int", "pdef", "mdef", "exp", "gold" })
                            if (o["@" + k] != null) e.Fields[k] = Int(o["@" + k], 0);
                        var t = o["@parameters"] as RUserData;
                        if (t != null && t.Data != null && t.Data.Length >= 20)
                        {
                            int xs = BitConverter.ToInt32(t.Data, 4);
                            int n = Math.Min(BitConverter.ToInt32(t.Data, 16), (t.Data.Length - 20) / 2);
                            e.ParamX = xs;
                            e.Params = new short[n];
                            for (int k = 0; k < n; k++) e.Params[k] = BitConverter.ToInt16(t.Data, 20 + 2 * k);
                        }
                        list.Add(e);
                    }
                    lists[f.Key] = list;
                }
                catch
                {
                    // File busy or unreadable: keep the previous list.
                }
            }
        }

        public DbEntry Find(string section, int id)
        {
            List<DbEntry> l;
            if (lists.TryGetValue(section, out l))
                foreach (var e in l) if (e.Id == id) return e;
            return null;
        }

        public List<DbEntry> List(string section)
        {
            List<DbEntry> l;
            return lists.TryGetValue(section, out l) ? l : new List<DbEntry>();
        }

        public void SaveConfig() { Config.Save(DataDir); }
    }

    /// <summary>Puts the game script into Data/Scripts.rxdata.</summary>
    public static class ScriptInstaller
    {
        public const string ScriptName = "Attributes";
        static readonly string[] OldNames = { "Crit Stats" };

        public enum State { NotInstalled, Outdated, Installed, Unknown }

        public static string ScriptText()
        {
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Attributes.rb"))
            using (var r = new StreamReader(s, Encoding.UTF8))
            {
                return Normalize(r.ReadToEnd()).Replace("\n", "\r\n");
            }
        }

        static string Normalize(string s) { return s.Replace("\r\n", "\n").Trim(); }

        static bool IsOurs(object o, out bool oldName)
        {
            oldName = false;
            var e = o as List<object>;
            if (e == null || e.Count < 3 || e[1] == null) return false;
            string n = e[1].ToString();
            if (n == ScriptName) return true;
            oldName = Array.IndexOf(OldNames, n) >= 0;
            return oldName;
        }

        public static State Check(Project p)
        {
            try
            {
                var arr = MarshalReader.LoadFile(p.ScriptsPath) as List<object>;
                if (arr == null) return State.Unknown;
                string ours = Normalize(ScriptText());
                foreach (object o in arr)
                {
                    bool old;
                    if (!IsOurs(o, out old)) continue;
                    if (old) return State.Outdated;
                    var code = ((List<object>)o)[2] as RString;
                    if (code == null) return State.Outdated;
                    string text = Encoding.UTF8.GetString(Zlib.Inflate(code.Bytes));
                    return Normalize(text) == ours ? State.Installed : State.Outdated;
                }
                return State.NotInstalled;
            }
            catch { return State.Unknown; }
        }

        /// <summary>Inserts or updates the script above "Main" (replacing an old "Crit Stats"). Returns the backup path.</summary>
        public static string Install(Project p)
        {
            string path = p.ScriptsPath;
            string backup = path + "." + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".bak";
            File.Copy(path, backup, true);

            var arr = (List<object>)MarshalReader.LoadFile(path);
            var code = new RString(Zlib.Deflate(Encoding.UTF8.GetBytes(ScriptText())));
            bool done = false;
            for (int i = arr.Count - 1; i >= 0; i--)
            {
                bool old;
                if (!IsOurs(arr[i], out old)) continue;
                if (done) { arr.RemoveAt(i); continue; }   // keep only one copy
                var e = (List<object>)arr[i];
                e[1] = new RString(ScriptName);
                e[2] = code;
                done = true;
            }
            if (!done)
            {
                int index = arr.Count;
                for (int i = arr.Count - 1; i >= 0; i--)
                {
                    var e = arr[i] as List<object>;
                    if (e != null && e.Count >= 2 && e[1] != null && e[1].ToString() == "Main") { index = i; break; }
                }
                arr.Insert(index, new List<object> { (long)new Random().Next(1, 99999999), new RString(ScriptName), code });
            }
            string tmp = path + ".tmp";
            File.WriteAllBytes(tmp, MarshalWriter.Dump(arr));
            File.Delete(path);
            File.Move(tmp, path);
            return backup;
        }
    }
}
