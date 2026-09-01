This repo is for personal use to build a lightweight Desktop Environment on a clean minimal/server Arch Linux installation with the Noctalia shell, and for now two different compositors: labwc and mango (mangowm).

Objective
- setup_noctalia.sh is the SINGLE installer: it asks (or takes a flag) for the window manager — labwc or mango — and configures it from one codebase. It replaces the old split scripts (setup_labwc.sh, setup_mango.sh), which have been deleted (backed up elsewhere).
- Display manager is greetd + noctalia-greeter (graphical, Noctalia-themed) with agreety as fallback.
- GPU/platform detection: the script auto-detects the GPU vendor (Intel / AMD / NVIDIA) from /sys/class/drm and adds the matching driver packages + CPU microcode (intel-ucode/amd-ucode). For Intel it distinguishes modern (Broadwell+ → intel-media-driver) from legacy (G45–Haswell → libva-intel-driver); force legacy with INTEL_OLD=1. Intel UNMATCHED/unknown ids default to MODERN. If detection FAILS entirely (unknown vendor), it installs the FOSS (mesa) stacks for all three vendors (intel-media-driver, vulkan-intel, vulkan-radeon, libva-mesa-driver) + all microcodes, and assumes modern hardware for everything.
- The noctalia config is IDENTICAL across labwc/mango (bar position bottom, taskbar start / settings center / disks end, dock, launcher pinned, keyboard custom labels, osd, lockscreen with HDMI-A-2, wallpaper pointing at the packaged default /usr/share/noctalia/assets/noctalia-wallpaper.png, theme templates, taskbar capsule, active_window icon_only, arch-round launcher icon). Verify any future config edit updates ALL scripts (diff the rendered heredocs; each ~6318 bytes).
- IMPORTANT wallpaper gotcha: the wallpaper path must be a file that survives the /home rollback cleanup (which deletes /home/salva/Pictures/). A /home-resident path (e.g. a wallhaven download) OVERRIDES and cancels the noctalia default, so no wallpaper shows until one is set with the wallhaven plugin. Use /usr/share/noctalia/assets/noctalia-wallpaper.png (package-provided, always present) as the default.

Current Status
- setup_noctalia.sh is the only script; old setup_labwc.sh/setup_mango.sh deleted (merged logic folded in; both WM config blocks verified identical to the originals, syntax OK, sandbox-run for both branches).
- Platform/GPU auto-detection added (intel modern/legacy, amd, nvidia) + matching vendor packages & CPU microcode. Unknown GPU → installs FOSS stacks for all three vendors + all microcodes, assuming modern hw. Unit-tested for all vendors incl. the target (Intel N100/Alder Lake-N → intel + intel-media-driver).
- MANGO TEST PASSED end-to-end on the clean target: --mango branch ran headless to SCRIPT_EXIT=0; built yay + AUR (wlroots0.20-hidpi-xprop, scenefx0.5, mangowm-git) → /usr/bin/mango; greetd + seatd enabled, default graphical.target, /etc/greetd/config.toml correct; all 9 mango cfg files + config.conf present; noctalia config 6318 bytes (matches labwc baseline); noctalia config validate ✓ (3 cosmetic warnings).
- Target rolled back to clean (round 3) via rollback.sh; currently booted into the clean root. Next: labwc re-test with platform detection active.

Important Details
- Project: git repo /home/salva/dev/archdot
- Credentials: target salva@192.168.0.111 ssh/sudo password asdasd . SSH needs -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/opencode/known_hosts2-111 (per-target known_hosts file; wipe on fresh installs). Local tool dir /tmp/opencode/ may be wiped on reboots.
- Headless run pattern on .111 works: temp sudoers /etc/sudoers.d/zz-dotarch-temp with salva ALL=(ALL) NOPASSWD: ALL, then launch nohup sh -c "bash /tmp/setup_labwc.sh > /tmp/setup.log 2>&1; echo SCRIPT_EXIT=$? > /tmp/setup.exit" & as salva (NOT wrapped in sudo -n).
- Critical deployment bug found: launching the nohup under sudo -n sh -c runs the script as root → hits the "Do NOT run as root" guard and bails (exit 0). Correct launch is as the salva user, letting internal sudo calls elevate. Also: the failed root run left root-owned /tmp/setup.log//tmp/setup.exit that salva couldn't overwrite — must clean via sudo -n rm -f before relaunching.
- noctalia-greeter installed from AUR on .111 (target): built via makepkg -si (1.3.0-1) with toolchain base-devel git go just meson + deps (wayland, wayland-protocols, wlroots0.20, libglvnd, freetype2, fontconfig, cairo, pango, harfbuzz, libxkbcommon, glib2, tomlplusplus, nlohmann-json, stb, libwebp, librsvg). greetd config updated to command = "/usr/bin/noctalia-greeter-session", user greeter (greeter uid 965 in video+seat). Verified rendering: noctalia-greeter-compositor running on tty1 for greeter, greetd active, no errors in journal.
- Dolphin palette fix: script dolphinrc now ColorScheme=noctalia (lowercase), matching target.


