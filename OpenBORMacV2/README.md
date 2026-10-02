# OpenBORMacV2

This directory is the clean start for the macOS-first V2 runtime.

## Scope

V2 is not meant to replace the current project in one jump. It exists so we can
build a better macOS runtime without breaking the launcher and engine setup that
already works today.

## Design Goals

- native macOS window behavior
- Metal-first rendering
- stable fullscreen/windowed transitions
- keep the SwiftUI launcher experience
- isolate the old SDL/macOS window path from the new runtime

## Planned Modules

- `App/`
  SwiftUI app shell and navigation
- `Host/`
  AppKit/macOS window lifecycle and fullscreen behavior
- `Renderer/`
  Metal presentation and shader pipeline
- `EngineBridge/`
  OpenBOR process/runtime bridge
- `Docs/`
  focused V2 technical notes

## First Milestone

Get a native macOS host window and Metal surface running as a separate
prototype, before reconnecting the real engine.

## In-Game Shaders

The Embedded Engine quick menu includes Original, Bilinear, Scanlines and
CRT Lite host-side Metal presets. Select the shader row and use left/right,
or confirm/click to cycle. Changes apply immediately without restarting the
engine or modifying live savestates.

The current selection is temporary until saved for the current game or as
the global default. Game overrides take precedence, including an explicit
Original (off) override. Saving a global default removes the current game's
override, but preserves overrides for other games. The follow-global action
removes only the current game's override. Preferences persist in UserDefaults;
game keys use standardized PAK paths. Reloading a savestate uses the saved
shader preference. A suspended/resumed live session keeps its current shader.

Shader GPU and preference test:
`swiftc OpenBORMacV2/Host/InterfaceLanguage.swift OpenBORMacV2/Renderer/HostShader.swift tests/test_host_shaders.swift -o /tmp/test_host_shaders`
then `/tmp/test_host_shaders`.

## Integrated Launcher

`OpenBORFrontend` compiles the same Host, Renderer and EngineBridge sources,
excluding the standalone V2 app entry point. The launcher owns a single
HostWindowCoordinator in process mode; Play, resume and slot loading use that
coordinator rather than opening the legacy SDL app directly. macOS 14 or later
is required, matching the tested V2 runtime.

Settings share QuickMenuPreferences and InterfaceLanguagePreferences with the
runtime. English, Italian, Spanish and Portuguese translations apply immediately
to the launcher and menu; game content itself is not translated. Testing-app
preferences are imported only where the launcher has no existing value. V2
snapshot storage is retained, and testing-library PAKs supplement the existing
launcher library. Existing PAKs, cover files and the cover database are preserved.

The launcher uses separate Frontend subdirectories for bridge IPC and working
saves, so it cannot consume the standalone app's frames or input. Archived
snapshots are shared for compatibility. Close the standalone V2 before testing
the launcher to avoid running two games at once.
