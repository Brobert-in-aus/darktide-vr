# Full-body IK from 3-point tracking: research for Darktide VR

Date: 2026-09-15. Web research only, no code changes.

**Labels.** **[S]** means the claim comes from the cited source (the source number is in brackets). **[I]** means it is my inference or recommendation and no source states it. Parameter values from open-source code are quoted as the code has them. Units are engine-specific: Bethesda units in FRIK, Quake units in Quake VR, metres in Unity.

---

## 0. Summary

- Among shipped products, the careful ones show a body only where tracking can support it. Many show hands only (Half-Life: Alyx, and RE4 VR in first person) or leave legs out of first person (Meta Avatars, and Meta Horizon policy). The main reason is proprioceptive mismatch: legs or arms that do not match the player's real limbs feel wrong [S 1,2,3,4,5].
- Flat-to-VR mods show full bodies anyway, and the working ones share a pattern. They compute the pose after animation and before render. The camera stays the HMD and the body follows it, never the reverse. They hide the head and headgear only for the local view, use analytic two-bone arm IK with heuristic elbow poles, and fall back to game animation when tracking is bad. Examples: FRIK for Fallout 4 VR, VHVR for Valheim, Doom 3 BFG VR [S 6,7,8].
- The closest precedent for Darktide is the Valheim VR mod. It drives head, spine and arms with VRIK, turns VRIK locomotion off, and lets the game's own animation move the legs. That is the hybrid approach [S 7].
- The virtual shoulder should be one estimate that both the body rig and the virtual stock read. Concrete offset values come from VRArmIK, Google's Daydream arm model and Quake VR (section 4) [S 9,10,11].

---

## 1. Shipped games and mods

| Title | What is shown | Legs | Comfort handling / known problems |
|---|---|---|---|
| **Half-Life: Alyx** | Hands only. Invisible arms still exist for collision [S 1] | none | Valve could not make arms accurate enough across different arm lengths, and getting them wrong was jarring. Playtesters did not notice the missing arms [S 1] |
| **Meta Avatars / Horizon** | In first person: no legs and no head. In third person: legs [S 3,4,12] | Leg IK, third person only. The beta could not crouch [S 4] | Bosworth said legs that don't match your real legs are disconcerting, so the wearer sees no legs of their own [S 3]. Meta's rule for avatar poses: in first person, prioritise tracking accuracy; in third person, prioritise animation quality [S 13] |
| **Meta Movement SDK** | 70 upper-body joints, or 84 with Generative Legs. Quest 3 adds camera-based inside-out body tracking (IOBT) of elbows and torso [S 14,15] | Generative Legs is an ML estimate from the upper body. It detects crouch and jump but not knee raises [S 16] | Auto-calibrates during the first ~10 s while standing, and height can be overridden. Also works on PC over Link [S 14] |
| **Rec Room** | Optional full-body avatars, beta 2024. The bean body is still the default [S 17] | yes | Pitched mainly as better in third person and for social play [S 17] |
| **Resident Evil 4 VR** | Full upper-body rig on Leon, but first person shows only hands and a watch [S 5] | none in first person | Kicks and suplexes cut to a third-person camera and back instead of showing a leg [S 5] |
| **Lone Echo** | Arms and hands, with arm IK widely rated as among the best, plus procedural finger posing [S 18] | n/a (zero-g) | GDC talk on the first-person body and locomotion [S 19] |
| **Boneworks / Bonelab** | Full physics body, IK-driven from head and hands (the Hexabody rig) [S 20] | Physically simulated legs | High sickness potential. Body parts snag when climbing. In Bonelab, crouching in real life and moving forward makes the character stand up [S 21] |
| **Contractors** | Optional: floating hands, or an IK body [S 22] | not verified | User choice |
| **Into the Radius 1/2** | Player body | not verified | Patched so the body no longer gets in the way when crouching. In ITR2 the body turns with the head when aiming [S 23] |
| **Blade & Sorcery** | Body with IK, plus optional waist and feet trackers [S 24] | With trackers only, as far as sources show | Tracker users report contorted torsos and swapped feet [S 24] |
| **Pavlov** | not verified | not verified | No shoulder pivot; aim comes from the hands only, and players asked for one [S 25] |
| **Onward, Population: One, Asgard's Wrath 2** | **No primary source found in this session. Not verified; don't rely on my memory for these.** | | |
| **VRChat** | Local avatar with the head bones scaled down (Head Chop). Mirror and shadow clones keep the full head [S 26] | IK 2.0 | Measure by arm span (default ratio 0.4537, ~0.415 may fit better) or by height [S 27] |
| **FRIK (Fallout 4 VR mod)** | Full body, weapons in the body's hands [S 6] | Procedural stepping (section 2.4) | Pushes the head back 5 units and hides headgear meshes by name. Hiding does not change hitboxes. Hides the body in scopes. Its FAQ accepts some bulky-armour view obstruction [S 6,28] |
| **VHVR (Valheim VR mod)** | Full body with FinalIK VRIK [S 7] | **Game animation** (VRIK locomotion weight 0) | Near clip 0.09 m. Options that tie the camera to the character during dodge rolls or ship tilt are off by default and flagged as possible sickness triggers [S 29] |
| **Doom 3 BFG VR: Fully Possessed** | IK for arms and body. Ported to Doom3Quest [S 8] | leg IK | Known issue: leg IK sometimes distorts the torso [S 8] |

