# Full-height options and weapon aim stabilisation

DMF's options lists ended at authored Y=1010, leaving the bottom half empty on
the taller VR canvas. The stereo mod now obtains the actual fitted screen size
from UIScenegraph.size_scaled and extends both category and settings grids to
70 layout units above the bottom. Mask/interaction padding is preserved, header
and tab layout remains owned by DMF, and grid caches refresh after resizing.
Desktop height and returning from a tall canvas are covered. Installed DMF
sources are not modified.

Weapon aim now shares an adaptive quaternion filter across presentation and
gameplay direction consumers. It applies to ranged templates including force
staffs. The default strength is 75%, adjustable from 0 (off) to 100 in Mod
Options. Small tremors receive stronger damping; deliberate angular motion
raises the response rate, with transient lag capped at three degrees. Filtering
in body-anchor space keeps body turning immediate. Controller positions remain
raw, and stock recoil/spread remain downstream. Melee is excluded.

History resets on weapon/player/hand changes, tracking loss, UI ownership,
transport generation changes, stale or reordered samples, settings changes and
large pose discontinuities. Multiple consumers reuse one filtered result per
tracked sample. Quaternion components are stored as Lua numbers rather than
retaining transient engine quaternion objects.

Validation on Windows x64:

- Configured the existing isolated build with `cmake -S . -B build/xr-frame-stage-timing`;
  no native/viewer rebuild was performed.
- `ctest --test-dir build/xr-frame-stage-timing -C Release -R
  '^(weapon_stabilization|options_layout|gun_aim|online_reticle|reticle_owner|controller_bindings|controller_prompts|hud_options|melee_preview|melee_simulation_visual)$'
  --output-on-failure`: 10/10 passed (0.35 s).
- The HUD options fixture needed the settings-write API used by the preceding
  action-binding migration; its mock now implements that API.
- At 90/120 Hz, synthetic 0.4-degree, 12-Hz tremor RMS fell to 30.9%/31.1% of raw.
  A 180-degrees/second turn had maximum lag 2.025/2.042 degrees. These measurements
  describe isolated tests, not headset acceptance.
- `tools/stereo/test-darktide-lua-source.ps1`: all 54 main Lua chunks compile.

Deployment is pending the user's completion of testing. The focused deployment
branch receives the same two new modules and only the required installation and
settings edits; unrelated main-branch features are excluded. Preserve the
accepted capture DLL, bootstrap and viewer, plus current SoloPlay/user settings.
Run Ready preflight before deployment, then require fresh stereo initialization
and advancing nonzero shared_ready. Worn checks: both menu lists fill the lower
canvas; gun/staff aim is steadier without uncomfortable lag; switching weapons
and opening menus do not retain stale aim. Hit-marker stereo and missing staff
charge feedback remain separate open TODO items.

Focused deployment validation: the filter, layout and HUD-options fixtures pass
against the focused source, and its LuaJIT gate compiles all 47 chunks. The
focused main Lua change is only six installation lines; no unrelated gun,
support-grip, renderer or native changes were copied from the main checkout.
