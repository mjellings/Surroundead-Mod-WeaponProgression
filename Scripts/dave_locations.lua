-- ============================================================================
-- WeaponProgression - Dave development spawn locations
--
-- DEVELOPMENT FILE
--
-- TestLocation:
--   Set this to the location number you want Dave to use during testing.
--   Reload the WeaponProgression Lua scripts, then press F6 to respawn Dave.
--
-- ZOffset:
--   Dave's BP_QuestGiver actor origin is ~80 Unreal units above his feet.
--   Keep this at -80.0 unless future testing proves otherwise.
--
-- Locations:
--   Use the RAW F9 coordinates from NPCLocationResearch here.
--   Do NOT manually subtract 80 from Z; gunsmith.lua applies ZOffset for you.
--
-- For the public 0.19 release we can fold/obscure these coordinates and choose
-- a spawn randomly so this file does not become a convenient treasure map.
-- ============================================================================

return {
    ZOffset = -80.0,

    -- Change this while testing:
    -- 1 = Safe Zone
    -- 2 = Fishing Lodge
    TestLocation = 1,

    Locations = {
        {
            Name = "Safe Zone",
            X = 113972.8,
            Y = 132500.1,
            Z = 1269.2,
            Pitch = 0.0,
            Yaw = -14.2,
            Roll = 0.0,
        },

        {
            Name = "Fishing Lodge",
            X = 89134.4,
            Y = 193073.4,
            Z = 1185.6,
            Pitch = 0.0,
            Yaw = -3.1,
            Roll = 0.0,
        },

        -- Add future locations below using the same format:
        --
        -- {
        --     Name = "Example Location",
        --     X = 0.0,
        --     Y = 0.0,
        --     Z = 0.0,
        --     Pitch = 0.0,
        --     Yaw = 0.0,
        --     Roll = 0.0,
        -- },
    },
}
