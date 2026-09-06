-- Weapon roles do not rename raw tracking, anatomical wrists or controls.
-- Construct a fixed policy at a session boundary; do not mutate it mid-charge.
local Roles = {}
function Roles.new(dominant)
    dominant = dominant == "left" and "left" or "right"
    local sides = {left="left",right="right",dominant=dominant,
        support=dominant=="right" and "left" or "right"}
    return {physical=function(role) return sides[role] end}
end
return Roles
