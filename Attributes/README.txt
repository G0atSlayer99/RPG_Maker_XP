Attributes for RPG Maker XP
===========================

An "Attributes" panel that docks next to the Database window and adds settings the
Database doesn't have:

  Actors     Name, Class, Level / Max level (up to 100) / EXP per level-up,
             HP, SP, Str, Mg, Crtr, CrtD, Spd, Luck, Def, Res, Move:
             a value at level 1 and a value at the max level
  Enemies    Crit Rate / Crit Damage
  Weapons    crit bonus while equipped
  Armors     crit bonus while equipped
  States     crit bonus while the state is active
  Skills     critical hits (can crit, extra rate / damage)
             range in tiles            (FE Tactics)
             targeting: default / single target / area of effect
               area: radius (1 = 3x3), shape (square, diamond, cross), friendly fire
  System     defaults, max crit damage, Status screen labels, game script install

Crit Rate   = chance of a critical hit, 0 - 100 %
Crit Damage = extra damage of a critical hit in %   (100 % = double damage)

Actors page
-----------
An actor that was never edited shows its Database values (name, class, levels,
MaxHP/MaxSP/STR/INT/AGI/DEX at level 1 and at the final level, clamped to the
ranges below) and keeps using the Database in the game. The first edit stores all
values; "Reset to defaults" removes them again.

  HP   1 - 10000  -> MaxHP (the game caps MaxHP at 9999)
  SP   1 - 1000   -> MaxSP
  Str  1 - 100    -> STR        Mg   1 - 100 -> INT
  Spd  1 - 100    -> AGI        Luck 1 - 100 -> DEX
  Def  1 - 100    -> added to PDEF
  Res  1 - 100    -> added to MDEF
  Crtr 0 - 100 %  -> Crit Rate  CrtD (100 % = x2) -> Crit Damage
  Move 1 - 25     -> FE Tactics move points
  Level, Max level (1 - 100), EXP / level-up (every level-up needs the same EXP)

Level 1 value <= max level value, Level <= Max level: the field you change wins.
Levels in between: until the level-up system exists, every level below the max
level uses the level 1 value and the max level uses the max level value.


1. Start the editor together with RPG Maker XP (once)
------------------------------------------------------
Steam > Library > RPG Maker XP > right-click > Properties > General > Launch Options:

  "E:\SteamLibrary\steamapps\common\RPGXP\Attributes\AttributesEditor.exe" %command%

(If you used the earlier "Crit Stats" version, replace its launch option with this one.)
Starting RPG Maker XP from Steam now also starts the editor, which waits in the tray
(red "A" icon) and closes when RPG Maker XP closes.


2. Install the game scripts (once per project)
----------------------------------------------
a) Attributes: close RPG Maker XP, right-click the tray icon >
   "Install / update game script...". It adds "Attributes" above "Main"
   (replacing an old "Crit Stats" entry) and keeps a backup
   (Data\Scripts.rxdata.<date>.bak).
   While RPG Maker XP is open, use "Copy game script to clipboard" instead and paste it
   into the Script Editor (F11): right-click "Main" > Insert, name it "Attributes".
b) FE Tactics: replace the old "FE Tactics" script with the updated FE_Tactics.rb.


3. Use it
---------
Open the Database (F9). The panel follows the selected tab and entry and hides when
the Database closes. Changes are saved immediately to Data\Attributes.rxdata
(Cancel in the Database does not undo them). Old crit values from
Data\CritConfig.rxdata are taken over automatically.

FE Tactics, area-of-effect skills: after choosing the skill, move the cursor to any
tile inside the red/green range; the orange area shows what gets hit, the forecast
shows "Units hit". C casts, B goes back. Enemies use the same skills and avoid
hitting their own units with friendly fire.

Script calls (Event > Script...):
  $game_actors[1].crit_rate_plus   += 5    permanent +5 % crit rate
  $game_actors[1].crit_damage_plus += 25   permanent +25 % crit damage
  Attributes.get("skills", 7, "range_max") any value set in the panel (nil if not set)
  Attributes.actor_stat(1, "hp")           [level 1 value, max level value] (nil if not edited)


Files
-----
  AttributesEditor.exe  the editor (needs only .NET Framework 4, built into Windows)
  Attributes.rb         the game script (also built into the .exe)
  src\, build.bat       source code; run build.bat to rebuild the .exe
