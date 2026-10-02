# OpenBOR macOS V2 Roadmap

## Goal

Build a macOS-first OpenBOR host that keeps the current SwiftUI launcher,
replaces fragile SDL/Cocoa window handling on macOS, and uses Metal as the
native presentation path on Apple Silicon.

## Why V2

The current project works, but window/fullscreen behavior is still tied to an
old SDL-driven path that behaves poorly on modern macOS. The V2 effort should:

- keep the existing frontend ideas that already work well
- stop depending on SDL for macOS window semantics
- separate "launcher UX" from "engine runtime host"
- make Metal the real native rendering layer on macOS

## Keep From Current Project

- `OpenBORFrontend/`
  The SwiftUI launcher, game library, settings, cover handling, saves browser,
  and CLI ideas are all still good foundations.
- `openbor-src/engine/`
  The OpenBOR engine remains the gameplay core.
- `openbor-src/engine/sdl/metal.m`
  The Metal experiments are useful as rendering knowledge, but should not be
  treated as the final architecture.

## Replace In V2

- SDL-driven fullscreen/window restore logic on macOS
- mixed Cocoa/SDL window geometry handling
- direct reliance on the engine's legacy window lifecycle for user-facing UX

## Target Architecture

### 1. SwiftUI Shell

Responsible for:

- game library
- settings
- saves and screenshots browser
- cover management
- launch flow
- renderer selection and diagnostics

### 2. Native macOS Host Window

Responsible for:

- creating and managing the macOS window
- fullscreen and windowed transitions
- cursor behavior
- display/screen geometry
- input focus

This should be implemented with AppKit/Swift, not left to legacy SDL behavior.

### 3. Metal Presentation Layer

Responsible for:

- presenting the game framebuffer
- scaling policy
- fullscreen output
- shader presets
- future CRT/scanline/video filters

### 4. Engine Bridge

Responsible for:

- launching OpenBOR
- passing pak/save/log/screenshot paths
- exchanging framebuffer/input/audio data
- handling engine lifecycle and crash isolation

## Suggested V2 Phases

### Phase 1: Host Split

- create a dedicated macOS host layer in Swift
- keep the current launcher, but route game launch through the new host
- preserve stable CLI behavior

### Phase 2: Metal Window Runtime

- create a native macOS window controller
- host a Metal drawable surface
- keep fullscreen/window logic fully outside SDL

### Phase 3: Engine Integration

- define how OpenBOR frame output reaches the Metal host
- start with "framebuffer presentation only"
- keep audio/input integration simple at first

### Phase 4: UX and Filters

- restore shader presets in a native way
- expose renderer diagnostics in settings
- add clean fallback behavior if Metal fails

## Recommended Technology Direction

### Primary

- SwiftUI for launcher and app structure
- AppKit for window control
- Metal for rendering

### Optional Later

- Rust for an engine bridge/runtime layer if we want a stricter and more
  portable systems core

Rust is attractive, but for the next step Swift + Metal is the fastest route to
something stable on macOS.

## Immediate Next Step

Create a dedicated `OpenBORMacV2` workspace area with:

- architecture notes
- host runtime scaffold
- Metal renderer scaffold
- engine bridge contract notes

That lets V2 evolve without destabilizing the current working build.
