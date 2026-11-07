# Changelog

Major changes to WeaponProgression are listed below. Earlier development checkpoints are retained for troubleshooting and research.

## v0.18.5 — Melee progression, capped-stat fix and database safety

Release summary (details in the development entries below):

- **Melee progression.** Melee weapons now level up from kills with their own XP curve, ranks and stat rolls (Melee Damage, Stamina Cost, Critical Chance, Critical Multiplier), plus attack speed from ranks. Progress is saved in a separate `melee.db` and configured in the new `[Melee]`, `[MeleeStatUpgrades]`, `[MeleeCaps]` and `[MeleeMilestones]` sections of `config.ini`. F8 and the inventory hover tooltip show melee stats like firearms.
- **No more wasted upgrades.** Level-up rewards and Dave's rerolls skip stats that are already at their cap.
- **Safer `data.db`.** An emptied or truncated `data.db` is recovered from `data.db.bak`, and a save that would lose weapons is refused.
- **Correct kill credit.** Kills go to the gun that fired, not to whichever slot the game queried last.
- **Dave's F5/F6/F7 developer keys are off by default** (`[Utility] DevControls=true` turns them on).
- The mod no longer fails to load when UE4SS does not report its folder.
- `data.db` v2 format and existing config keys are unchanged. Update by replacing the mod folder; keep your `data.db` (and `melee.db` if you have one).

## v0.18.5-dev4 — Melee in F8 and tooltips

- F8 now shows melee weapons: level, XP, rank, next rank and its bonus, and the stat rows Melee Dmg, Crit Mult, Crit Chance, Stamina and Attack Speed (base → current, with the bonus). Previously it said "no firearm progression". Firearm rows keep their own labels.
- Hovering a tracked melee weapon in the inventory now shows its upgraded stats with the bonus, like firearms (for example `7.5 (-6%)` for Stamina Cost). Small values keep one decimal so a stamina reduction is visible.
- Stamina Cost bonuses show as a percentage (`-6%`) instead of points.
- The F8 panel refreshes after a melee hit while it is open.
- 7 new offline tests (75 total); the test harness can now read the F8 state and simulate an inventory hover.

## v0.18.5-dev3 — Melee progression

- Added melee weapon progression (`Scripts/melee/melee_progression.lua`). Melee kills are detected from `BP_MeleePickup_C:HitHead`/`HitBody` after the zombie's `Death`, only while the melee slot is active. Melee weapons have their own XP curve, stat rolls (Melee Damage, Stamina Cost, Critical Chance, Critical Multiplier), caps and ranks, and are saved in a separate `melee.db`. Firearm progression and `data.db` are unchanged.
- Melee damage upgrades keep the stat's roll range: after `UpdateStatByUID` (which writes one value to both ends), the upper end is restored to the upgraded value and read back.
- Stamina Cost is a new lower-is-better stat mode (`reduce`) with a `MinStaminaDrain` floor.
- Attack speed comes from `AttackSpeedPercent` melee ranks and is applied to the pickup's swing speed and swing delay from the captured defaults, so it never compounds.
- New config sections: `[Melee]`, `[MeleeStatUpgrades]`, `[MeleeCaps]`, `[MeleeMilestones]`. New melee strings in English, Russian and French.
- `core/persistence.lua` now builds independent stores from a column schema; `data.db` keeps the exact same format.
- 16 new offline tests (68 total). Melee still needs in-game verification, especially the roll-range write and attack speed.

## v0.18.5-dev2 — Capped-stat rewards, database safety, kill credit and dev keys

- Level-up rewards no longer roll stats that are already at their `[Caps]` limit (including milestone bonuses). Previously the upgrade was counted, clamped to the cap, and still announced, so it was wasted.
- When every captured stat on a weapon is capped, a level-up is logged as `STAT UPGRADE SKIPPED` and awards nothing. It is not banked as a pending reward. Levels, ranks and milestones are unchanged.
- Dave's rerolls only place rolls on stats with room below their cap. Rolls that could not improve anything are dropped, so the first reroll on an over-capped weapon removes its wasted upgrades.
- `data.db` loading falls back to `data.db.bak` when `data.db` is present but has no readable records (e.g. emptied or truncated by a crash), and logs `DATABASE RECOVERY`. Unreadable lines are counted in a `DATABASE WARNING`.
- `data.db` saving now refuses to write fewer weapon records than were loaded (records are never deleted at runtime), and checks every write and the file close before replacing `data.db`. A failed write leaves `data.db` and `data.db.bak` untouched.
- Kill credit: a kill is now credited to the UID whose saved record is the same weapon model as the firearm that fired, picked from the last few UIDs the game reported. Previously it went to whichever equipment slot was queried last, which could credit (and rename) another tracked gun. When no recent UID matches and the latest one belongs to a different tracked weapon, the kill is not credited and `KILL CREDIT MISMATCH` is logged once.
- Dave's F5/F6/F7 developer keys are now off by default. Set `DevControls=true` under `[Utility]` in `config.ini` to enable them.
- If UE4SS does not report `main.lua`'s path, the mod now falls back to the usual `Mods/WeaponProgression` locations and logs `MOD DIR` instead of failing to load.
- Added an offline test suite (`tests/`, not shipped in the release zip). It runs the real `main.lua` against a fake UE4SS/SurrounDead layer and covers kills, XP, level-ups, rewards, milestones, caps, restarts, Dave's rerolls and `data.db` safety. Run it with `lua tests/run_tests.lua`; see `tests/README.md`.
- No change to the `data.db` v2 format or config keys. All 52 offline tests pass at dev2; in-game verification is still required.