Pattern **[I]**: no shipped title lets body simulation move the camera, except opt-in options that are labelled as sickness risks (VHVR). Where legs are shown in first person, users either opted in or are playing mods.

---

## 2. IK techniques

### 2.1 FinalIK VRIK: the de-facto reference

**Structure [S 30,31].** VRIK solves spine (head target, optional pelvis target), two arms, two legs and a locomotion module.
- Locomotion has two modes. *Procedural* creates steps itself. *Animated* leaves the legs to an animator.
- Plant Feet pins the toes to the floor.
- Scale is 1 for an average adult.

**Default values** [S 32, a public mirror of VRIK's fields]:
- Spine:
  - `minHeadHeight 0.8`, `bodyPosStiffness 0.55`, `bodyRotStiffness 0.1`, `neckStiffness 0.2`
  - `rotateChestByHands 1`, `chestClampWeight 0.5` (0.5 allows 90° of chest rotation relative to the head [S 31])
  - `headClampWeight 0.6`, `moveBodyBackWhenCrouching 0.5`
  - `maxRootAngle 25°`: how far the head can turn before the root turns to follow
- Arms: `shoulderRotationMode YawPitch`, `armLengthMlp 1`
- Locomotion:
  - `footDistance 0.3 m`, `stepThreshold 0.4 m`, `angleThreshold 60°`, `comAngleMlp 1`
  - `maxVelocity 0.4`, `velocityFactor 0.4`, `maxLegStretch 1`
  - `rootSpeed 20`, `stepSpeed 3`, `relaxLegTwistMinAngle 20°`, step interpolation InOutSine

**Tuning proposals from Neos VR users** [S 33]:
- `maxRootAngle` 25→15
- `shoulderRotationWeight` 0.33→0.66 (hands reach their targets more accurately)
- `neckStiffness` 0.2→0.1, `bodyRotStiffness` 0.1→0
- `moveBodyBackWhenCrouching` 0.5→1
- `stepSpeed` 3→2, step interpolation InOutQuintic
- `relaxLegMinTwistAngle` 20→30 (less foot sliding when the head turns)
- Avatar height compensation 0.95→0.93

**VHVR's hybrid VRIK setup for the local player** [S 7]. VHVR is the closest analogue to this project:
- Legs are left to game animation: `locomotion.weight = 0`, `plantFeet = false`, leg weights 0.
- `bodyPosStiffness = bodyRotStiffness = 0`, `headClampWeight = 0` (for more vertical head look), `maxRootAngle = 180`, `minHeadHeight = 0`, pelvis weights 0.
- The head target is offset from the camera by (0, −0.165, −0.09) m × root scale.
- Root scale is 0.9, because Valheim characters are 2 m tall.
- Per-equipment hand-target offsets and elbow hints (`palmToThumbAxis`).
- Default player height offset is −0.2 m. Physical sneak starts when eye height drops below 70% of standing height [S 29].

### 2.2 Head-and-hands upper-body heuristics (Parger et al., VRST 2018)

The paper's approach [S 34,35]:
- Kinematic chains start at the **head**, not the pelvis.
- Heuristics set the shoulders and elbows, driven by the shoulder-to-hand distance, and avoid joint limits.
- Calibration takes the controller span in a T-pose and standing headset height.
- In a 55-person study the method was more accurate than generic IK. Users preferred it even over mocap, partly because the mocap had latency.
- A known limit: rotating the elbow while hands and head stay still cannot be recovered from these inputs.

The open-source implementation is VRArmIK (MIT). Its default constants are [S 9]:
- **Neck:** head position + head rotation × (0, −1, −0.05) × 0.03 m.
- **Shoulder centre:** neck + (0, −0.10, −0.02) m.
- **Shoulder yaw:** direction of the summed horizontal head-to-hand vectors, clamped to within 80° of head yaw. Hands-behind-head is detected by a 150–210° jump and handled by flipping 180°.
- **Forward tilt when crouching:** grows with height loss (factor 142° × relative height drop, plus 0.3 × head pitch), clamped to 50°.
- **Clavicles:** rotate forward up to 33° once the hand is more than 0.5 arm-lengths forward (multiplier 30° per arm-length). Upward rotation is also capped at 33°.
- **Reach:** if the hand is beyond 99.5% of arm length, the arm root slides toward the hand ("shoulder dislocation").
- **Elbow angle** around the shoulder-to-hand axis:
  - base 135°, minus 60° × normalised hand height
  - z-weights +260 (above) / −100 (below) when the hand is closer than 0.6 arm-lengths forward
  - x-weight −50
  - soft-clamped to 13–175°
- **Hand roll:** adds elbow rotation, smoothed over 0.08 s.
- **Wrist twist:** split 30% and 80% across two forearm twist bones.

UBIK ports this to Unreal [S 36].

### 2.3 FRIK's arm and torso solver (credits prog's Skyrim VRIK)

The code is public [S 37]. Units are Bethesda units; roughly 70 units per metre is a common community figure **[I]**.

**Torso and pelvis:**
- **Body yaw:** HMD yaw plus 0.7 × a "neck yaw" computed from the summed HMD-to-hand vectors.
  - The neck yaw is clamped to ±50°.
  - It is down-weighted when hands are above the head (−0.05 per unit of height) or crossed over the chest.
  - It is ignored when a hand is within 10 units of the HMD.
  - When pitch passes 80° it switches to a secondary angle.
- **Body pitch:** 105.3° × (fraction of height lost) + 0.1 × neck pitch. Divided by 1.2 out of power armour.
- **Neck and pelvis:**
  - The neck sits under the HMD and moves back by 5 × |neck pitch| × scale, so looking down pushes the body back.
  - The hip is placed torso-length from the neck along that pitch.
  - The spine is rotated to align hip→neck.
- **Scale:** skeleton scale = configured player height / default camera height. Changing height breaks weapon-hand alignment [S 28].

**Arms:**
- **Clavicle:** rotates toward the hand by up to 8% of arm length, ramping in once reach exceeds 50%.
- **Elbow direction:** starts from body forward and is twisted by wrist orientation, blended between two twist estimates and smoothed 25% per frame.
  - Limits run from −85° to +55°.
  - The limits tighten when hands are crossed in front of the chest (elbows lift), raised above the chest (elbows drop), or behind the body.
  - The elbow is then swung about 150° sideways, less when the hands cross or go behind the head.
- **Arm length:** the chain stretches proportionally past full length. If the hand is more than 2.25 × arm length away, or the tracked position is NaN/inf, the solver **gives up and leaves that arm on game animation**.
- **Hand smoothing:** optional slerp/lerp at strength 0.6, with player velocity removed first. It is off in scopes by default.

### 2.4 Procedural legs

**FRIK walk()** [S 37]:
- Feet are pulled 30% toward each other.
- Speed comes from HMD motion.
  - A step starts at ≥35 units/s, with a random first foot.
  - Walking stops below 20 units/s. A sharp slowdown (−20 units/s per frame) resets the target.
- Step time = clamp(cos(speed/140), 0.28, 0.50) s.
- Stride = speed × stepTime × 1.5, capped at 140.
- Foot lift = sin arc of height max(9 × stride/150, 1).
- The spine sways ±3° per step.
- The foot target re-aims if the direction dot product drops below 0.9.
- Legs are solved with an analytic knee.

**VRIK procedural** [S 30,32]: a step triggers when the target is more than 0.4 m away or rotated 60°, or when the centre of mass tips out of balance. Velocity prediction uses 0.4.

**Quake VR crouch** [S 11]: crouch ratio = calibratedHeight / currentHeight − 1, clamped to [0,1].

### 2.5 Body yaw from head vs hands (Quake VR)

From the Quake VR source [S 11]:
- **Yaw source:** head yaw is used as-is while pitch is within ±50°. Beyond that, the head's forward vector is blended toward its up vector (or down vector) in proportion to pitch/90, so looking straight down does not flip the yaw.
- **Hand contribution:** hand vectors are taken from points 10 units behind the head and 6.5 units either side, averaged and divided by 10. If the result points behind the body it is clamped to length 0.1.
- **Blend:** body direction = normalize(lerp(headFwd, handDir, 0.8)).
- **Fallback:** if either controller is inactive, pure head yaw.

### 2.6 Engine solvers

- **Unreal FBIK** (Control Rig) is a position-based solver [S 38]:
  - Per-bone position/rotation stiffness (0 = free, 1 = locked), used for example to calm the pelvis.
  - Rotation limits: free, limited or locked.
  - Pull-chain alpha and iterations; cost rises with iterations.
  - `HideBoneByName` hides a bone by setting its scale to 0 [S 39].
- **Unity Animation Rigging** [S 40]: Two Bone IK with a Hint object for the elbow/knee pole. Multi-Aim constraints on the spine.

### 2.7 Learned estimators

| Method | Summary |
|---|---|
| AvatarPoser (ECCV 2022) | Transformer; separates global from local motion; refines arms with IK so they still match the tracked hands [S 41] |
| AGRoL (CVPR 2023, Meta) | MLP diffusion model; 196 frames in 35 ms on a V100 using 5 DDIM steps [S 42] |
| BoDiffusion (ICCV 2023) | Conditional diffusion model [S 43] |
| EgoPoser (ECCV 2024) | Copes with hands tracked only while in view and with varied body shapes; over 600 fps [S 44] |
| QuestSim (SIGGRAPH Asia 2022) | Reinforcement-learning physics avatar; trained on 8 h of mocap from 172 people [S 45] |
| HMD-Poser | Runs in real time on the headset [S 46] |

**[I]** None of these is practical inside a Lua mod on the Stingray engine. Heuristics are the realistic path.

---

## 3. Presenting the body in first person

**Head.** Four known approaches:
1. Scale the head bones to ~0 for the local render only, keeping full-head clones for mirror and shadow (VRChat Head Chop [S 26], Unreal `HideBoneByName` [S 39]).
2. Push the head back or up instead of hiding it, so the shadow keeps a head. FRIK moves it back 5 units, plus 2 × neck pitch [S 28,37].
3. Hide headgear and face meshes by name. FRIK's list: helmet, hood, hat, mask, goggles, visor, hair, beard, eyes and similar. Its slots list covers hair, head, headband, eyes, beard, mouth, neck and scalp [S 28].
4. Headless first-person variants, as in Meta Avatars [S 12].

**Clipping and near plane.**
- VHVR uses a 0.09 m near clip and suggests adjusting it if the character's nose shows [S 29].
- FRIK moves the body back as the head pitches down [S 37].
- FRIK's FAQ accepts some line-of-sight blocking by bulky armour and suggests moving the body down or the camera up [S 28].
- **[I]** Darktide shoulder pads, backpacks and hoods need the same per-slot hide list, applied only to the local HMD view.

**Scopes and ADS.** FRIK hides the whole body while looking through a vanilla scope [S 28].

**Camera height vs model scale.** Two strategies:
- Scale the skeleton to the user: FRIK uses userHeight / defaultCameraHeight [S 37].
- Scale the model down a little and add a vertical offset: VHVR uses root 0.9 and −0.2 m [S 7,29].
- **[I]** For cosmetics, do not scale the model non-uniformly. Keep stock proportions, align the model's eye with the HMD, and let arm stretch or clavicle reach absorb length mismatch.

**Observers.** Meta prioritises accuracy for the self-view and animation quality for others [S 13]. **[I]** In Darktide the sim is stock and other players see the stock animation, so the IK body can be tuned purely for the local player's accuracy.

---

## 4. Shared virtual shoulder and chest (body IK plus weapon stock)

**Offset data from sources:**
- **VRArmIK** [S 9]: shoulder centre ≈ eye − 0.03 m (along head down/back) − 0.10 m down − 0.02 m back. Lateral offset comes from the rig's shoulder bones.
- **Google Daydream arm model** [S 10]: shoulder rest position (±0.17, −0.20, −0.03) m from the head. Neck model offset (0, 0.075, 0.08) m.
- **Quake VR virtual stock** [S 11]:
  - The shoulder is placed relative to a *body* anchor, not the head, on body yaw from section 2.5.
  - The anchor pitches forward by up to −35° × crouch ratio (crouch ratio capped at 0.8) and drops by 18 units × crouch ratio.
  - Offsets are x −1.5, y ±1.75, z 16 × height calibration.
  - The stock engages when the rear (holding) hand is within 10 units of the shoulder.
  - Aim direction = lerp(hand-to-hand, shoulder-to-front-hand, 0.5).
  - Engage and release blend at 5/s (~0.2 s).
  - Two-hand grip requires alignment with the gun's direction above 0.65, and can be disabled per weapon.
- **H3VR:** the virtual stock rests against the shoulder once the gun comes close to the body and pivots at a set distance [S 47].
- **HL2VR Unleashed:** blends two-handed aim with an approximate, tunable shoulder position [S 48].

**[I] Recommendations:**
- Compute the shoulder **once per frame** from the body solve, after body yaw, crouch and pitch. Both the rig's clavicle/upper-arm target and the stock pivot read it, so the gun butt visibly meets the model's shoulder.
- Anchor it on body yaw, not raw head yaw. Head-only yaw swings the stock when the player glances sideways. Hands-biased yaw (FRIK 0.7, Quake 0.8) follows the aim naturally.
- Use side = dominant hand, with a user-tunable offset. A starting point in metres: lateral 0.15–0.18, down 0.13–0.20 from the eye, back 0.02–0.05.

---

## 5. Recommended architecture for Darktide VR [I unless cited]

**Principles**
1. **Presentation only.** Pose the stock third-person unit after the game's animation update and before render. Never write back to the sim, hitboxes or camera. FRIK's hitboxes are unaffected by hiding [S 28], and Meta requires 1:1 head tracking [S 49].
2. **The camera is the HMD; the body follows it.** Nothing in the body solve moves the view. Clamps and smoothing apply to the body, never the camera.
3. **Hybrid.** Lower body from Darktide's stock locomotion animation (already driven by sim velocity, crouch, sprint, slide and jump), as VHVR does [S 7]. Upper body from IK. Keep a FRIK-style procedural-legs fallback [S 37] for states where the stock animation is unusable.

**Per-frame pipeline**
1. **Inputs:** HMD pose and controller poses. Gate on validity: NaN, lost tracking, or a hand more than ~2× arm length from the shoulder [S 37].
2. **Body yaw.**
   - Target = head yaw blended with hand direction (weight 0.7–0.8), with the Quake pitch-safe forward beyond ±50° [S 11,37].
   - Clamp the body-to-head delta to ~50–80° [S 9,37].
   - Turn the root once the delta passes ~15–25° (VRIK maxRootAngle [S 32,33]), smoothed over ~0.1–0.2 s.
3. **Neck.** Eye pose plus a head-local offset, down ~0.10–0.17 m and back ~0.02–0.09 m [S 7,9]. Calibrate against the model's eye-to-neck bone distance.
4. **Crouch and pitch.**
   - Crouch ratio from calibrated standing eye height [S 11].
   - Pitch the torso forward with height loss (VRArmIK/FRIK formulas [S 9,37]).
   - Move the pelvis back as the head pitches down (FRIK, VRIK moveBodyBack [S 32,37]).
5. **Pelvis.**
   - Horizontal: stays with the animated root, but is pulled toward under-the-neck with a limit.
   - Vertical: torso length below the neck. Don't let the stock animation's pelvis height override a real-life crouch; blend.
6. **Spine.** Rotate 2–3 spine bones so pelvis→neck aligns, spreading the rotation. Add some chest yaw toward the hands (VRIK rotateChestByHands [S 32]).
7. **Shared shoulder (section 4)**, then clavicle rotation up to ~30° forward/up [S 9], or an 8% reach offset [S 37].
8. **Arms.**
   - Analytic two-bone IK with a heuristic pole: VRArmIK elbow-angle rules, or FRIK's twist-limited elbow direction [S 9,37].
   - Allow a small stretch only near full reach. Past the limit, drop IK weight toward the animated arm.
   - Hand bone = controller pose × per-weapon grip offset (VHVR keeps separate equipped and unequipped offsets and elbow hints [S 7]).
9. **Local-view hiding.** Head bone scale 0 or push it back. Hide headgear, hood and face cosmetic meshes by slot. Near clip 0.05–0.09 m [S 26,28,29]. Hide the body while ADS through scopes [S 28].
10. **Blend weight.** A single master IK weight, eased over ~0.2 s, goes to 0 in:
    - cutscenes, menus, ledge hang, being carried or netted, knocked down, revive animations
    - any state where the stock third-person animation is authoritative.

**Calibration**
- Standing eye height is required: Parger, Quake VR and the Meta auto-calibration all use it [S 11,14,34].
- Arm span from a T-pose is optional [S 34]; VRChat supports span or height [S 27].
- Store it in the mod settings with a one-button recalibrate. Support a seated mode with separate offsets (FRIK keeps separate standing and seated offset sets [S 28]).

**Comfort rules**
- Never drive the camera from animation (root motion, stagger, dodge). VHVR keeps those options off by default [S 29].
- Offer settings for body off, arms only, and full body. Players differ, and shipped titles make legs or body optional [S 3,17,22].
- Prefer hiding over clipping: anything within ~15–25 cm of the eyes should be hidden. Daydream fades geometry at 0.25 m forward and 0.15 m to the side [S 10].
- Prefer tracking accuracy for the self-view [S 13].

**Performance**
- Everything above is closed-form: a few dozen vector and quaternion operations plus ~6 two-bone solves per frame. Iterative FBIK is not needed [S 38].
- In Lua: cache bone indices, reuse vector and quaternion objects, and skip the solve when the body isn't visible (menus, scopes).

**Suggested rollout**
1. Arms plus clavicles on the stock torso, with the head hidden.
2. Body yaw, torso pitch and crouch.
3. Stock-animation legs with pelvis reconciliation.
4. The virtual stock reads the shared shoulder.
5. Optional procedural legs.

---

## Sources

1. Game Informer, Valve on why arms don't work in VR (2020): https://gameinformer.com/interview/2020/03/23/valve-talks-half-life-alyx-and-why-arms-dont-work-in-vr
2. PC Gamer, keep Alyx armless: https://www.pcgamer.com/keep-alyx-armless/
3. UploadVR, Meta third-person avatar legs: https://www.uploadvr.com/meta-developing-third-person-avatar-legs/
4. TechCrunch, Meta avatars legs beta (2023): https://techcrunch.com/2023/08/29/meta-avatars-are-finally-getting-legs-in-beta/
5. NME, Armature on RE4 VR: https://www.nme.com/features/gaming-features/armature-studio-on-bringing-resident-evil-4-to-vr-3074898
6. FRIK repo: https://github.com/rollingrock/Fallout-4-VR-Body (Nexus page: https://www.nexusmods.com/fallout4/mods/53464)
7. VHVR VrikCreator.cs: https://github.com/brandonmousseau/vhvr-mod/blob/master/ValheimVRMod/Scripts/VrikCreator.cs
8. Doom 3 BFG VR: Fully Possessed: https://github.com/KozGit/DOOM-3-BFG-VR and PR #110 https://github.com/KozGit/DOOM-3-BFG-VR/pull/110
9. VRArmIK source (ShoulderPoser.cs, VRArmIK.cs): https://github.com/dabeschte/VRArmIK
10. Google GvrArmModel reference: https://developers.google.com/vr/reference/unity/class/GvrArmModel
11. Quake VR source (vr.cpp, vr_cvars.cpp): https://github.com/vittorioromeo/quakevr
12. Meta Avatars SDK OvrAvatarEntity (views and manifestations): https://developers.meta.com/horizon/documentation/unity/meta-avatars-ovravatarentity/
13. Meta Avatars best practices: https://developers.meta.com/horizon/documentation/unity/meta-avatars-best-practices/
14. Meta Movement SDK body tracking (Unity): https://developers.meta.com/horizon/documentation/unity/move-body-tracking/
15. Meta blog, IOBT and Generative Legs: https://developers.meta.com/horizon/blog/inside-out-body-tracking-and-generative-legs/
16. UploadVR, Quest 3 body tracking: https://www.uploadvr.com/quest-3-body-tracking/
17. Road to VR, Rec Room full-body avatars: https://roadtovr.com/rec-room-full-body-avatars-beta/ ; https://www.uploadvr.com/rec-room-full-body-avatars/
18. Road to VR, Lone Echo's virtual hands: https://www.roadtovr.com/lone-echos-virtual-hands-unassuming-vr-innovation/
19. GDC Vault, Lone Echo animation and locomotion: https://www.gdcvault.com/play/1024446/It-s-All-in-the
20. Boneworks (Wikipedia): https://en.wikipedia.org/wiki/Boneworks
21. UploadVR Bonelab review: https://www.uploadvr.com/bonelab-review/ ; Android Central: https://www.androidcentral.com/gaming/virtual-reality/bonelab-review-the-new-standard-for-vr-physics-based-games
22. 6DOF Reviews, Contractors: https://6dofreviews.com/reviews/games/quest/contractors-vr/
23. Into the Radius 2 discussions: https://steamcommunity.com/app/2307350/discussions/0/598519309481874809/
24. Blade & Sorcery FBT discussions: https://steamcommunity.com/app/629730/discussions/0/3202619099981120657/
25. Pavlov two-handed aiming thread: https://steamcommunity.com/app/555160/discussions/0/1489992080524926052/
26. VRChat wiki, Avatar Descriptor / Head Chop: https://wiki.vrchat.com/wiki/Avatar_Descriptor ; https://wiki.vrchat.com/wiki/Inverse_Kinematics
27. VRChat IK 2.0 options: https://docs.vrchat.com/docs/ik-20-features-and-options
28. FRIK config and FAQ: https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/data/config/FRIK.ini ; https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/docs/faq.md ; mesh_hide_face.ini and mesh_hide_slots.ini in the same folder
29. VHVR config: https://github.com/brandonmousseau/vhvr-mod/blob/master/ValheimVRMod/Utilities/VHVRConfig.cs
30. RootMotion VRIK docs: http://www.root-motion.com/finalikdox/html/page16.html (TLS certificate error when fetched; content seen via search summary)
31. VRIK inspector breakdown: https://eaysasi.wordpress.com/2025/07/23/vrik-inspector-breakdown/ ; Resonite VRIK: https://wiki.resonite.com/Component:VRIK
32. VRIK field defaults mirrored in BeatSaberCustomAvatars: https://github.com/nicoco007/BeatSaberCustomAvatars/blob/main/Source/CustomAvatar/Scripts/VRIKManager.cs
33. Neos VRIK tweak proposal: https://github.com/Neos-Metaverse/NeosPublic/issues/1598
34. Parger et al. 2018 (ACM): https://dl.acm.org/doi/10.1145/3281505.3281529
35. Parger blog: https://dabeschte.github.io/paper/2018/12/01/vrarmik.html
36. UBIKSolver: https://github.com/kjduling/UBIKSolver
37. FRIK Skeleton.cpp: https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/src/skeleton/Skeleton.cpp
38. Unreal Control Rig Full Body IK: https://dev.epicgames.com/documentation/en-us/unreal-engine/control-rig-full-body-ik-in-unreal-engine
39. Unreal HideBoneByName: https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/USkinnedMeshComponent/HideBoneByName
40. Unity Two Bone IK: https://docs.unity3d.com/Packages/com.unity.animation.rigging@1.3/manual/constraints/TwoBoneIKConstraint.html
41. AvatarPoser: https://arxiv.org/abs/2207.13784
42. AGRoL: https://dulucas.github.io/agrol/ ; https://arxiv.org/abs/2304.08577
43. BoDiffusion: https://arxiv.org/abs/2304.11118
44. EgoPoser: https://arxiv.org/abs/2308.06493
45. QuestSim: https://arxiv.org/abs/2209.09391
46. HMD-Poser: https://arxiv.org/abs/2403.03561
47. H3VR Gun Stabilization (via search summary): https://h3vr.fandom.com/wiki/Gun_Stabilization
48. HL2VR Unleashed README: https://github.com/vittorioromeo/HL2VRU
49. Meta locomotion comfort guidance: https://developers.meta.com/horizon/design/locomotion-comfort-usability/ ; https://developers.meta.com/horizon/design/comfort/
50. CNN, why no legs in VR (not fetchable, HTTP 451): https://www.cnn.com/2022/02/15/tech/vr-no-legs-explainer

**Gaps and limits.**
- Sources 30 (RootMotion's own site) and 47 (H3VR wiki) could not be fetched directly; their content was seen only through search summaries.
- The Nexus pages for FRIK and Skyrim VRIK were blocked (403), so the GitHub source was used instead.
- No primary sources were found for Onward, Population: One or Asgard's Wrath 2 body handling, nor for the Lone Echo GDC talk's technical details.
