# Two-handed weapon handling and virtual stocks in VR shooters: research notes

Date: 2026-09-15. Scope: web research only, no code changes.

> **Correction after reading the code (same day).** These notes were written from
> the todo's description of the mod. That description was wrong: the mod
> discards neither the dominant hand's rotation nor its roll.
> `Pose.correction` already applies the smallest rotation on top of the
> dominant hand's pose, as VRE and FRIK do. What differs is *where the
> smoothing sits*. The correction is low-passed in controller-local space, so
> a wrist rotation first swings the barrel off the support hand and then
> drifts back. See
> [the two-hand aim design](../two-hand-aim-design-2026-09-15.md) for the
> measurement and the fix.

Tags: **[S]** means a source says it (linked in brackets). **[I]** means my own inference or engineering reasoning, not stated by a source. Many shipped games don't publish how they do this. Where a game has no public detail, I say so rather than guess. Steam and Reddit posts are mostly from players, not developers, so they report how a game feels, not how it's built.

---

## 0. TL;DR for the Darktide mod

- The best evidence comes from open implementations: VRExpansionPlugin GS_GunTools for UE4/5, FRIK for Fallout 4 VR, and Unity XRI. None of them works the way the mod does now ("gun direction = dominant grip to support socket, dominant hand's rotation thrown away"). All three start from the gun as the **dominant hand places it, including its rotation**. They then apply the **smallest rotation** that swings the gun's authored foregrip line onto the real hand-to-hand line. **The gun's origin stays at the dominant grip.** Because that swing is the smallest possible rotation, **twist and roll still come from the dominant wrist** [S: VRE, FRIK source]. Right now the mod drops the dominant hand's rotation completely. That's the likeliest reason moving the right hand feels "off" [I].
- VRE's virtual stock works differently when "mounted". The aim line becomes **estimated shoulder to support hand**. The shoulder is the HMD position plus an offset turned by the head's yaw only, with its height following the dominant hand. The gun still sits at the dominant hand. The stock engages when the dominant hand is within **35 cm** of the shoulder point and blends in over a **20 cm** band [S: VRE source]. The result is that side-to-side movement of the dominant hand stops steering the aim, and the aim baseline gets longer [I].
- Add a One Euro filter to the support-hand point, not to the result [S: VRE does this]. Allow a distance falloff on how much the support hand counts [S: VRE GripInfluence 50/100 cm]. Settings players commonly get: a virtual stock toggle, physical-gunstock mode with per-weapon calibration, hand smoothing, breath hold, and grip or release modes [S: see section 2].

---

## 1. How shipped games and frameworks do two-handed aiming

### 1a. Frameworks with readable source or docs. This is the strongest evidence.

**VRExpansionPlugin (mordentral), `GS_GunTools` grip script, UE4/5** [S: source, header and cpp]
- The gun is first posed from the dominant (primary) controller, including its full rotation: `WorldTransform = Grip.RelativeTransform * Grip.AdditionTransform * ParentTransform`.
- Two-handed branch:
  - `BasePoint` and the pivot are the primary hand's location.
  - `frontLocOrig` is where the authored secondary grip point currently sits, given the primary hand's pose, relative to the primary hand.
  - `frontLoc` is the real secondary hand's location, relative to the same point.
  - The code then applies `FQuat::FindBetweenVectors(frontLocOrig, frontLoc)` about the primary pivot.
  - FindBetweenVectors gives the smallest rotation that turns one vector into the other, so it adds no twist around the barrel axis. **Roll therefore stays with the primary hand** [S for the code, I for the roll consequence].
- Offset handling: the rotation lines up the *authored* secondary grip direction with the *actual* hand direction. A physical hand that is off the socket still pivots correctly, and the gun doesn't snap to the hand. `PivotOffset` is described as "good for centering pivot into the palm" [S].
- Smoothing:
  - `SecondarySmoothing` is a One Euro low-pass filter applied to `frontLoc`, the secondary location, before the rotation is computed.
  - `SecondaryGripScaler` (0 to 1) sets the smoothing amount. Global One Euro defaults are MinCutoff 0.1, CutoffSlope 10, DeltaCutoff 10, in UE units (cm).
  - The struct's own defaults are 0.9 / 1.0 / 0.007 [S].
