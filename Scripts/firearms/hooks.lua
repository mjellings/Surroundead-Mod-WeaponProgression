-- WeaponProgression firearm hook manifest.
-- Keeps hook ownership separate from bootstrap/lifecycle registration.
local M = {}

function M.Build(paths, callbacks)
    return {
        {"GET_EQUIPMENT_UID", paths.GET_EQUIPMENT_UID, callbacks.on_get_equipment_uid},
        {"GET_ACTIVE_WEAPON", paths.GET_ACTIVE_WEAPON, callbacks.ui_on_get_active_weapon},
        {"GET_ACTIVE_SLOT",   paths.GET_ACTIVE_WEAPON_SLOT, callbacks.ui_on_get_active_weapon_slot},
        {"GET_EQUIPPED_REF",  paths.GET_EQUIPPED_ITEM_REF, callbacks.ui_on_get_equipped_item_ref},
        {"JIG_TRY_ADD",       paths.JIG_TRY_ADD, callbacks.on_inventory_add_cache_invalidate},
        {"TOOLTIP_UPDATE",    paths.TOOLTIP_UPDATE, callbacks.on_tooltip_update},
        {"STAT_W_CONSTRUCT",  paths.STAT_W_CONSTRUCT, callbacks.on_stat_w_construct},
        {"ADD_XP",            paths.ADD_XP, callbacks.on_add_xp},
        {"ZOMBIE_DEATH",      paths.DEATH, callbacks.on_death},
        {"SERVER_DAMAGE",     paths.SERVER_DAMAGE, callbacks.on_server_damage},
    }
end

return M
