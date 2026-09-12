local Census = {}

function Census.install(mod, classify)
    local flag = Mods.lua.io.open(
        "./../mods/darktidevr/darktidevr_render_world_census.flag", "r")
    if not flag then return nil end
    local text = flag:read(32)
    flag:close()
    if type(text) ~= "string" or #text > 31 then return nil end
    local warmup = text:lower():match("^[ \t\r\n]*enabled[ \t\r\n]+warmup=(%d+)[ \t\r\n]*$")
    if warmup then
        warmup = tonumber(warmup)
        if not warmup or warmup > 600 then return nil end
    elseif text:lower():match("^[ \t\r\n]*enabled[ \t\r\n]*$") then
        warmup = 120
    else return nil end

    local state = { frame = 0, records = 0, complete = false }
    function state.observe(world)
        if not state.complete and classify(world) == "gameplay" then
            state.frame = state.frame + 1
        end
    end
    local function record(world, target)
        local name = World.get_data(world, "name") or "unnamed"
        local viewports = World.get_data(world, "viewports") or {}
        local viewport_name = "unmapped"
        for key, viewport in pairs(viewports) do
            if viewport == target then viewport_name = tostring(key); break end
        end
        local queue = World.get_data(world, "render_queue") or {}
        state.records = state.records + 1
        mod:info("DARKTIDEVR_WORLD_CENSUS record=%d frame=%d world=%s class=%s viewport=%s queued=%d",
            state.records, state.frame, tostring(name), classify(world), viewport_name, #queue)
        if state.records >= 64 then
            state.complete = true
            mod:info("DARKTIDEVR_WORLD_CENSUS complete records=%d", state.records)
        end
    end
    mod:hook(Application, "render_world", function(func, world, camera, target, ...)
        if not state.complete and state.frame > warmup then
            local ok, err = pcall(record, world, target)
            if not ok then
                state.complete = true
                mod:error("DARKTIDEVR_WORLD_CENSUS failed error=%s", tostring(err))
            end
        end
        return func(world, camera, target, ...)
    end)
    mod:info("DARKTIDEVR_WORLD_CENSUS armed warmup=%d limit=64", warmup)
    return state
end

return Census