- Distance falloff:
  - `bUseSecondaryGripDistanceInfluence` turns it on.
  - `GripInfluenceDeadZone` = 50: "Distance from grip point where there is 100% influence".
  - `GripInfluenceDistanceToZero` = 100: "Distance before all influence is lost" [S].
- Virtual stock: see section 2.
- Recoil can be a logical blend (max translation and rotation, decay and lerp rates) or a physical force [S].

**FRIK, Fallout 4 VR body and weapon mod. Open source and the closest analogue: a flat game converted to VR** [S: WeaponPositionAdjuster.cpp, FRIK.ini]
- Aim: `weaponToOffhand = offhandPos - primaryHandPos`. That vector goes through a per-weapon `_offhandOffsetRot` (an authored foregrip-line correction). The code then takes `vec2Vec(adjusted, forward)` and composes it onto the weapon's existing rotation, which comes from the primary hand. After rotating, it moves the weapon back so "the grip stays in place". That makes the primary hand the pivot [S].
- It then turns the *primary hand bone* so the hand stays on the stock, with a manual correction noted as "no idea why it's off by specific angle" [S]. It is the same minimal-swing idea as VRE.
- When the grab counts: the off hand must be within about 17° of the barrel axis (`dot > 0.955`) and more than 15 game units from the primary hand. This avoids grabbing "when two hands are just close" [S].
- Grab and release modes:
  - (1) auto-snap in range, release by moving the hand away fast (`GripLetGoThreshold = 2.5`)
  - (2) auto-snap, release with the grip button
  - (3) hold grip to keep holding
  - (4) press to toggle [S: FRIK.ini]
- Smoothing: `DampenHands` defaults to rotation 0.6 and translation 0.6, on a 0 to 0.95 scale. A separate in-scope setting defaults to 0.2 and 0.2 and is off by default, with the warning "may be hard to do fine-tuned adjustments" [S].

**Unity XR Interaction Toolkit, `XRGeneralGrabTransformer.TwoHandedRotationMode`** [S: API docs]
- `FirstHandOnly`: uses only the first hand.
- `FirstHandDirectedTowardsSecondHand`: "using first hand and then directing the object towards the second one".
- `TwoHandedAverage`: directs toward the second hand but uses "the two handed average to determine the base rotation".
- In all modes the position anchors to the first hand. The grab-time offset (`m_OffsetPose`) is captured and kept, not snapped. The average mode slerps both hands' up vectors and flips the up vector if it reverses between frames, to stop roll flipping [S: package source via mirror, summarised by fetch tool; treat details as moderate confidence].

**HurricaneVR, physics hands for Unity** [S: search excerpt of the Cloudwalkin gun-system docs]
- The gun has a Grip grabbable and a Stabilizer grabbable. By default the stabilizer hand's *rotation strength* (torque) is removed, "so that only the grip hand can rotate the weapon".
- "Stabilizer Two Handed" overrides strength while both are held. The stabilizer can require the grip to be held first and drops when the grip is released.
- In a joint-driven setup the support hand's position force still bends the gun toward it, while twist comes from the grip hand. That is the physics version of the same split [I].

**ArcVR (Arctic's VR Guns, Garry's Mod)** [S: Workshop changelog, 7 March 2020]
- Added "alternative 2 hand aim", then "sensitivity option controlling balance between off and main hand for aiming". This is a player-facing blend weight between dominant-hand direction and hands-line direction.

### 1b. Shipped games (information is patchier)

