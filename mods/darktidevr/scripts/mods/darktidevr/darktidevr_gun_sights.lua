-- Gun aim ray on the sight line (todo item 4, 15 September).
--
-- The gun is held at the tracked grip with its bore along the aim, and the
-- reticle sits where the aim ray hits. That ray used to start at the
-- controller, below the bore, so it ran parallel to the iron sights instead
-- of through them: on the galvanic rifle the sight line is 11.8 cm above the
-- grip, which puts the reticle 0.66 degrees under the sights at 10 m and
-- about 2 degrees at 3 m.
--
-- For a wielded gun with a known sight offset, the ray starts on the sight
-- line: grip + aim rotation * offset. The offset is measured in the muzzle
-- frame as (eye - grip), with the eye from the stock aim-down-sights pose of
-- the hidden first-person rig (sights on the camera) and the grip from the
-- placed third-person gun. Both are measured live; a shipped value covers a
-- weapon until then.
local Sights = {}

-- Muzzle-frame x (right) and z (up) of the stock ADS eye, by weapon template.
-- Values: the DARKTIDEVR_GUN_SIGHTS eye line (artifacts/unattended/stray-bullet-20260915/sight2).
Sights.SHIPPED_EYES = {
    galvanic_rifle_p1_m1 = {x = -0.008, z = 0.032},
}
Sights.ADS_SETTLE_SECONDS = 0.8
-- Implausible measurements (a gun not at the eye, animation mid-blend).
Sights.MAX_EYE_OFFSET = 0.15
Sights.MAX_GRIP_OFFSET = 0.25

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end

-- The sight offset from the grip in the muzzle frame, or nil. Pure.
function Sights.offset(eye, grip)
    if type(eye) ~= "table" or type(grip) ~= "table" or not finite(eye.x) or not finite(eye.z) or
        not finite(grip.x) or not finite(grip.z) then return nil end
    if math.abs(eye.x) > Sights.MAX_EYE_OFFSET or math.abs(eye.z) > Sights.MAX_EYE_OFFSET or
        math.abs(grip.x) > Sights.MAX_GRIP_OFFSET or math.abs(grip.z) > Sights.MAX_GRIP_OFFSET then return nil end
    return {x = eye.x - grip.x, z = eye.z - grip.z}
end

function Sights.install(mod, presentation)
    local api = {eyes = {}, grips = {}}
    for name, eye in pairs(Sights.SHIPPED_EYES) do api.eyes[name] = {x = eye.x, z = eye.z, source = "shipped"} end
    local ads_since, failures = nil, 0

    local function wielded_gun(unit)
        local weapon = unit and ScriptUnit.has_extension(unit, "weapon_system")
        local template = weapon and weapon:weapon_template()
        if not template or not presentation.gun_aim or not presentation.gun_aim.is_gun(template) then return nil end
        return template, weapon
    end

    -- The origin for the dominant hand's aim ray while a gun is wielded, or nil.
    function api.origin(unit, rotation)
        if not rotation then return nil end
        local template = wielded_gun(unit)
        local offset = template and Sights.offset(api.eyes[template.name], api.grips[template.name])
        local grip = offset and presentation.weapon_grip_target and presentation.weapon_grip_target("dominant")
        if not grip then return nil end
        return grip + Quaternion.rotate(rotation, Vector3(offset.x, 0, offset.z))
    end

    -- Gun aim reports where the placed gun's muzzle is relative to the grip.
    function api.observe_grip(template_name, muzzle_pose, grip_position)
        local local_grip = Matrix4x4.transform(Matrix4x4.inverse(muzzle_pose), grip_position)
        local x, z = Vector3.x(local_grip), Vector3.z(local_grip)
        if not finite(x) or not finite(z) then return end
        local known = api.grips[template_name]
        if not known then
            mod:info("DARKTIDEVR_GUN_SIGHTS grip template=%s grip_in_muzzle=%.4f,%.4f", template_name, x, z)
        end
        api.grips[template_name] = {x = x, z = z}
    end

    local function measure(unit, t)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local alternate = unit_data and unit_data:read_component("alternate_fire")
        local template = wielded_gun(unit)
        if not template or not alternate or not alternate.is_active then ads_since = nil; return end
        ads_since = ads_since or t
        local eye = api.eyes[template.name]
        if t - ads_since < Sights.ADS_SETTLE_SECONDS or (eye and eye.source == "measured") then return end
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local inventory = unit_data:read_component("inventory")
        local muzzle_name = template.fx_sources and template.fx_sources._muzzle
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local camera = first_person and first_person:first_person_unit()
        if not loadout or not muzzle_name or not camera then return end
        local unit_1p, node_1p = loadout:unit_and_node_from_node_name(inventory.wielded_slot, muzzle_name)
        if not unit_1p or not node_1p then return end
        local local_eye = Matrix4x4.transform(Matrix4x4.inverse(Unit.world_pose(unit_1p, node_1p)),
            Unit.world_position(camera, 1))
        local measured = {x = Vector3.x(local_eye), z = Vector3.z(local_eye), source = "measured"}
        if not Sights.offset(measured, {x = 0, z = 0}) then return end
        api.eyes[template.name] = measured
        mod:info("DARKTIDEVR_GUN_SIGHTS eye template=%s eye_in_muzzle=%.4f,%.4f previous=%s", template.name,
            measured.x, measured.z, eye and string.format("%.4f,%.4f", eye.x, eye.z) or "none")
    end

    function api.update(unit, t)
        local ok, message = pcall(measure, unit, t)
        if not ok then
            failures = failures + 1
            if failures == 1 then mod:info("DARKTIDEVR_GUN_SIGHTS failed=%s", tostring(message):sub(1, 160)) end
        end
    end
    return api
end

return Sights
