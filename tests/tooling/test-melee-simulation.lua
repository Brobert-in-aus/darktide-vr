local Simulation, Contacts, Policy = dofile(arg[1]), dofile(arg[2]), dofile(arg[3])
local simulation, batch, ledger = Simulation.new(), Contacts.new(), Policy.new(0, 1)
local target, queries, hits = {}, 0, 0
local function run(frame, time, tracking, resimulating)
    local ok, reason = Simulation.begin_step(simulation, {
        frame=frame, time=time, tracking_valid=tracking, resimulating=resimulating})
    if not ok then return reason end
    queries = queries + 1
    Contacts.clear(batch)
    -- Same stationary contact and controller sample for every simulation tick.
    -- Physics checks obstruction before handing this contact to the collector.
    for substep=1,4 do
        Contacts.add(batch, {target=target, actor=target, priority=1,
            position={x=0,y=0,z=0}, normal={x=0,y=1,z=0}})
    end
    for _, contact in ipairs(batch.ordered) do
        if Policy.accept_contact(ledger, contact.target, time, "light", .5) then
            hits = hits + 1
        end
    end
end
run(0, 0, true, false)
run(1, .25, true, false)
assert(hits == 1 and queries == 2)
run(2, .5, true, false)
assert(hits == 2 and queries == 3, "stationary pose stopped eligible contact")
assert(run(2, 1, true, false) == "repeated_frame")
assert(run(3, .5, true, false) == "nonadvancing_time")
assert(run(3, .75, true, true) == "resimulation")
assert(simulation.last_frame == 2 and simulation.last_time == .5)
assert(run(3, .75, false, false) == "invalid_tracking")
assert(run(3, 1, true, false) == "repeated_frame")
run(4, .8, true, false)
assert(hits == 2, "tracking reacquisition erased target cooldown")
run(5, 1, true, false)
assert(hits == 3)
assert(run(1, .25, true, false) == "repeated_frame")
assert(run(6, 0/0, true, false) == "invalid_step")
assert(run(6.5, 1.25, true, false) == "invalid_step")
assert(run(6, 1.25, true, nil) == "invalid_step")
run(6, 1.5, true, false)
assert(hits == 4 and queries == 6)
print("stationary simulation contact, duplicate/replayed ticks and persistent cooldowns passed")
