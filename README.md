This repo is for personal use to build a lightweight Desktop Environment on a clean minimal/server Arch Linux installation with the Noctalia shell, and for now two different compositors: labwc and mango (mangowm).

Objective
- setup_noctalia.sh is the SINGLE installer: it asks (or takes a flag) for the window manager — labwc or mango — and configures it from one codebase. It replaces the old split scripts (setup_labwc.sh, setup_mango.sh), which have been deleted (backed up elsewhere).
- Display manager is greetd + noctalia-greeter (graphical, Noctalia-themed) with agreety as fallback.
- The noctalia config is IDENTICAL across labwc/mango (bar position bottom, taskbar start / settings center / disks end, dock, launcher pinned, keyboard custom labels, osd, lockscreen with HDMI-A-2, wallpaper pointing at the packaged default /usr/share/noctalia/assets/noctalia-wallpaper.png, theme templates, taskbar capsule, active_window icon_only, arch-round launcher icon). Verify any future config edit updates ALL scripts (diff the rendered heredocs; each ~6318 bytes).
- IMPORTANT wallpaper gotcha: the wallpaper path must be a file that survives the /home rollback cleanup (which deletes /home/salva/Pictures/). A /home-resident path (e.g. a wallhaven download) OVERRIDES and cancels the noctalia default, so no wallpaper shows until one is set with the wallhaven plugin. Use /usr/share/noctalia/assets/noctalia-wallpaper.png (package-provided, always present) as the default.

Current Status
- setup_noctalia.sh is the only script; old setup_labwc.sh/setup_mango.sh deleted (merged logic folded in; both WM config blocks verified identical to the originals, syntax OK, sandbox-run for both branches).
- Re-testing now on the clean target: setup_noctalia.sh --mango (building mangowm from the AUR).

Important Details
- Project: git repo /home/salva/dev/archdot
- Credentials: target salva@192.168.0.111 ssh/sudo password asdasd . SSH needs -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/opencode/known_hosts2-111 (per-target known_hosts file; wipe on fresh installs). Local tool dir /tmp/opencode/ may be wiped on reboots.
- Headless run pattern on .111 works: temp sudoers /etc/sudoers.d/zz-dotarch-temp with salva ALL=(ALL) NOPASSWD: ALL, then launch nohup sh -c "bash /tmp/setup_labwc.sh > /tmp/setup.log 2>&1; echo SCRIPT_EXIT=$? > /tmp/setup.exit" & as salva (NOT wrapped in sudo -n).
- Critical deployment bug found: launching the nohup under sudo -n sh -c runs the script as root → hits the "Do NOT run as root" guard and bails (exit 0). Correct launch is as the salva user, letting internal sudo calls elevate. Also: the failed root run left root-owned /tmp/setup.log//tmp/setup.exit that salva couldn't overwrite — must clean via sudo -n rm -f before relaunching.
- noctalia-greeter installed from AUR on .111 (target): built via makepkg -si (1.3.0-1) with toolchain base-devel git go just meson + deps (wayland, wayland-protocols, wlroots0.20, libglvnd, freetype2, fontconfig, cairo, pango, harfbuzz, libxkbcommon, glib2, tomlplusplus, nlohmann-json, stb, libwebp, librsvg). greetd config updated to command = "/usr/bin/noctalia-greeter-session", user greeter (greeter uid 965 in video+seat). Verified rendering: noctalia-greeter-compositor running on tty1 for greeter, greetd active, no errors in journal.
- Dolphin palette fix: script dolphinrc now ColorScheme=noctalia (lowercase), matching target.


Next Move
1. Retest setup_noctalia.sh on the rolled-back clean target with --mango (slower: builds mangowm from AUR) to confirm the mango branch works end-to-end; --labwc was validated via the sandbox run.
2. Review and commit setup_noctalia.sh and this README.

Usage
- setup_noctalia.sh [--labwc | --mango]   (no flag → interactive prompt, default labwc)
- Headless (target .111): reinstall temp NOPASSWD sudoers, launch as salva via
  nohup sh -c "bash /tmp/setup_noctalia.sh --mango > /tmp/setup.log 2>&1; echo SCRIPT_EXIT=$? > /tmp/setup.exit" &
