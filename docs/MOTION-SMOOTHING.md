# Aim and weapon motion smoothing

Research and implementation recommendation, 5 September 2026. No live smoothing
change is enabled by this document. This concerns controller pose stabilization;
compositor frame generation/reprojection is a separate system.

## Recommended policy for this mod

| Use | Starting policy | Consistency requirement |
| --- | --- | --- |
| Menu laser | Light adaptive stabilization | Hover and trigger selection consume the same ray sample. |
| Ranged aim / current hand-directed stock attacks | Adjustable light angular stabilization; little positional filtering | Reticle, muzzle/weapon presentation and attack direction must agree. |
| Physical melee | Direct tracking or minimal adaptive filtering | Visible weapon and swept collision volume share the same pose policy. |
| Left-hand blocking | Minimal filtering | Shield/block direction must not noticeably trail the hand. |
| Head pose | No added application smoothing | Retain runtime tracking and prediction. |

These are project recommendations, not universal published weapon-filter values.
Offer an off setting. Strong aim assistance, virtual gunstock constraints and
physics-simulated weapon weight are separate choices; do not silently introduce
them as smoothing.

## Evidence and trade-offs

The [One Euro filter authors](https://gery.casiez.net/1euro/) describe adaptive
low-pass filtering that reduces jitter during slow motion and reduces lag during
fast motion. Their tuning procedure separates steady-hand jitter from quick-motion
lag and notes that parameters depend on data units. Their illustrative 1 Hz
starting point is not a calibrated VR weapon default. We should compare a lightly
tuned quaternion/position implementation against direct tracking before selecting
any release values.

[Unity's XR Transform Stabilizer](https://docs.unity3d.com/Packages/com.unity.xr.interaction.toolkit@3.2/manual/xr-transform-stabilizer.html)
provides low-latency pose stabilization, particularly for rays, with separate
angular and positional bounds. This is a useful alternative comparison to an
adaptive low-pass filter. Avoid stacking both without measuring total lag.

[Meta's One Euro interface](https://developers.meta.com/horizon/reference/interaction/v69/interface_oculus_interaction_input_i_one_euro_filter/)
explicitly treats each filter step as a state mutation and provides reset and
elapsed-time inputs. For our stereo renderer, advance once per new controller
sample, cache the result, and reuse it for both eyes and all consumers. Advancing
again in right-eye rendering would introduce the same class of asymmetry as the
previous marker easing bug.

[Unity's grab documentation](https://docs.unity3d.com/Packages/com.unity.xr.interaction.toolkit@3.2/manual/xr-grab-interactable.html)
distinguishes immediate pose following from physics-driven following: the latter
can add apparent lag, while direct movement needs separate collision handling.
It also describes updating visuals between physics steps. For this mod, visual
updates may run more often than simulation, but the collision/render relationship
must remain explicit. Do not show a heavily delayed sword while testing hits at
an unrelated direct-tracked pose.

[PhysX collision documentation](https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/AdvancedCollisionDetection.html)
distinguishes linear sweep CCD from approaches that account for angular motion.
This supports retaining rotational subdivision and current overlap in our melee
plan; smoothing is not a replacement for collision coverage. This reference does
not establish which PhysX options Darktide exposes through Lua.

## Integration details and safeguards

Current inspection found no dedicated application aim filter in the controller
bridge/aim path. `src/xr/main.cpp` locates controller poses at predicted display
time, then publishes them with a monotonic publication timestamp and sequence.
The shared controller record also includes a transport generation. Publication
time is not the same as the pose's requested prediction time.

[OpenXR xrLocateSpace](https://registry.khronos.org/OpenXR/specs/1.1/man/html/xrLocateSpace.html)
supports locating at a requested historical or future time, with future poses
already predicted by the runtime. It distinguishes valid from actively tracked
poses during tracking loss. Therefore, preserve pose time semantics and tracking
flags rather than adding an unmeasured second prediction stage.

Implementation plan:

1. Preserve direct poses for diagnostics. Filter aim and grip in separate state;
   their offsets and purposes differ. Use elapsed time between fresh samples,
   not a fixed per-render blend coefficient. Normalize quaternions and handle
   equivalent opposite signs with shortest-arc interpolation.
2. Filter in a stable tracking frame. Apply locomotion/body mapping afterward so
   walking or turning the avatar does not make the weapon lag in world space.
   Reset on recenter, writer generation change, tracking reacquisition, invalid
   pose, or a large sample gap; never interpolate through a teleport.
3. Publish one stabilized aim snapshot with its source sequence. Use it for ray
   intersection and the corresponding attack decision. Do not smooth trigger
   edges, delay the click until the filter catches up, or silently use a later ray.
4. Keep melee collision sampling and cooldowns in simulation time. Carry pose
   prediction/sample time explicitly when introducing the adapter; do not treat
   publication age as proof of simulation-time alignment. Validate prediction and
   resimulation separately from visual latency.
5. Motion speed may adjust filter strength. It must never become a minimum swing
   speed or damage gate: the user's always-active volume, stationary contacts,
   per-enemy cooldowns, initial heavy cooldown and infinite cleave remain intact.

Use shared filter configuration and sample ownership, not duplicate independent
filters for the reticle and the attack. Sampling later for presentation can be
useful, but any discrepancy with the committed shot must be measured and bounded.
Do not smooth hit positions across different targets; filter the ray before the
intersection query so a reticle does not drift through empty space between hits.

## Tuning and acceptance

Record direct and filtered samples together. Compare stationary angular jitter,
slow tracking, fast acquisition/reversal, trigger squeeze, weapon-tip travel and
added lag. Include different update rates, duplicate reads, pauses, recenter and
tracking loss. Angles in radians versus degrees change filter parameter meaning.
For physical melee, include tip-only arcs, thin targets and stationary overlap;
measure both missed and duplicate contacts.

Start with aim-only tuning while leaving physical melee direct. Stronger steady
aim settings should remain optional. No universal cutoff, beta or millisecond
budget is claimed here: select defaults from measured traces and worn feedback
on this controller/runtime setup, then validate other hardware separately.
