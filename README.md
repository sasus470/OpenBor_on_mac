# OpenBOR on macOS

Native macOS frontend and patched OpenBOR engine build for Apple Silicon Macs.

This project packages:

- a patched OpenBOR engine source tree for macOS
- a native SwiftUI frontend launcher
- a reusable macOS build script for generating the app bundle

## What This Repo Contains

- `OpenBORFrontend/`
  SwiftUI macOS launcher UI
- `openbor-src/`
  OpenBOR source tree used for the macOS port
- `OpenBORMacV2/`
  Shared V2 runtime host, Metal/OpenGL rendering, quick menu and state management
- `build_openbor_frontend.sh`
  Main script that builds the engine and packages the frontend app

## Current Features

- native macOS launcher app
- current V2 engine with selectable Metal and OpenGL rendering
- keyboard and Bluetooth controller input
- quick menu with configurable shortcut and English, Italian, Spanish and Portuguese
- suspended live sessions, disk savestate slots and selectable shader presets
- preview-based rewind with synchronized music and half-second checkpoints
- fullscreen/windowed rewind layouts and optional animated launcher background
- cover art system with:
  - generated local covers
  - manual cover import
  - local SQLite cover database
- support-ready structure for future frontend integrations such as ES-DE

## Build Requirements

- macOS on Apple Silicon
- Xcode command line tools
- Homebrew
- required libraries installed through Homebrew:
  - `sdl2`
  - `sdl2_gfx`
  - `libpng`
  - `libogg`
  - `libvorbis`
  - `libvpx`

## How To Build

From the repository root:

```bash
./build_openbor_frontend.sh
```

The generated app will be placed in:

```text
build/frontend/OpenBOR Frontend Launcher.app
```

## Runtime Notes

- Launcher Settings offers Metal (default) and OpenGL host rendering with the same current V2 engine, quick menu, shaders, and live savestates. The selection applies to new sessions; resuming a suspended session keeps its original renderer.
- The arcade-style launcher includes an optional animated background, which pauses while playing or when the app is inactive and respects Reduce Motion. Language and quick-menu shortcut settings also apply to the in-game menu.
- Optional rewind can be enabled in Settings or the quick menu, with a configurable shortcut (initially F6). Press it to pause and browse a bottom horizontal rail of 30 session-local checkpoints at half-second intervals, oldest left and newest right. Hover/click or arrows change the full-screen visual preview without applying state. Enter, controller A or Resume here confirms; Escape/B cancels without changing the game. Short synthesized opening/navigation cues accompany browsing. Confirmation restores the checkpoint in the same engine process and discards its future history. Background clocks and scrolling state are included. History resets on level changes or disabling rewind, and manual save slots are unaffected.
- Rewind restores the music decoder cursor, buffered PCM and mixer position together with volume/fade state for the selected checkpoint (OGG and BOR/ADPCM). These audio checkpoints are session-local, not part of disk savestates. New V8 snapshots preserve transient-effect cleanup flags, while V6/V7 imports remain supported.
- The rewind rail centers the active checkpoint, including both endpoints. Empty space to the right of the newest frame fills with newer checkpoints when browsing backwards. Each arrow/D-pad press has a short navigation cue, including presses at the history limits.
- The selected game preview fits entirely above the rewind rail. Windowed mode uses smaller thumbnails and controls, while fullscreen retains the larger rail and navigation hints.
- The launcher stores its user data in `~/Library/Application Support/OpenBOR Frontend/`
- Covers are cached locally and stored in a local SQLite database
- Imported covers are copied into the local `Covers` folder

## Command Line Usage

The frontend launcher also supports command-line usage for integrations and advanced workflows.

Supported options:

- `--pak <file>`
- `--launch <file>`
- `--paks-dir <dir>`
- `--saves-dir <dir>`
- `--logs-dir <dir>`
- `--screenshots-dir <dir>`
- `--engine-arg <arg>`
- `--engine-args ...`
- `--help`

Examples:

```bash
./build/final/OpenBOR\ Frontend\ Launcher.app/Contents/MacOS/openbor-launch --pak "/path/to/game.pak"
```

```bash
./build/final/OpenBOR\ Frontend\ Launcher.app/Contents/MacOS/openbor-launch --pak "/path/to/game.pak" --saves-dir "/path/to/saves"
```

If a single file path is passed directly, `openbor-launch` treats it as a `.pak` shortcut automatically.

## GitHub Releases

Source code belongs in the repository.

Built app packages such as:

- `.app`
- `.zip`

should be published through GitHub `Releases`, not committed into source control.

Current validated launcher build: **V2.0, 20261002-1902**, macOS 14+ on Apple Silicon.
See [release notes](docs/RELEASE_20261002.md). Historical development builds are
archived separately and should not be confused with the current launcher.
Games, user saves, logs and compilation caches are not distributed.

Prepare the current package and a cleaned historical archive locally with:

```bash
python3 tools/prepare_release.py
```

Use `--current-only` when publishing an update without rebuilding the historical archive.

The generated packages and SHA-256 manifests are placed in `build/publish/`.

## Project Status

This is a custom macOS port and frontend integration project, not an official OpenBOR release.

The current focus is:

- stable macOS launcher workflow
- native-feeling frontend UX
- preserving compatibility with OpenBOR content on Apple Silicon