| Game | What is publicly known |
|---|---|
| **Pavlov VR** | Dev davevillz on Steam: there is an intentional grip offset "to allow non-cumbersome two hand grip, so no matter where you grab near the weapon grip it will work". A "mount friendly" opt-out came in 0.8.12. A shooting-range calibration for weapon angle was added later [S]. Virtual Stock "makes stocked weapons lock to your virtual shoulder when held with two hands" [S]. Players say that without the stock "aiming is wobbly and recoil control is practically impossible", and with it the aim feels "constricting", "unadjustable" and slow, with no blind fire or point shooting [S]. Players also note that the controllers' pointing direction and the line between the hands can disagree, so moving the support hand shifts aim while the player "feels" on target [S]. In 2017 a player asked for a shoulder pivot, citing BrandonJLa's video, and the dev replied "experimental stuff on the stress_test beta" [S]. A 2020 UW report says Pavlov then parented the gun to the trigger hand with the front hand having no effect. This conflicts with the later Virtual Stock and two-hand reports, so treat it as dated or low confidence [S/I]. |
| **Onward** | Settings: Gunstock off, Physical or Virtual [S]. Virtual Gunstock Mode was added for the Rift S and WMR (inside-out tracking): when a two-handed weapon is raised it "automatically engages and locks the weapon in position", and "the front hand and body movement then control aiming". The stated cause is controllers close under the headset dropping out of camera range. UploadVR saw accurate scoped shots "although there is a slight loss of fine control" [S]. Physical mode has per-gun calibration using the thumbsticks to change the gun angle [S]. The older "Gun Stock" option treats the off-hand controller as tilted about 45° for locomotion [S, player]. |
| **H3VR** | "Virtual Stock" option: with two hands and a stocked gun, the stock "rest[s]" against the shoulder when brought close, "allowing you to pivot the gun at a set distance away from you and reduce recoil". Pistol stocks add this to pistols. Adjustable stock length moves the sights nearer to or farther from the eye [S: H3VR wiki via search excerpt]. |
| **Contractors** | Physical Gunstock Mode with per-weapon calibration in the range [S: vendor guides]. Players report that gunstock calibration follows the "Movement Hand" setting rather than "Weapon Mount", which breaks it for left-handers [S]. |
| **Boneworks / Bonelab** | Fully physics-driven body. The stock is steadied by resting against the physics body at the shoulder or hip. A 2020 academic summary describes the shoulder as "the primary pivot" [S]. Pitfalls players report: the stock gets stuck on the chest or elbows and can't come up to ADS; cross-eye-dominant players have to tilt their head [S]. Bonelab players say "the mix of locking to shoulder and the smoothing is causing weapons to feel pretty awful" (floaty), and that switching to two hands "shifts aim and loses zero" [S]. |
| **Half-Life: Alyx** | Every weapon is one-handed so the gravity-glove hand stays free. You can steady the gun with the off hand [S]. I found no source saying the off hand changes the aim, so it is likely mainly visual support [I, unverified]. |
| **Into the Radius** | Virtual stock under Gameplay: pull the rifle to your "shoulder" and it stops there. It "almost entirely fixes" shake on rifles [S]. Some SMGs (MP5, PP-2000, PP-91) "pivot off of different points" and use the foregrip "like a ball joint", so the stock doesn't help them [S, player]. Breath hold: press A/X on the off hand while two-handing and aim becomes "super slow and stable" [S]. |
| **Ghosts of Tabor** | Default, Virtual and Physical gunstock modes. Virtual "places the in-game buttstock in your middle chest area instead of your shoulder". There is also a "Hand Smoothing" toggle and a "Janky Sight Fix" [S: Sanlaki guide]. |
| **Arizona Sunshine (2)** | When two-handing, the support hand snaps to the receiver, and the controllers need to be held next to each other [S: search excerpt]. |
| **Medal of Honor: Above and Beyond** | A review notes the off hand "will fly confusingly away from the foregrip and to the charging handle" [S]. No aiming model is published. |
| **Firewall Ultra (PSVR2)** | A dedicated ADS mode on L2/R2 gives "a virtual stock, so that the butt of your gun is on your shoulder", making it easier to "aim by turning your head". It also forces less natural arm positions. Eye tracking is used "as part of stabilizing your aim". Primary weapons switch between one-handed and two-handed holds [S: UploadVR]. |
| **Zero Caliber** | Its virtual stock "reduced controller jitter and slowed the rate at which rifles would slew" [S, player description]. |
| **Walking Dead: Saints & Sinners** | Weapons have simulated weight. Two-handed guns "flop around" and are hard to grab with the second hand, and raising a pistol "takes a long time" [S, players]. |
| **Hard Bullet** | "Tactical" mode needs two hands to manage recoil [S]. Found nothing on the aiming maths. |
| **Stride** | Nothing found. |
| **Firewall Zero Hour (PSVR1)** | Designed around the PS VR Aim controller, a single rigid device. Found no two-controller aiming details. |

---

## 2. Virtual stock, stock emulation and gunstock accessories

