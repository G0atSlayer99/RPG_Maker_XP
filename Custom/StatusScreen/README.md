# Status Screen (book style)

Replaces the default Status screen of the Soulbond project with an open book
(German texts, database stays English).

| File | What it is |
|---|---|
| `status_screen.rb` | The game script ("Status Screen"), RGSS1 / Ruby 1.8.1 |
| `make_statusbook.cs` | Draws the static artwork with GDI+ (4x supersampled) |
| `pictures/StatusBook.png` | 640x480 background: cover, pages, ribbon, rings, badge, boxes, bar frames |
| `pictures/StatusBookIcons.png` | 90x18 equipment icons: weapon, shield, helmet, body armor, accessory |
| `inject_script.py` | Puts the script into `Data\Scripts.rxdata` and copies the pictures |
| `test/run_tests.py` | Renders test cases with the real engine (Game.exe) in a copy of the project |
| `test/render_cases.rb` | The test cases (reference actor, every actor, states, accessory, long names, level 100, 0 HP, no equipment, crit) |
| `old/` | The StatusBook pictures of an earlier attempt, kept for reference |

## Install / update

Close RPG Maker XP first (it overwrites `Scripts.rxdata` when you save).

```
python inject_script.py "C:\Users\sasch\OneDrive\Desktop\Soulbond"
```

- Backs up `Data\Scripts.rxdata` to `Scripts.rxdata.<date-time>.bak` (never overwrites a backup).
- Inserts "Status Screen" after "Windowskin", before "Main" (or replaces it on later runs).
- Copies the two pictures to `Graphics\Pictures` (a different existing file is backed up first).
- Reads the file back and checks all other scripts are unchanged.

## Rebuild the artwork

```
%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe /nologo /out:make_statusbook.exe /r:System.Drawing.dll make_statusbook.cs
make_statusbook.exe pictures
```

## Test

```
python test\run_tests.py "C:\Users\sasch\OneDrive\Desktop\Soulbond" <work folder>
```

Writes `out_<case>.png` into the work folder. The project itself is not touched.

## Data shown

| Screen | Source |
|---|---|
| Str / Mg / Spd / Luck / Def / Res | STR / INT / AGI / DEX / PDEF / MDEF (with equipment); bars up to 100 |
| Move | Attributes `attr_move`, else `FE_Config::ACTOR_MOVE[class]` / `DEFAULT_MOVE`; bar up to 25 |
| CrtR / CrtD | Attributes `crit_rate` (%) / `crit_damage` (100 = x2) |
| KP / SP | HP / SP |
| EXP | current / needed for the next level, "Max. Level" at the cap |
| Status | state with the highest rating (rating >= 1), "Normal" if none |
| Ausrüstung | weapon, shield, helmet, body armor; "Accessoire" row only if one is equipped |

Class and state names: `CLASS_NAMES` / `STATE_NAMES` at the top of the script.
Face crops: `FACE_RECTS` ("battler file" => [x, y, size]).

## Undo

Restore the backup made by the installer (RPG Maker XP closed):
`Data\Scripts.rxdata.<date-time>.bak` -> `Data\Scripts.rxdata`,
or delete the "Status Screen" script in the Script Editor (F11).
The pictures in `Graphics\Pictures` can stay; nothing else uses them.
