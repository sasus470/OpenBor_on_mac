# Engine Bridge Plan

## Objective

Move from a launcher that shells out to OpenBOR toward a host/runtime split with
a clear bridge API.

## Contract

The host should know:

- what to launch
- where saves/logs/screenshots live
- which renderer mode is requested
- when the engine is running or has failed
- how to receive new frame data

The engine should not own:

- macOS window geometry
- fullscreen semantics
- cursor policy

## Integration Path

### Step 1

Use `MockOpenBORRuntime` to exercise:

- state changes
- frame callbacks
- renderer updates

### Step 2

Create a `ProcessOpenBORRuntime` implementation that:

- launches the packaged `openbor-launch` or engine binary
- sets environment variables
- captures logs and diagnostics

This scaffold now exists; the remaining work is the real frame transport path.

### Step 3

Design a frame transport path.

Options:

- shared memory
- mmap-backed frame file
- IOSurface-backed frame exchange
- a temporary process boundary with native view embedding if feasible

For macOS, `IOSurface` is likely the cleanest long-term direction once the host
and renderer are ready.

The codebase now contains:

- a generic `EngineFrameTransport` contract
- an `InProcessFrameTransport` for development
- an `IOSurfaceTransportPlan` to guide the real process bridge
