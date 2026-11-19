"""Tests the FE Tactics squads with the real RGSS engine (Game.exe) in a COPY of the project.

    python run_tests.py <project folder> <work folder>

Copies the project to <work>/game, injects status_screen.rb, levelup_screen.rb, book_menu.rb and
squad_test.rb (in place of Main), runs Game.exe, prints squad_log.txt and converts
every out_<name>.rgb to <work>/out_<name>.png. The project itself is not changed.
"""
import os, sys, shutil, subprocess, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CUSTOM = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(CUSTOM, 'StatusScreen'))
sys.path.insert(0, os.path.join(CUSTOM, 'StatusScreen', 'test'))
import inject_script as inj
from run_tests import png_write

def main():
    project, work = sys.argv[1], sys.argv[2]
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
    subprocess.check_call([py, '-I', tool, game, '--no-backup', '--force'])
    subprocess.check_call([py, '-I', tool, game, '--no-backup', '--force', '--no-pictures',
                           '--name', 'Level Up', '--after', 'Status Screen',
                           '--script', os.path.join(CUSTOM, 'LevelUp', 'levelup_screen.rb')])
    subprocess.check_call([py, '-I', tool, game, '--no-backup', '--force', '--no-pictures',
                           '--name', 'Book Menu', '--after', 'Level Up',
                           '--script', os.path.join(CUSTOM, 'BookMenu', 'book_menu.rb')])
    subprocess.check_call([py, '-I', tool, game, '--no-backup', '--force', '--no-pictures',
                           '--name', 'FE Tactics',
                           '--script', os.path.join(CUSTOM, 'FETactics', 'fe_tactics.rb')])
    path = os.path.join(game, 'Data', 'Scripts.rxdata')
    scripts = inj.load_scripts(path)
    src = open(os.path.join(HERE, 'squad_test.rb'), 'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
    for s in scripts:
        if s[1] == b'Main': s[1] = b'SquadTest'; s[2] = zlib.compress(src)
    print('order:', [s[1].decode() for s in scripts][-5:])
    open(path, 'wb').write(inj.dump_scripts(scripts))
    for f in os.listdir(work):
        if f.startswith('out_'): os.remove(os.path.join(work, f))
    subprocess.run([os.path.join(game, 'Game.exe')], cwd=game, timeout=600)
    print(open(os.path.join(game, 'squad_log.txt'), encoding='utf-8', errors='replace').read())
    for f in sorted(os.listdir(game)):
        if f.startswith('out_') and f.endswith('.rgb'):
            png_write(os.path.join(work, f[:-4] + '.png'), 640, 480, open(os.path.join(game, f), 'rb').read())

if __name__ == '__main__':
    main()
