"""Tests the Battle UI with the real RGSS engine (Game.exe) in a COPY of the project.

    python run_tests.py <project folder> <work folder> [test script]

Copies the project to <work>/game, injects Attributes, FE Tactics, Status Screen,
Level Up, Book Menu and Battle UI from this repository, puts the test script
(default: battle_test.rb) in place of Main, runs Game.exe, prints the log
(<name>_log.txt) and converts every out_<name>.rgb to <work>/out_<name>.png.
The project itself is not changed.
"""
import os, sys, shutil, subprocess, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CUSTOM = os.path.dirname(os.path.dirname(HERE))
ROOT = os.path.dirname(CUSTOM)
sys.path.insert(0, os.path.join(CUSTOM, 'StatusScreen'))
sys.path.insert(0, os.path.join(CUSTOM, 'StatusScreen', 'test'))
import inject_script as inj
from run_tests import png_write

SCRIPTS = [  # name, after, file
    ('Attributes', None, os.path.join(ROOT, 'Attributes', 'Attributes.rb')),
    ('FE Tactics', None, os.path.join(CUSTOM, 'FETactics', 'fe_tactics.rb')),
    ('Status Screen', None, None),
    ('Level Up', 'Status Screen', os.path.join(CUSTOM, 'LevelUp', 'levelup_screen.rb')),
    ('Book Menu', 'Level Up', os.path.join(CUSTOM, 'BookMenu', 'book_menu.rb')),
    ('Battle UI', 'Book Menu', os.path.join(CUSTOM, 'BattleUI', 'battle_ui.rb')),
]

def main():
    project, work = sys.argv[1], sys.argv[2]
    test = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, 'battle_test.rb')
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
    tool = os.path.join(CUSTOM, 'StatusScreen', 'inject_script.py')
    for name, after, path in SCRIPTS:
        args = [py, '-I', tool, game, '--no-backup', '--force']
        if path is not None:
            args += ['--no-pictures', '--name', name, '--script', path]
            if after: args += ['--after', after]
        subprocess.check_call(args, stdout=subprocess.DEVNULL)
    path = os.path.join(game, 'Data', 'Scripts.rxdata')
    scripts = inj.load_scripts(path)
    src = open(test, 'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
    for s in scripts:
        if s[1] == b'Main': s[1] = b'Test'; s[2] = zlib.compress(src)
    print('order:', [s[1].decode() for s in scripts][-8:])
    open(path, 'wb').write(inj.dump_scripts(scripts))
    for f in os.listdir(work):
        if f.startswith('out_'): os.remove(os.path.join(work, f))
    subprocess.run([os.path.join(game, 'Game.exe')], cwd=game, timeout=900)
    for f in sorted(os.listdir(game)):
        if f.endswith('_log.txt'):
            print(open(os.path.join(game, f), encoding='utf-8', errors='replace').read())
    for f in sorted(os.listdir(game)):
        if f.startswith('out_') and f.endswith('.rgb'):
            png_write(os.path.join(work, f[:-4] + '.png'), 640, 480, open(os.path.join(game, f), 'rb').read())

if __name__ == '__main__':
    main()
