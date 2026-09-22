# Changelog

All notable progress, recorded per playable demo. Newest first.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/).
Every entry corresponds to a commit on `main` that produced a working build.

## [Unreleased]

### Added
- Repository scaffold: `README.md`, `AGENTS.md`, `TODO.md`, `CHANGELOG.md`,
  `ATTRIBUTION.md`, `LICENSE`, and the `docs/`, `scripts/`, `game/`,
  `blender/`, `exports/` directory tree.
- `docs/ENVIRONMENT.md` — pinned toolchain (Godot 4.7.2, Blender 4.5.14 LTS,
  Chromium 153, ffmpeg 7.0.1) with reproducible install commands and the
  platform gotchas encountered while installing them.
- `docs/RECOVERY.md` — cold-start instructions so a new agent can resume the
  project from the repository alone after the build sandbox is destroyed.
