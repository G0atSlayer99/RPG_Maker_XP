"""Puts status_screen.rb into an RPG Maker XP project as the script "Status Screen".

    python inject_script.py <project folder> [--script file.rb] [--name "Status Screen"]
                            [--before Main] [--no-pictures] [--no-backup]

- Refuses to run while RPG Maker XP is open (it would overwrite Scripts.rxdata on save).
- Backs up Data/Scripts.rxdata to Data/Scripts.rxdata.<timestamp>.bak first (never overwrites a backup).
- Replaces an existing script of the same name, otherwise inserts it right after "Windowskin"
  (or before --before, default "Main").
- Copies StatusBook.png / StatusBookIcons.png into Graphics/Pictures (existing files are backed up).
- Reads the file back and checks every script survived unchanged.
"""
import os, sys, zlib, random, shutil, subprocess, time, argparse

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- Ruby Marshal (just what Scripts.rxdata uses)

class Reader:
    def __init__(self, data):
        if data[:2] != b'\x04\x08': raise ValueError('not a Ruby Marshal 4.8 file')
        self.b = data; self.i = 2; self.syms = []
    def byte(self):
        v = self.b[self.i]; self.i += 1; return v
    def long(self):
        c = self.byte()
        if c > 127: c -= 256
        if c == 0: return 0
        if 5 <= c <= 127: return c - 5
        if -128 <= c <= -5: return c + 5
        n = abs(c); v = 0
        for k in range(n): v |= self.byte() << (8 * k)
        if c < 0: v -= 1 << (8 * n)
        return v
    def raw(self):
        n = self.long(); s = self.b[self.i:self.i + n]; self.i += n; return s
    def sym(self):
        t = chr(self.byte())
        if t == ':': s = self.raw(); self.syms.append(s); return s
        if t == ';': return self.syms[self.long()]
        raise ValueError('symbol expected, got ' + t)
    def read(self):
        t = chr(self.byte())
        if t == '[': return [self.read() for _ in range(self.long())]
        if t == 'i': return self.long()
        if t == 'l':
            sign = chr(self.byte()); n = self.long() * 2
            v = int.from_bytes(self.b[self.i:self.i + n], 'little'); self.i += n
            return -v if sign == '-' else v
        if t == '"': return self.raw()
        if t == 'I':   # string with instance variables (encoding): keep the bytes only
            v = self.read()
            for _ in range(self.long()): self.sym(); self.read()
            return v
        if t == '0': return None
        raise ValueError('unexpected type %r at %d' % (t, self.i - 1))

def w_long(n):
    if n == 0: return b'\x00'
    if 0 < n < 123: return bytes([n + 5])
    if -124 < n < 0: return bytes([(n - 5) & 0xff])
    for k in range(1, 5):
        if -(1 << (8 * k - 1)) <= n < (1 << (8 * k - 1)) or (n > 0 and n < (1 << (8 * k))):
            break
    if n > 0:
        out = n.to_bytes(k, 'little'); return bytes([k]) + out
    out = (n + (1 << (8 * k))).to_bytes(k, 'little'); return bytes([256 - k]) + out

def w(o):
    if isinstance(o, list): return b'[' + w_long(len(o)) + b''.join(w(x) for x in o)
    if isinstance(o, bytes): return b'"' + w_long(len(o)) + o
    if isinstance(o, int):
        if -(1 << 30) <= o < (1 << 30): return b'i' + w_long(o)
        mag = abs(o); n = (mag.bit_length() + 15) // 16
        return b'l' + (b'-' if o < 0 else b'+') + w_long(n) + mag.to_bytes(n * 2, 'little')
    raise TypeError(type(o))

def load_scripts(path):
    return Reader(open(path, 'rb').read()).read()

def dump_scripts(scripts):
    return b'\x04\x08' + w(scripts)

# ---------------------------------------------------------------- helpers

def rpgxp_running():
    # tasklist prints in the console code page (German umlauts), so read bytes.
    out = subprocess.run(['tasklist', '/NH', '/FO', 'CSV', '/FI', 'IMAGENAME eq RPGXP.exe'], capture_output=True).stdout
    return b'"rpgxp.exe"' in out.lower()

def backup(path):
    stamp = time.strftime('%Y%m%d-%H%M%S')
    dest = '%s.%s.bak' % (path, stamp); n = 1
    while os.path.exists(dest):
        n += 1; dest = '%s.%s-%d.bak' % (path, stamp, n)
    shutil.copy2(path, dest)
    return dest

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('project')
    ap.add_argument('--script', default=os.path.join(HERE, 'status_screen.rb'))
    ap.add_argument('--name', default='Status Screen')
    ap.add_argument('--after', default='Windowskin')
    ap.add_argument('--before', default='Main')
    ap.add_argument('--pictures', default=os.path.join(HERE, 'pictures'))
    ap.add_argument('--no-pictures', action='store_true')
    ap.add_argument('--no-backup', action='store_true')
    ap.add_argument('--force', action='store_true', help='write even if RPG Maker XP is running')
    a = ap.parse_args()

    path = os.path.join(a.project, 'Data', 'Scripts.rxdata')
    if not os.path.isfile(path): sys.exit('not found: ' + path)
    if rpgxp_running() and not a.force:
        sys.exit('RPG Maker XP is open. Close it first, otherwise it overwrites Scripts.rxdata when you save.')

    src = open(a.script, 'rb').read().decode('utf-8')
    src = src.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8')
    name = a.name.encode('utf-8')

    scripts = load_scripts(path)
    before = [(s[0], s[1], zlib.decompress(s[2])) for s in scripts]
    names = [s[1] for s in scripts]
    ids = set(s[0] for s in scripts)
    entry_code = zlib.compress(src)

    if name in names:
        i = names.index(name); scripts[i][2] = entry_code; action = 'replaced'
    else:
        sid = random.randint(1, 99999999)
        while sid in ids: sid = random.randint(1, 99999999)
        if a.after.encode() in names: i = names.index(a.after.encode()) + 1
        elif a.before.encode() in names: i = names.index(a.before.encode())
        else: i = len(scripts)
        if a.before.encode() in names: i = min(i, names.index(a.before.encode()))
        scripts.insert(i, [sid, name, entry_code]); action = 'inserted at position %d' % i

    if not a.no_backup: print('backup:', backup(path))
    tmp = path + '.tmp'
    open(tmp, 'wb').write(dump_scripts(scripts))
    os.replace(tmp, path)

    # Round trip: everything else unchanged, the new script readable
    after = [(s[0], s[1], zlib.decompress(s[2])) for s in load_scripts(path)]
    others = [x for x in after if x[1] != name]
    if others != [x for x in before if x[1] != name]: sys.exit('ROUND TRIP FAILED: other scripts changed')
    mine = [x for x in after if x[1] == name]
    if len(mine) != 1 or mine[0][2] != src: sys.exit('ROUND TRIP FAILED: script text differs')
    print('%s "%s" (%d bytes); order: %s' % (action, a.name, len(src), ' > '.join(x[1].decode('utf-8', 'replace') for x in after[-5:])))

    if not a.no_pictures:
        pics = os.path.join(a.project, 'Graphics', 'Pictures')
        os.makedirs(pics, exist_ok=True)
        for f in ('StatusBook.png', 'StatusBookIcons.png'):
            dst = os.path.join(pics, f); s = os.path.join(a.pictures, f)
            if os.path.exists(dst) and open(dst, 'rb').read() != open(s, 'rb').read():
                print('backup:', backup(dst))
            shutil.copy2(s, dst)
        print('pictures copied to', pics)

if __name__ == '__main__':
    main()
