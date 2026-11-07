# WeaponProgression offline tests

These tests run the real mod code (`Scripts/main.lua` and every module it loads) in plain Lua 5.4. SurrounDead and UE4SS are replaced with a small fake game, so you can check the progression logic in a couple of seconds without launching the game.

## Running

1. Install Lua 5.4 once. On Windows, run `winget install DEVCOM.Lua` in a terminal, or download `lua-5.4.x_Win64_bin.zip` from LuaBinaries and put `lua54.exe` on your PATH.
2. From the mod folder, run:

```
lua tests/run_tests.lua
```

Each test prints `PASS` or `FAIL` with the reason. The command exits with code 1 if anything fails.

- `lua tests/run_tests.lua caps` runs only the tests whose name contains "caps".
- Set `WP_TEST_VERBOSE=1` to see the mod's own log lines while the tests run. In PowerShell that's `$env:WP_TEST_VERBOSE=1`.
- Set `WP_MOD_ROOT` to a folder containing `Scripts/` and `config.ini` to test a different copy of the mod. For example, testing the RC2 folder shows the 12 tests that cover the bugs fixed in v0.18.5 failing.

The tests never touch your real `data.db` or `config.ini`. Each simulated game session gets its own scratch folder under `tests/.sandbox/`. That folder can be deleted at any time and should not ship in the release zip (and neither should `tests/`).

## What's covered

| File | What it checks |
| --- | --- |
| `test_progression_rules.lua` | The XP curve, `[LevelThresholds]`, percent and point stat maths, milestones and their RPM to falloff fallback, caps, and which stat a level-up may pick |
| `test_kills_and_levels.lua` | Base stat capture on first shot, kill XP and the multiplier, level-ups with overflow, several level-ups from one kill, kill attribution (wrong zombie, non-kill XP, duplicate events), MaxLevel, and weapons tracked separately |
| `test_rewards_and_caps.lua` | Live stat writes on level-up, toast text, no repeated stat, no RPM on weapons without it, milestone bonuses applied live, caps held all the way to level 100, no wasted upgrades, and pending rewards paid out |
| `test_restart_and_save.lua` | Saving after every kill, saved upgrades re-applied after a restart (without re-capturing boosted stats as bases), and recovery from a crash-emptied `data.db` |
| `test_gunsmith.lua` | Dave's reroll: level 5 minimum, held-weapon check, level, XP and kills kept, live stats following the new rolls, and over-capped legacy weapons trimmed |
| `test_persistence.lua` | `data.db` round-trip, `.bak` rotation and fallback, refusing to save fewer records than were loaded, and a failed write leaving files intact |

## How the fake game works (`lib/fake_game.lua`)

`H.new_game{ config = {...} }` writes a sandbox `config.ini` (your shipped `config.ini` with any overrides merged in), then `game:boot()` loads `main.lua` with fake versions of `RegisterHook`, `ExecuteWithDelay`, `StaticFindObject`, `FindAllOf` and the rest. Hook registration retries and timers run on a fake clock, so they finish instantly.

`game:add_weapon{ name = "M2010", stats = { damage = 100, rpm = 600, ... } }` creates a fake inventory slot with those stats. Then:

- `weapon:equip()` fires the equip and active-weapon hooks, as switching to the weapon does.
- `weapon:kill(xp)` fires `AddXP`, then the zombie's `Death`, then the killing shot's `SERVER_DamageEvent`, in the order the game does.
- `weapon:hit()` damages without killing.
- `weapon:stat("damage")` gives the live value after any `UpdateStatByUID` writes.
- `weapon:record()` reads the weapon's row back from the sandbox `data.db`.
- `game.toasts`, `game.logs`, `game:awarded()` and `game:has_log("...")` show what the player would have seen.
- `game:restart()` simulates a full game restart: weapons go back to their original stats and the mod reloads from the same `data.db`.
- `game:seed_db{...}` writes a `data.db` before boot, for legacy or edge-case records.
- `game.gunsmith.Reroll(uid)` and `game.gunsmith.GetSnapshot()` are the same functions `main.lua` hands to Dave's UI.

Dave's spawning and UI (`gunsmith/gunsmith.lua`), the F8 panel and the tooltip widgets need the real game. They are stubbed out here and still need in-game checks. Stat randomness is seeded, so a run is repeatable.

To add a test, put a `test("what it checks", function() ... end)` in one of the files (or a new file listed in `run_tests.lua`), using `eq`, `near` and `ok` for assertions.