## v0.18.4-rc2 — Game-thread crash hotfix candidate

- Moved delayed stat verification onto the game thread after a report of an access violation on UE4SS's async thread shortly after firearm level-up. The reported address and timing suggest this path, but the crash dump has not yet been examined.
- Moved delayed level-up notifications, tooltip updates, and core and Dave hook-registration retries onto the game thread when they access Unreal objects or UE4SS registration APIs.
- No intended changes to firearm progression rules, Dave's rerolls, language selection, config defaults, or the `data.db` v2 format. In-game verification is still required.

## v0.18.4-rc1 — Release candidate

- Introduced Dave's native `[F]` gunsmith interaction at the configured Safe Zone spawn. Tracked Level 5+ firearms can reroll their ordinary stat upgrades for free while keeping weapon identity, level, XP, kills and mastery bonuses.
- Preserved existing `data.db` v2 records and firearm progression while splitting the runtime into focused core, firearm, UI, compatibility and gunsmith modules.
- Added selectable English, Russian and French mod UI text through `[Localization] Language`.
- Delayed the first core Blueprint hook registration pass to avoid early-startup stack-trace noise; late-loading hooks continue to retry.
- Kept the extra tooltip progression rows disabled by default because they can crash some UE4SS builds. F8 remains the full progression view.
- Firearm progression and the quiet-startup build were tested in game. Dave's interaction and the Russian/French layouts were subsequently checked before publication.

### Development checkpoints

#### v0.18.4-dev11a5.2 — French and Russian localisation

- Wired the existing `[Localization] Language` option into the runtime. English remains the default; `ru` and `fr` now select Russian and French strings, with unsupported values falling back to English.
- Translated the F8 status card, Dave's gunsmith UI and reroll messages, level-up notifications, and milestone bonus descriptions. Built-in milestone names are translated for display; user-authored rank names and saved data stay unchanged.
- Kept gameplay rules, firearm event attribution, stat mutation, persistence, hook registration, and Dave's spawning behaviour unchanged.
- Test checkpoint based on the runtime-proven dev11a5.1 build. French and Russian display still require in-game verification, especially Cyrillic glyph rendering and text fit.

#### v0.18.4-dev11a5.1 — Quiet startup hook registration

- Based directly on dev11a5; no firearm event/progression behavior changes.
- Defers the first core hook-registration pass by 6 seconds so Blueprint UFunctions can finish initialising before `RegisterHook` is called.
- Prevents the normal early-startup `UFunction::Func: 0x0` registration window from flooding UE4SS with misleading Lua stack traces.
- Existing retry lifecycle remains active for genuinely late-loading Blueprints.
- Tested in game on the author's gaming PC: normal firearm progression and upgrades worked. Dave was not visited during this checkpoint.


#### v0.18.4-dev11a5 — Firearm event boundary

- Based directly on the runtime-proven dev11a4 baseline.
- Added `Scripts/firearms/events.lua` for transient damage/death attribution state and kill-to-progression orchestration.
- Kept hook lifecycle, resolver/stat mutation, UI/tooltip, Dave and persistence responsibilities in their existing modules.
- No intended gameplay, balance, database, UI, Dave or reroll changes.
- This checkpoint was superseded by the game-tested dev11a5.1 build.


#### v0.18.4-dev11a4 — Resolver and live stat boundary

- Extracted live firearm/JSI resolution and transient UObject cache ownership into `Scripts/firearms/resolver.lua`.
- Extracted native stat mutation, delayed verification and reconciliation into `Scripts/firearms/stats.lua`.
- Retains the proven richest-populated duplicate-slot selection policy.
- Retains fresh live stat-entry reacquisition immediately before `UpdateStatByUID`.
- No intended gameplay, balance, database, UI, Dave or reroll changes.
- Test checkpoint based on runtime-proven dev11a3.


