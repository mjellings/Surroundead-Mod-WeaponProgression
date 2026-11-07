-- WeaponProgression persistence module
-- Owns data.db v2 discovery, recovery, parsing and atomic replacement.
local M = {}
local dbPath = nil

local function db_num(v)
    if v == nil then return "" end
    return string.format("%.15g", v)
end

local function ensure_db_file(paths, log)
    for _, path in ipairs(paths or {}) do
        local existing = io.open(path, "r")
        if existing then existing:close(); dbPath = path; return true end

        local backupPath = path .. ".bak"
        local backup = io.open(backupPath, "r")
        if backup then
            backup:close()
            local recovered, recoverErr = os.rename(backupPath, path)
            if recovered then
                dbPath = path
                log("DATABASE RECOVERY | restored last-known-good " .. backupPath)
                return true
            end
            log("DATABASE RECOVERY FAILED | " .. tostring(recoverErr))
        end

        local f = io.open(path, "w")
        if f then
            f:write("# WeaponProgression data.db v2\n")
            f:write("# uid\\tlevel\\txp\\tkills\\tweapon\\tlast_upgrade\\tbase_damage\\tup_damage\\tbase_critmult\\tup_critmult\\tbase_critchance\\tup_critchance\\tbase_rpm\\tup_rpm\\tbase_falloff\\tup_falloff\\tpending_rewards\n")
            f:close(); dbPath = path; return true
        end
    end
    return false
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

local function count_records(records)
    local n = 0
    for _ in pairs(records or {}) do n = n + 1 end
    return n
end

-- Parses a data.db v2 file. Returns records, recordCount, dataLineCount,
-- or nil when the file cannot be opened.
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
                    pending_rewards=math.max(0, math.floor(tonumber(c[17]) or 0)),
                    bases={}, upgrades={}
                }
                r.bases.damage = tonumber(c[7]);       r.upgrades.damage = math.max(0, math.floor(tonumber(c[8]) or 0))
                r.bases.critmult = tonumber(c[9]);     r.upgrades.critmult = math.max(0, math.floor(tonumber(c[10]) or 0))
                r.bases.critchance = tonumber(c[11]);  r.upgrades.critchance = math.max(0, math.floor(tonumber(c[12]) or 0))
                r.bases.rpm = tonumber(c[13]);         r.upgrades.rpm = math.max(0, math.floor(tonumber(c[14]) or 0))
                r.bases.falloff = tonumber(c[15]);     r.upgrades.falloff = math.max(0, math.floor(tonumber(c[16]) or 0))
                records[uid] = r
            end
        end
    end
    f:close()
    return records, count_records(records), dataLines
end

-- Number of records the database held when it was loaded. Records are never
-- deleted at runtime, so a save that would write fewer is refused: it means
-- the in-memory table was lost or the file on disk was empty/corrupt.
local loadedCount = 0

function M.Load(paths, log)
    loadedCount = 0
    if not ensure_db_file(paths, log) then
        log("ERROR: could not find/create a writable data.db.")
        return {}
    end
    log("Database path: " .. dbPath)

    local records, count, dataLines = parse_file(dbPath)
    if records == nil then
        log("ERROR: could not open " .. dbPath .. " for reading.")
        records, count, dataLines = {}, 0, 0
    end

    -- data.db present but yielding no records (truncated by a crash, emptied,
    -- or garbled). Prefer the last-known-good backup if it has records, so the
    -- next save does not rotate the bad file over the good backup.
    if count == 0 then
        local backupRecords, backupCount = parse_file(dbPath .. ".bak")
        if backupRecords ~= nil and backupCount > 0 then
            log("DATABASE RECOVERY | " .. dbPath .. " had no readable records (data lines=" .. tostring(dataLines) ..
                "); loaded " .. tostring(backupCount) .. " record(s) from " .. dbPath .. ".bak")
            records, count = backupRecords, backupCount
        end
    elseif dataLines > count then
        log("DATABASE WARNING | " .. tostring(dataLines - count) .. " unreadable line(s) skipped in " .. dbPath)
    end

    loadedCount = count
    log("Loaded " .. count .. " weapon record(s).")
    return records
end

function M.Save(records, log)
    if dbPath == nil then return false end
    local count = count_records(records)
    if count < loadedCount then
        log("ERROR: refusing to save " .. tostring(count) .. " record(s); " .. tostring(loadedCount) ..
            " were loaded and records are never deleted. data.db and data.db.bak left untouched.")
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

    write("# WeaponProgression data.db v2\n")
    write("# uid\\tlevel\\txp\\tkills\\tweapon\\tlast_upgrade\\tbase_damage\\tup_damage\\tbase_critmult\\tup_critmult\\tbase_critchance\\tup_critchance\\tbase_rpm\\tup_rpm\\tbase_falloff\\tup_falloff\\tpending_rewards\n")
    local keys={}; for uid in pairs(records or {}) do table.insert(keys,uid) end; table.sort(keys)
    for _, uid in ipairs(keys) do
        local r=records[uid]
        r.bases=r.bases or {}; r.upgrades=r.upgrades or {}
        local weapon=tostring(r.weapon or "Unknown"):gsub("[\t\r\n]"," ")
        local last=tostring(r.last_upgrade or ""):gsub("[\t\r\n]"," ")
        write(table.concat({
            uid, tostring(math.floor(r.level or 1)), db_num(r.xp or 0), tostring(math.floor(r.kills or 0)), weapon, last,
            db_num(r.bases.damage), tostring(math.floor(r.upgrades.damage or 0)),
            db_num(r.bases.critmult), tostring(math.floor(r.upgrades.critmult or 0)),
            db_num(r.bases.critchance), tostring(math.floor(r.upgrades.critchance or 0)),
            db_num(r.bases.rpm), tostring(math.floor(r.upgrades.rpm or 0)),
            db_num(r.bases.falloff), tostring(math.floor(r.upgrades.falloff or 0)),
            tostring(math.floor(r.pending_rewards or 0))
        }, "\t") .. "\n")
    end
    local closed, closeErr = f:close()
    if writeErr ~= nil or not closed then
        os.remove(tmp)
        log("ERROR writing " .. tmp .. ": " .. tostring(writeErr or closeErr) .. " | data.db left untouched")
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
            os.remove(tmp); log("ERROR rotating data.db to backup: " .. tostring(rotateErr)); return false
        end
    end
    local ok,err=os.rename(tmp,dbPath)
    if not ok then
        if hadExisting then
            local restored, restoreErr = os.rename(backup, dbPath)
            if not restored then log("CRITICAL: data.db promotion failed and backup restore also failed: " .. tostring(restoreErr)) end
        end
        log("ERROR replacing data.db: " .. tostring(err)); return false
    end
    return true
end

return M