Next Move
1. Reboot the target and confirm greetd presents the noctalia login screen and mango starts on login (visual check).
2. Optionally validate the --labwc branch on a rolled-back box as well.
3. Review and commit the scripts/README when the user is ready.

Usage
- setup_noctalia.sh [--labwc | --mango]   (no flag → interactive prompt, default labwc)
- Headless (target .111): reinstall temp NOPASSWD sudoers, launch as salva via
  nohup sh -c "bash /tmp/setup_noctalia.sh --mango > /tmp/setup.log 2>&1; echo SCRIPT_EXIT=$? > /tmp/setup.exit" &
- setup_noctalia.sh --help prints usage.

Rollback to Pre-Setup Clean State (btrfs snapshot "backup")
- Target .111 runs btrfs single disk nvme0n1p2 with subvols: @ (root), @home (257), @log (258), @pkg (259). fstab mounts / as subvol=/@ and /home as subvol=/@home.
- Bootloader = GRUB + UKI (grub.d/15_uki) + grub-btrfs. The "backup" snapshot = @/.snapshots/1/snapshot (grub-btrfs label "backup"), the clean pre-setup root. IMPORTANT: booting the "backup" entry only loads that snapshot read-only as /; it does NOT touch the persistent @, and leaves /home (separate @home subvol) untouched. A TRUE rollback must replace the @ subvol (and reset /home).
- STREAMLINED: run rollback.sh (in this repo) as root on the target. One command does: mount top-level btrfs → safety snapshot @.pre_rollback<N> → move current root to @.dirty<N> → restore @ from the clean backup → verify clean → reset /home to pristine (first preserving noctalia config/Pictures/Videos to /tmp/opencode/home-preserve) → umount → reboot. round N auto-increments so earlier @.dirty/@.pre_rollback artifacts are preserved.
  - scp rollback.sh; ssh ... "echo asdasd | sudo -S bash rollback.sh"   (one session, no NOPASSWD needed)
  - Automatic suffix: round 1 → @.pre_rollback/@.dirty, round 2 → @.pre_rollback2/@.dirty2, etc.
  - Override the clean snapshot source with ROLLBACK_SRC=…  (default /mnt/top/@.dirty/.snapshots/1/snapshot)
- After reboot the box lands in the new clean @; /home is pristine (only .bash_logout/.bash_profile/.bashrc). Re-run setup_noctalia.sh. Old roots @.dirty<N>/@.pre_rollback<N> are not in the fstab path (won't break boot); delete with btrfs subvolume delete once no longer needed.
- Manual equivalent (if rollback.sh is unusable, all in ONE ssh session to avoid mount vanishing between connections):
  mkdir -p /mnt/top && mount -t btrfs -o subvolid=5,compress=zstd:3 /dev/nvme0n1p2 /mnt/top &&
  btrfs subvolume snapshot -r /mnt/top/@ /mnt/top/@.pre_rollback2 && mv /mnt/top/@ /mnt/top/@.dirty2 &&
  btrfs subvolume snapshot /mnt/top/@.dirty/.snapshots/1/snapshot /mnt/top/@ &&        # clean backup path (see below)
  # verify /mnt/top/@ clean, then home reset + umount + reboot

Relevant Files
- /home/salva/dev/archdot/setup_noctalia.sh — the single installer; unified labwc/mango (flag or prompt), merged noctalia config, greetd/noctalia-greeter DM, AUR build for mangowm.
- /home/salva/dev/archdot/rollback.sh — ONE-shot rollback to the clean btrfs backup snapshot (root swap + /home reset + reboot).
- /home/salva/dev/archdot/changes to adddress on the bar/config.toml and settings.toml — source files for the merged noctalia config (settings.toml values used verbatim).
- /home/salva/dev/archdot/README.md — this file.
- ~/.config/noctalia/config.toml (declarative base) + ~/.local/state/noctalia/settings.toml (GUI overrides, loaded last) — the two sources merged into the script's config.
- Preserve dir on .111: /tmp/opencode/home-preserve/ (config.toml, settings.toml, Pictures, Videos, .config/noctalia, .config/labwc) staged before /home cleanup.
- Preserved subvols on .111: @.dirty (old post-setup root, subvolid 256), @.pre_rollback (subvolid 271) — deletable once no longer needed.
- /home/salva/dev/archdot/.git — git repo, branch main, changes uncommitted.