#### v0.18.4-dev11a3 — Firearm responsibility split
- Extracted pure firearm progression policy into `Scripts/firearms/progression.lua`.
- Extracted native firearm level-up notifications into `Scripts/firearms/notifications.lua`.
- Extracted the firearm/UI hook manifest into `Scripts/firearms/hooks.lua`.
- Kept live Unreal resolver/stat mutation code in `main.lua` for a later isolated checkpoint.
- No intended gameplay, balance, persistence, Dave, reroll, F8, tooltip, or DB-format changes.

#### v0.18.4-dev11a2 — Persistence and hook lifecycle split

- Continued the tested dev11a1 structural refactor.
- Moved data.db v2 load/save/recovery into `Scripts/core/persistence.lua`.
- Moved delayed Blueprint hook registration/retry/compatibility gating into `Scripts/core/hook_lifecycle.lua`.
- No intentional firearm progression, balance, UI, Dave, reroll, or database-format changes.

#### v0.18.4-dev11a1 — Dave recovery hook startup

- Made Dave's two recovery hooks register independently and retry quietly when their Blueprint functions load late.
- Kept firearm progression, Dave interaction, rerolls and `data.db` v2 unchanged.

#### v0.18.4-dev11a — Architecture checkpoint

- Derived from the runtime-tested Dev10 baseline.
- No intentional firearm gameplay or balance changes.
- Split F8 UI, compatibility, localisation, and Dave into responsibility-based subfolders.
- Kept firearm runtime in `main.lua` for this checkpoint to minimise regression risk.
- Preserved `data.db` v2 compatibility and Dave reroll behaviour.
- Prepared the source tree for the next firearm/melee/localisation modularisation pass.

#### v0.18.4-dev10 — Integrated stability checkpoint

- Combined Dave's lifetime and recovery safeguards with fresh stat-entry reacquisition, player Jig resolution at mutation time and deferred native level-up notification.
- Kept firearm balance and the existing `data.db` format. Added the initial English/Russian localisation dictionary without routing the UI through it yet.

## Earlier releases and research

### v0.18.4-dev7

- Integrated the experimental Dave gunsmith NPC directly into WeaponProgression.
- Removed the temporary file-based bridge between NPCRerollResearch and WeaponProgression; gunsmith state and rerolls now use direct in-memory callbacks.
- Added a native `[F] Dave` interaction prompt by updating the QuestGiver `Name` / interaction fields on the spawned NPC.
- Added the dedicated `gunsmith.lua` and `gunsmith_ui.lua` modules.
- Added free reroll testing for Level 5+ tracked firearms while preserving weapon level, XP, kills, identity and mastery.
- Added automatic UI close when the player walks away from Dave.
- Added development controls:
  - `F5` lowers the current test spawn by 10 Unreal units and respawns Dave.
  - `F6` destroys and respawns Dave.
  - `F7` removes Dave.
- Added `dave_locations.lua` for named development spawn points and a shared `ZOffset`.
- Confirmed a QuestGiver actor-origin offset of approximately `-80` Unreal units for ground placement.
- Added the initial Safe Zone and Fishing Lodge development locations.
- The standalone `NPCRerollResearch` mod is no longer required for integrated testing.

### v0.18.3

- Added a tooltip compatibility release based on multi-user crash investigation.
- Stopped reading/converting live tooltip `FText` values where WeaponProgression already had authoritative numeric/stat data.
- Stopped inspecting unrelated item stat widgets unless a tracked firearm tooltip context is active.
- Kept progression bonus values visible directly in the normal weapon stat rows.
- Disabled the custom Level / XP / Kills / Rank tooltip rows by default after they were linked to native access-violation crashes on some UE4SS builds.
- Added `ShowProgressionTooltipRows=false` under `[Utility]`.
- Full progression information remains available through the F8 status card.
- Existing `data.db` progression files remain compatible.

### v0.18.2-dev1 / dev2 / dev3

- Investigated native crashes triggered while hovering items with additional tooltip rows.
- Identified that the original generic `BP_StatW_C:Construct` hook touched bags, food, healing items and other non-weapon stat widgets before confirming a firearm tooltip context.
- Added an early tooltip-context guard, resolving crashes for non-weapon items in affected installations.
- Removed live `FText` reads from the tracked-firearm stat formatting path.
- Added detailed diagnostic breadcrumbs around weapon tooltip resolution, stat-row writes and custom progression-row injection.
- Isolated the remaining native crash boundary to the custom progression-row injection path.
- Disabled that path by default, retaining F8 as the safe detailed progression view.

### v0.18.1

- Added compatibility/retry handling for Blueprint tooltip hook registration.
- Improved startup behaviour on systems where tooltip Blueprint classes were not immediately available.


## v0.17.0-dev1

- Added configurable mastery milestones and named ranks.
- Added deterministic milestone bonuses derived from weapon level.
- Added cumulative caps shared by ordinary upgrades and milestone bonuses.
- Added Rank / Next information to the inventory tooltip.
- Added mastery rank, next milestone and next bonus to the F8 status card.

