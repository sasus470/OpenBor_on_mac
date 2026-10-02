# IOSurface Bridge Next Steps

## Current Status

The V2 codebase now contains an `IOSurfaceFrameTransport` scaffold.

It can:

- allocate an `IOSurface`
- publish frame bytes into the surface
- expose a surface identifier for diagnostics and future attachment

Right now the host still renders from the in-process frame packet path, but the
surface transport now exists as a concrete macOS-native bridge target.

## Why This Matters

The real V2 process mode should not show the legacy SDL/OpenBOR window.
Instead:

1. OpenBOR produces frame data
2. that frame data lands in an `IOSurface`
3. the native AppKit + Metal host presents the `IOSurface`

That is the path that lets us keep:

- the new host window
- native fullscreen behavior
- modern Metal rendering

while dropping:

- the old visible SDL/Cocoa engine window
- the old fullscreen/window restore bugs

## Remaining Work

### Host Side

- let the Metal renderer consume a shared `IOSurface` directly as a Metal texture
- add diagnostics to show whether the host is using packet mode or surface mode

### Runtime Side

- decide how OpenBOR publishes frames into the shared surface
- expose surface metadata to the runtime process
- stop treating the real process as a pure shell-out launcher

### Integration Step

The first practical integration milestone is:

- use `IOSurfaceFrameTransport` inside `ProcessOpenBORRuntime`
- keep the packet fallback for development
- surface the transport mode in the V2 UI
