using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

namespace XpAttributes
{
    /// <summary>Reads the state of RPG Maker XP's Database dialog (read-only).</summary>
    public static class Win32
    {
        // Control IDs from RPGXP.exe's dialog resources.
        public const int DatabaseTabId = 3101;   // SysTabControl32 in the "Database" dialog
        public const int EntryListId = 1014;     // ListBox on each Database page

        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr h, int id);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int index);
        [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, int msg, IntPtr w, IntPtr l, int flags, int timeout, out IntPtr result);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
        static extern IntPtr SendMessageTimeoutText(IntPtr h, int msg, IntPtr w, StringBuilder l, int flags, int timeout, out IntPtr result);
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);

        const int SMTO_ABORTIFHUNG = 2;
        const int LB_GETTEXT = 0x189, LB_GETTEXTLEN = 0x18A, LB_GETCURSEL = 0x188;
        const int TCM_GETCURSEL = 0x130B;

        static string ClassOf(IntPtr h)
        {
            var s = new StringBuilder(64);
            GetClassName(h, s, 64);
            return s.ToString();
        }

        public static int ProcessOf(IntPtr h)
        {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            return (int)pid;
        }

        static long Send(IntPtr h, int msg, int w)
        {
            IntPtr r;
            if (SendMessageTimeout(h, msg, (IntPtr)w, IntPtr.Zero, SMTO_ABORTIFHUNG, 200, out r) == IntPtr.Zero) return -1;
            return r.ToInt64();
        }

        /// <summary>Finds a visible Database dialog that belongs to one of the given processes.</summary>
        public static IntPtr FindDatabase(int[] pids, out int pid)
        {
            IntPtr found = IntPtr.Zero;
            int foundPid = 0;
            if (pids.Length > 0)
            {
                EnumWindows((h, l) =>
                {
                    if (!IsWindowVisible(h)) return true;
                    int p = ProcessOf(h);
                    if (Array.IndexOf(pids, p) < 0) return true;
                    if (ClassOf(h) != "#32770") return true;
                    IntPtr tab = GetDlgItem(h, DatabaseTabId);
                    if (tab == IntPtr.Zero || ClassOf(tab) != "SysTabControl32") return true;
                    found = h;
                    foundPid = p;
                    return false;
                }, IntPtr.Zero);
            }
            pid = foundPid;
            return found;
        }

        public static bool Alive(IntPtr h) { return h != IntPtr.Zero && IsWindow(h) && IsWindowVisible(h); }

        public static int GetTabIndex(IntPtr db)
        {
            IntPtr tab = GetDlgItem(db, DatabaseTabId);
            return tab == IntPtr.Zero ? -1 : (int)Send(tab, TCM_GETCURSEL, 0);
        }

        /// <summary>The entry ListBox of the page that is currently shown.</summary>
        public static IntPtr GetVisibleEntryList(IntPtr db)
        {
            IntPtr found = IntPtr.Zero;
            EnumChildWindows(db, (h, l) =>
            {
                if (GetDlgCtrlID(h) == EntryListId && IsWindowVisible(h) && ClassOf(h) == "ListBox")
                {
                    found = h;
                    return false;
                }
                return true;
            }, IntPtr.Zero);
            return found;
        }

        public static int GetSelection(IntPtr list)
        {
            return list == IntPtr.Zero ? -1 : (int)Send(list, LB_GETCURSEL, 0);
        }

        /// <summary>Text of a list item (e.g. "002: Basil"), or null if it can't be read.</summary>
        public static string GetItemText(IntPtr list, int index)
        {
            if (list == IntPtr.Zero || index < 0) return null;
            int style = GetWindowLong(list, -16);
            bool ownerDraw = (style & 0x30) != 0;      // LBS_OWNERDRAWFIXED | LBS_OWNERDRAWVARIABLE
            bool hasStrings = (style & 0x40) != 0;     // LBS_HASSTRINGS
            if (ownerDraw && !hasStrings) return null;
            long len = Send(list, LB_GETTEXTLEN, index);
            if (len <= 0 || len > 1000) return null;
            var sb = new StringBuilder((int)len + 2);
            IntPtr r;
            if (SendMessageTimeoutText(list, LB_GETTEXT, (IntPtr)index, sb, SMTO_ABORTIFHUNG, 200, out r) == IntPtr.Zero) return null;
            return sb.ToString();
        }

        /// <summary>Visible window bounds (without the invisible resize border).</summary>
        public static Rectangle GetFrame(IntPtr h)
        {
            RECT r;
            if (DwmGetWindowAttribute(h, 9 /* DWMWA_EXTENDED_FRAME_BOUNDS */, out r, Marshal.SizeOf(typeof(RECT))) != 0)
                GetWindowRect(h, out r);
            return Rectangle.FromLTRB(r.L, r.T, r.R, r.B);
        }

        public static Rectangle GetWindowBounds(IntPtr h)
        {
            RECT r;
            GetWindowRect(h, out r);
            return Rectangle.FromLTRB(r.L, r.T, r.R, r.B);
        }

        // ---- Current directory of another (32-bit) process = RPGXP's open project ----

        [StructLayout(LayoutKind.Sequential)]
        struct PBI
        {
            public IntPtr ExitStatus, PebBaseAddress, AffinityMask, BasePriority, UniqueProcessId, InheritedFromUniqueProcessId;
        }
        [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out int read);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

        static byte[] ReadMem(IntPtr proc, IntPtr addr, int size)
        {
            var b = new byte[size];
            int read;
            if (!ReadProcessMemory(proc, addr, b, size, out read) || read != size) return null;
            return b;
        }

        public static string GetProcessCurrentDirectory(int pid)
        {
            if (IntPtr.Size != 4) return null;   // this layout is for a 32-bit build reading a 32-bit process
            IntPtr h = OpenProcess(0x0400 | 0x0010, false, pid);   // QUERY_INFORMATION | VM_READ
            if (h == IntPtr.Zero) return null;
            try
            {
                var pbi = new PBI();
                int ret;
                if (NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), out ret) != 0) return null;
                byte[] b = ReadMem(h, IntPtr.Add(pbi.PebBaseAddress, 0x10), 4);           // PEB.ProcessParameters
                if (b == null) return null;
                IntPtr parameters = new IntPtr(BitConverter.ToInt32(b, 0));
                byte[] us = ReadMem(h, IntPtr.Add(parameters, 0x24), 8);                   // CurrentDirectory.DosPath
                if (us == null) return null;
                int len = BitConverter.ToUInt16(us, 0);
                IntPtr buf = new IntPtr(BitConverter.ToInt32(us, 4));
                if (len <= 0 || len > 4096) return null;
                byte[] s = ReadMem(h, buf, len);
                return s == null ? null : Encoding.Unicode.GetString(s);
            }
            catch { return null; }
            finally { CloseHandle(h); }
        }
    }
}
