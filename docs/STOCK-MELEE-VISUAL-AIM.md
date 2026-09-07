# Stock-input melee visual aim correction

8 September 2026, offline candidate. The first-swing preview review exposed a
reproduced presentation mismatch in stock-input mode. This mode deliberately
disables action-local controller pose overrides. Animated rigid hands still
asked that disabled path for rotation, received nil, and followed the untouched
head-facing first-person animation. The equipment sync was also conditional on
a non-nil rotation. Meanwhile, the stock sweep used simulated hand-directed aim.

`controller_aim.melee_visual_rotation` now resolves the owned local first-person
simulation rotation when stock-input mode is active. Otherwise it retains the
existing dominant-controller rotation. Animated hand following and the melee
aim-constraint branch use this helper. Non-melee constraint behavior is unchanged.
Foreign, nonlocal, missing and retiring first-person owners cannot supply a
simulation rotation or silently substitute fresh controller aim.

This changes presentation only. It does not write first-person components,
network inputs, action references, hitboxes, timing, damage or camera orientation.
Existing animation origins/pivots are retained; worn positional alignment still
requires observation. No physical melee has been enabled.

`test-melee-simulation-visual.lua` executes the actual body-IK melee branch and
aim-constraint hook with the real aim module. Before the fix it failed because
stock-input animated hands received no simulated rotation. After the fix it
passes simulated/local direction ownership, equipment synchronization, owner
rejection and unchanged non-melee constraint behavior. Engine skeleton transforms
remain fixture sinks. The stacked candidate passed full Windows x64 CTest
134/134 in 24.79 seconds with headset tests OFF; 47 Lua chunks compile. Evidence:
`artifacts/unattended/stock-melee-visual-134-20260908.log`.

For the focused accepted-baseline preview branch, rerun its Lua gate and these
tests against that checkout. A stacked full-suite result does not establish a
separate focused native build. No deployment or worn/server damage acceptance
has occurred. The eventual observation should compare the first swing and guide
while looking away from the aimed direction, and confirm both hands/equipment
follow the attack without shifting its apparent origin unexpectedly.
