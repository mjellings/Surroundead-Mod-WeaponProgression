# WeaponProgression

A UE4SS Lua mod for **SurrounDead** that gives individual weapons their own persistent progression.

Instead of every weapon of the same type being identical, WeaponProgression tracks each physical weapon separately. Use a weapon in combat, earn XP with it, level it up, and receive permanent stat improvements that stay associated with that specific weapon.

**Version:** v0.18.5 · **Game:** SurrounDead · **Framework:** UE4SS

v0.18.5 adds **melee weapon progression** (with its own `melee.db`, F8 panel and tooltips), stops level-up rewards being wasted on capped stats, makes `data.db` recover from its backup instead of losing progress, and fixes kills being credited to the wrong gun. Dave's developer keys are now off by default. Existing `data.db` v2 files stay compatible.

---

## Features

### Individual Weapon Progression

Each physical firearm is tracked independently using its unique in-game identity.

Two weapons of the same type can therefore have completely different:

- Levels
- XP
- Kill counts
- Stat upgrades
- Mastery ranks

Switching weapons does not transfer progression between them.

### Weapon XP & Levels

Weapons earn XP through normal combat.

Progression is configurable, including:

- Base XP required per level
- XP increase per level
- Weapon XP multiplier
- Maximum weapon level

Weapon XP and levels persist between game sessions.

### Permanent Stat Upgrades

Every time a weapon levels up, it receives a permanent random stat improvement from the stats available on that weapon.

Currently supported firearm stats include:

- Damage
- Critical Hit Chance
- Critical Hit Multiplier
- Rate of Fire (RPM)
- Damage Falloff

Not every firearm contains every stat. WeaponProgression detects the stats actually available on the individual weapon and only selects from valid options.

By default, the same stat will not be selected on two consecutive level-ups when another eligible stat is available.

### Mastery Milestones

In addition to the random level-up reward, weapons can unlock fixed mastery milestones at configured levels.

Each milestone grants:

- A named rank (for example Proven I, Trusted II, Elite I)
- A deterministic bonus to a specific stat

Milestone bonuses are separate from the normal random upgrades. They are reconstructed from the weapon's level, so a weapon that reaches Level 20 always receives every milestone up to that level.

Key behaviour:

- Milestones are fully configurable in `config.ini`
- Bonuses only apply when the weapon actually has that stat
- Optional fallbacks are supported (for example RPM milestones can fall back to Damage Falloff on weapons without FirearmRPM)
- Milestone bonuses and random upgrades share the same cumulative caps
- Percentage milestone bonuses are applied from the captured original base, not compounded onto already-upgraded values

Default milestones currently run every 5 levels from Level 5 through Level 75, progressing through Proven, Trusted, Veteran, Elite, and Signature ranks.

Current rank and next-milestone information is shown on the **F8 status card**.

The normal inventory tooltip still shows the effective progression bonus beside supported weapon stats. Extra custom Level / XP / Kills / Rank tooltip rows are disabled by default for compatibility because some UE4SS builds were observed to native-crash while additional tooltip widgets were being injected.

Press **F8** while holding a tracked firearm to open the native status card. It auto-closes after a few seconds and resets that timer if you switch weapons.

### Dave's Gunsmith

Find **Dave** at the Safe Zone and press **F** to open his gunsmith screen. He can reroll a tracked firearm at **Level 5 or above** if it has ordinary progression upgrades. Rerolling redistributes those ordinary upgrades while preserving the weapon's identity, level, XP, kills and mastery bonuses. Rerolls are free in this version.

Dave uses a native QuestGiver interaction prompt. His screen closes when you walk away. His location is currently fixed by `Scripts/gunsmith/locations.lua`; random spawns and a reroll cost are future work. The development controls F5 (lower and respawn), F6 (respawn) and F7 (remove Dave) are off by default; set `DevControls=true` under `[Utility]` in `config.ini` to enable them. The standalone `NPCRerollResearch` mod is no longer needed.

### Melee Weapon Progression (experimental)

Melee weapons level up from **melee kills** with their own XP curve, stats and ranks. Melee progress is saved in `melee.db`, separately from firearms in `data.db`.

Each melee level-up rolls one of:

- **Melee Damage** +2% (the whole roll range moves, not just the lower end)
- **Stamina Cost** -3% per swing (never below `MinStaminaDrain`)
- **Critical Chance** +1
- **Critical Multiplier** +2

