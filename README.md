# WeaponProgression

A UE4SS Lua mod for **SurrounDead** that gives individual weapons their own persistent progression.

Instead of every weapon of the same type being identical, WeaponProgression tracks each physical weapon separately. Use a weapon in combat, earn XP with it, level it up, and receive permanent stat improvements that stay associated with that specific weapon.

> **Current status:** Early development / testing  
> **Current stable baseline:** v0.15.0  
> **In development:** v0.17.0-dev1 (mastery milestones)  
> **Game:** SurrounDead  
> **Framework:** UE4SS

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

Current rank and next milestone are shown in:

- The inventory tooltip (Rank / Next)
- The F8 status card (rank, next rank, and next bonus)

Press **F8** while holding a tracked firearm to open the native status card. It auto-closes after a few seconds and resets that timer if you switch weapons.

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

WeaponProgression requires **UE4SS**.

Place the `WeaponProgression` folder inside:

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
        └── Scripts/
            ├── main.lua
            └── ui.lua
```

WeaponProgression will create its progression database automatically when required.

---

## Configuration

Progression behaviour can be customised through `config.ini`.

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

These values are subject to balancing while the mod remains in development.

---

## Important: `data.db`

WeaponProgression stores per-weapon progression in:

```text
data.db
```

This file is specific to your game and is deliberately excluded from this repository.

### Resetting progression

Deleting `data.db` resets WeaponProgression's knowledge of existing weapon progression.

**After deleting or resetting `data.db`, fully restart SurrounDead before using weapons again.**

Reloading UE4SS mods alone is not sufficient for this particular operation because live weapon stats already modified during the current game session may remain in memory.

A full game restart allows SurrounDead to reconstruct the weapon's original state before WeaponProgression captures new base statistics.

For ordinary Lua/mod development, UE4SS's **Reload All Mods** functionality can still be used.

---

## Current Limitations

WeaponProgression is still under active development.

Known limitations currently include:

- **Melee weapons are not supported.**
- Progression currently focuses on firearms.
- Some runtime weapon discovery operations still need performance optimisation.
- Compatibility across all SurrounDead weapons has not yet been exhaustively tested.
- The persistence format may change during development.
- Multiplayer behaviour has not yet been considered stable or supported.

Back up your saves when testing development versions.

---

## Development Status

### v0.15.0 — Current Stable Baseline

v0.15.0 is the current known-working release. It builds on the proven v0.13.0 progression core (per-weapon XP, permanent upgrades, persistence, and native level-up notifications), with later additions including live weapon caching (v0.14.0) and native inventory tooltip display of weapon level, XP, and kills.

v0.15.0 is being retained as the known-working baseline while further development continues.

### v0.17.0-dev1 — In Development

Current development work adds configurable mastery milestones on top of the v0.15.x / v0.16.x progression and status UI core.

New in this line of work:

- Configurable mastery ranks and fixed milestone bonuses
- Deterministic milestone reconstruction from weapon level
- Shared cumulative caps across random upgrades and milestones
- Tooltip Rank / Next rows
- F8 status card showing current rank, next milestone, and next bonus

---

## Planned Work

Areas currently being investigated include:

- Runtime performance improvements and safer weapon caching
- Melee weapon support
- Additional weapon/stat types
- Milestone balancing and additional bonus types
- More notification configuration
- Database migrations and backups
- Broader weapon compatibility testing
- Reduced development/debug logging

Longer-term progression systems may also include greater player choice over weapon upgrades.

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

## Disclaimer

WeaponProgression is an unofficial community mod and is not affiliated with or endorsed by the developer or publisher of SurrounDead.

SurrounDead and its associated names and assets belong to their respective owners.

This project does not distribute SurrounDead game assets.

---

## License

A licence has not yet been selected.

Until one is added, please do not assume that the absence of a licence grants permission to redistribute or incorporate the source into other projects.