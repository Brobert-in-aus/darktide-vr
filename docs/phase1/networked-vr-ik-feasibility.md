# Networked VR IK feasibility

## Outcome

Two useful delivery levels exist, but they have different compatibility
boundaries:

1. **Every player can see dominant-hand weapon aim.** Feed the tracked weapon
   direction through Darktide's existing authoritative `aim_direction`. Stock
   remote clients already consume that field through `PlayerHuskAimExtension`.
2. **Peers with the VR mod can see full head/two-hand embodiment.** Full IK
   requires a separate versioned pose channel because the stock replicated
   player schema has no independent head, left-wrist, or right-wrist fields.

An unmodified client cannot display full independent VR IK without Fatshark
adding protocol/state support. Trying to overload unrelated RPC fields is not a
safe compatibility strategy.

## Evidence from the local source

- `PlayerUnitAimExtension` publishes one `aim_direction`.
- `PlayerHuskAimExtension` reconstructs the normal remote aim constraint from
  that value.
- Darktide RPC and game-object schemas are predefined rather than dynamically
  extensible by a Lua mod.
- DMF's `modules/core/network.lua` still leaves its network dictionary and DMF
  peer discovery as `TODO`; it does not provide a production mod transport.
- `PartyImmateriumManager.broadcast` can carry an integer and string through a
  backend party event, but its latency and rate limits are unknown. It is at
  most a handshake/signalling candidate until explicitly measured, not a pose
  stream.

## Mod-to-mod transport shape

Keep Darktide authoritative for root position, locomotion, actions, combat and
hit testing. Transmit only presentation data relative to the already replicated
avatar root:

- protocol version and feature bits;
- peer/avatar identifier;
- sequence number and sender timestamp;
- head pose;
- left and right wrist poses;
- tracking-validity bits, dominant hand and calibration/profile revision; and
- optionally a small set of gesture/finger values later.

Do not send solved bone rotations. Each receiver applies its local copy of the
same constrained retargeter to the remote husk. This keeps packets small and
allows the solver to respect the target client's exact Darktide skeleton and
character-height scale.

A practical compressed packet is comfortably below 100 bytes. At 30--60 Hz it
uses roughly 3--6 KB/s per remote VR avatar before transport overhead. More
important than bandwidth are:

- an interpolation buffer of roughly 80--120 ms;
- bounded extrapolation for short loss only;
- smooth blending to stock husk animation when data is older than roughly
  250 ms, tracking is invalid, or versions are incompatible;
- root-relative validation and anatomical limits before applying a pose; and
- strict presentation-only writes after animation, never collision, hitbox,
  action, reach, attack-origin or movement changes.

## Discovery and relay options

For the first private two-client prototype, use an explicit session code and a
small authenticated WebSocket/UDP relay owned by the mod project. This avoids
depending on backend party-event rate limits and handles NAT consistently.
Later options, in order of evidence required, are:

1. test the Darktide party broadcast only for exchanging a short-lived session
   token/relay room;
2. investigate whether the existing Steam transport can be used without
   hooking or impersonating game traffic; and
3. consider direct UDP hole punching only as an optional low-latency path with
   relay fallback.

Never place account credentials, Fatshark authentication tokens, raw IP
addresses, or unvalidated serialized Lua in the pose channel.

## Receiver integration

The receiving mod finds the stock remote player husk by the peer/avatar mapping,
reads its live scaled rig, and runs the same post-animation retargeting stages
used locally:

1. head/chest target reconstruction;
2. constrained shoulder-girdle distribution;
3. analytic two-bone arms;
4. distributed forearm twist; and
5. wrist/hand presentation.

The base game's remote locomotion and legs remain authoritative. If the remote
VR stream disappears, blend the upper body back to its stock aim/animation
instead of freezing the last pose.

## Staged implementation gates

1. Drive stock `aim_direction` from the accepted weapon-hand aiming solution
   and verify it with one unmodded observer in a private session.
2. Implement a loopback native pose codec with malformed-packet tests,
   timestamps and interpolation.
3. Apply loopback data to a synthetic remote rig without networking.
4. Run a private two-PC relay test between identical mod builds.
5. Test tracking loss, mixed versions, reconnect, player join/leave, character
   scale differences and non-VR fallback.
6. Only then test party-token signalling or broader distribution.