- setup_noctalia.sh --help prints usage.

Rollback to Pre-Setup Clean State (btrfs snapshot "backup")
- Target .111 runs btrfs single disk nvme0n1p2 with subvols: @ (root, subvolid 256), @home (257), @log (258), @pkg (259). fstab mounts / as subvol=/@ and /home as subvol=/@home.
- Bootloader = GRUB + UKI (grub.d/15_uki) + grub-btrfs. The "backup" snapshot = @/.snapshots/1/snapshot (created 2026-09-01 07:57, grub-btrfs label "backup"), the clean pre-setup root. grub-btrfs timeline snapshots 2/3/4 are hourly (08:00/09:00/10:00).
- IMPORTANT: Booting the "backup" grub-btrfs entry only loads that snapshot read-only as /; it does NOT touch the persistent @ root. And it leaves /home (separate @home subvol) untouched. A true rollback must replace the @ subvol.
- Snapshot 1 is readonly (btrfs sub show → Flags: readonly). When booted FROM it, / is read-only → cannot run pacman/setup. Only a rolled-back (writable) @ is usable for re-testing.
- Rollback procedure (must run from a NORMAL boot into @, NOT from the snapshot; / requires password sudo, no NOPASSWD):
  1. mount -t btrfs -o subvolid=5,compress=zstd:3 /dev/nvme0n1p2 /mnt/top
  2. btrfs subvolume snapshot -r /mnt/top/@ /mnt/top/@.pre_rollback        # safety copy of current dirty @
  3. mv /mnt/top/@ /mnt/top/@.dirty                                        # move dirty @ aside (old @ keeps subvolid 256)
  4. btrfs subvolume snapshot /mnt/top/@.dirty/.snapshots/1/snapshot /mnt/top/@   # backup snapshot becomes new @ (new subvolid ~272)
  5. Verify new @ clean: ls /mnt/top/@/usr/bin/labwc|mango|noctalia-greeter-session /etc/greetd → all absent
  6. umount /mnt/top
- No bootloader/fstab change needed: normal boot already loads subvol=/@, which now points to the new clean @.
- Reset /home to pristine pre-setup (it is a separate subvol and is NOT restored by the root rollback): rm -rf /home/salva/.config /home/salva/.local /home/salva/.cache /home/salva/.dotarch-backup-* /home/salva/Desktop /home/salva/Documents /home/salva/Downloads /home/salva/Music /home/salva/Pictures /home/salva/Projects /home/salva/Public /home/salva/Templates /home/salva/Videos /home/salva/config.toml /home/salva/settings.toml (leaving original .bash_logout/.bash_profile/.bashrc). Preserve wanted files first to /tmp/opencode/home-preserve/ (e.g. config.toml, settings.toml, Pictures, Videos, .config/noctalia, .config/labwc).
- After rollback, reboot to land in the clean root, then re-run setup_noctalia.sh. Preserved copies for safety: @.dirty (old post-setup root) and @.pre_rollback; they are not in the fstab path so they don't break boot. Can be deleted (btrfs subvolume delete) once no longer needed.

Relevant Files
- /home/salva/dev/archdot/setup_noctalia.sh — the single installer; unified labwc/mango (flag or prompt), merged noctalia config, greetd/noctalia-greeter DM, AUR build for mangowm.
- /home/salva/dev/archdot/changes to adddress on the bar/config.toml and settings.toml — source files for the merged noctalia config (settings.toml values used verbatim).
- /home/salva/dev/archdot/README.md — this file.
- ~/.config/noctalia/config.toml (declarative base) + ~/.local/state/noctalia/settings.toml (GUI overrides, loaded last) — the two sources merged into the script's config.
- Preserve dir on .111: /tmp/opencode/home-preserve/ (config.toml, settings.toml, Pictures, Videos, .config/noctalia, .config/labwc) staged before /home cleanup.
- Preserved subvols on .111: @.dirty (old post-setup root, subvolid 256), @.pre_rollback (subvolid 271) — deletable once no longer needed.
- /home/salva/dev/archdot/.git — git repo, branch main, changes uncommitted.