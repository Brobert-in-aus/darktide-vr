# Repeatable SoloPlay mission measurements

The performance target is 120 distinct stereo frames/s, either about 60
original plus 60 generated frames or the highest sustainable native rate.
Hub spin remains a control; it does not establish mission performance.

`run-synthetic-framegen-benchmark.ps1 -SoloMission cm_archives -SoloDifficulty 3`
launches the installed SoloPlay mod's normal mission path from character
select. The initial workload is the stationary mission starting area of
Archivum Sycorax on Malice, with default circumstance and side mission.
It does not simulate a combat route, a horde, or online server load. SoloPlay
runs gameplay authority locally, which is another difference from online play.

The runner requires `-ExpectedInstalledSoloSha256`, backs up the installed
SoloPlay main chunk and any existing helper, appends a helper load, and compiles
both with the pinned LuaJIT validator before launch. The helper waits for the
stock Start button and input gates, requests the mission once, and reports
ready only for the selected mission, a single-player session and a local
player unit. The launcher also requires fresh synchronized stereo activation.
The workload timer begins then; analysis excludes its normal warm-up interval.

Settings, both Lua files and native trial DLLs share the runner's byte-exact
backup/restoration procedure. No permanent SoloPlay setting or mod load-order
change is required. The source fixture checks blocked startup, one-shot
execution and rejection of readiness in another mission or a non-solo session.

The selected simulator has a 120 Hz process-local clock, Quest 3 frusta,
2112x2304 eyes and no preview copies. Before launching the game the runner
checks the consumer's reported display period against the requested clock;
an older runtime ignoring the refresh selection fails this check. FG on uses one generated frame and stock
cap 120; FG off uses Unlimited. NVIDIA board telemetry records the same bounded
workload window. Mission results are recorded after clean completion and
restoration, under `artifacts/unattended/synthetic-solo-*`.

The first 120-second FG-on trial delivered 119.41 distinct pairs/s over 108.01
analyzed seconds: 59.71 original and 59.71 generated, with 0.574 cached
repeats/s. Producer publication averaged 59.96 pairs/s for each type. There
were no pose mismatches. The 110-second board telemetry window averaged
75.54% GPU busy time and 287.26 W, with complete coverage. The mission identity
and difficulty matched, and clean shutdown and exact restoration passed.
This reaches approximately 120 FPS in the stationary mission-start workload;
the native-only comparison and combat workload remain to be measured.
