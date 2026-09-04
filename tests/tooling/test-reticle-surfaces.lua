-- Surface classification only; no game systems or raycasts execute.
require = function() return {} end
local aim = assert(loadfile(arg[1]))()
assert(not aim.is_reticle_surface(false, false, true, "afro"),
    "suppression volume stopped the reticle")
assert(not aim.is_reticle_surface(false, true, true, "afro"),
    "static classification bypassed suppression exclusion")
assert(not aim.is_reticle_surface(true, false, true, "torso"),
    "local body stopped the reticle")
assert(not aim.is_reticle_surface(false, false, true, nil),
    "movement capsule stopped the reticle")
assert(aim.is_reticle_surface(false, false, true, "torso"))
assert(aim.is_reticle_surface(false, false, true, "shield"))
assert(aim.is_reticle_surface(false, true, false, nil))
print("reticle_surfaces=pass")
