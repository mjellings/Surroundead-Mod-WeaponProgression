-- WeaponProgression persistence module
-- Owns tab-separated progression database discovery, recovery, parsing and
-- atomic replacement.
--
-- M.NewStore(schema) creates an independent database (own path, own backup,
-- own record-count guard). M.Load / M.Save are the firearm data.db v2 store,
-- whose on-disk format is unchanged.
--
-- Row layout: uid, level, xp, kills, weapon, last_upgrade, then a
-- (base, upgrade count) pair per schema.stats entry, then schema.extra fields.
local M = {}

local function db_num(v)
    if v == nil then return "" end
    return string.format("%.15g", v)
end

local function split_tabs(line)
    local out = {}
    local pos = 1
    while true do
        local tab = line:find("\t", pos, true)
        if not tab then table.insert(out, line:sub(pos)); break end
        table.insert(out, line:sub(pos, tab - 1))
        pos = tab + 1
    end
    return out
end
M.SplitTabs = split_tabs

local function count_records(records)
    local n = 0
    for _ in pairs(records or {}) do n = n + 1 end
    return n
end

-- Extra fields are "name" (a field on the record) or "table.name" (a field in
-- a sub-table, e.g. "maxes.meleedamage"). kind "int" is floored and >= 0;
-- kind "num" may be empty (nil).
local function get_field(r, key)
    local t, k = key:match("^([%w_]+)%.([%w_]+)$")
    if t then return r[t] and r[t][k] or nil end
    return r[key]
end

local function set_field(r, key, value)
    local t, k = key:match("^([%w_]+)%.([%w_]+)$")
    if t then r[t] = r[t] or {}; r[t][k] = value; return end
    r[key] = value
end

