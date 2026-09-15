# Research: arm length calibration in VR (16 September 2026)

Web research for the arm length design
([arm-length-calibration-2026-09-16.md](../arm-length-calibration-2026-09-16.md)).
Gathered by a research subagent and summarised here with its sources. Where
no usable source was found (Owlchemy and Connect talks, Pavlov, Onward, H3VR,
Hand Physics, Kinemation, Half-Life: Alyx, Unity Animation Rigging), nothing
is claimed. Calculations on the ANSUR II anthropometric survey (6,068 US Army
adults, [calmcode copy](https://calmcode.io/static/data/ergonomics.csv)) are
marked **[ANSUR calc]**; they were run for this note, not taken from a paper.

## 1. Calibration poses in shipped products and frameworks

- **VRArmIK (Parger, TU Graz 2018).** Standing headset height, then a
  T-pose for the controller-to-controller distance; one sample, no
  rejection. Reference 1.70 m height, 1.39 m width
  ([PoseManager.cs](https://github.com/dabeschte/VRArmIK/blob/master/Assets/Plugins/VRArmIK/Scripts/PoseManager.cs),
  [thesis](https://diglib.tugraz.at/download.php?id=5c4a48dc5a282&amp;location=browse)).
- **Meta Movement SDK.** Height auto-calibrates in the first ~10 s with the
  user standing; seated users draw a ~0.3 m circle with an extended arm.
  Retargeting scales height from the wrist positions in a T-pose and scales the
  arms to match them
  ([Unity body tracking](https://developers.meta.com/horizon/documentation/unity/move-body-tracking/),
  [Unreal advanced](https://developers.meta.com/horizon/documentation/unreal/unreal-movement-advanced-materials/)).
- **Final IK VRIK.** Documented calibration is a uniform scale from head
  height; arm length is a multiplier (`armLengthMlp`), not measured
  ([VRIK docs](http://www.root-motion.com/finalikdox/html/page16.html)).
- **VRChat.** "Measure by arm span or avatar height", with a custom arm ratio
  (default 0.4537, around 0.415 may fit better); measure-by-height tends to
  work better for full-body tracking
  ([IK 2.0](https://docs.vrchat.com/docs/ik-20-features-and-options)).
- **FRIK (Fallout 4 VR).** Manual arm length slider saved to ini
  ([FRIK.ini](https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/data/config/FRIK.ini)).
- **Skyrim VRIK.** A calibration power sets height and body size in one
  pass, plus an arm length setting
  ([MGO](https://synergyvr.org/mgo/mod-highlights/vrik/)).
- **Bonelab.** Typed body measurements including wingspan, no pose
  ([UploadVR](https://www.uploadvr.com/bonelab-avatar-system/)).
- **Blade &amp; Sorcery.** Limb length slider
  ([Steam](https://steamcommunity.com/app/629730/discussions/2/1743355067107794137/)).
- **SlimeVR AutoBone.** The only multi-sample fit found: about 1,500 samples,
  optimised bone lengths, with body trackers
  ([SlimeVR docs](https://docs.slimevr.dev/server/body-config.html)).

No product surveyed captures an arms-forward reach pose. Shipped practice is
one standing height plus either one T-pose span or a slider; no published
outlier rejection was found.

## 2. Deriving arm length

- **VRArmIK formula:** arm length = (wrist span - shoulder width) / 2, split
  48 % upper arm and 52 % forearm; the author calls the maths good enough for
  the study, not production
  ([ArmTransforms.cs](https://github.com/dabeschte/VRArmIK/blob/master/Assets/Plugins/VRArmIK/Scripts/ArmTransforms.cs),
  [blog](https://dabeschte.github.io/paper/2018/12/01/vrarmik.html)).
- **Height ratios (Drillis and Contini via Winter):** upper arm 0.186 H,
  forearm 0.146 H, hand 0.108 H, shoulder height 0.818 H; to be used "in the
  absence of better data, preferably measured directly"
  ([Winter ch. 4](https://courses.grainger.illinois.edu/me481/sp2021/Anthro-Winter.pdf)).
- **Arm span is about height** (ratio mostly 0.97-1.03).
- **[ANSUR calc]:**
  - eye height ≈ 0.935 × stature;
  - biacromial width 0.233 × stature;
  - upper arm 0.191 × stature, forearm 0.151 × stature (upper about 56 % of
    the two);
  - wrist crease to grip centre about 6 cm;
  - grip-to-grip span ≈ 1.008 × eye height - 0.107 m, residual SD 4.4 cm.

  Surface segment lengths overshoot the real span by about 19 cm (landmark
  definitions), so ratios cannot fix the split between shoulder width and arm
  length on their own.
- **OpenXR grip pose:** a fixed point that "generally lines up with the palm
  centroid" ([OpenXR spec](https://registry.khronos.org/OpenXR/specs/1.0/html/xrspec.html)),
  so the wrist sits roughly 6-8 cm behind it.

## 3. Applying it to a skinned avatar

- **Meta:** per-limb scaling does not preserve proportions but minimises mesh
  deformation; the alternative uniform mode keeps proportions and loses
  position accuracy.
- **VRIK `armLengthMlp`** displaces the hand and forearm local positions
  rather than scaling bones; large values look unnatural
  ([Resonite](https://wiki.resonite.com/Common_Avatar_Issues)).
- **FRIK** multiplies the rig's upper-arm and forearm lengths and writes the
  forearm and hand local positions
  ([Skeleton.cpp](https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/src/skeleton/Skeleton.cpp)).
- Scaling a bone also scales the cross-section (thicker sleeves and armour);
  moving child positions stretches skin along the bone only.

## 4. Runtime reach mismatch

- **FRIK:** stretch past full reach is split by segment length, no cap until
  2.25 × arm length; the clavicle moves the shoulder up to 8 % of arm length
  toward the hand, ramped from 0.5 to 1.35 × arm length; elbow twist smoothed
  at 0.25 per frame.
- **VRIK:** `stretchCurve` maps distance over arm length to stretch;
  `shoulderRotationWeight` 1 by default; bend normal from chest direction and
  hand orientation
  ([IKSolverVRArm.cs](https://github.com/xyonico/CustomAvatarsPlugin/blob/master/CustomAvatar/VRIK/IKSolverVRArm.cs)).
- **Parger:** shoulder yaw from the head-to-hands directions, clamped to ±90
  degrees of the head; shoulders rotate forward past a reach threshold;
  VRArmIK lets the arm dislocate when out of reach.

## 5. Embodiment research

- **Stretch your reach (CHI 2024, 40 participants):** stretching the arms to
  meet the controller gave higher embodiment, preference and performance; mean
  maximum stretch 26.3 cm ([arXiv](https://arxiv.org/html/2407.08011)).
- **Articular limits:** ownership dropped only when the real arm was fully
  extended while the avatar elbow stayed bent; the authors suggest virtual
  limbs slightly shorter than real ones
  ([PMC8890650](https://pmc.ncbi.nlm.nih.gov/articles/PMC8890650/)).
- **Kilteni 2012:** ownership held for arms up to 3 × real length when the
  movement matched ([PLoS ONE](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0040867)).