**Concrete, published algorithm (VRE `GS_GunTools`)** [S: source]
- Anchor or "mount": `MountWorld = HMD location + PureYaw.RotateVector(StockSnapOffset)`, rotated by head yaw only. `StockSnapOffset` is "an offset to apply to the HMD location to be considered the neck / mount pivot". It defaults to zero, so a game has to author a shoulder offset. A `VirtualStockComponent` can replace the HMD.
- `bAdjustZOfStockToPrimaryHand` defaults to true and replaces the anchor's height with the primary hand's height.
- Engagement: it compares the distance between the **primary hand** and the anchor. `StockSnapDistance` = 35 cm. `StockSnapLerpThreshold` = 20 cm ("distance from the edge ... where it will be at 100% influence"). `StockLerpValue` blends from 0 to 1 across that band.
- It works only while the secondary hand is gripping.
- When mounted, the rotation maps the gun's forward first onto (primary hand minus anchor), then onto (secondary hand minus anchor). The pivot stays at the primary hand. In effect the **barrel axis is parallel to shoulder-to-support-hand** while the gun stays in the dominant hand [S for the code, I for the geometric reading].
- Optional One Euro smoothing of the stock-side hand (`bSmoothStockHand`, `SmoothingValueForStock` 0 to 1). Settings can be global, saved per player (`bUseGlobalVirtualStockSettings`), plus a debug draw [S].

**How games present it**
- As a toggle: Pavlov, H3VR, Into the Radius, Onward, Ghosts of Tabor [S].
- As a mode that turns on automatically when the gun is raised: Onward [S].
- As a held ADS button: Firewall Ultra [S].
- With a chest-centred anchor instead of the shoulder: Ghosts of Tabor [S].
- Through stock length: H3VR adjustable stocks move the eye-to-sight distance [S].
- As physical body collision: Boneworks [S].
- The trade-offs players report: steadier and better at range and with recoil, but less freedom (no blind fire or point shooting), a "slight loss of fine control", and floatiness when combined with heavy smoothing [S: Pavlov, Onward/UploadVR, Bonelab threads].

**Physical gunstocks (ProTubeVR MagTube, Sanlaki, and others)**
- Why people use them: more contact points (hands, shoulder, cheek, torso) remove shaky hands and give steady ADS. Magnets release the controllers for reloads. A sling takes weight off [S: ProTubeVR, GBAtemp review].
- A players' framing: "You NEED a third point of contact to pivot" [S, Onward thread].
- Games support them with per-weapon calibration of grip angle and offset: Onward, Contractors, Pavlov, Ghosts of Tabor, Breachers at -30 to -40° for Index [S].
- A stock couples the two controllers rigidly. A software model that treats the controllers as independent and snaps them to authored sockets fights the stock unless the grip angle can be calibrated [I, consistent with the Pavlov "mount friendly" and calibration history].

**Stocks and ADS (sight-to-eye alignment)**
- Firewall Ultra's stock ADS lets you aim "by turning your head" [S]. H3VR uses stock length to set eye relief [S]. Boneworks' realistic shoulder placement hurts cross-eye-dominant players and forces head tilt [S].
- Onward's virtual stock exists partly because inside-out cameras lose controllers held close under the headset during ADS [S]. That applies to Quest 3 as well [I].
- Design implication [I]:
  - Place the anchor so that, when mounted, the authored sight line passes near the **dominant eye** (the HMD eye position), not the head centre.
  - The vertical offset should be roughly the sight height above the stock line.
  - Let players shift the anchor sideways for cross-dominance, and give a per-weapon sight-height or offset correction.

---

## 3. Developer write-ups, discussions and pitfalls

- **Hands line vs controller pointing.** Players can "feel" on target from wrist orientation while the hands line points elsewhere, so moving the support hand shifts aim unexpectedly [S: Pavlov thread]. The mod has the mirror image: moving the dominant hand pivots the gun around the support socket while the wrist says "I haven't re-aimed" [I].
- **Lever-arm amplification** [I, standard geometry]. Angular error ≈ lateral displacement / baseline.
  - Grip-to-foregrip baseline of about 0.3 m: 1 cm of unintended dominant-hand drift ≈ 1.9° of aim change, and 1 mm of tracking jitter ≈ 0.19°.
  - Shoulder-to-support baseline of about 0.6 m: roughly half of that.
  - Pinning the rear point to a head-derived anchor removes dominant-hand lateral noise from the aim altogether. That is the core argument for a virtual stock.
  - For scale, published Quest 2 controller precision studies report millimetre-level variability and sub-degree rotational variability [S: MDPI Actuators paper and ACM tracking comparison, via search excerpts]. Controller rotation noise (about 0.1 to 0.3°) is similar in size to hands-line noise at a 30 cm baseline, so "wrist rotation is too noisy to use" doesn't hold up [I].
