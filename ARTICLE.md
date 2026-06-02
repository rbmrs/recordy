<!-- expander:image-slot name="hero" placeholder -->
<!-- ADD AN IMAGE, either way:
     A) Drop any image file into  docs/images/hero/  (any filename), then re-run the skill.
     B) GitHub web editor: delete the <img> line below, click the empty line, paste a screenshot. -->
<img alt="hero — PASTE" src="PASTE">
<!-- /expander:image-slot -->

## The friction that started it

Recordy is a small macOS screen recorder I built because OBS was more tool than I needed for the thing I did most. OBS is excellent, and I still respect how much it can do. But that range is also the cost. Most days I just wanted to capture one rectangle of my screen and hand the file to someone, and getting there meant more steps than opening the app and pressing a button.

That gap between "open the app" and "actually recording the part of the screen I care about" is where the friction lived. When I record a specific portion of my screen, I want to define that region and go. The extra setup in a heavier tool kept interrupting the exact workflow it was supposed to support. Small interruptions, repeated many times a day, add up to a real drag on how often I bother to record anything at all.

So I scoped a tool down to the path I actually walk: pick a region, pick a couple of settings, press record, press stop, get a file. That is the whole product. Recordy is not trying to be a streaming suite or a production studio. It is a screen recorder for the case where you know what you want to capture and you want it to be one or two clicks away.

## What it does

Recordy is a macOS screen recorder built around recording a chosen region of your screen with a few configurable knobs and dropdown menus. It gives you control over frames per second, a quality profile, and whether audio is captured, then gets out of the way. The settings exist because they change the output in ways I care about day to day, and nothing more is bolted on past that. It is deliberately narrow: a tool for capturing part of the screen quickly, not a general-purpose recording platform.

## Install

Recordy is a Swift Package Manager executable targeting macOS 14 and later. Clone the repo and build it with the Swift toolchain:

```bash
git clone https://github.com/rbmrs/recordy.git
cd recordy
swift build -c release
```

Run it directly through SwiftPM:

```bash
swift run recordy
```

### A `recordy` command in your terminal

The way I launch it day to day is a small wrapper script on my `PATH` so that typing `recordy` from any terminal opens the app. The script points at the project, builds it if the binary is not there yet, and then runs it. Drop something like this in a directory on your `PATH` (for example `~/.local/bin/recordy`) and make it executable:

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

Point `PROJECT_DIR` at wherever you cloned the repo. After that, `recordy` from the terminal builds on demand and opens the app.

### Screen Recording permission

Recordy captures the screen through ScreenCaptureKit, which macOS gates behind the system Screen Recording permission. The first time you try to record, macOS will prompt you to grant Recordy access under System Settings, Privacy and Security, Screen Recording. Until that permission is granted, the system does not hand any screen content to the app, so granting it is a one-time setup step before your first capture.

## Usage

Launch Recordy and you get a single window that doubles as the recording region. The recording button sits at the top of that window, so starting a capture is a matter of pressing it. Press stop and the recording is written out automatically as an MP4 to `~/Movies/Recordy/`, named with the date and time of the capture. There is no save dialog to navigate and no export step to think about: stop means saved.

Before you record, set the three knobs to taste:

- **FPS:** how many frames per second to capture.
- **Quality:** a profile that trades file size against fidelity.
- **Audio:** system audio capture on or off.

## How it works: the recording window is the region

The feature I most wanted, and the one that makes Recordy feel different to use, is that the recording tool behaves like a window you look through. The app window can be positioned over any application you want to record. The portion of the screen being captured stays visible underneath the window for the whole session, so you can see exactly what is going inside the frame while you record.

That visibility is the point. Instead of drawing a region on a dimmed overlay and then losing track of where it was, you move the Recordy window over the thing you want to capture and what you see through it is what gets recorded. You can click through the recording area, so the window defining your capture zone does not block you from interacting with the app underneath it. The result is a simple but effective way to establish a designated recording zone: put the window where you want the recording, and record.

