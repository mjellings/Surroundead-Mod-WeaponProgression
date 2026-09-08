# Changelog

This file records the significant development milestones for WeaponProgression.

The project is still in pre-release development, so older entries include research builds that established behaviour later retained by the current mod.

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
