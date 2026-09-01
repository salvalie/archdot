# archdot

Personal Arch Linux desktop setup for building a lightweight Wayland desktop on a clean/minimal or server Arch installation, using the [Noctalia](https://github.com/noctalia-shell/noctalia) shell.

## Features

- **Single installer** — `setup_noctalia.sh` configures your chosen window manager from one codebase:
  - `labwc` (stable, official repos)
  - `mangowm` (rolling build from the AUR)
  - pick at runtime with `--labwc` / `--mango`, or answer an interactive prompt
- **Display manager** — greetd + the Noctalia greeter (agreety as fallback)
- **GPU/platform auto-detection** — detects Intel / AMD / NVIDIA from `/sys/class/drm` and installs the matching drivers + CPU microcode. Intel is split into legacy (`libva-intel-driver`, pre-Broadwell) and modern (`intel-media-driver`); unmatched hardware assumes modern. If detection fails entirely it installs the FOSS (mesa) stacks for all three vendors plus every microcode.
- **Shared merged Noctalia config** — same bar, dock, launcher, lockscreen and theme for both window managers; wallpaper points at the packaged default so nothing breaks across home resets.

## Usage

```sh
./setup_noctalia.sh [--labwc | --mango]
```

Run as a normal user (sudo is handled internally). `--help` prints usage.

> **Note:** this repo is for personal use. Internal/organizational notes live in an uncommitted, gitignored `AGENT.md`.

## License

Private / personal use.
