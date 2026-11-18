"""Renders the Status screen test cases with the real RGSS engine (Game.exe) in a COPY of the project.

    python run_tests.py <project folder> <work folder>

Copies the project to <work>/game, injects status_screen.rb plus render_cases.rb (in place of Main),
runs Game.exe, converts every out_<case>.rgb to PNG and builds side_by_side.png (reference | render).
"""
import os, sys, shutil, subprocess, zlib, struct

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import inject_script as inj

def png_write(path, w, h, rgb):
    raw = b''.join(b'\x00' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, c): return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

def main():
    project, work = sys.argv[1], sys.argv[2]
    test_script = sys.argv[3] if len(sys.argv) > 3 else 'render_cases.rb'
    game = os.path.join(work, 'game')
    if os.path.exists(game): shutil.rmtree(game)
    os.makedirs(game)
    for f in os.listdir(project):
        s = os.path.join(project, f)
        if os.path.isdir(s):
            if f in ('Data', 'Graphics', 'Audio'): shutil.copytree(s, os.path.join(game, f))
        elif f.lower().endswith(('.exe', '.dll', '.ini', '.rxproj')):
            shutil.copy2(s, game)
    py = sys.executable
    sd = os.path.dirname(HERE)
    subprocess.check_call([py, '-I', os.path.join(sd, 'inject_script.py'), game, '--no-backup', '--force'])
    # test script replaces Main in the copy
    path = os.path.join(game, 'Data', 'Scripts.rxdata')
    scripts = inj.load_scripts(path)
    src = open(os.path.join(HERE, test_script), 'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
    for s in scripts:
        if s[1] == b'Main': s[1] = b'RenderCases'; s[2] = zlib.compress(src)
    open(path, 'wb').write(inj.dump_scripts(scripts))
    for f in os.listdir(work):
        if f.startswith('out_'): os.remove(os.path.join(work, f))
    subprocess.run([os.path.join(game, 'Game.exe')], cwd=game, timeout=300)
    print(open(os.path.join(game, 'render_log.txt'), encoding='utf-8', errors='replace').read())
    for f in sorted(os.listdir(game)):
        if f.startswith('out_') and f.endswith('.rgb'):
            rgb = open(os.path.join(game, f), 'rb').read()
            png_write(os.path.join(work, f[:-4] + '.png'), 640, 480, rgb)

if __name__ == '__main__':
    main()