- **Short-baseline and crossed hands.** FRIK rejects grips closer than 15 units or more than about 17° off-axis [S]. VRE fades support influence between 50 and 100 cm from the grip point [S]. Also [I]: below about 10 to 15 cm, fall back to one-handed or fade the swing toward zero. If the support hand ends up behind the grip (the dot product of the hands line with the authored forward is ≤ 0), release or ignore it to avoid a 180° flip.
- **Roll flips.** Look-at builds that need an up vector flip when the barrel passes vertical. XRI guards against this by negating an up vector that reversed between frames [S]. Minimal-swing composition avoids the problem because roll comes from the wrist [I].
- **Wrist strain.** Forcing the hands to keep their relative rotation was "somewhat uncomfortable" when aiming low. Players preferred the lenient relative-position model [S: UW report]. So don't demand wrist agreement, and don't ignore the wrist completely either [I].
- **Smoothing.** The One Euro filter changes its cutoff with speed. Tuning: set beta to 0, lower mincutoff until jitter at rest is acceptable, then raise beta until fast moves stop lagging. Starting point is mincutoff about 1 Hz with beta beginning at 0.001 [S: Casiez]. Too much smoothing plus a shoulder lock feels floaty [S: Bonelab]. FRIK warns that in-scope dampening makes fine adjustment hard [S]. Filter the *support point*, which is the noisy input to the hands line, as VRE does, rather than the whole gun pose, so the trigger hand stays 1:1 [I].
- **Physics vs kinematic.** Physics weight (Saints & Sinners, Boneworks) adds a feeling of heft but makes guns lag and flop and get stuck on the body [S]. For a mod over a non-physics game, kinematic plus filtering is the better fit [I].
- **Grip snapping and offsets.** Pavlov kept an offset so any grab near the grip works, but had to add a "mount friendly" opt-out and later calibration for stock users [S]. VRE and XRI keep the grab-time offset and align *directions*, not positions [S]. Auto-moving the support hand to other interaction points confuses players (MoH) [S].

Developer talks: I found no GDC or Connect talk giving two-handed aiming maths in usable detail. A widely cited BrandonJLa (Stress Level Zero) shoulder-pivot demo video is referenced in the Pavlov thread (youtube.com/watch?v=iYrkXK3V2ik). I didn't watch it and can't vouch for its contents. The open-source code above is the most concrete evidence available.

---

## 4. Recommended model for the mod

All numbers are starting points. The ones marked [S] come from sources, and the rest are [I].

```
inputs per frame: Pd (dominant grip pos), Rd (dominant rot), Ps (support pos)
authored: gripSocket G, foregripSocket F on the weapon; per-weapon offsetRot (optional)

1. pose0      = weapon posed rigidly by dominant hand (Pd, Rd) incl. authored grip offset
2. Ps_f       = OneEuro(Ps)                      # filter support point only
3. a          = pose0.rotate(F - G)              # authored foregrip dir under dominant pose
4. b          = Ps_f - Pd                        # actual hands line
5. gate       : |b| > ~12-15 cm, angle(a,b) < grab cone (FRIK ~17 deg to grab; wider to keep holding)
6. w          = support weight: 1 inside dead zone, fading to 0 by far limit
                 (VRE 50 -> 100 cm from grip point [S]); optional player "two-hand balance" [S ArcVR]
7. q_swing    = slerp(identity, FromTo(a, b), w)  # minimal rotation => roll stays from Rd [S VRE/FRIK]
8. stock (optional, rifles):
     A        = HMD_pos + yawOnly(HMD).rotate(shoulderOffset); A.z = Pd.z   [S VRE]
     s        = 0 beyond 35 cm of Pd, 1 inside 15 cm (35/20 cm band)          [S VRE]
     b_stock  = Ps_f - A
     q_swing  = slerp(q_swing, FromTo(a, b_stock) composed so Pd stays pivot, s)
9. final      = rotate pose0 by q_swing about Pd  # origin stays at dominant grip [S VRE/XRI/FRIK]
```

