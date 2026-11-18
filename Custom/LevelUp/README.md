# Level Up screen

Fire Emblem style level-up screen for Soulbond (RGSS1). One screen per level, queued per actor,
shown on the map. Only actors edited in the Attributes panel (class growth) get it.

- `levelup_screen.rb` – the "Level Up" script (below "Status Screen", above "Main").
  Sounds, keys (`SKIP_KEYS`), timing and colours are constants at the top.
- Needs "Attributes" (class growth rolls) and "Status Screen" (`StatusBook.round_face`, fonts).

## Install (RPG Maker XP must be closed)

```
python -I ..\StatusScreen\inject_script.py <project> --no-pictures --name "Level Up" --after "Status Screen" --script levelup_screen.rb
```

A timestamped `Scripts.rxdata.*.bak` is written first.

## Test

```
python -I test\run_tests.py <project> <work folder>
```

Runs the real Game.exe on a copy of the project with `test/levelup_test.rb` in place of Main
(per-level log, animation timeline with simulated keys, Change EXP + Show Text on the real map)
and writes `out_*.png` composites to the work folder. The test EXP gains only happen in the copy.
