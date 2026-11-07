-- User-facing text only. Database and configuration values stay language-independent.
local L = {}
local packs = {
    en = {
        weapon_progression="WEAPON PROGRESSION", level="LEVEL", xp="XP", kills="Kills", rank="Rank", weapon_stats="WEAPON STATS",
        damage="Damage", crit_mult="Crit Mult", crit_chance="Crit Chance", rpm="RPM", falloff="Falloff",
        critical_multiplier="Critical Multiplier", critical_chance="Critical Chance", damage_falloff="Damage Falloff",
        melee_damage="Melee Damage", stamina_cost="Stamina Cost",
        melee_dmg_short="Melee Dmg", stamina_short="Stamina", attack_speed="Attack Speed",
        next="NEXT", max="MAX", no_active_weapon="No active weapon", unranked="UNRANKED", max_rank="MAX RANK",
        no_progression_data="No progression data", no_firearm_progression="No firearm progression",
        resolving_weapon="Resolving weapon...", unknown_weapon="Unknown", no_stat_bonus="No applicable stat bonus",
        level_up="%s reached Level %d - %s", dave_title="DAVE'S GUNSMITH",
        unknown_weapon_upper="UNKNOWN WEAPON", untracked_weapon="UNTRACKED WEAPON",
        free_reroll="FREE REROLL", reroll="REROLL",
        reroll_explanation="Redistributes ordinary progression bonuses.\nLevel, XP, kills and mastery are preserved.",
        reroll_explanation_count="Redistributes %d ordinary progression bonuses.\nLevel, XP, kills and mastery are preserved.",
        dave_no_weapon="Alright?\nI can't help much if you aren't holding a firearm.",
        dave_unresolved="I can see it, but I can't identify this weapon yet.\nTry switching weapons and give me another look.",
        dave_untracked="I don't know this one yet.\nUse it a little and come back.",
        dave_low_level="Not enough history on this one yet.\nCome back when it reaches Level 5.",
        reroll_unavailable="I can't reroll this weapon right now.",
        reroll_level_required="This weapon must reach Level 5\nbefore I can reroll it.",
        reroll_no_bonuses="This weapon has no ordinary progression bonuses\nto reroll.",
        rerolling="Rerolling...", reroll_success="Reroll successful.\nNew progression stats are shown above.",
        reroll_failed="Reroll failed.", reroll_no_stats="No eligible captured firearm stats",
        reroll_no_rolls="No ordinary progression rolls to reroll", reroll_no_uid="No physical weapon UID was supplied",
        reroll_weapon_changed="The held weapon changed before reroll could be applied",
        reroll_record_missing="Weapon progression record not found", reroll_min_level="Weapon must be Level 5 or higher",
        reroll_no_rewards="No ordinary progression bonuses are available to reroll",
        reroll_same_distribution="Reroll produced no different stat distribution",
        reroll_save_failed="Database save failed; original progression was restored",
        rank_proven="Proven", rank_trusted="Trusted", rank_veteran="Veteran",
        rank_elite="Elite", rank_signature="Signature",
    },
    ru = {
        weapon_progression="ПРОГРЕСС ОРУЖИЯ", level="УРОВЕНЬ", xp="ОПЫТ", kills="Убийства", rank="Ранг", weapon_stats="ХАРАКТЕРИСТИКИ",
        damage="Урон", crit_mult="Крит. множитель", crit_chance="Шанс крита", rpm="Темп стрельбы", falloff="Падение урона",
        critical_multiplier="Множитель крит. урона", critical_chance="Шанс крит. удара", damage_falloff="Падение урона",
        melee_damage="Урон в ближнем бою", stamina_cost="Расход выносливости",
        melee_dmg_short="Урон", stamina_short="Выносливость", attack_speed="Скорость атаки",
        next="ДАЛЕЕ", max="МАКС.", no_active_weapon="Нет оружия в руках", unranked="БЕЗ РАНГА", max_rank="МАКС. РАНГ",
        no_progression_data="Нет данных о прогрессе", no_firearm_progression="Для ближнего боя нет прогресса",
        resolving_weapon="Определение оружия...", unknown_weapon="Неизвестно", no_stat_bonus="Нет подходящего бонуса",
        level_up="%s: уровень %d — %s", dave_title="ОРУЖЕЙНИК ДЭЙВ",
        unknown_weapon_upper="НЕИЗВЕСТНОЕ ОРУЖИЕ", untracked_weapon="ОРУЖИЕ НЕ ОТСЛЕЖИВАЕТСЯ",
        free_reroll="БЕСПЛАТНЫЙ ПЕРЕРОЛЛ", reroll="ПЕРЕРОЛЛ",
        reroll_explanation="Перераспределяет обычные бонусы.\nУровень, опыт, убийства и ранг сохраняются.",
        reroll_explanation_count="Перераспределяет обычные бонусы (%d).\nУровень, опыт, убийства и ранг сохраняются.",
        dave_no_weapon="Привет!\nВозьми огнестрельное оружие, и я помогу.",
        dave_unresolved="Вижу оружие, но пока не могу его определить.\nСмени оружие и попробуй снова.",
        dave_untracked="Это оружие мне пока незнакомо.\nПопользуйся им и возвращайся.",
        dave_low_level="Оружие ещё недостаточно изучено.\nВозвращайся на 5-м уровне.",
        reroll_unavailable="Сейчас нельзя перераспределить бонусы.",
        reroll_level_required="Для перераспределения нужен\n5-й уровень оружия.",
        reroll_no_bonuses="Нет обычных бонусов\nдля перераспределения.",
        rerolling="Перераспределение...", reroll_success="Готово!\nНовые характеристики показаны выше.",
        reroll_failed="Не удалось перераспределить бонусы.", reroll_no_stats="Нет доступных характеристик оружия",
        reroll_no_rolls="Нет обычных бонусов для перераспределения", reroll_no_uid="Не указан идентификатор оружия",
        reroll_weapon_changed="Оружие в руках сменилось до перераспределения",
        reroll_record_missing="Данные о прогрессе оружия не найдены", reroll_min_level="Оружие должно достичь 5-го уровня",
        reroll_no_rewards="Нет обычных бонусов для перераспределения",
        reroll_same_distribution="Характеристики после перераспределения не изменились",
        reroll_save_failed="Не удалось сохранить данные; прежние бонусы восстановлены",
        rank_proven="Проверенный", rank_trusted="Надёжный", rank_veteran="Ветеран",
        rank_elite="Элита", rank_signature="Легенда",
    },
    fr = {
        weapon_progression="PROGRESSION DES ARMES", level="NIVEAU", xp="XP", kills="Éliminations", rank="Rang", weapon_stats="STATISTIQUES",
        damage="Dégâts", crit_mult="Mult. critique", crit_chance="Chance crit.", rpm="Cadence", falloff="Perte de dégâts",
        critical_multiplier="Multiplicateur critique", critical_chance="Chance de critique", damage_falloff="Perte de dégâts",
        melee_damage="Dégâts de mêlée", stamina_cost="Coût d'endurance",
        melee_dmg_short="Dégâts mêlée", stamina_short="Endurance", attack_speed="Vitesse d'attaque",
        next="SUIVANT", max="MAX.", no_active_weapon="Aucune arme en main", unranked="SANS RANG", max_rank="RANG MAX.",
        no_progression_data="Aucune donnée de progression", no_firearm_progression="Pas de progression d'arme à feu",
        resolving_weapon="Identification de l'arme...", unknown_weapon="Inconnue", no_stat_bonus="Aucun bonus applicable",
        level_up="%s atteint le niveau %d - %s", dave_title="L'ARMURERIE DE DAVE",
        unknown_weapon_upper="ARME INCONNUE", untracked_weapon="ARME NON SUIVIE",
        free_reroll="RELANCE GRATUITE", reroll="RELANCER",
        reroll_explanation="Redistribue les bonus ordinaires.\nNiveau, XP, éliminations et maîtrise conservés.",
        reroll_explanation_count="Redistribue %d bonus ordinaires.\nNiveau, XP, éliminations et maîtrise conservés.",
        dave_no_weapon="Salut !\nPrends une arme à feu et je pourrai t'aider.",
        dave_unresolved="Je vois ton arme, mais je ne peux pas l'identifier.\nChange d'arme et réessaie.",
        dave_untracked="Je ne connais pas encore cette arme.\nUtilise-la un peu et reviens.",
        dave_low_level="Je ne connais pas assez cette arme.\nReviens quand elle atteint le niveau 5.",
        reroll_unavailable="Je ne peux pas relancer cette arme maintenant.",
        reroll_level_required="Cette arme doit atteindre le niveau 5\navant la relance.",
        reroll_no_bonuses="Cette arme n'a aucun bonus ordinaire\nà redistribuer.",
        rerolling="Relance en cours...", reroll_success="Relance réussie.\nLes nouvelles statistiques sont affichées ci-dessus.",
        reroll_failed="La relance a échoué.", reroll_no_stats="Aucune statistique d'arme à feu disponible",
        reroll_no_rolls="Aucun bonus ordinaire à redistribuer", reroll_no_uid="Aucun identifiant d'arme fourni",
        reroll_weapon_changed="L'arme en main a changé avant la relance",
        reroll_record_missing="Progression de cette arme introuvable", reroll_min_level="L'arme doit atteindre le niveau 5",
        reroll_no_rewards="Aucun bonus ordinaire à redistribuer",
        reroll_same_distribution="La relance n'a pas modifié les statistiques",
        reroll_save_failed="Échec de sauvegarde ; les bonus précédents ont été rétablis",
        rank_proven="Éprouvé", rank_trusted="Fiable", rank_veteran="Vétéran",
        rank_elite="Élite", rank_signature="Emblématique",
    },
}

function L.new(language)
    local code = tostring(language or "en"):lower():match("^%s*([a-z]+)") or "en"
    local available = packs[code] ~= nil
    local selected = packs[code] or packs.en
    local function t(key)
        return selected[key] or packs.en[key] or tostring(key)
    end
    local function rank(name)
        if name == nil then return nil end
        local prefix, suffix = tostring(name):match("^(%a+) (I+V?)$")
        local key = prefix and ("rank_" .. prefix:lower()) or nil
        if key and packs.en[key] then return t(key) .. " " .. suffix end
        return name -- Preserve custom milestone names from config.ini.
    end
    return t, code, available, rank
end

return L