This is the mental model for the whole tool. The window is not a control panel that points at some other region of the screen. The window is the region. Where you place it and how you size it is the capture setup, and there is no separate step to confirm or commit that choice. It collapses "define the region" and "see the region" into the same object on screen.

<!-- expander:image-slot name="body-1" placeholder -->
<!-- ADD AN IMAGE, either way:
     A) Drop any image file into  docs/images/1/  (any filename), then re-run the skill.
     B) GitHub web editor: delete the <img> line below, click the empty line, paste a screenshot. -->
<img alt="body-1 — PASTE" src="PASTE">
<!-- /expander:image-slot -->

Around that core idea, the controls stay minimal on purpose. The record button is the most prominent element because starting a recording is the most common thing you do. Everything else is the small set of dropdowns and toggles for FPS, quality, and audio. There is no mode-switching, no scene system, no layering. You see the region, you set a few options, you press the button.

## Quality profiles and file size

The quality profiles are the setting I reach for most, because most of the time the goal is to share the recording, and most of the time I do not want to send someone a large file. A screen recording at full fidelity is heavier than it needs to be for "here, watch this." The profiles let me select a lower quality that slightly reduces the file size, which makes the recording easier for a friend or colleague to download without a significant time investment on their end.

That is the trade the profiles are designed around: a small step down in quality for a meaningful step down in how long the file takes to move between people. When the recording is going straight to someone over a chat or an email, that trade is almost always worth it, and having it as a dropdown means I make the choice up front instead of re-encoding later.

Beyond the profiles, there are a number of subtle adjustments made under the hood so that everything functions seamlessly. Those details are not knobs I expose, because the point of the tool is that you should not have to think about them. They are there so that the visible settings are the only things you need to touch.

## Why I built it this way

I built Recordy for myself, and the surprise has been how much more I use it than I expected. The settings I ended up with are FPS, quality, and system audio, and on evaluation those have been comprehensive enough for most of what I need. That set was not designed to be complete. It is the set of things I actually adjusted, which is a different and more honest list than the one I would have written down if I were trying to anticipate every use.

<!-- expander:image-slot name="body-2" -->
<img width="691" height="429" alt="image" src="https://github.com/user-attachments/assets/17e16d9f-f480-4fe7-a77b-94e14cd3e9eb" />
<!-- /expander:image-slot -->

It is still a work in progress, and I am committed to refining it incrementally. My primary objective is to keep it simple and easy to use, so any changes I make are weighed against that. I may make minor adjustments for specific needs, but the bar for adding something is that it should not erode the one or two click path that made the tool worth building. One thing I might add later is a setting to toggle the microphone on or off, which fits the existing shape: another small switch next to the ones already there, not a new mode.

The reason the tool exists in this shape is that simplicity was the feature, not a constraint I settled for. A more capable recorder already exists, and it is good. What did not exist, for me, was a recorder that treated "capture this part of the screen and save it" as the entire job and optimized for the two clicks that job actually takes.

## When to use it, and when not to

Reach for Recordy when:

- You are on macOS and want a screen recorder scoped to a region of the screen.
- You want to see the exact area you are capturing while you record, and click through it to the app underneath.
- You want to start and stop with a button and have the file saved automatically to a default folder.
- You want to trade a little quality for a smaller, easier-to-share file via a quality profile.

It may not be the right fit when:

- You need the breadth of a full recording suite like OBS, with scenes, layering, and streaming.
- You are not on macOS. Recordy is currently built exclusively for Mac, since that is my primary operating system.

If you find Recordy useful and need additional functionality, or you would like it tailored to a different system such as Windows or Linux, reach out through the project's GitHub page. I am open to expanding its compatibility if there is encouragement to do so, and willing to help adapt it.

## Built with Claude Code

This tool was designed, written, and iterated on with [Claude Code](https://claude.com/claude-code) as the primary author.

<!-- expander:v1 -->
