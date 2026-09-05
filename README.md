# WeaponProgression

A UE4SS Lua mod for **SurrounDead** that gives individual weapons their own persistent progression.

Instead of every weapon of the same type being identical, WeaponProgression tracks each physical weapon separately. Use a weapon in combat, earn XP with it, level it up, and receive permanent stat improvements that stay associated with that specific weapon.

> **Current status:** Early development / testing  
> **Current stable baseline:** v0.13.0  
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
            └── main.lua
```

WeaponProgression will create its progression database automatically when required.

---

## Configuration

Progression behaviour can be customised through `config.ini`.

Current configurable values include weapon XP progression and the strength of individual stat upgrades.

Default upgrade values are currently:

| Upgrade | Default |
| --- | ---: |
| Damage | +2% |
| Critical Hit Chance | +1 |
| Critical Hit Multiplier | +2 |
| RPM | +2% |
| Damage Falloff | +2% |

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

### v0.13.0 — Stable Core Baseline

v0.13.0 represents the first version where the core progression architecture has been successfully tested across multiple physical firearms and full game restarts.

Testing has demonstrated:

- Independent physical weapon identification
- Multiple weapons progressing simultaneously
- Independent XP and kill tracking
- Variable firearm stat sets
- Permanent stat upgrades
- Preservation of original rolled statistics
- Deterministic stat reconstruction
- Progression persistence across full game restarts
- Live stat mutation
- Post-mutation verification
- Native SurrounDead level-up notifications
- Weapon switching without progression crossing between weapons

v0.13.0 is being retained as the known-working baseline while further development continues.

---

## Planned Work

Areas currently being investigated include:

- Runtime performance improvements and safer weapon caching
- Melee weapon support
- Additional weapon/stat types
- Improved progression/status UI
- More notification configuration
- Database migrations and backups
- Additional configuration options
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
Eligible stat selected
   ↓
Reward persisted
   ↓
Live weapon stat updated
   ↓
Updated value verified
   ↓
Native level-up notification displayed
```

On later game sessions, persisted upgrade counts are used together with the weapon's original base statistics to reconstruct the correct upgraded values.

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