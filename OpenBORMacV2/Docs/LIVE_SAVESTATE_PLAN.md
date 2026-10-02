# Live Save State Plan

## Meaning

A real live save state for V2 should capture the exact runtime moment:

- current level position
- player/enemy/projectile state
- timers and RNG
- script variables
- audio/video timing

That is different from:

- `Resume Sessione Live`, which keeps the process suspended in memory
- `Riprendi Salvataggio`, which reloads normal save files from disk
- `Snapshot Disco`, which copies those save files manually

## Current Foundation

As of September 1, 2026, V2 now has:

- a dedicated `V2LiveSaveStateStore`
- a separate `LiveSaveStates` root in Application Support
- runtime capability metadata through `EngineLiveSaveStateSupport`
- dedicated artifact models distinct from disk-save snapshots
- a file-based bridge path for exporting a live runtime manifest from OpenBOR

## Remaining Engine Work

To become a true RetroArch-style save state, the runtime still needs one of
these strategies:

1. `runtimeSerialization`
   The OpenBOR engine explicitly serializes and restores its whole live state.

2. `liveProcessSnapshot`
   A lower-level snapshot captures enough process state to resume exactly.

## Preferred Path

The safer long-term path is `runtimeSerialization`, because it can be made aware
of OpenBOR-specific objects instead of depending on opaque process memory.

## Immediate Next Step

The next implementation milestone is to define the minimum OpenBOR state bundle
that must be serializable inside the engine process, starting from:

- current session/level identifiers
- entity lists
- player state
- projectile/effect state
- scripted globals that affect gameplay flow

## Runtime Manifest Bridge

The engine now receives:

- `OPENBOR_V2_LIVESTATE_REQUEST_PATH`
- `OPENBOR_V2_LIVESTATE_MANIFEST_PATH`

When the request file appears, the hosted engine exports the versioned
`openbor-v2-runtime-state-v1` payload. It records the entire active entity pool
rather than a small sample, identifies entities by stable slots instead of raw
pointers, and includes engine version metadata. It is deliberately not offered
as restorable until the matching import path can rebuild every recorded object.

## Generic Implementation Order

1. Capture a complete, versioned state payload for every PAK.
2. Add an importer that validates engine version, PAK identity, and schema.
3. Recreate the loaded level and its spawn cursor without replaying prior
   spawns.
4. Recreate entities in pool slots, then reconnect owner, parent, opponent,
   weapon, and player references.
5. Serialize script variables, timers, RNG, audio state, and mod-defined data.
6. Enable the user-facing restore control only after cross-PAK regression tests
   prove that a save resumes from the same gameplay moment.
