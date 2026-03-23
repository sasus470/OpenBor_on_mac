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
- `build_openbor_frontend.sh`
  Main script that builds the engine and packages the frontend app

## Current Features

- native macOS launcher app
- embedded OpenBOR engine
- fullscreen fix for the gameplay transition after `Press Start`
- controller-friendly launcher flow
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

## Project Status

This is a custom macOS port and frontend integration project, not an official OpenBOR release.

The current focus is:

- stable macOS launcher workflow
- native-feeling frontend UX
- preserving compatibility with OpenBOR content on Apple Silicon
