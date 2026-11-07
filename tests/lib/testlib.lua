-- Minimal test framework: test("name", fn), expect helpers, summary.
local T = { tests = {}, current_file = nil }

function T.test(name, fn)
    T.tests[#T.tests + 1] = { file = T.current_file, name = name, fn = fn }
end

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" then return string.format("%.10g", v) end
    return tostring(v)
end

local function fail(msg, level) error({ __test_failure = true, msg = msg }, (level or 1) + 2) end

function T.eq(actual, expected, what)
    if actual ~= expected then fail((what and (what .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual)) end
end

function T.near(actual, expected, what, tol)
    tol = tol or math.max(1e-6, math.abs(expected or 0) * 1e-9)
    if type(actual) ~= "number" or math.abs(actual - expected) > tol then
        fail((what and (what .. ": ") or "") .. "expected ~" .. fmt(expected) .. ", got " .. fmt(actual))
    end
end

function T.ok(cond, what)
    if not cond then fail(what or "expected condition to be true") end
end

function T.run(filter)
    local passed, failed = 0, {}
    local lastFile = nil
    for _, t in ipairs(T.tests) do
        if filter == nil or (t.file .. " " .. t.name):lower():find(filter:lower(), 1, true) then
            if t.file ~= lastFile then io.write("\n", t.file, "\n"); lastFile = t.file end
            local ok, err = xpcall(t.fn, function(e)
                if type(e) == "table" and e.__test_failure then return e end
                return { msg = tostring(e), trace = debug.traceback("", 2) }
            end)
            if ok then
                passed = passed + 1
                io.write("  PASS  ", t.name, "\n")
            else
                failed[#failed + 1] = t
                io.write("  FAIL  ", t.name, "\n        ", err.msg, "\n")
                if err.trace and os.getenv("WP_TEST_VERBOSE") then io.write(err.trace, "\n") end
            end
        end
    end
    io.write(string.format("\n%d passed, %d failed\n", passed, #failed))
    return #failed == 0
end

return T
