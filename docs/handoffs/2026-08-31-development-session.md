# 2026-08-31 development session

## Premium Store coordinate ownership

Live geometry disproved the previous crop-local Store scenegraph assumption.
Mode 6 presents a native-landscape client, laser and visible cursor, but the
retained Store widgets remain in the portrait eye canvas. A source miss at
`(626,297)/1024x576` reported the full-grid rectangle near `(142,863)` with
extent `2210x1040`.

The production contract now keeps presentation pixels landscape, transforms
only semantic Store hit tests into the portrait canvas, and passes a null input
service to the stock grid while XR owns the pointer. This removes the offset
Windows-hover owner. Store also samples its full-grid `is_hover` before the
draw pass applies `force_hover`; the XR hook now publishes both on the same
atomic trigger frame so a matched card is not force-disabled.

An unattended source-pixel pointer probe preserves one synthetic edge across
all hooked UI passes until the semantic owner consumes it. The live proof used
`pointer_500_360_1280_720`: `StoreView._draw_grid` activated the real card and
opened `store_item_detail_view`. Escape then returned to the landing page and
the hub. Worn corner alignment remains the authoritative acceptance gate.

## Escape menu coordinate evidence

The first live Escape inventory found the same split contract. SystemView is
captured through the landscape panel, but its retained grid rectangles occupy
the portrait eye canvas: Options was near `(240,1539)` with extent `650x65`.
The semantic SystemView ray now transforms source pixels into that canvas while
the visible laser remains panel-local. The corrected source probe
`pointer_290_421_1280_720` mapped to portrait position `(566,1572)`, activated
`grid_content_pivot_widget_11`, and opened `options_view`. Two staged Back
inputs then closed Options and SystemView, restored mode 1, and resumed fresh
stereo pairs with no pose-pair mismatches. Worn laser alignment remains the
authoritative visual gate.

## Diagnostic polling overhead

The performance audit found several development flags performing a filesystem
open every UI or fixed-update frame even when consumed or absent. System-menu,
vendor-menu and input-inventory probes now poll every 15 UI updates;
Psykhanium and hotspot inventory poll at 250 ms; movement inventory uses its
existing 60-fixed-frame guard. Active vendor child-close state still advances
every frame. These are diagnostic-only overhead removals and do not change
production pose, rendering or controller semantics.

## Validation

Commands run:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 900 -GameStartTimeoutSeconds 180 -AutoEnterHub -AutoAdvanceSplash -EnableMenuInput -EnableMenuTestControls
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure
```

The source gate passes at 198/198 file-scope locals. Fresh live runs contained
the stereo mod initialization messages and nonzero advancing `shared_ready`.
All 30 CTest cases pass in Release.
The Premium Store landing-to-detail transition and Escape-to-Options path both
completed without script errors or pose-pair mismatches. The validated Escape
run reached `shared_ready=5850`; back-navigation restored continuously advancing
fresh pairs.

## Fixed HUD target population

Source inspection of `UIWidget` identified why the earlier fixed-HUD resource
target stayed empty. Setting only UIHud's element retained lookup to false did
not change the retained mode stored on each widget pass, and an existing
retained ID caused the draw to short-circuit before the offscreen pass. The
prototype now temporarily sets only fixed-HUD widget passes to immediate mode,
marks those passes dirty, authors the target once per simulation time, and then
restores every stock retained-mode field and ID. The stock HUD remains the only
update/event owner; spatial elements continue drawing once per eye.

The feature remains default-off and can be gated with
`darktidevr_hud_panel.flag` (`enable`/`disable`). In a fresh live hub run the
target was created, the spatial/fixed partition was logged, fixed player/team
HUD content remained visible after being removed from the stock eye draw, and
the flag cleanly restored the ordinary HUD. That is direct target-population
evidence. Worn panel depth, comfort, binocular parity and coverage are still
required before enabling it in production.

## Private-range input isolation and muzzle origin

The unattended Psykhanium run exposed an ownership bug in the synthetic test
provider: controller tracking and gameplay buttons were both published through
flat loading and menu states. Its periodic Back/Menu phase therefore closed the
training-options view after the mod selected Shooting Range. Synthetic tracking
now remains continuous, while gameplay buttons are emitted only in
`stereo_world`. A clean authenticated launch then completed the scripted flow
with `DARKTIDEVR_PSYKHANIUM result=pass game_mode=shooting_range` and reached
`shared_ready=17259` with one transient pose mismatch across the whole run.

The ranged-action hook now derives the shot origin from Darktide's registered
third-person muzzle source and attachment node. It preserves the stock origin
if that live node is absent, handles alternating muzzles using the just-prepared
shot index, and retains the existing first-projectile ownership rule for
simultaneous groups. The available Psyker loadout used a chain-lightning staff,
which does not inherit `ActionShoot`; synthetic primary input was delivered but
could not exercise this firearm-specific hook. A live firearm/projectile shot
therefore remains a user/loadout gate, and Psyker targeting modules require a
separate controller-aim path rather than pretending this run validated them.
