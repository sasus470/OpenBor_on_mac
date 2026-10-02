# V2 Architecture Notes

## Principle

The launcher and the engine should stop sharing responsibility for macOS window
behavior.

## Proposed Ownership

- SwiftUI: navigation, library, settings, content management
- AppKit host: window creation, fullscreen, focus, cursor, geometry
- Metal renderer: framebuffer presentation and filters
- OpenBOR bridge: game process and runtime I/O

## Boundary Rule

OpenBOR should provide game execution and frame data.
The macOS host should decide how the window behaves.

## Why This Matters

The current SDL-based path mixes old engine assumptions with modern macOS
windowing rules. That is the main source of the fullscreen/window restore bugs
we have been fighting.
