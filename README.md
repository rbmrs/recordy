# Recordy

A small, native macOS screen recorder scoped to a region. The app window *is* the capture region — position it over what you want, press record, press stop, and an MP4 is saved automatically. A few knobs (FPS, quality, audio), nothing more.

> Read the story behind it in [ARTICLE.md](ARTICLE.md).

## Requirements

- macOS 14 (Sonoma) or later
- [Homebrew](https://brew.sh) — recommended install path
- Swift toolchain (Xcode Command Line Tools, Xcode 16+) — only needed if building from source; the Homebrew formula pulls this in as a build dependency
- Screen Recording permission — macOS prompts on first capture (System Settings → Privacy & Security → Screen Recording)

## Install

```bash
brew tap rbmrs/recordy
brew install rbmrs/recordy/recordy
```

This compiles recordy from source on your machine. There's no Apple Developer ID behind this project, so nothing is signed or notarized — building locally is what avoids Gatekeeper's "unidentified developer" dialog entirely. `recordy` lands on your `PATH` automatically.

### Building from source

```bash
git clone https://github.com/rbmrs/recordy.git
cd recordy
swift build -c release
swift run recordy
```

## Usage

1. **Place the window** — the window is the recording region. Move and size it over the area you want to capture; what shows through it is what gets recorded. You can click through it to the app underneath.
2. **Set the knobs** — `FPS`, a `Quality` profile (trades file size for fidelity), and `Audio` (system audio on/off).
3. **Record** — press the record button at the top of the window.
4. **Stop** — the recording is written automatically as an MP4 to `~/Movies/Recordy/`, named with the capture date and time. No save dialog, no export step.