## v0.16.x

### v0.16.0-dev3

- Refined the standalone native UMG status card.
- Added aligned progression stats, divider styling and a native XP progress bar.

### v0.16.0-dev2

- Stabilised the active physical weapon UID used by the UI during combat callbacks.
- Added three-second automatic status-card close.
- Weapon switching restarts the close timer.

### v0.16.0-dev1

- Integrated the reusable `ui.lua` module.
- Added the F8 status card using active-slot to physical-weapon UID mapping.

## v0.15.x

### v0.15.1

- Improved database replacement and recovery safety.
- Made the player Jig cache lifecycle-safe.
- Added dynamic mod-path discovery.
- Reduced routine production logging.
- Removed obsolete tooltip probes and hooks.

### v0.15.0

- Added the production native weapon tooltip.
- Added rounded bonus-stat display plus weapon Level, XP percentage and Kills.

### v0.15.0-dev9

- Added one-decimal tooltip formatting and native Level / XP / Kills rows.

### v0.15.0-dev

- Added the initial read-only `OnHoverTooltipWidget.Update` investigation and hovered physical-slot identity research.

## v0.14.x

### v0.14.0

- Added the production live-weapon cache with populated-slot selection and lifecycle-safe fallback.

### v0.14.0-dev3

- Preferred GUID-matching `JSI_Slot_C` instances with populated firearm `ItemStats`.
- Rejected zero-stat duplicate/stub slots.

### v0.14.0-dev2

- Invalidated cached weapon slots when inventory re-adds the same physical GUID.
- Reacquired a fresh live representation after relevant lifecycle changes.

### v0.14.0-dev

- Added validation and reuse of cached live `JSI_Slot_C` weapon slots before a full scan.

## v0.13.x

### v0.13.0

- Added production native weapon level-up notifications.
- Removed notification research/probe hooks from the production path.

## v0.12.x

### v0.12.10

- Proved safe custom Unreal `FText` creation through `KismetTextLibrary:Conv_StringToText`.
- Visually confirmed custom native SurrounDead notifications.

### v0.12.9

- Retained verification debounce and used only live vanilla `FText` wrappers for synchronous native notification passthrough.

### v0.12.8

- Added duplicate stat-verification debounce.
- Established that passing a Lua string directly where native code expects `FText` can crash UE4SS.

### v0.12.7

- Added a read-only synchronous `S_NotificationDetails` structure probe.

### v0.12.6

- Confirmed the vanilla notification route through `GameFunctionLibrary:CreateNotificationUI` and `HUD_Game:Notification`.

### v0.12.5

- Tested and rejected the player-character notification hook as a way to observe the vanilla XP toast.

### v0.12.4

- Added persistent per-physical-weapon stat upgrades owned by WeaponProgression's `data.db`.

## v0.11.x

### v0.11.3

- Confirmed generic primary, secondary and sidearm live-stat resolution.

### v0.11.2

- Removed a leftover Crusher-specific call site from the generic resolver path.

### v0.11.1

- Confirmed direct `BP_PlayerCharacter.BP_JigMultiplayer` resolution and removed the pickup dependency.

### v0.11.0

- Confirmed controlled `FirearmDamage` runtime mutation with live read-back.

## v0.10.x

### v0.10.9

- Found the exact physical weapon's live stats by scanning `JSI_Slot_C` instances by `ItemUniqueID`.

### v0.10.8

- Established that UObject identity calls against stale `FindItemByUID` results can native-crash UE4SS.

### v0.10.7

- Retired unsafe raw UObject-anatomy probing after native instability.

### v0.10.6

- Confirmed that a stale `FindItemByUID` result could resolve the correct physical GUID while exposing empty `ItemStats`.

### v0.10.5

- Confirmed that the cooked inventory route could resolve equipment UID through `BP_JigMultiplayer + FindItemByUID`.

### v0.10.4

- Confirmed the player's `BP_JigMultiplayer` context.

### v0.10.3

- Tested and rejected a broad JigComponent scan as an authoritative physical-weapon resolver.

### v0.10.2

- Tested and rejected the inventory-pickup route for reliably observing an existing dropped/re-picked weapon.

### v0.10.1

- Safely aborted the first mutation attempt after identifying an incorrect live-slot context with empty `ItemStats`.

### v0.10.0

- Added configurable weapon XP multiplier and progression curve.

## v0.9.x

### v0.9.9

- Confirmed escalating XP thresholds, overflow XP and restart persistence.

### v0.9.8a

- Added delayed hook registration and immediate database creation.

### v0.9.8

- Integrated the early progression path and identified timing/lifecycle issues that drove later resolver work.

### v0.9.5

- Initial successful progression data collection and early runtime experiments.
