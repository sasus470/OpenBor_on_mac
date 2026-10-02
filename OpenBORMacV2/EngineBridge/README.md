# EngineBridge

The V2 engine bridge owns the contract between the native macOS host and the
OpenBOR runtime.

## Responsibilities

- launch configuration
- runtime lifecycle
- input submission
- frame delivery
- diagnostics

## Current State

Right now the module includes:

- shared engine/runtime data models
- a launch argument builder aligned with the existing frontend CLI
- a mock runtime that emits demo frames
- a process runtime scaffold that can launch the packaged helper and capture diagnostics
- a frame transport contract for the future host/runtime split
- an in-process transport implementation for early development
- an IOSurface transport scaffold for the future macOS-native process bridge

The mock runtime lets us connect the future host window and Metal renderer
before we wire in the real engine process.

## Next Step

Replace `MockOpenBORRuntime` with a real bridge that can:

- launch the packaged OpenBOR runtime
- stream or share frame data into the host renderer
- forward input back into the engine