function M.NewStore(schema)
    assert(type(schema) == "table" and type(schema.stats) == "table", "persistence schema required")
    local title = schema.title or "WeaponProgression database"
    local label = schema.label or "database"
    local subTables = schema.sub_tables or {}
    local extra = schema.extra or {}

    local headerCols = { "uid", "level", "xp", "kills", "weapon", "last_upgrade" }
    for _, key in ipairs(schema.stats) do
        headerCols[#headerCols + 1] = "base_" .. key
        headerCols[#headerCols + 1] = "up_" .. key
    end
    for _, e in ipairs(extra) do headerCols[#headerCols + 1] = (e.column or e.key) end
    local HEADER = "# " .. title .. "\n# " .. table.concat(headerCols, "\\t") .. "\n"

    local S = { dbPath = nil, loadedCount = 0 }

    local function ensure_db_file(paths, log)
        for _, path in ipairs(paths or {}) do
            local existing = io.open(path, "r")
            if existing then existing:close(); S.dbPath = path; return true end

            local backupPath = path .. ".bak"
            local backup = io.open(backupPath, "r")
            if backup then
                backup:close()
                local recovered, recoverErr = os.rename(backupPath, path)
                if recovered then
                    S.dbPath = path
                    log("DATABASE RECOVERY | restored last-known-good " .. backupPath)
                    return true
                end
                log("DATABASE RECOVERY FAILED | " .. tostring(recoverErr))
            end

            local f = io.open(path, "w")
            if f then
                f:write(HEADER)
                f:close(); S.dbPath = path; return true
            end
        end
        return false
    end

    -- Returns records, recordCount, dataLineCount, or nil when the file
    -- cannot be opened.
    local function parse_file(path)
        local f = io.open(path, "r")
        if not f then return nil, 0, 0 end
        local records, dataLines = {}, 0
        for line in f:lines() do
            if line:sub(1,1) ~= "#" and line:match("%S") then
                dataLines = dataLines + 1
                local c = split_tabs(line)
                local uid = c[1]
                if uid and uid ~= "" then
                    local r = {
                        level=math.max(1, math.floor(tonumber(c[2]) or 1)),
                        xp=math.max(0, tonumber(c[3]) or 0),
                        kills=math.max(0, math.floor(tonumber(c[4]) or 0)),
                        weapon=(c[5] and c[5] ~= "") and c[5] or "Unknown",
                        last_upgrade=c[6] or "",
                        bases={}, upgrades={}
                    }
                    for _, t in ipairs(subTables) do r[t] = {} end
                    local col = 7
                    for _, key in ipairs(schema.stats) do
                        r.bases[key] = tonumber(c[col])
                        r.upgrades[key] = math.max(0, math.floor(tonumber(c[col + 1]) or 0))
                        col = col + 2
                    end
                    for _, e in ipairs(extra) do
                        local v = tonumber(c[col])
                        if e.kind == "int" then v = math.max(0, math.floor(v or 0)) end
                        set_field(r, e.key, v)
                        col = col + 1
                    end
                    records[uid] = r
                end
            end
        end
        f:close()
        return records, count_records(records), dataLines
    end

    local store = {}

    function store.Path() return S.dbPath end

    function store.Load(paths, log)
        S.loadedCount = 0
        if not ensure_db_file(paths, log) then
            log("ERROR: could not find/create a writable " .. label .. ".")
            return {}
        end
        log("Database path: " .. S.dbPath)

        local records, count, dataLines = parse_file(S.dbPath)
        if records == nil then
            log("ERROR: could not open " .. S.dbPath .. " for reading.")
            records, count, dataLines = {}, 0, 0
        end

        -- File present but yielding no records (truncated by a crash, emptied,
        -- or garbled). Prefer the last-known-good backup if it has records, so
        -- the next save does not rotate the bad file over the good backup.
        if count == 0 then
            local backupRecords, backupCount = parse_file(S.dbPath .. ".bak")
            if backupRecords ~= nil and backupCount > 0 then
                log("DATABASE RECOVERY | " .. S.dbPath .. " had no readable records (data lines=" .. tostring(dataLines) ..
                    "); loaded " .. tostring(backupCount) .. " record(s) from " .. S.dbPath .. ".bak")
                records, count = backupRecords, backupCount
            end
        elseif dataLines > count then
            log("DATABASE WARNING | " .. tostring(dataLines - count) .. " unreadable line(s) skipped in " .. S.dbPath)
        end

        -- Records are never deleted at runtime, so a save that would write
        -- fewer is refused: the in-memory table was lost or the file on disk
        -- was empty/corrupt.
        S.loadedCount = count
        log("Loaded " .. count .. " weapon record(s).")
        return records
    end

    function store.Save(records, log)
        if S.dbPath == nil then return false end
        local dbPath = S.dbPath
        local count = count_records(records)
        if count < S.loadedCount then
            log("ERROR: refusing to save " .. tostring(count) .. " record(s); " .. tostring(S.loadedCount) ..
                " were loaded and records are never deleted. " .. label .. " and its .bak left untouched.")
            return false
        end

        local tmp = dbPath .. ".tmp"
        local f = io.open(tmp, "w")
        if not f then log("ERROR: could not open " .. tmp); return false end

        local writeErr = nil
        local function write(text)
            if writeErr ~= nil then return end
            local ok, err = f:write(text)
            if not ok then writeErr = err or "unknown write error" end
        end

        write(HEADER)
        local keys={}; for uid in pairs(records or {}) do table.insert(keys,uid) end; table.sort(keys)
        for _, uid in ipairs(keys) do
            local r=records[uid]
            r.bases=r.bases or {}; r.upgrades=r.upgrades or {}
            local weapon=tostring(r.weapon or "Unknown"):gsub("[\t\r\n]"," ")
            local last=tostring(r.last_upgrade or ""):gsub("[\t\r\n]"," ")
            local cols = { uid, tostring(math.floor(r.level or 1)), db_num(r.xp or 0), tostring(math.floor(r.kills or 0)), weapon, last }
            for _, key in ipairs(schema.stats) do
                cols[#cols + 1] = db_num(r.bases[key])
                cols[#cols + 1] = tostring(math.floor(r.upgrades[key] or 0))
            end
            for _, e in ipairs(extra) do
                local v = get_field(r, e.key)
                if e.kind == "int" then cols[#cols + 1] = tostring(math.floor(v or 0))
                else cols[#cols + 1] = db_num(v) end
            end
            write(table.concat(cols, "\t") .. "\n")
        end
        local closed, closeErr = f:close()
        if writeErr ~= nil or not closed then
            os.remove(tmp)
            log("ERROR writing " .. tmp .. ": " .. tostring(writeErr or closeErr) .. " | " .. label .. " left untouched")
            return false
        end

        local backup = dbPath .. ".bak"
        os.remove(backup)
        local hadExisting = false
        local existing = io.open(dbPath, "r")
        if existing then existing:close(); hadExisting = true end
        if hadExisting then
            local rotated, rotateErr = os.rename(dbPath, backup)
            if not rotated then
                os.remove(tmp); log("ERROR rotating " .. label .. " to backup: " .. tostring(rotateErr)); return false
            end
        end
        local ok,err=os.rename(tmp,dbPath)
        if not ok then
            if hadExisting then
                local restored, restoreErr = os.rename(backup, dbPath)
                if not restored then log("CRITICAL: " .. label .. " promotion failed and backup restore also failed: " .. tostring(restoreErr)) end
            end
            log("ERROR replacing " .. label .. ": " .. tostring(err)); return false
        end
        return true
    end

    return store
end

-- Firearm progression: data.db v2 (format unchanged since v0.13).
local firearms = M.NewStore({
    title = "WeaponProgression data.db v2",
    label = "data.db",
    stats = { "damage", "critmult", "critchance", "rpm", "falloff" },
    extra = { { key = "pending_rewards", kind = "int" } },
})
M.Load = firearms.Load
M.Save = firearms.Save

return M
