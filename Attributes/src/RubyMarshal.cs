// Minimal Ruby Marshal (format 4.8) reader/writer for RPG Maker XP data files.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace XpAttributes
{
    public sealed class RSymbol
    {
        public readonly string Name;
        public RSymbol(string name) { Name = name; }
        public override string ToString() { return ":" + Name; }
    }

    public sealed class RString
    {
        public byte[] Bytes;
        public RString(byte[] bytes) { Bytes = bytes; }
        public RString(string s) { Bytes = Encoding.UTF8.GetBytes(s); }
        public override string ToString() { return Encoding.UTF8.GetString(Bytes); }
    }

    public sealed class RObject
    {
        public string ClassName;
        public readonly Dictionary<string, object> Vars = new Dictionary<string, object>();
        public object this[string name]
        {
            get { object v; return Vars.TryGetValue(name, out v) ? v : null; }
        }
    }

    public sealed class RUserData
    {
        public string ClassName;
        public byte[] Data;
    }

    public sealed class RHash
    {
        public readonly List<KeyValuePair<object, object>> Pairs = new List<KeyValuePair<object, object>>();
        public object Default;

        public void Add(object key, object value) { Pairs.Add(new KeyValuePair<object, object>(key, value)); }

        public object Get(object key)
        {
            foreach (var p in Pairs) if (KeyEquals(p.Key, key)) return p.Value;
            return null;
        }

        public static bool IsNumber(object o) { return o is long || o is int || o is double; }

        static bool KeyEquals(object a, object b)
        {
            if (a == null || b == null) return a == b;
            if (IsNumber(a) && IsNumber(b)) return Convert.ToDouble(a) == Convert.ToDouble(b);
            if (a is RSymbol && b is RSymbol) return ((RSymbol)a).Name == ((RSymbol)b).Name;
            if ((a is RString || a is string) && (b is RString || b is string)) return a.ToString() == b.ToString();
            return a.Equals(b);
        }
    }

    public sealed class MarshalReader
    {
        readonly byte[] d;
        int pos;
        readonly List<object> objects = new List<object>();
        readonly List<string> symbols = new List<string>();

        MarshalReader(byte[] data) { d = data; }

        public static object Load(byte[] data)
        {
            if (data.Length < 2 || data[0] != 4 || data[1] != 8) throw new InvalidDataException("Not a Ruby Marshal 4.8 file");
            var r = new MarshalReader(data);
            r.pos = 2;
            return r.Read();
        }

        public static object LoadFile(string path) { return Load(File.ReadAllBytes(path)); }

        byte Byte() { return d[pos++]; }

        long Long()
        {
            sbyte c = (sbyte)Byte();
            if (c == 0) return 0;
            if (c >= 5) return c - 5;
            if (c <= -5) return c + 5;
            long x;
            if (c > 0)
            {
                x = 0;
                for (int i = 0; i < c; i++) x |= (long)Byte() << (8 * i);
                return x;
            }
            x = -1;
            for (int i = 0; i < -c; i++)
            {
                x &= ~(0xFFL << (8 * i));
                x |= (long)Byte() << (8 * i);
            }
            return x;
        }

        byte[] Bytes()
        {
            int n = (int)Long();
            var b = new byte[n];
            Array.Copy(d, pos, b, 0, n);
            pos += n;
            return b;
        }

        string Symbol()
        {
            byte t = Byte();
            if (t == ':')
            {
                string s = Encoding.UTF8.GetString(Bytes());
                symbols.Add(s);
                return s;
            }
            if (t == ';') return symbols[(int)Long()];
            if (t == 'I')
            {
                string s = Symbol();
                int n = (int)Long();
                for (int i = 0; i < n; i++) { Symbol(); Read(); }
                return s;
            }
            throw new InvalidDataException("Symbol expected at " + (pos - 1));
        }

        object Read()
        {
            byte t = Byte();
            switch ((char)t)
            {
                case '0': return null;
                case 'T': return true;
                case 'F': return false;
                case 'i': return Long();
                case ':':
                case ';':
                    pos--;
                    return new RSymbol(Symbol());
                case '@': return objects[(int)Long()];
                case 'I':
                    {
                        object o = Read();
                        int n = (int)Long();
                        for (int i = 0; i < n; i++)
                        {
                            string k = Symbol();
                            object v = Read();
                            var ro = o as RObject;
                            if (ro != null) ro.Vars[k] = v;
                        }
                        return o;
                    }
                case '"':
                    {
                        var s = new RString(Bytes());
                        objects.Add(s);
                        return s;
                    }
                case 'f':
                    {
                        string s = Encoding.ASCII.GetString(Bytes());
                        int nul = s.IndexOf('\0');
                        if (nul >= 0) s = s.Substring(0, nul);
                        double v;
                        if (s == "inf") v = double.PositiveInfinity;
                        else if (s == "-inf") v = double.NegativeInfinity;
                        else if (s == "nan") v = double.NaN;
                        else v = double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);
                        objects.Add(v);
                        return v;
                    }
                case 'l':
                    {
                        byte sign = Byte();
                        int len = (int)Long() * 2;
                        double v = 0, mul = 1;
                        for (int i = 0; i < len; i++) { v += Byte() * mul; mul *= 256; }
                        if (sign == '-') v = -v;
                        objects.Add(v);
                        return v;
                    }
                case '[':
                    {
                        var a = new List<object>();
                        objects.Add(a);
                        int n = (int)Long();
                        for (int i = 0; i < n; i++) a.Add(Read());
                        return a;
                    }
                case '{':
                case '}':
                    {
                        var h = new RHash();
                        objects.Add(h);
                        int n = (int)Long();
                        for (int i = 0; i < n; i++)
                        {
                            object k = Read();
                            object v = Read();
                            h.Add(k, v);
                        }
                        if (t == '}') h.Default = Read();
                        return h;
                    }
                case 'o':
                case 'S':
                    {
                        var o = new RObject();
                        objects.Add(o);
                        o.ClassName = Symbol();
                        int n = (int)Long();
                        for (int i = 0; i < n; i++)
                        {
                            string k = Symbol();
                            o.Vars[k] = Read();
                        }
                        return o;
                    }
                case 'u':
                    {
                        var u = new RUserData();
                        u.ClassName = Symbol();
                        u.Data = Bytes();
                        objects.Add(u);
                        return u;
                    }
                case 'U':
                    {
                        var o = new RObject();
                        objects.Add(o);
                        o.ClassName = Symbol();
                        o.Vars["__data"] = Read();
                        return o;
                    }
                case 'e':
                case 'C':
                    Symbol();
                    return Read();
                case '/':
                    {
                        var s = new RString(Bytes());
                        Byte();
                        objects.Add(s);
                        return s;
                    }
                case 'c':
                case 'm':
                case 'M':
                    {
                        var s = new RString(Bytes());
                        objects.Add(s);
                        return s;
                    }
                default:
                    throw new InvalidDataException("Unsupported Marshal type '" + (char)t + "' at " + (pos - 1));
            }
        }
    }

    public sealed class MarshalWriter
    {
        readonly MemoryStream ms = new MemoryStream();

        public static byte[] Dump(object o)
        {
            var w = new MarshalWriter();
            w.ms.WriteByte(4);
            w.ms.WriteByte(8);
            w.Write(o);
            return w.ms.ToArray();
        }

        void Long(long x)
        {
            if (x == 0) { ms.WriteByte(0); return; }
            if (x > 0 && x < 123) { ms.WriteByte((byte)(x + 5)); return; }
            if (x < 0 && x > -124) { ms.WriteByte((byte)((x - 5) & 0xFF)); return; }
            var buf = new byte[5];
            int i;
            for (i = 1; i < 5; i++)
            {
                buf[i] = (byte)(x & 0xFF);
                x >>= 8;
                if (x == 0) { buf[0] = (byte)i; break; }
                if (x == -1) { buf[0] = (byte)(-i); break; }
            }
            ms.Write(buf, 0, i + 1);
        }

        void Bytes(byte[] b)
        {
            Long(b.Length);
            ms.Write(b, 0, b.Length);
        }

        void Write(object o)
        {
            if (o == null) { ms.WriteByte((byte)'0'); return; }
            if (o is bool) { ms.WriteByte((byte)((bool)o ? 'T' : 'F')); return; }
            if (o is int || o is long)
            {
                long v = Convert.ToInt64(o);
                if (v < -(1L << 30) || v >= (1L << 30)) throw new ArgumentOutOfRangeException("Integer too large for Fixnum");
                ms.WriteByte((byte)'i');
                Long(v);
                return;
            }
            if (o is double)
            {
                double v = (double)o;
                string s;
                if (double.IsPositiveInfinity(v)) s = "inf";
                else if (double.IsNegativeInfinity(v)) s = "-inf";
                else if (double.IsNaN(v)) s = "nan";
                else s = v.ToString("R", CultureInfo.InvariantCulture);
                ms.WriteByte((byte)'f');
                Bytes(Encoding.ASCII.GetBytes(s));
                return;
            }
            if (o is string) { ms.WriteByte((byte)'"'); Bytes(Encoding.UTF8.GetBytes((string)o)); return; }
            if (o is RString) { ms.WriteByte((byte)'"'); Bytes(((RString)o).Bytes); return; }
            if (o is RSymbol) { ms.WriteByte((byte)':'); Bytes(Encoding.UTF8.GetBytes(((RSymbol)o).Name)); return; }
            var list = o as System.Collections.IList;
            if (list != null)
            {
                ms.WriteByte((byte)'[');
                Long(list.Count);
                foreach (object e in list) Write(e);
                return;
            }
            var h = o as RHash;
            if (h != null)
            {
                ms.WriteByte((byte)(h.Default == null ? '{' : '}'));
                Long(h.Pairs.Count);
                foreach (var p in h.Pairs) { Write(p.Key); Write(p.Value); }
                if (h.Default != null) Write(h.Default);
                return;
            }
            throw new ArgumentException("Cannot marshal " + o.GetType().Name);
        }
    }

    public static class Zlib
    {
        public static byte[] Inflate(byte[] data)
        {
            using (var src = new MemoryStream(data, 2, data.Length - 2))
            using (var ds = new DeflateStream(src, CompressionMode.Decompress))
            using (var o = new MemoryStream())
            {
                ds.CopyTo(o);
                return o.ToArray();
            }
        }

        public static byte[] Deflate(byte[] data)
        {
            var o = new MemoryStream();
            o.WriteByte(0x78);
            o.WriteByte(0x9C);
            using (var ds = new DeflateStream(o, CompressionMode.Compress, true)) ds.Write(data, 0, data.Length);
            uint a = 1, b = 0;
            foreach (byte x in data) { a = (a + x) % 65521; b = (b + a) % 65521; }
            uint adler = (b << 16) | a;
            o.WriteByte((byte)(adler >> 24));
            o.WriteByte((byte)(adler >> 16));
            o.WriteByte((byte)(adler >> 8));
            o.WriteByte((byte)adler);
            return o.ToArray();
        }
    }
}
