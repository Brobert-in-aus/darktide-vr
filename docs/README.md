# Documentation index

`docs/` holds two kinds of note: **current contracts and status**, which are
maintained, and **dated evidence**, which records what was measured on a day
and is superseded by later notes. Start from the current entry points; treat
anything with a date in its name as history unless a current note links to it.

## Current entry points

- [Current status and operation](CURRENT-STATUS.md)
- [Working agreements](../AGENTS.md) and [project infrastructure](PROJECT-INFRASTRUCTURE.md)
- [Maintenance implementation plan](maintenance-plan-2026-09-05.md)
- **The current work is always the newest dated file of each kind**: the
  newest [handover](handoffs/), the newest `todo-*.md` and the newest
  `test-checklist-*.md` in [phase1](phase1/). As of 18 September that is the
  [17 September handover](handoffs/2026-09-17-session.md), the
  [18 September todo](phase1/todo-2026-09-18.md) and its
  [detailed away-list](phase1/todo-2026-09-18-detailed.md), and the
  [worn checklist](phase1/test-checklist-2026-09-16.md) (items 47 to 54).
  The two worn rounds of 17 September are recorded in
  [worn-results-2026-09-17.md](phase1/worn-results-2026-09-17.md).
- [User guide](USER-GUIDE.md) (ships in the package), [very early alpha readiness](EARLY-ALPHA-READINESS.md) and [release package](RUNTIME-PACKAGE.md)
- [Whole-project code review, 11 September](CODE-REVIEW-2026-09-11.md)
- [Performance bundle, 11 September](PERFORMANCE-BUNDLE-2026-09-11.md): the
  day's optimisations as the deployed baseline, launcher defaults, controls
- [Remote-server mission admission, 12 September](REMOTE-MISSION-ADMISSION-2026-09-12.md):
  stock-input route in dedicated-server missions, setting, worn check

## Contracts that govern changes

- Stereo and presentation: [stereo camera coherence](STEREO-CAMERA-COHERENCE.md),
  [XR swapchain resource state](XR-SWAPCHAIN-RESOURCE-STATE.md),
  [XR delivery cadence](XR-DELIVERY-CADENCE.md),
  [native original ring](NATIVE-ORIGINAL-RING.md) and its
  [legacy dependencies](NATIVE-RING-LEGACY-DEPENDENCIES.md),
  [FG recovery after a DLSS quality change](FG-QUALITY-SWITCH-RECOVERY-2026-09-11.md)
- Desktop and capture: [desktop mirror performance contract](DESKTOP-MIRROR-PERFORMANCE-CONTRACT.md),
  [on-demand window capture](ON-DEMAND-WINDOW-CAPTURE.md),
  [simulator window capture control](SIMULATOR-WINDOW-CAPTURE-2026-09-11.md)
- Engine safety: [shadow atlas capture contract](SHADOW-ATLAS-CAPTURE-CONTRACT.md),
  [stereo shadow reuse contract](STEREO-SHADOW-REUSE-CONTRACT.md),
  [cluster list initialization contract](CLUSTER-LIST-INITIALIZATION-CONTRACT.md)
- Input and gameplay: [stock melee input contract](STOCK-MELEE-INPUT-CONTRACT.md),
  [tracked melee design](TRACKED-MELEE-DESIGN.md), [two-handing](VR-TWO-HANDING-ADS.md),
  [roomscale collider follow](ROOMSCALE-COLLIDER-FOLLOW.md),
  [Psykhanium online rules](PSYKHANIUM-ONLINE-RULES.md),
  [online mission requirements](ONLINE-MISSION-REQUIREMENTS.md)
- Runtimes and headsets: [SteamVR and Steam Frame readiness](STEAMVR-STEAM-FRAME.md)
- Render cost: [Foveated rendering](FOVEATED-RENDERING.md) -- what variable rate
  shading would take here, and why the OpenXR foveation extensions cannot help
  (investigation, not yet validated live)
- Deployment and operation: [deployment transactions](DEPLOYMENT-TRANSACTIONS.md),
  [SoloPlay setup](SOLOPLAY-SETUP.md), [Quest passthrough recovery](QUEST-PASSTHROUGH-RECOVERY.md),
  [synthetic frame-generation benchmark](SYNTHETIC-FRAMEGEN-BENCHMARK.md)

## Design and reference

- [Design brief](DARKTIDE-VR-DESIGN-BRIEF.md), [remaining development](REMAINING-DEVELOPMENT.md),
  [post-release](POST-RELEASE.md), [mission readiness](MISSION-READINESS.md)
- Reference PDFs: 6DOF head tracking, AER modes and optical-flow frame
  generation, motion-smoothing AER fix guide, making 6DOF mods 3D

## Dated evidence

Performance trials, audits and investigations are named by topic and often by
date (`*-2026-09-NN.md`). Handovers live in [handoffs/](handoffs/), day plans
in [phase1/](phase1/) and the earliest feasibility notes in [phase0/](phase0/).
Each dated note states its own limits; do not treat a measured number as
current without checking the newest note on the same topic.
