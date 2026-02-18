# Timeline Creator

> Part of [PostFlows](https://github.com/postflows) toolkit for DaVinci Resolve

Create timelines with custom numbers of video/audio tracks, track names, and start timecode; save/load presets.

## What it does

GUI for timeline name, video/audio track counts (1–20), optional start timecode, per-track names. Creates empty timeline, adds tracks, renames them. Presets saved to user config (macOS: `~/.davinci_resolve_timeline_presets.lua`; Windows: `%APPDATA%/DaVinci Resolve Timeline Presets.lua`).

## Requirements

- DaVinci Resolve Studio
- Open project

## Installation

Copy the script to:

- **macOS:** `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/`
- **Windows:** `C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\`

## Usage

Run script. Enter timeline name, set track counts and names, optionally set start timecode. Use Presets to Save/Load/Delete. Click Create Timeline.

## License

MIT © PostFlows