Melee ranks (Scrapper, Brawler, Bruiser, Executioner) add fixed bonuses, including **attack speed**: a faster swing and a shorter delay between swings. Attack speed only comes from ranks, because it is not an item stat. Everything is configured in the `[Melee]`, `[MeleeStatUpgrades]`, `[MeleeCaps]` and `[MeleeMilestones]` sections of `config.ini`, and `[Melee] Enabled=false` turns it off. F8 shows a melee weapon's level, rank and stats (Melee Dmg, Crit Mult, Crit Chance, Stamina, Attack Speed), and hovering it in the inventory shows its upgraded stats like a firearm. Dave's rerolls are firearm-only for now.

### Rolled Weapon Stats Are Preserved

SurrounDead weapons can have different base/rolled statistics.

WeaponProgression records the original values belonging to each physical weapon and calculates progression from those values rather than replacing them with generic weapon defaults.

Percentage upgrades are calculated deterministically from the original base value, avoiding cumulative floating-point drift or accidental stat compounding.

### Persistent Progression

Progression is stored by WeaponProgression and reconstructed when required.

Persisted information includes:

- Weapon identity
- Weapon name
- Level
- XP
- Kill count
- Original base statistics
- Number of upgrades applied to each stat
- Last upgraded stat
- Pending rewards

Mastery rank is derived from the weapon's level and the configured milestone table, so it does not need a separate persisted field.

This allows an upgraded physical weapon to retain its progression across full SurrounDead restarts.

### Native Level-Up Notifications

WeaponProgression uses SurrounDead's native notification UI when a weapon levels up.

For example:

> **Crusher reached Level 8 - Critical Multiplier +2**

Notifications therefore appear as part of the normal game UI rather than using a separate debug overlay.

---

## Installation

WeaponProgression requires **UE4SS**. Place the complete `WeaponProgression` folder inside:

```text
SurrounDead\Binaries\Win64\ue4ss\Mods\
```

The resulting structure should look like:

```text
ue4ss/
└── Mods/
    └── WeaponProgression/
        ├── enabled.txt
        ├── config.ini
        ├── README.md
        ├── CHANGELOG.md
        └── Scripts/
            ├── main.lua
            ├── core/
            ├── firearms/
            ├── ui/status.lua
            ├── compatibility/compatibility.lua
            └── gunsmith/
```

If you already use the mod, keep your `data.db`, `data.db.bak` and any custom `config.ini` values when replacing the files. The ZIP contains no personal database. Add `[Localization] Language=en` to an older config if you want to choose another language. WeaponProgression creates `data.db` automatically for a new installation.

---

## Configuration

Progression behaviour can be customised through `config.ini`.

### Language

In `[Localization]`, set `Language=en` (English, default), `Language=ru` (Russian), or `Language=fr` (French), then restart the game or reload the mod. The setting changes WeaponProgression's F8 card, Dave's screen, native level-up messages and milestone descriptions. Game-provided weapon names keep the game's language. Custom mastery rank names in `config.ini` display exactly as written; built-in ranks are translated for display. Unknown language codes fall back to English. Language selection does not change `data.db`.

### Stat upgrades

Default per-level random upgrade values:

| Upgrade | Default |
| --- | ---: |
| Damage | +2% |
| Critical Hit Chance | +1 |
| Critical Hit Multiplier | +2 |
| RPM | +2% |
| Damage Falloff | +2% |

### Caps

`[Caps]` sets the maximum total progression bonus above the captured original base. Caps apply to random level-up rewards and milestone bonuses combined.

Level-up rewards and Dave's rerolls only pick stats that still have room below their cap. Once every stat on a weapon is capped, further level-ups still raise its level and mastery rank but award no ordinary stat upgrade. With the default settings this happens at around level 54.

Default caps:

| Stat | Default cap |
| --- | ---: |
| Damage | +30% |
| Critical Hit Chance | +15 |
| Critical Hit Multiplier | +20 |
| RPM | +25% |
| Damage Falloff | +25% |

### Mastery milestones

The `[Milestones]` section controls fixed rank rewards.

```ini
[Milestones]
Enabled=true

; Format:
; LevelX=Rank Name|BonusType|Value
;
; Optional fallback:
; LevelX=Rank Name|BonusType|Value|FallbackBonusType

Level5=Proven I|DamagePercent|2
Level20=Trusted I|RPMPercent|3|FalloffPercent
```

