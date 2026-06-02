# Recordy

A small, native macOS screen recorder scoped to a region. The app window *is* the capture region — position it over what you want, press record, press stop, and an MP4 is saved automatically. A few knobs (FPS, quality, audio), nothing more.

> Read the story behind it in [ARTICLE.md](ARTICLE.md).

## Requirements

- macOS 14 or later
- Swift toolchain (to build)
- Screen Recording permission — macOS prompts on first capture (System Settings → Privacy & Security → Screen Recording)

## Install

```bash
git clone https://github.com/rbmrs/recordy.git
cd recordy
swift build -c release
```

## Run

```bash
swift run recordy
```

### A `recordy` command on your `PATH` (optional)

Drop a wrapper script somewhere on your `PATH` (e.g. `~/.local/bin/recordy`) so typing `recordy` from any terminal builds on demand and opens the app:

```sh
#!/bin/sh
set -eu

PROJECT_DIR="/path/to/recordy"
BINARY="$PROJECT_DIR/.build/debug/recordy"

if [ ! -x "$BINARY" ]; then
  (cd "$PROJECT_DIR" && swift build)
fi

exec "$BINARY" "$@"
```

Make it executable and point `PROJECT_DIR` at your clone.

## Usage

1. **Place the window** — the window is the recording region. Move and size it over the area you want to capture; what shows through it is what gets recorded. You can click through it to the app underneath.
2. **Set the knobs** — `FPS`, a `Quality` profile (trades file size for fidelity), and `Audio` (system audio on/off).
3. **Record** — press the record button at the top of the window.
4. **Stop** — the recording is written automatically as an MP4 to `~/Movies/Recordy/`, named with the capture date and time. No save dialog, no export step.