Why this shape:
- **Origin at the dominant grip.** Every implementation examined does this, and it keeps the trigger hand 1:1 [S].
- **Minimal swing instead of a pure look-at.** The dominant wrist keeps roll and twist, and wrist pitch and yaw still count as the starting pose. The support hand then corrects direction by the smallest amount [S for the technique, I for why it feels better]. Applied to the mod: moving the right hand without turning the wrist still rotates the gun toward the support hand. But when the player turns the wrist, as people naturally do while re-aiming, the result follows their intent, and cant or roll works [I].
- **Stock anchor.** Once engaged it removes dominant-hand lateral noise from aim, lengthens the baseline, and matches the real rifle's three contact points [S for the mechanism and player benefit, I for the noise argument]. Keep it optional and auto-engaging by distance, because it costs freedom and fine control [S].

**Typical options to expose**
- Virtual stock: off / auto / ADS-button. Offsets for anchor side, height and forward, with a cross-dominance side flip.
- Engage distance.
- Physical gunstock mode with per-weapon angle calibration [S: Onward, Contractors, Pavlov, GoT].
- Hand smoothing strength, normal and scoped [S: GoT, FRIK].
- Two-hand balance weight [S: ArcVR].
- Grip mode: auto-snap or button, hold or toggle, fast-pull release [S: FRIK].
- Breath hold for extra smoothing on a button [S: ITR].

**Suggested A/B tests with the user** [I]
1. Current look-at vs minimal swing (w = 1).
2. Minimal swing with w = 0.7.
3. Minimal swing plus stock anchor.

For each, move the right hand while two-handing and check whether it now matches the left-hand feel.

---

## Sources