Supported bonus types:

- `DamagePercent`
- `CriticalChancePoints`
- `CriticalMultiplierPoints`
- `RPMPercent`
- `FalloffPercent`

Set `Enabled=false` to disable milestones entirely while leaving the rest of progression unchanged.

These values can be customised to suit your game.

### Tooltip compatibility

The `[Utility]` section contains:

```ini
[Utility]
VerboseLogging=false
ShowProgressionTooltipRows=false
```

`ShowProgressionTooltipRows=false` is the recommended/default setting. Progression bonuses still appear beside supported weapon stats in the normal tooltip, while full Level / XP / Kills / Rank information remains available through F8.

The optional extra progression rows are currently considered experimental because native access-violation crashes were reproduced on some UE4SS builds while those additional tooltip widgets were being injected.

---

## Important: `data.db`

WeaponProgression stores per-weapon progression in:

```text
data.db
```

This file is specific to your game and is deliberately excluded from the download. Back it up before updating the mod.

WeaponProgression keeps the previous version as `data.db.bak` on every save. If `data.db` is found empty or unreadable at startup, the mod loads `data.db.bak` instead and logs `DATABASE RECOVERY`. It also refuses to save a database with fewer weapons than it loaded, so a damaged file cannot overwrite the backup.

### Resetting progression

Deleting `data.db` resets WeaponProgression's knowledge of existing weapon progression.

**After deleting or resetting `data.db`, fully restart SurrounDead before using weapons again.**

Reloading UE4SS mods alone is not sufficient for this particular operation because live weapon stats already modified during the current game session may remain in memory.

A full game restart allows SurrounDead to reconstruct the weapon's original state before WeaponProgression captures new base statistics.

For ordinary Lua/mod development, UE4SS's **Reload All Mods** functionality can still be used.

---

## Current Limitations

Known limitations include:

- Melee progression is new, so its balance may change. Dave does not reroll melee weapons yet.
- Some runtime weapon discovery operations still need performance optimisation.
- Compatibility across all SurrounDead weapons has not yet been exhaustively tested.
- Extra custom progression rows in the inventory tooltip are disabled by default for compatibility.
- Dave spawns at a fixed location and rerolls are free in this version.
- Multiplayer behaviour is not yet considered stable or supported.

Back up your progression data and saves before updating.

---

## What's next

The next development work includes in-game melee balancing, broader weapon compatibility testing, more Dave spawn locations and reroll balancing, plus runtime performance improvements. See [CHANGELOG.md](CHANGELOG.md) for the complete development history.

---

## How It Works

At a high level, WeaponProgression identifies the physical weapon involved in combat and associates progression with that weapon's unique identity.

When a weapon levels up:

```text
Combat
   ↓
Weapon identified
   ↓
XP awarded
   ↓
Weapon levels up
   ↓
Eligible random stat selected
   ↓
If level matches a milestone → fixed rank bonus applied
   ↓
Reward persisted
   ↓
Live weapon stats reconciled
   ↓
Updated value verified
   ↓
Native level-up notification displayed
```

On later game sessions, persisted upgrade counts and the weapon's level are used together with the original base statistics to reconstruct both random upgrades and milestone bonuses.

The mod deliberately avoids blindly modifying whatever weapon happens to be equipped or relying only on a weapon's type/name.

---

## Research

WeaponProgression grew out of reverse-engineering work investigating SurrounDead's Unreal Engine weapon, inventory and runtime stat systems.

Technical research and discoveries that may also be useful to other SurrounDead mod developers are maintained separately in the **surroundead-research** project.

The intention is to keep this repository focused on the actual WeaponProgression mod while keeping general reverse-engineering knowledge reusable by the wider modding community.

---

## License

**WeaponProgression — GPL-3.0**  
Copyright © 2026 Matt Jellings

WeaponProgression is free and open-source software licensed under the GNU General Public License v3.0.

You may use, modify and redistribute the mod in accordance with the GPL-3.0 licence. Modified versions distributed to others must retain the applicable licence notices and source-code obligations.

The full licence text is included in [`LICENSE`](LICENSE).

SurrounDead and associated assets are property of their respective owners. This project is unofficial and is not affiliated with or endorsed by the developers of SurrounDead.

This project does not distribute SurrounDead game assets.
