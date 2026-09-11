WeaponProgression v0.18.4-dev7 - Integrated Dave development build

Current development state
-------------------------
Dave is now integrated directly into WeaponProgression.

The old standalone NPCRerollResearch mod should be disabled while testing this build.

Integrated gunsmith
--------------------
- Native interaction prompt displays: [F] Dave
- Custom Dave's Gunsmith UI
- Held-weapon/progression state is read directly from WeaponProgression memory
- No temporary active_weapon.api / reroll.request file bridge
- Level 5+ eligibility check
- Free reroll testing for now
- Rerolls redistribute ordinary random progression upgrades
- Level, XP, kills, weapon identity and mastery are preserved
- UI closes when the player walks more than ~5m away

Development spawn locations
---------------------------
Spawn research currently uses:

    Scripts/dave_locations.lua

That file contains:
- ZOffset=-80.0
- TestLocation=<index>
- Named development locations
- Raw F9 coordinates captured with NPCLocationResearch

Current locations:
1. Safe Zone
2. Fishing Lodge

Development controls
--------------------
F5 = lower the selected test spawn by another 10 Unreal units and respawn Dave
F6 = destroy and respawn Dave at the selected test location
F7 = remove/unload Dave

Current ground-placement research
---------------------------------
BP_QuestGiver_C uses an actor origin approximately 80 Unreal units above the NPC's feet.

For development we therefore keep raw player/ground coordinates in dave_locations.lua and apply:

    ActualDaveZ = RawLocationZ + ZOffset

with:

    ZOffset = -80.0

Production plan
---------------
For v0.19, the friendly named development location file is expected to be folded into the production code (or otherwise obscured) so it does not become an obvious treasure map.

The production build should choose from verified Dave locations automatically rather than use TestLocation.