- VRExpansionPlugin GS_GunTools.h: https://raw.githubusercontent.com/mordentral/VRExpansionPlugin/master/VRExpansionPlugin/Source/VRExpansionPlugin/Public/GripScripts/GS_GunTools.h
- VRExpansionPlugin GS_GunTools.cpp: https://raw.githubusercontent.com/mordentral/VRExpansionPlugin/master/VRExpansionPlugin/Source/VRExpansionPlugin/Private/GripScripts/GS_GunTools.cpp
- VRExpansionPlugin VRBPDatatypes.h (One Euro struct, secondary grip types): https://raw.githubusercontent.com/mordentral/VRExpansionPlugin/master/VRExpansionPlugin/Source/VRExpansionPlugin/Public/VRBPDatatypes.h
- VRExpansionPlugin VRGlobalSettings.cpp (One Euro defaults): https://raw.githubusercontent.com/mordentral/VRExpansionPlugin/master/VRExpansionPlugin/Source/VRExpansionPlugin/Private/VRGlobalSettings.cpp
- FRIK repo: https://github.com/rollingrock/Fallout-4-VR-Body (src/weapon-position/WeaponPositionAdjuster.cpp, data/config/FRIK.ini)
- Unity XRI TwoHandedRotationMode: https://docs.unity3d.com/Packages/com.unity.xr.interaction.toolkit@2.5/api/UnityEngine.XR.Interaction.Toolkit.Transformers.XRGeneralGrabTransformer.TwoHandedRotationMode.html
- XRI source mirror: https://raw.githubusercontent.com/needle-mirror/com.unity.xr.interaction.toolkit/master/Runtime/Interaction/Transformers/XRGeneralGrabTransformer.cs
- HurricaneVR gun system (search excerpt): https://www.cloudwalkingames.com/en/interactions/gun-system
- ArcVR changelog: https://steamcommunity.com/sharedfiles/filedetails/changelog/1985324827?l=danish
- Pavlov gun placement, dev davevillz: https://steamcommunity.com/app/555160/discussions/0/154644787622699656
- Pavlov shoulder pivot request, dev reply: https://steamcommunity.com/app/555160/discussions/0/1489992080524926052/
- Pavlov virtual stock: https://steamcommunity.com/app/555160/discussions/0/1744480967009513148/
- Pavlov two-hand wobble / hands line: https://steamcommunity.com/app/555160/discussions/0/4629230582747976163
- Pavlov virtual stock trade-offs: https://steamcommunity.com/app/555160/discussions/0/4739473745771673963
- Onward Virtual Gunstock Mode (UploadVR): https://www.uploadvr.com/onward-inside-out-tracking-update/
- Onward virtual gun stock thread: https://steamcommunity.com/app/496240/discussions/0/1621724915773046011/
- Onward "Gun Stock" setting thread: https://steamcommunity.com/app/496240/discussions/0/1480982971163357192/
- H3VR Gun Stabilization wiki (search excerpt): https://h3vr.fandom.com/wiki/Gun_Stabilization
- H3VR stock option thread: https://steamcommunity.com/app/450540/discussions/0/1694923613860095941/
- Contractors left-handed calibration: https://steamcommunity.com/app/963930/discussions/0/1837937637898871531/
- Boneworks gun shoulder locking: https://steamcommunity.com/app/823500/discussions/0/1740009710700044986/
- Bonelab aim smoothing: https://steamcommunity.com/app/1592190/discussions/0/3395175706746481425/
- Bonelab gun handling: https://steamcommunity.com/app/1592190/discussions/0/3370405530901593802/
- Half-Life: Alyx two-handed thread: https://steamcommunity.com/app/546560/discussions/0/1861615926797145137/
- Into the Radius virtual stock: https://steamcommunity.com/app/1012790/discussions/0/3269061071534037082
- Into the Radius SMG pivots: https://steamcommunity.com/app/1012790/discussions/0/3877093063232387264/
- Into the Radius 2 breath hold: https://steamcommunity.com/app/2307350/discussions/0/4518884060226386091/
- Ghosts of Tabor settings (Sanlaki): https://sanlaki.shop/blogs/vr-gaming/best-vr-gunstock-settings-for-ghost-of-tabor
- Gunstock settings per game (Sanlaki): https://sanlaki.shop/blogs/vr-accessories-guide/game-settings-for-the-sanlaki-gunstock
- Contractors gunstock guide (Wield VR, search excerpt): https://wieldvr.com/blogs/news/best-contractors-vr-gunstock-setup-calibration-and-top-recommendations
- Firewall Ultra review (UploadVR): https://www.uploadvr.com/firewall-ultra-review/
- Firewall Ultra hands-on (UploadVR): https://www.uploadvr.com/firewall-ultra-hands-on-blinded-psvr-2/
- MoH Above and Beyond review (Road to VR): https://www.roadtovr.com/medal-of-honor-above-and-beyond-review-war-never-felt-so-bland/
- Zero Caliber virtual stock: https://steamcommunity.com/app/877200/discussions/0/3722819013062038015
- Saints & Sinners two-handed physics (search-engine excerpt; I didn't open the thread, and the quote may come from another result in the same search): https://steamcommunity.com/app/916840/discussions/0/3091137796304440679/
- Arizona Sunshine two-handed (search-engine excerpt; I didn't open the thread, and the quote may come from another result in the same search): https://steamcommunity.com/app/342180/discussions/0/1694922345929945678/
- Hard Bullet (UploadVR): https://www.uploadvr.com/vr-action-shooter-hard-bullet-finds-a-new-home-on-quest-3/
- ProTubeVR MagTube: https://www.protubevr.com/en/vr-fps-gunstock-vr-accessories/537-meta-quest-3-vr-gunstock-magtube-best-vr-gun-stock.html
- MagTube review (GBAtemp): https://gbatemp.net/review/protubevr-magtube-vr-gunstock.1648/
- Rudasics, "Exploring Methods for Two-Handed Object Interaction in VR Using 6-DOF Controllers" (UW CSE490V, 2020): https://courses.cs.washington.edu/courses/cse490v/20wi/public/report_15.pdf
- 1€ filter (Casiez): https://gery.casiez.net/1euro/
- Quest 2 controller precision (MDPI Actuators, search excerpt): https://www.mdpi.com/2076-0825/12/6/257
- SteamVR 2.0 vs Quest 2 tracking (ACM, search excerpt): https://dl.acm.org/doi/fullHtml/10.1145/3463914.3463921
- Half-Life 2: VR Mod features: https://halflife2vr.com/features/
- BrandonJLa shoulder pivot video (referenced, not viewed): https://www.youtube.com/watch?v=iYrkXK3V2ik
