# Post-initial-release work

## LOD distance and cost

The user accepted lod_object_multiplier=3 on 5 September 2026 as a sufficient
starting point. At 1, nearby shields, mace sections and terrain changed detail
around 3m. At 3, that boundary extends but remains imperfect. Disabling mesh
streaming did not improve it and was reverted. Keep the accepted baseline;
after initial release, investigate projection/FOV-dependent LOD selection and
find a better quality/performance policy across equipment and terrain.

## Selective smoke-cloud billboard suppression

Identify smoke-cloud effects/materials before adding a selective suppression
option. The current native billboard shader substitution is shared by particle
draws; disabling that shader or all particles is not smoke-only. The stock
SmokeFogSystem can stop particle flow on its own smoke units, but that does not
identify all ambient smoke clouds, and its gameplay line-of-sight/buff handling
must remain intact. Scope requires effect/material attribution and verification
that fire, sparks, impact effects, other particles and fog gameplay remain intact.
The user explicitly allowed this to wait when selective removal is complex.

## Texture streaming trial

On this RTX 4090 (24 GB), trial feedback_streamer_settings.max_texture_pool_size
2048 instead of the installed 1024. This is a machine-local experiment in
bundle/application_settings/settings_common.ini, not a portable release default.
The active texture_streamer_type is feedback_streamer. All tile budgets, other
streaming pools and mesh settings remain unchanged; LOD multiplier stays at the
accepted 3. Worker count also changed to 7 in this run, so total performance
changes cannot be attributed solely to the pool. Compare 1024 versus 2048 again
with seven workers fixed before adopting a streaming default.

The original community report includes firsthand NVIDIA success reports:
https://forums.fatsharkgames.com/t/i-fixed-stutter-and-textures-not-loading-in-texutre-streaming-config-file-change/102199
The updated guide targets the feedback streamer but includes slower detail
loading reports, so do not import its whole configuration bundle:
https://forums.fatsharkgames.com/t/how-to-fix-amd-gpu-stutters-and-improve-clarirty-streaming-settings-config-fix/108373
Measure frame-time spikes, texture convergence and memory usage on a repeatable
route. Texture residency and distance-based geometry LOD are separate concerns.
Rollback only max_texture_pool_size to 1024 while the game is closed; preserve
other edits. Original file and trial metadata are under ignored artifacts/unattended.
