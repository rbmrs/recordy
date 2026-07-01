# Recordy

A small, native macOS screen recorder scoped to a region. The app window *is* the capture region — position it over what you want, press record, press stop, and an MP4 is saved automatically. A few knobs (FPS, quality, audio), nothing more.

> Read the story behind it in [ARTICLE.md](ARTICLE.md).

## Requirements

- macOS 14 (Sonoma) or later
- [Homebrew](https://brew.sh) — recommended install path
- Screen Recording permission — macOS prompts on first capture (System Settings → Privacy & Security → Screen Recording)

## Install

```bash
brew tap rbmrs/recordy https://github.com/rbmrs/recordy
brew trust rbmrs/recordy
brew install --cask recordy
```

This installs a real `Recordy.app` in `/Applications` — open it from Spotlight, Launchpad, or `open -a Recordy`, no terminal required afterward. There's no Apple Developer ID behind this project, so the app is ad-hoc signed rather than notarized; the cask strips the quarantine flag on install so Gatekeeper doesn't block it. `brew trust` is required on Homebrew 6.0+, which refuses to load third-party taps until explicitly trusted.

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
