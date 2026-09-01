These scripts are for personal use with the intention to build lightweight Desktop Enviroments on clean minimal/server arch linux instalations with Noxtalia shell and for now two different compositors, labwc and mango.

Objective
- Move the Arch/CachyOS desktop setup from mangowm to labwc (official repo) with greetd + noctalia-greeter (graphical, Noctalia-themed) as the display manager, based on setup_mango.sh.
- Finalize setup_labwc.sh, apply fixes live on target PC (192.168.0.111), mirror fixes into the script, then re-test on a clean Arch install the user plans to do.
Important Details
- Project: git repo /home/salva/dev/archdot
- Credentials: target salva@192.168.0.111 ssh/sudo password asdasd . SSH needs -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/opencode/known_hosts2-111 (per-target known_hosts file; wipe on fresh installs). Local tool dir /tmp/opencode/ may be wiped on reboots.
- Headless run pattern on .111 works: temp sudoers /etc/sudoers.d/zz-dotarch-temp with salva ALL=(ALL) NOPASSWD: ALL, then launch nohup sh -c "bash /tmp/setup_labwc.sh > /tmp/setup.log 2>&1; echo SCRIPT_EXIT=$? > /tmp/setup.exit" & as salva (NOT wrapped in sudo -n).
- Critical deployment bug found: launching the nohup under sudo -n sh -c runs the script as root → hits the "Do NOT run as root" guard and bails (exit 0). Correct launch is as the salva user, letting internal sudo calls elevate. Also: the failed root run left root-owned /tmp/setup.log//tmp/setup.exit that salva couldn't overwrite — must clean via sudo -n rm -f before relaunching.
- noctalia-greeter installed from AUR on .111 (target): built via makepkg -si (1.3.0-1) with toolchain base-devel git go just meson + deps (wayland, wayland-protocols, wlroots0.20, libglvnd, freetype2, fontconfig, cairo, pango, harfbuzz, libxkbcommon, glib2, tomlplusplus, nlohmann-json, stb, libwebp, librsvg). greetd config updated to command = "/usr/bin/noctalia-greeter-session", user greeter (greeter uid 965 in video+seat). Verified rendering: noctalia-greeter-compositor running on tty1 for greeter, greetd active, no errors in journal.
- Dolphin palette fix: script dolphinrc now ColorScheme=noctalia (lowercase), matching target.


Next Move
1. re-test setup labwc on target salva@192.168.0.111 ssh/sudo password asdasd.
2. Verify all script edits (bash -n setup_labwc.sh setup_mango.sh), then review and commit both scripts (delete old setup.sh if superseded); user will do clean Arch reinstall for final re-test.
3. change setup_mango.sh to greetd and noctalia-greeter as well as setup.sh

Relevant Files
- /home/salva/dev/archdot/setup_labwc.sh — main deliverable; all fixes staged in working tree (icon fix pending). 747 lines.
- /home/salva/dev/archdot/setup_mango.sh — parallel script; gnome-keyring removed (3 refs), dolphin/portal edits mirrored.
- ~/.config/noctalia/config.toml (target .111) — launcher custom_image = "$HOME/.local/share/icons/arch-round.svg" (unexpanded, the bug).
- ~/.local/share/icons/arch-round.svg (target) — 3333 bytes, valid SVG (39 lines), present; not rendered due to path bug.
- ~/.config/labwc/rc.xml, menu.xml, ~/.config/foot/foot.ini, ~/.config/dolphinrc, ~/.config/xdg-desktop-portal/labwc-portals.conf — all fixed on target and mirrored in script.
- /etc/greetd/config.toml (target .111) — now command = "/usr/bin/noctalia-greeter-session", user greeter; .bak in /etc/greetd/config.toml.bak.
- /tmp/opencode/apply_ws.py, /tmp/opencode/menu.xml — scp'd patch/menu artifacts (local).
- /home/salva/dev/archdot/.git — git repo, branch main, changes uncommitted.
- /home/salva/dev/dotarch/setup.sh — old non-git copy (superseded).