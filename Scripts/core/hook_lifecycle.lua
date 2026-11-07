-- WeaponProgression hook lifecycle module
-- Owns delayed Blueprint hook registration/retry and compatibility gating.
local M = {}
local started = false

function M.Start(opts)
    if started then return end
    started = true

    local hooks = opts.Hooks or {}
    local compatibility = opts.Compatibility
    local findGuidLibrary = opts.FindGuidLibrary
    local log = opts.Log or function() end
    local retryDelay = opts.RetryDelayMs or 3000
    local maxRounds = opts.MaxRetryRounds or 40
    local initialDelay = opts.InitialDelayMs or 0
    local registered = {}
    local retryRound = 0

    local function register_one(key, path, callback)
        local ok, preId, postId = pcall(function() return RegisterHook(path, callback) end)
        if not ok then
            if retryRound == 1 or retryRound % 5 == 0 then log("WAITING " .. tostring(key) .. " | " .. tostring(preId)) end
            return false
        end
        registered[key] = { preId, postId }
        log(string.format("REGISTERED %-18s | ids=%s,%s", key, tostring(preId), tostring(postId)))
        return true
    end

    local function registered_count()
        local n = 0
        for _, h in ipairs(hooks) do if registered[h[1]] then n=n+1 end end
        return n
    end

    local function attempt()
        retryRound = retryRound + 1
        if findGuidLibrary then findGuidLibrary() end
        if compatibility ~= nil and retryRound == 1 then compatibility.LogEnvironment() end

        for _, h in ipairs(hooks) do
            local key = h[1]
            if not registered[key] then
                local allowed, reason = true, nil
                if compatibility ~= nil then allowed, reason = compatibility.CheckHook(key) end
                if allowed then
                    register_one(key, h[2], h[3])
                elseif retryRound == 1 or retryRound % 5 == 0 then
                    log("COMPAT WAIT | " .. tostring(key) .. " | hook not attempted; expected capability not available yet | missing=" .. tostring(reason))
                end
            end
        end

        local n = registered_count()
        if n == #hooks then
            if compatibility ~= nil then compatibility.Summarize() end
            log("All " .. tostring(#hooks) .. " hooks active.")
            log("Ready: configurable progression is active.")
            log("Persistent progression armed: first resolved use captures base stats; each level-up awards and stores one stat upgrade.")
            return
        end

        if retryRound == 1 or retryRound % 5 == 0 then
            log(string.format("Waiting for game Blueprints: %d/" .. tostring(#hooks) .. " hooks active (pass %d/%d).", n, retryRound, maxRounds))
        end
        if retryRound < maxRounds then
            ExecuteWithDelay(retryDelay, function() ExecuteInGameThread(attempt) end)
            return
        end

        local skippedTooltip = 0
        if compatibility ~= nil then
            for _, h in ipairs(hooks) do
                local key = h[1]
                if not registered[key] and compatibility.IsTooltipHook(key) then
                    local allowed, reason = compatibility.CheckHook(key)
                    if not allowed then
                        registered[key] = "compat_skipped"; skippedTooltip=skippedTooltip+1
                        log("COMPAT DISABLE | " .. tostring(key) .. " | hook was never attempted because expected capability is missing/changed | " .. tostring(reason))
                    end
                end
            end
        end
        n=registered_count()
        if n == #hooks then
            if compatibility ~= nil then compatibility.Summarize() end
            log("All " .. tostring(#hooks) .. " hooks resolved; " .. tostring(skippedTooltip) .. " tooltip hook(s) disabled by compatibility guard.")
            log("Ready: core configurable progression is active.")
            log("Persistent progression armed: first resolved use captures base stats; each level-up awards and stores one stat upgrade.")
        else
            log("ERROR: stopped hook retries before all required core hooks became available.")
        end
    end

    -- Blueprint UFunctions can exist during early startup before their script VM
    -- implementation is ready. Calling RegisterHook in that window makes UE4SS
    -- print a full error/stack trace even though pcall catches the failure.
    -- Defer the first registration pass so normal startup remains quiet; the
    -- existing retry loop still handles genuinely late-loading Blueprints.
    if initialDelay > 0 then
        log(string.format("Hook registration deferred %dms while game Blueprints initialise.", initialDelay))
        ExecuteWithDelay(initialDelay, function() ExecuteInGameThread(attempt) end)
    else
        attempt()
    end
end

return M
