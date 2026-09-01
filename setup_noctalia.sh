#!/usr/bin/env bash

set -euo pipefail


HOME_BAK="$HOME/.dotarch-backup-$(date +%Y%m%d%H%M%S)"

say()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m== %s ==\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------------------
# Window manager selection: labwc or mangowm.
#   setup_noctalia.sh --labwc     -> configure labwc (default; nothing extra)
#   setup_noctalia.sh --mango     -> configure mangowm (builds it from the AUR)
#   setup_noctalia.sh             -> ask interactively
# ------------------------------------------------------------------------------
WM=""
for arg in "$@"; do
    case "$arg" in
        --labwc) WM="labwc" ;;
        --mango) WM="mango" ;;
        --help|-h)
            echo "Usage: $0 [--labwc | --mango]"
            echo "  --labwc  configure the labwc window manager (default)"
            echo "  --mango  configure mangowm (built from the AUR)"
            exit 0
            ;;
        *) ;;
    esac
done

if [ -z "$WM" ]; then
    printf '%s\n' "Which window manager do you want to configure?"
    printf '  1) labwc   (stable, official repos; no extra build steps)\n'
    printf '  2) mango   (mangowm, rolling build from the AUR; slower)\n'
    while [ -z "$WM" ]; do
        read -rp "Type 1 or 2 [1]: " choice
        case "$choice" in
            1|labwc|Labwc|LABWC) WM="labwc" ;;
            2|mango|Mango|MANGO) WM="mango" ;;
            "") WM="labwc" ;;
            *) printf 'Invalid choice: %s\n' "$choice" ;;
        esac
    done
fi
say "Selected window manager: $WM"

# ------------------------------------------------------------------------------
# EDIT ME — application list.
# ------------------------------------------------------------------------------
# NOTE on noctalia-greeter: it lives in the official CachyOS repo (and the AUR),
# but NOT (yet) in vanilla Arch's core/extra/multilib. The script tries to pull
# it with pacman (works on CachyOS); if it is not in your enabled repos it
# falls back to the official greetd-agreety greeter so the box still boots to a
# login screen. Everything else below is official-repo only.
# Common packages (everything except the labwc binary), so labwc and mangowm
# share the same base. mangowm itself comes from the AUR (see AUR_PACKAGES).
PACKAGES=(
    # -- desktop / shell (official) ----------------------------------------------
    breeze noctalia foot

    # -- display manager / seat --------------------------------------------------
    greetd greetd-agreety seatd wlopm xdg-desktop-portal

    # -- gpu: common GL/VAAPI userspace (vendor drivers auto-detected below) ---
    mesa libva-utils xorg-xwayland

    # -- audio ------------------------------------------------------------------
    pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol alsa-utils

    # -- network / bluetooth ----------------------------------------------------
    networkmanager network-manager-applet bluez bluez-utils blueman

    # -- the look ---------------------------------------------------------------
    capitaine-cursors breeze-icons adw-gtk-theme qt6ct

    # -- fonts -------------------------------------------------------------------
    noto-fonts noto-fonts-emoji ttf-meslo-nerd ttf-nerd-fonts-symbols
    ttf-dejavu ttf-liberation cantarell-fonts

    # -- apps (normie + picks) ---------------------------------------------------
    chromium dolphin kde-cli-tools dolphin-plugins ark ffmpegthumbnailer xdg-user-dirs
    mpv mpv-mpris zathura zathura-pdf-mupdf imv micro btop htop fastfetch
    gnome-disk-utility qbittorrent glmark2
    # firefox

    # -- wayland / clipboard / portals ------------------------------------------
    wl-clipboard wlr-randr wdisplays xdg-desktop-portal-wlr xdg-desktop-portal-gtk

    # -- disks / the noctalia udiskie plugin -------------------------------------
    udisks2 udiskie xdg-utils

    # -- power / system tools -----------------------------------------------------
    power-profiles-daemon upower git rsync wget ripgrep unzip unrar p7zip zip
    bash-completion pacman-contrib reflector openssh polkit-kde-agent ufw
)

# AUR-only packages, used ONLY when WM=mango: mangowm itself plus its build
# deps (a wlroots 0.20 provider + scenefx 0.5). Not installed for labwc.
AUR_PACKAGES=(
    wlroots0.20-hidpi-xprop   # libwlroots-0.20.so (AUR-only build dep of mangowm-git)
    scenefx0.5                # scenefx 0.5 (AUR-only build dep of mangowm-git)
    mangowm-git               # the mango WM itself (rolling/development build)
)

# The WM binary, used as the greetd-agreety fallback session command and the
# thing the selected window manager launches.
if [ "$WM" = "labwc" ]; then
    PACKAGES+=(labwc)
    WM_SESSION_BIN="/usr/bin/labwc"
else
    WM_SESSION_BIN="/usr/bin/mango"
fi

# ------------------------------------------------------------------------------
# Platform / GPU detection (Intel, AMD, NVIDIA) — adds vendor-specific packages
# and the matching CPU microcode to PACKAGES.
#   GPU_VENDOR : intel | amd | nvidia | unknown
#   INTEL_OLD  : 1 when the Intel GPU predates Skylake/Broadwell+ (needs the
#                legacy VA-API driver libva-intel-driver instead of
#                intel-media-driver). Set, e.g. `INTEL_OLD=1`, to force it.
# Detection reads the kernel-visible PCI vendor/device IDs from /sys/class/drm.
# ------------------------------------------------------------------------------
detect_platform() {
    GPU_VENDOR="unknown"
    INTEL_OLD=0

    # Find PCI slots that expose a DRM connector (0-3 = the device fn).
    for d in /sys/class/drm/card[0-9]/device; do
        [ -e "$d/vendor" ] || continue
        vendor=$(cat "$d/vendor" 2>/dev/null)   # e.g. 0x8086
        devid=$(cat "$d/device" 2>/dev/null)    # e.g. 0x9bc4
        [ -n "$vendor" ] || continue

        case "$vendor" in
            0x8086) GPU_VENDOR=intel;  INTEL_PCIDEV="$devid"; break ;;
            0x1002|0x1022) GPU_VENDOR=amd; break ;;
            0x10de) GPU_VENDOR=nvidia; break ;;
        esac
    done

    # Intel branch: pick the VA-API driver by GPU generation.
    if [ "$GPU_VENDOR" = "intel" ]; then
        # Legacy = pre-Broadwell (GMA/965, G4x, Ironlake, Sandy/Ivy Bridge,
        # Haswell) PLUS the old-media-engine Atoms (Bay Trail + Cherry
        # Trail/Braswell). These need the i965 driver (libva-intel-driver);
        # intel-media-driver (iHD) only supports Broadwell and newer. Anything
        # not in the legacy list defaults to MODERN so the box always gets a
        # working driver. Override with INTEL_OLD=1 to force legacy.
        # (Device-id list sourced from mesa's pci_ids/i965_pci_ids.h.)
        INTEL_OLD=0   # default modern unless a legacy id below matches
        case "$INTEL_PCIDEV" in
            # Intel GMA 900/950/965 + G4x/GM45, Ironlake, Sandy/Ivy Bridge,
            # Haswell, Bay Trail (Valley View) + Cherry Trail / Braswell (N3xxx)
            0x29a2|0x2992|0x2982|0x2972|0x2a02|0x2a12|0x2a42|0x2e02|0x2e12|0x2e22|0x2e32|0x2e42|0x2e92| \
            0x0042|0x0046|0x0102|0x0112|0x0122|0x0106|0x0116|0x0126|0x010a| \
            0x0152|0x0162|0x0156|0x0166|0x015a|0x016a|0x0402|0x0412|0x0422| \
            0x0406|0x0416|0x0426|0x040a|0x041a|0x042a|0x040b|0x041b|0x042b| \
            0x040e|0x041e|0x042e|0x0c02|0x0c12|0x0c22|0x0c06|0x0c16|0x0c26| \
            0x0c0a|0x0c1a|0x0c2a|0x0c0b|0x0c1b|0x0c2b|0x0c0e|0x0c1e|0x0c2e| \
            0x0a02|0x0a12|0x0a22|0x0a06|0x0a16|0x0a26|0x0a0a|0x0a1a|0x0a2a| \
            0x0a0b|0x0a1b|0x0a2b|0x0a0e|0x0a1e|0x0a2e|0x0d02|0x0d12|0x0d22| \
            0x0d06|0x0d16|0x0d26|0x0d0a|0x0d1a|0x0d2a|0x0d0b|0x0d1b|0x0d2b| \
            0x0d0e|0x0d1e|0x0d2e|0x0f31|0x0f32|0x0f33|0x0157|0x0155| \
            0x22b0|0x22b1|0x22b2|0x22b3)
                INTEL_OLD=1 ;;
        esac
    fi
    export GPU_VENDOR INTEL_OLD
}

detect_platform

case "$GPU_VENDOR" in
    intel)
        if [ "$INTEL_OLD" -eq 1 ]; then
            GPGPU_PKGS=(libva-intel-driver vulkan-intel intel-ucode)
            GPX_NOTE="Intel (legacy, G45–Haswell): using libva-intel-driver"
        else
            GPGPU_PKGS=(intel-media-driver vulkan-intel intel-ucode)
            GPX_NOTE="Intel (Broadwell+): using intel-media-driver"
        fi
        ;;
    amd)
        GPGPU_PKGS=(vulkan-radeon libva-mesa-driver amd-ucode)
        GPX_NOTE="AMD: vulkan-radeon + libva-mesa-driver"
        ;;
    nvidia)
        GPGPU_PKGS=(nvidia nvidia-utils nvidia-settings)
        GPX_NOTE="NVIDIA: proprietary nvidia + nvidia-utils"
        ;;
    *)
        # Unknown/failed detection: install FOSS (mesa) stacks for all three
        # vendors plus every microcode, and assume MODERN hardware everywhere
        # (intel-media-driver, not the legacy libva-intel-driver).
        GPGPU_PKGS=(
            intel-media-driver vulkan-intel intel-ucode
            vulkan-radeon      libva-mesa-driver amd-ucode
            nvidia-utils
        )
        GPX_NOTE="unknown GPU — installing all three FOSS stacks (intel/amd) + nvidia-utils, all microcodes"
        ;;
esac
PACKAGES+=( "${GPGPU_PKGS[@]}" )
say "Platform: $GPU_VENDOR — $GPX_NOTE"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
sys_enable() {
    for svc in "$@"; do
        sudo systemctl enable --now "$svc" 2>/dev/null || sudo systemctl enable "$svc" \
            || printf '   [warn] could not enable %s\n' "$svc"
    done
}

usr_enable() {
    for svc in "$@"; do
        systemctl --user enable --now "$svc" 2>/dev/null \
            || systemctl --user enable "$svc" 2>/dev/null \
            || printf '   [warn] could not enable user unit %s (no session?)\n' "$svc"
    done
}

# ensure_yay: build the yay AUR helper once, if it is not already present.
ensure_yay() {
    if command -v yay >/dev/null 2>&1; then
        return
    fi
    say "Building yay from AUR"
    sudo pacman -S --noconfirm --needed base-devel git go
    tmp="$(mktemp -d)"
    git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm --needed)
    command -v yay >/dev/null 2>&1 || die "yay build failed."
}

# ------------------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] && die "Do NOT run as root — run as your user, sudo is handled internally."
command -v pacman >/dev/null || die "pacman not found — this script targets Arch Linux."
command -v sudo  >/dev/null || die "sudo not found."
grep -qi '^ID=arch' /etc/os-release 2>/dev/null || die "Not an Arch-based distro — refusing to run."

# Fresh archinstall images occasionally have an empty keyring.
if ! sudo pacman-key --list-keys >/dev/null 2>&1 || [ -z "$(sudo pacman-key --list-keys 2>/dev/null | awk '/^pub/{print $2}')" ]; then
    say "Bootstrapping pacman keyring"
    sudo pacman-key --init
    sudo pacman-key --populate archlinux
fi

say "Full system upgrade"
sudo pacman -Syu --noconfirm

# ------------------------------------------------------------------------------
# Base packages (official repos)
# ------------------------------------------------------------------------------
say "Installing packages from official repos"
sudo pacman -S --noconfirm --needed "${PACKAGES[@]}"

# ------------------------------------------------------------------------------
# Mango: mangowm from the AUR (only when WM=mango)
# ------------------------------------------------------------------------------
if [ "$WM" = "mango" ]; then
    say "Installing mangowm-git from AUR"
    ensure_yay
    yay -S --noconfirm --needed "${AUR_PACKAGES[@]}"
fi

# ------------------------------------------------------------------------------
# Greeter: noctalia-greeter (official on CachyOS, AUR on vanilla Arch)
# ------------------------------------------------------------------------------
# Try the packaged greeter first. On a CachyOS install with the cachyos repo
# enabled this resolves straight from pacman. On vanilla Arch it is missing, so
# we build it from the AUR (needs base-devel + git + an AUR helper such as yay).
# Only if both paths fail do we fall back to the official greetd-agreety greeter.
GREETER_SESSION=""
if command -v noctalia-greeter-session >/dev/null 2>&1; then
    GREETER_SESSION="$(command -v noctalia-greeter-session)"
elif sudo pacman -S --noconfirm --needed noctalia-greeter >/dev/null 2>&1 \
     && command -v noctalia-greeter-session >/dev/null 2>&1; then
    GREETER_SESSION="$(command -v noctalia-greeter-session)"
else
    say "noctalia-greeter not in your repos — installing from the AUR"
    ensure_yay
    if command -v yay >/dev/null 2>&1; then
        yay -S --noconfirm --needed noctalia-greeter >/dev/null 2>&1 \
            && command -v noctalia-greeter-session >/dev/null 2>&1 \
            && GREETER_SESSION="$(command -v noctalia-greeter-session)"
    fi
fi

# ------------------------------------------------------------------------------
# Configs (with backups of whatever already exists)
# ------------------------------------------------------------------------------
say "Deploying configs (backups in $HOME_BAK)"
mkdir -p "$HOME_BAK" "$HOME/.config/noctalia" \
         "$HOME/.config/foot" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" \
         "$HOME/.config/qt6ct" "$HOME/.config/mpv" \
         "$HOME/.config/xdg-desktop-portal" \
         "$HOME/.config/dolphinrc.d" 2>/dev/null || true
if [ "$WM" = "labwc" ]; then
    mkdir -p "$HOME/.config/labwc" 2>/dev/null || true
else
    mkdir -p "$HOME/.config/mango/cfg" 2>/dev/null || true
fi

backup() {   # backup <target-file>
    if [ -e "$1" ]; then
        mkdir -p "$HOME_BAK/$(dirname "${1#$HOME/}")"
        cp -a "$1" "$HOME_BAK/${1#$HOME/}"
        rm -rf "$1"
    fi
}

# ---------------- labwc (only when WM=labwc) ----------------
if [ "$WM" = "labwc" ]; then
# environment: keyboard layout, cursor theme/size, and the seat/portal env that
# labwc passes to every client. XKB layout mirrors the mangowm setup (latam).
backup "$HOME/.config/labwc/environment"
cat > "$HOME/.config/labwc/environment" <<'LABWC_ENV'
XKB_DEFAULT_LAYOUT=latam
XCURSOR_THEME=capitaine-cursors
XCURSOR_SIZE=24
LABWC_ENV

# rc.xml: window-stacking compositor. <default /> pulls in the built-in binds;
# we add Noctalia's IPC binds (launcher/control-center/settings + media keys)
# and the same app launcher keys as the mangowm setup. No inline XML comments
# (they made older labwc ignore the file). The Noctalia reconfig shortcut is
# SUPER+r → `noctalia config validate` + reload as the shell reads rc on reload.
backup "$HOME/.config/labwc/rc.xml"
cat > "$HOME/.config/labwc/rc.xml" <<'LABWC_RC'
<?xml version="1.0" encoding="UTF-8"?>
<labwc_config>
  <core>
    <gap>10</gap>
  </core>

  <placement>
    <policy>smart</policy>
  </placement>

  <resistance><screenEdgeStrength>20</screenEdgeStrength></resistance>

  <theme>
    <cornerRadius>10</cornerRadius>
    <dropShadows>yes</dropShadows>
  </theme>

  <windowSwitcher preview="no" outlines="yes">
    <osd style="thumbnail" />
  </windowSwitcher>

  <desktops number="8" />

  <keyboard>
    <default />

    <keybind key="W-t">
      <action name="Execute"><command>foot</command></action>
    </keybind>
    <keybind key="W-e">
      <action name="Execute"><command>dolphin</command></action>
    </keybind>
    <keybind key="W-b">
      <action name="Execute"><command>chromium</command></action>
    </keybind>

    <keybind key="W-1"><action name="GoToDesktop" to="1" /></keybind>
    <keybind key="W-2"><action name="GoToDesktop" to="2" /></keybind>
    <keybind key="W-3"><action name="GoToDesktop" to="3" /></keybind>
    <keybind key="W-4"><action name="GoToDesktop" to="4" /></keybind>
    <keybind key="W-5"><action name="GoToDesktop" to="5" /></keybind>
    <keybind key="W-6"><action name="GoToDesktop" to="6" /></keybind>
    <keybind key="W-7"><action name="GoToDesktop" to="7" /></keybind>
    <keybind key="W-8"><action name="GoToDesktop" to="8" /></keybind>

    <keybind key="W-S-1"><action name="SendToDesktop" to="1" wrap="no" /></keybind>
    <keybind key="W-S-2"><action name="SendToDesktop" to="2" wrap="no" /></keybind>
    <keybind key="W-S-3"><action name="SendToDesktop" to="3" wrap="no" /></keybind>
    <keybind key="W-S-4"><action name="SendToDesktop" to="4" wrap="no" /></keybind>
    <keybind key="W-S-5"><action name="SendToDesktop" to="5" wrap="no" /></keybind>
    <keybind key="W-S-6"><action name="SendToDesktop" to="6" wrap="no" /></keybind>
    <keybind key="W-S-7"><action name="SendToDesktop" to="7" wrap="no" /></keybind>
    <keybind key="W-S-8"><action name="SendToDesktop" to="8" wrap="no" /></keybind>

    <keybind key="W-Left"><action name="GoToDesktop" to="previous" /></keybind>
    <keybind key="W-Right"><action name="GoToDesktop" to="next" /></keybind>

    <keybind key="W-space">
      <action name="Execute"><command>noctalia msg panel-toggle launcher</command></action>
    </keybind>
    <keybind key="W-s">
      <action name="Execute"><command>noctalia msg panel-toggle control-center</command></action>
    </keybind>
    <keybind key="W-comma">
      <action name="Execute"><command>noctalia msg settings-toggle</command></action>
    </keybind>

    <keybind key="W-q">
      <action name="Close" />
    </keybind>
    <keybind key="W-w">
      <action name="Execute"><command>noctalia msg panel-toggle noctalia/wallhaven:browser</command></action>
    </keybind>
    <keybind key="W-c">
      <action name="Execute"><command>noctalia msg panel-toggle clipboard</command></action>
    </keybind>

    <keybind key="W-p">
      <action name="Execute"><command>noctalia msg screenshot-region</command></action>
    </keybind>
    <keybind key="W-S-p">
      <action name="Execute"><command>noctalia msg screenshot-fullscreen</command></action>
    </keybind>

    <keybind key="W-r">
      <action name="Execute"><command>noctalia config validate; labwc --reconfigure</command></action>
    </keybind>

    <keybind key="XF86AudioRaiseVolume">
      <action name="Execute"><command>noctalia msg volume-up</command></action>
    </keybind>
    <keybind key="XF86AudioLowerVolume">
      <action name="Execute"><command>noctalia msg volume-down</command></action>
    </keybind>
    <keybind key="XF86AudioMute">
      <action name="Execute"><command>noctalia msg volume-mute</command></action>
    </keybind>
    <keybind key="XF86MonBrightnessUp">
      <action name="Execute"><command>noctalia msg brightness-up</command></action>
    </keybind>
    <keybind key="XF86MonBrightnessDown">
      <action name="Execute"><command>noctalia msg brightness-down</command></action>
    </keybind>
  </keyboard>
</labwc_config>
LABWC_RC

# autostart: noctalia is the shell/bar. The wallpaper is owned by noctalia
# (wallpaper.path in config.toml), so we do not start swaybg — just the shell.
backup "$HOME/.config/labwc/autostart"
cat > "$HOME/.config/labwc/autostart" <<'LABWC_AUTOSTART'
noctalia
systemctl -q --no-block --user start labwc-session.target
LABWC_AUTOSTART

# shutdown: mirror the labwc-session.target bookkeeping.
backup "$HOME/.config/labwc/shutdown"
cat > "$HOME/.config/labwc/shutdown" <<'LABWC_SHUTDOWN'
systemctl -q --user stop graphical-session.target
LABWC_SHUTDOWN

# menu.xml: the stock labwc example root + client menus. Kept pristine so the
# menus behave exactly like an unmodified labwc (simple, reliable).
backup "$HOME/.config/labwc/menu.xml"
cat > "$HOME/.config/labwc/menu.xml" <<'LABWC_MENU'
<openbox_menu>
<menu id="client-menu">
  <item label="Minimize">
    <action name="Iconify" />
  </item>
  <item label="Maximize">
    <action name="ToggleMaximize" />
  </item>
  <item label="Fullscreen">
    <action name="ToggleFullscreen" />
  </item>
  <item label="Roll Up/Down">
    <action name="ToggleShade" />
  </item>
  <item label="Decorations">
    <action name="ToggleDecorations" />
  </item>
  <item label="Always on Top">
    <action name="ToggleAlwaysOnTop" />
  </item>
  <menu id="client-send-to-menu" />
  <item label="Close">
    <action name="Close" />
  </item>
</menu>

<menu id="root-menu">
  <item label="Terminal">
    <action name="Execute" command="foot" />
  </item>
  <separator />
  <item label="Reconfigure">
    <action name="Reconfigure" />
  </item>
  <item label="Exit">
    <action name="Exit" />
  </item>
</menu>
</openbox_menu>
LABWC_MENU
fi   # end labwc configs

# ---------------- mango (only when WM=mango) ----------------
if [ "$WM" = "mango" ]; then
backup "$HOME/.config/mango/config.conf"
cat > "$HOME/.config/mango/config.conf" <<'MANGO_ROOT'
source = ./cfg/monitors.conf
source = ./cfg/keybinds.conf
source = ./cfg/input.conf
source = ./cfg/autostart.conf
source = ./cfg/env.conf
source = ./cfg/appearance.conf
source = ./cfg/layout.conf
source = ./cfg/misc.conf
source = ./cfg/rules.conf
MANGO_ROOT

backup "$HOME/.config/mango/cfg/monitors.conf"
cat > "$HOME/.config/mango/cfg/monitors.conf" <<'MANGO_MONITORS'
# | Outputs Configuration |
# Configure your monitors here or in the DMS "Displays" settings. | https://mangowm.github.io/docs/configuration/monitors
# Run `wlr-randr` to get your monitors information.
# You will have to remove "#" and edit it for it to take effect.

# monitorrule = name:DP-1, width:2560, height:1440, refresh:179.999, x:0, y:0, rr:0, vrr:1
MANGO_MONITORS

backup "$HOME/.config/mango/cfg/keybinds.conf"
cat > "$HOME/.config/mango/cfg/keybinds.conf" <<'MANGO_KEYBINDS'
# | Keybinds |
# Configure your keybinds here. | https://mangowm.github.io/docs/bindings/keys

# Your favorite applications.
bind = SUPER, t, spawn, foot
bind = SUPER, e, spawn, dolphin
bind = SUPER, b, spawn, chromium

# Wine killer
bind = CTRL+ALT, q, spawn, wineserver -k

# Please choose the text editor of your choice.
# bind = SUPER, x, spawn, zed

bind = SUPER, q, killclient,

# Noctalia specific keybinds.
bind = SUPER, space, spawn, noctalia msg panel-toggle launcher
bind = SUPER, s, spawn, noctalia msg panel-toggle control-center
bind = SUPER+SHIFT, s, spawn, noctalia msg settings-toggle
bind = SUPER, w, spawn, noctalia msg panel-toggle noctalia/wallhaven:browser
bind = SUPER, c, spawn, noctalia msg panel-toggle clipboard
bind = SUPER+SHIFT, q, spawn, noctalia msg panel-toggle session

# Screenshots
bind = SUPER, p, spawn, noctalia msg screenshot-region
bind = SUPER+SHIFT, p, spawn, noctalia msg screenshot-fullscreen
bind = SUPER+ALT, p, spawn, noctalia msg screenshot-fullscreen all

# Reload config
bind = SUPER, r, reload_config

# Audio controls
bind = NONE, XF86AudioRaiseVolume, spawn, noctalia msg volume-up
bind = NONE, XF86AudioLowerVolume, spawn, noctalia msg volume-down
bind = NONE, XF86AudioMute, spawn, noctalia msg volume-mute

# Brightness controls
bind = NONE, XF86MonBrightnessUp, spawn, noctalia msg brightness-up
bind = NONE, XF86MonBrightnessDown, spawn, noctalia msg brightness-down

# Switch window focus
bind = SUPER, Tab, focusstack, next
bind = SUPER, Left, focusdir, left
bind = SUPER, Right, focusdir, right
bind = SUPER, Up, focusdir, up
bind = SUPER, Down, focusdir, down

# Swap window
bind = SUPER+SHIFT, Up, exchange_client, up
bind = SUPER+SHIFT, Down, exchange_client, down
bind = SUPER+SHIFT, Left, exchange_client, left
bind = SUPER+SHIFT, Right, exchange_client, right

# Switch window status
bind = SUPER, g, toggleglobal,
bind = ALT, Tab, toggleoverview,
bind = SUPER, v, togglefloating,
bind = SUPER, f, togglemaximizescreen,
bind = SUPER+SHIFT, f, togglefullscreen,
bind = SUPER+ALT, f, togglefakefullscreen,
bind = SUPER, i, minimized,
bind = SUPER, o, toggleoverlay,
bind = SUPER+SHIFT, I, restore_minimized
bind = SUPER, z, toggle_scratchpad

# Scroller layout
bind = SUPER+SHIFT, e, set_proportion, 1.0
bind = SUPER, x, switch_proportion_preset,

# Switch layout
bind = SUPER, n, switch_layout

# Switch between workspaces
bind = SUPER, 1, view, 1, 0
bind = SUPER, 2, view, 2, 0
bind = SUPER, 3, view, 3, 0
bind = SUPER, 4, view, 4, 0
bind = SUPER, 5, view, 5, 0
bind = SUPER, 6, view, 6, 0
bind = SUPER, 7, view, 7, 0
bind = SUPER, 8, view, 8, 0
bind = SUPER, 9, view, 9, 0

# Tag: move client to another workspace.
# Tagsilent: move client to another workspace but do not focus it.
# E.g bind = SUPER+SHIFT, 1, tagsilent, 1
bind = SUPER+SHIFT ,1, tag, 1, 0
bind = SUPER+SHIFT, 2, tag, 2, 0
bind = SUPER+SHIFT, 3, tag, 3, 0
bind = SUPER+SHIFT, 4, tag, 4, 0
bind = SUPER+SHIFT, 5, tag, 5, 0
bind = SUPER+SHIFT, 6, tag, 6, 0
bind = SUPER+SHIFT, 7, tag, 7, 0
bind = SUPER+SHIFT, 8, tag, 8, 0
bind = SUPER+SHIFT, 9, tag, 9, 0

# Switch between monitors
bind = SUPER+ALT, Left, focusmon, left
bind = SUPER+ALT, Right, focusmon, right
# Move window to another monitor
bind = SUPER+ALT, Left, tagmon, left
bind = SUPER+ALT, Right, tagmon, right

# Gaps
bind = SUPER+SHIFT, X, incgaps, 1
bind = SUPER+SHIFT, Z, incgaps, -1
bind = SUPER+SHIFT, R, togglegaps

# Movewin
bind = CTRL+SHIFT, Up, movewin, +0, -50
bind = CTRL+SHIFT, Down, movewin, +0, +50
bind = CTRL+SHIFT, Left, movewin, -50,+0
bind = CTRL+SHIFT, Right, movewin, +50,+0

# Resizewin
bind = CTRL+ALT, Up, resizewin, +0, -50
bind = CTRL+ALT, Down, resizewin, +0, +50
bind = CTRL+ALT, Left, resizewin, -50, +0
bind = CTRL+ALT, Right, resizewin, +50, +0

# Mouse Button Bindings.
# btn_left and btn_right can't bind none mod key
mousebind = SUPER, btn_left, moveresize,curmove
mousebind = NONE, btn_middle, togglemaximizescreen, 0
mousebind = SUPER, btn_right, moveresize, curresize
MANGO_KEYBINDS

backup "$HOME/.config/mango/cfg/input.conf"
cat > "$HOME/.config/mango/cfg/input.conf" <<'MANGO_INPUT'
# | Input Devices |
# Configure your input devices here. | https://mangowm.github.io/docs/configuration/input

xkb_rules_layout = latam

# If you want to disable pointer acceleration, uncomment the lines below.
# accel_profile = 1
# accel_speed = 0.2
MANGO_INPUT

backup "$HOME/.config/mango/cfg/autostart.conf"
cat > "$HOME/.config/mango/cfg/autostart.conf" <<'MANGO_AUTOSTART'
# | Auto Start |
# autostart your favorite applications here

exec-once = noctalia &
MANGO_AUTOSTART

backup "$HOME/.config/mango/cfg/env.conf"
cat > "$HOME/.config/mango/cfg/env.conf" <<'MANGO_ENV'
# | Environment Variables |
# Set your environment variables here. | https://mangowm.github.io/docs/configuration/basics#environment-variables

env = TERMINAL,foot
# QT_QPA_PLATFORMTHEME deliberately NOT set (commented, exactly like the source
# box): shell-spawned and D-Bus/systemd-activated apps (e.g. dolphin --daemon
# via FileManager1) then share the same Qt env and get identical styling from
# kdeglobals' ColorScheme=Noctalia instead of splitting on QPA theme.
# env = QT_QPA_PLATFORMTHEME,qt6ct
# env = QT_QPA_PLATFORMTHEME_QT6,qt6ct
MANGO_ENV

backup "$HOME/.config/mango/cfg/appearance.conf"
cat > "$HOME/.config/mango/cfg/appearance.conf" <<'MANGO_APPEARANCE'
# | Look & Feel |
# theming | https://mangowm.github.io/docs/visuals

gappih = 1
gappiv = 1
gappoh = 1
gappov = 1
borderpx = 2
border_radius = 10

scratchpad_width_ratio = 0.8
scratchpad_height_ratio = 0.9

rootcolor = 0x201b14ff
bordercolor = 0x444444ff
focuscolor = 0x47add6ff
maximizescreencolor = 0x47add6ff
urgentcolor = 0xad401fff
scratchpadcolor = 0x516c93ff
globalcolor = 0xb153a7ff
overlaycolor = 0x14a57cff

cursor_theme = capitaine-cursors
cursor_size = 24

blur = 1
blur_layer = 0
blur_optimized = 1
blur_params_num_passes = 2
blur_params_radius = 4
blur_params_noise = 0.04
blur_params_brightness = 0.9
blur_params_contrast = 0.9
blur_params_saturation = 1.2

shadows = 1
layer_shadows = 0
shadow_only_floating = 0
shadows_size = 4
shadows_blur = 5
shadows_position_x = 0
shadows_position_y = 0
shadowscolor = 0x000000ff

animations = 1
layer_animations = 1
animation_type_open = zoom
animation_type_close = zoom
animation_fade_in = 1
animation_fade_out = 1
tag_animation_direction = 1
zoom_initial_ratio = 0.1
zoom_end_ratio = 0.5
fadein_begin_opacity = 0.3
fadeout_begin_opacity = 0.2
animation_duration_move = 300
animation_duration_open = 100
animation_duration_tag = 300
animation_duration_close = 400
animation_duration_focus = 0
animation_curve_open = 0.87, 0, 0.13, 1
animation_curve_move = 0.46, 1.0, 0.29, 1
animation_curve_tag = 0.46, 1.0, 0.29, 1
animation_curve_close = 0.87, 0, 0.13, 1
animation_curve_focus = 0.46, 1.0, 0.29, 1
animation_curve_opafadeout = 0.5, 0.5, 0.5, 0.5
animation_curve_opafadein = 0.46, 1.0, 0.29, 1
MANGO_APPEARANCE

backup "$HOME/.config/mango/cfg/layout.conf"
cat > "$HOME/.config/mango/cfg/layout.conf" <<'MANGO_LAYOUT'
# | Layout |
# layouts | https://mangowm.github.io/docs/window-management/layouts

# Change your layout here for each workspace.
# tile, scroller, grid, deck, monocle, center_tile, vertical_tile, right_tile, vertical_scroller, dwindle, fair, vertical_fair, vertical_grid, vertical_deck
tagrule = id:1, layout_name:dwindle
tagrule = id:2, layout_name:dwindle
tagrule = id:3, layout_name:dwindle
tagrule = id:4, layout_name:dwindle
tagrule = id:5, layout_name:dwindle
tagrule = id:6, layout_name:dwindle
tagrule = id:7, layout_name:dwindle
tagrule = id:8, layout_name:dwindle
tagrule = id:9, layout_name:dwindle

# Scrolling layout settings
scroller_structs = 40
scroller_default_proportion = 0.5
scroller_focus_center = 0
scroller_prefer_center = 0
scroller_prefer_overspread = 1
edge_scroller_pointer_focus = 1
scroller_default_proportion_single = 2.0
scroller_proportion_preset = 0.5, 0.8, 1.0

# Master-Stack layout settings
new_is_master = 1
default_mfact = 0.65
default_nmaster = 1
smartgaps = 0
MANGO_LAYOUT

backup "$HOME/.config/mango/cfg/misc.conf"
cat > "$HOME/.config/mango/cfg/misc.conf" <<'MANGO_MISC'
# | Miscellaneous |
# https://mangowm.github.io/docs/configuration/miscellaneous

allow_tearing = 2
syncobj_enable = 1
# xwayland-persistence = 1

drag_tile_to_tile = 1
MANGO_MISC

backup "$HOME/.config/mango/cfg/rules.conf"
cat > "$HOME/.config/mango/cfg/rules.conf" <<'MANGO_RULES'
# | Rules |
# Window/Tag/Layer rules. | https://mangowm.github.io/docs/window-management/rules

windowrule = isfloating:1, appid:[Ss]team
windowrule = isfloating:0, title:Steam
windowrule = isfloating:1, appid:steam, title:Steam Settings

layerrule = noanim:1, noblur:1, layer_name:selection
MANGO_RULES

fi   # end mango configs

# ---------------- noctalia ----------------
backup "$HOME/.config/noctalia/config.toml"
cat > "$HOME/.config/noctalia/config.toml" <<'NOCTALIA'
[bar.default]
background_opacity = 0.89999997988343239
center = [ "workspaces", "Spacer_2", "settings" ]
end = [
    "tray",
    "Spacer_2",
    "disks",
    "udiskie",
    "temp",
    "wdisplays",
    "spacer",
    "notifications",
    "clipboard",
    "Spacer_2",
    "network",
    "bluetooth",
    "volume",
    "brightness",
    "battery",
    "Spacer_2",
    "date",
    "clock",
    "Spacer_2",
    "session",
    "Spacer"
]
margin_edge = 0
margin_ends = 0
position = "bottom"
radius_bottom_left = 0
radius_bottom_right = 0
radius_top_left = 0
radius_top_right = 0
start = [ "Spacer", "launcher", "Spacer_2", "taskbar" ]
thickness = 40

[dock]
icon_size = 32
main_axis_padding = 7
pinned = [ "chromium" ]
smart_auto_hide = true

[wallpaper.default]
path = "/usr/share/noctalia/assets/noctalia-wallpaper.png"

[wallpaper.last]
path = "/usr/share/noctalia/assets/noctalia-wallpaper.png"

[wallpaper.monitors.HDMI-A-2]
path = "/usr/share/noctalia/assets/noctalia-wallpaper.png"

[idle]
behavior_order = [ "lock", "screen-off", "lock-and-suspend" ]

    [idle.behavior.Screen-off]
    action = "command"
    enabled = true
    timeout = 300.0
    command = "wlopm --off DP-1"
    resume_command = "wlopm --on DP-1"

    [idle.behavior.lock]
    action = "lock"
    enabled = true
    timeout = 600.0

    [idle.behavior.lock-and-suspend]
    action = "suspend"
    enabled = true
    lock_before_suspend = false
    timeout = 900.0

[osd]
background_opacity = 0.99999997764825821

[lockscreen_widgets]
enabled = false
schema_version = 2
widget_order = [ "lockscreen-login-box@HDMI-A-2", "lockscreen-login-box@DP-2", "lockscreen-login-box@DP-1" ]

    [lockscreen_widgets.grid]
    cell_size = 16
    major_interval = 4
    visible = true

    [lockscreen_widgets.widget."lockscreen-login-box@DP-1"]
    box_height = 196.0
    box_width = 720.0
    cx = 1280.0
    cy = 1321.0
    output = "DP-1"
    placement_height = 0.0
    placement_width = 0.0
    rotation = 0.0
    type = "login_box"

        [lockscreen_widgets.widget."lockscreen-login-box@DP-1".settings]
        background_color = "surface_variant"
        background_opacity = 0.88
        background_radius = 12.0
        center_password_text = false
        input_opacity = 1.0
        input_radius = 6.0
        layout = "regular"
        show_caps_lock = true
        show_keyboard_layout = true
        show_login_button = true
        show_media = true
        show_session_buttons = true
        show_unlock_hint = true
        show_weather = true

    [lockscreen_widgets.widget."lockscreen-login-box@DP-2"]
    box_height = 196.0
    box_width = 720.0
    cx = 1280.0
    cy = 1321.0
    output = "DP-2"
    placement_height = 0.0
    placement_width = 0.0
    rotation = 0.0
    type = "login_box"

        [lockscreen_widgets.widget."lockscreen-login-box@DP-2".settings]
        background_color = "surface_variant"
        background_opacity = 0.88
        background_radius = 12.0
        center_password_text = false
        input_opacity = 1.0
        input_radius = 6.0
        layout = "regular"
        show_caps_lock = true
        show_keyboard_layout = true
        show_login_button = true
        show_media = true
        show_session_buttons = true
        show_unlock_hint = true
        show_weather = true

    [lockscreen_widgets.widget."lockscreen-login-box@HDMI-A-2"]
    box_height = 196.0
    box_width = 810.0
    cx = 960.0
    cy = 898.0
    output = "HDMI-A-2"
    placement_height = 1080.0
    placement_width = 1920.0
    rotation = 0.0
    type = "login_box"

        [lockscreen_widgets.widget."lockscreen-login-box@HDMI-A-2".settings]
        background_color = "surface_variant"
        background_opacity = 0.88
        background_radius = 12.0
        center_password_text = false
        input_opacity = 1.0
        input_radius = 6.0
        layout = "regular"
        show_caps_lock = true
        show_keyboard_layout = true
        show_login_button = true
        show_media = true
        show_session_buttons = true
        show_unlock_hint = true
        show_weather = true

[plugin_settings."noctalia/screen_recorder"]
restore_portal = false

[plugins]
enabled = [ "noctalia/screen_recorder", "dotnetrob/cat", "noctalia/wallhaven", "aristides/udiskie" ]

    [[plugins.source]]
    kind = "git"
    location = "https://github.com/noctalia-dev/official-plugins"
    name = "official"

    [[plugins.source]]
    kind = "git"
    location = "https://github.com/noctalia-dev/community-plugins"
    name = "community"

[shell]
polkit_agent = true
settings_show_advanced = true

[shell.keyboard_layout.custom_labels]
"Spanish (Latin American)" = "es"

[shell.launcher]
pinned = [
    "chromium",
    "foot",
    "org.gnome.DiskUtility",
    "org.kde.dolphin",
    "network.cycles.wdisplays",
    "btop",
    "org.qbittorrent.qBittorrent"
]

[theme]
builtin = "Noctalia"
mode = "light"
source = "wallpaper"

    [theme.templates]
    builtin_ids = [ "btop", "foot", "gtk3", "gtk4", "kcolorscheme", "qt" ]

[widget.temp]
type = "sysmon"
stat = "cpu_temp"

[widget.Spacer]
length = 10
type = "spacer"

[widget.Spacer_2]
type = "spacer"

[widget.cat]
cat_size = 34
type = "dotnetrob/cat:cat"

[widget.date]
format = "{:%a %d %b -}"

[widget.launcher]
custom_image = "$HOME/.local/share/icons/arch-round.svg"
scale = 1.45

[widget.network]
show_label = false

[widget.recorder]
type = "noctalia/screen_recorder:recorder"

[widget.workspaces]
anchor = true
show_labels = false

[widget.wdisplays]
type = "custom_button"
glyph = "device-desktop"

[widget.wdisplays.actions]
left = "exec wdisplays"

[widget.udiskie]
type = "custom_button"
glyph = "device-usb"

[widget.udiskie.actions]
left = "exec noctalia msg panel-toggle aristides/udiskie:manager"

[widget.active_window]
display = "icon_only"
icon_size = 18

[widget.disks]
type = "custom_button"
glyph = "air-conditioning-disabled"

[widget.disks.actions]
left = "exec gnome-disks"

[widget.taskbar]
capsule = true
capsule_fill = "on_secondary"
capsule_opacity = 0.79000000000000004
icon_scale = 1.2000000000000002
item_spacing = 9
show_window_title = false
window_title_max_width = 180
show_active_indicator = true
active_indicator_color = "primary"
active_opacity = 1.0
inactive_opacity = 0.75
show_all_outputs = true
group_by_workspace = false
NOCTALIA

# noctalia reads custom_image as a literal path and does NOT expand $HOME, so
# substitute the real absolute home path (the heredoc above is quoted on purpose
# to keep the rest of the config literal).
sed -i "s|\\\$HOME|$HOME|g" "$HOME/.config/noctalia/config.toml"


# ---------------- gtk / qt6ct / kde / dolphin / foot / portals ----------------
backup "$HOME/.config/foot/foot.ini"
cat > "$HOME/.config/foot/foot.ini" <<'FOOT'
[main]
include=~/.config/foot/themes/noctalia
font=MesloLGM Nerd Font Mono:size=12
FOOT

backup "$HOME/.config/gtk-3.0/settings.ini"
cat > "$HOME/.config/gtk-3.0/settings.ini" <<'GTK3'
[Settings]
gtk-theme-name=adw-gtk3
gtk-cursor-theme-name=capitaine-cursors-light
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
GTK3

for v in 3.0 4.0; do
    backup "$HOME/.config/gtk-$v/gtk.css"
    printf '@import url("noctalia.css");\n' > "$HOME/.config/gtk-$v/gtk.css"
done

backup "$HOME/.config/qt6ct/qt6ct.conf"
# qt6ct is INSTALLED but deliberately INERT: no app runs with a
# QT_QPA_PLATFORMTHEME env, so KDE/Qt apps style themselves natively from
# kdeglobals' ColorScheme=Noctalia on every launch path, exactly like the
# source box. The file is kept so the qt6ct GUI/KCM shows the source settings.
cat > "$HOME/.config/qt6ct/qt6ct.conf" <<'QT6CT'
[Appearance]
color_scheme_path=~/.local/share/color-schemes/noctalia.colors
custom_palette=true
icon_theme=breeze
standard_dialogs=default
style=Breeze
QT6CT

# Launcher applet round Arch logo, bundled (no icon-theme dependency).
mkdir -p "$HOME/.local/share/icons"
backup "$HOME/.local/share/icons/arch-round.svg"
cat > "$HOME/.local/share/icons/arch-round.svg" <<'ARCH_ROUND_SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
 <defs>
  <linearGradient id="lG3764" x1="1" x2="47" gradientUnits="userSpaceOnUse" gradientTransform="matrix(0,-1,1,0,0,48)">
   <stop style="stop-color:#1791d1"/>
   <stop offset="1" style="stop-color:#19a0e3"/>
  </linearGradient>
 </defs>
 <g>
  <path d="m 36.31 5 c 5.859 4.062 9.688 10.831 9.688 18.5 c 0 12.426 -10.07 22.5 -22.5 22.5 c -7.669 0 -14.438 -3.828 -18.5 -9.688 c 1.037 1.822 2.306 3.499 3.781 4.969 c 4.085 3.712 9.514 5.969 15.469 5.969 c 12.703 0 23 -10.298 23 -23 c 0 -5.954 -2.256 -11.384 -5.969 -15.469 c -1.469 -1.475 -3.147 -2.744 -4.969 -3.781 z m 4.969 3.781 c 3.854 4.113 6.219 9.637 6.219 15.719 c 0 12.703 -10.297 23 -23 23 c -6.081 0 -11.606 -2.364 -15.719 -6.219 c 4.16 4.144 9.883 6.719 16.219 6.719 c 12.703 0 23 -10.298 23 -23 c 0 -6.335 -2.575 -12.06 -6.719 -16.219 z" style="opacity:0.05"/>
  <path d="m 41.28 8.781 c 3.712 4.085 5.969 9.514 5.969 15.469 c 0 12.703 -10.297 23 -23 23 c -5.954 0 -11.384 -2.256 -15.469 -5.969 c 4.113 3.854 9.637 6.219 15.719 6.219 c 12.703 0 23 -10.298 23 -23 c 0 -6.081 -2.364 -11.606 -6.219 -15.719 z" style="opacity:0.1"/>
  <path d="m 31.25 2.375 c 8.615 3.154 14.75 11.417 14.75 21.13 c 0 12.426 -10.07 22.5 -22.5 22.5 c -9.708 0 -17.971 -6.135 -21.12 -14.75 a 23 23 0 0 0 44.875 -7 a 23 23 0 0 0 -16 -21.875 z" style="opacity:0.2"/>
 </g>
 <g>
  <path d="m 24 1 c 12.703 0 23 10.297 23 23 c 0 12.703 -10.297 23 -23 23 -12.703 0 -23 -10.297 -23 -23 0 -12.703 10.297 -23 23 -23 z" style="fill:url(#lG3764)"/>
 </g>
 <g>
  <g>
   <g transform="translate(1,1)">
    <g style="opacity:0.1">
     <!-- color: #19a0e3 -->
     <g>
      <path d="m 24 10 c -1.07 2.617 -1.715 4.332 -2.902 6.875 c 0.727 0.77 1.621 1.672 3.078 2.688 c -1.566 -0.641 -2.629 -1.289 -3.426 -1.957 c -1.523 3.176 -3.91 7.699 -8.75 16.395 c 3.805 -2.195 6.754 -3.551 9.504 -4.066 c -0.121 -0.508 -0.188 -1.055 -0.184 -1.629 l 0.004 -0.121 c 0.063 -2.438 1.328 -4.313 2.832 -4.184 c 1.5 0.125 2.668 2.207 2.609 4.645 c -0.012 0.457 -0.063 0.898 -0.156 1.309 c 2.719 0.531 5.637 1.887 9.391 4.055 c -0.738 -1.363 -1.402 -2.598 -2.031 -3.766 c -0.992 -0.77 -2.031 -1.77 -4.145 -2.852 c 1.453 0.379 2.492 0.813 3.305 1.301 c -6.414 -11.941 -6.934 -13.523 -9.133 -18.684 m 0.004 0" style="fill:#000"/>
     </g>
    </g>
   </g>
  </g>
 </g>
 <g>
  <g>
   <!-- color: #19a0e3 -->
   <g>
    <path d="m 24 10 c -1.07 2.617 -1.715 4.332 -2.902 6.875 c 0.727 0.77 1.621 1.672 3.078 2.688 c -1.566 -0.641 -2.629 -1.289 -3.426 -1.957 c -1.523 3.176 -3.91 7.699 -8.75 16.395 c 3.805 -2.195 6.754 -3.551 9.504 -4.066 c -0.121 -0.508 -0.188 -1.055 -0.184 -1.629 l 0.004 -0.121 c 0.063 -2.438 1.328 -4.313 2.832 -4.184 c 1.5 0.125 2.668 2.207 2.609 4.645 c -0.012 0.457 -0.063 0.898 -0.156 1.309 c 2.719 0.531 5.637 1.887 9.391 4.055 c -0.738 -1.363 -1.402 -2.598 -2.031 -3.766 c -0.992 -0.77 -2.031 -1.77 -4.145 -2.852 c 1.453 0.379 2.492 0.813 3.305 1.301 c -6.414 -11.941 -6.934 -13.523 -9.133 -18.684 m 0.004 0" style="fill:#f9f9f9"/>
   </g>
  </g>
 </g>
 <g>
  <path d="m 40.03 7.531 c 3.712 4.084 5.969 9.514 5.969 15.469 0 12.703 -10.297 23 -23 23 c -5.954 0 -11.384 -2.256 -15.469 -5.969 4.178 4.291 10.01 6.969 16.469 6.969 c 12.703 0 23 -10.298 23 -23 0 -6.462 -2.677 -12.291 -6.969 -16.469 z" style="opacity:0.1"/>
 </g>
</svg>
ARCH_ROUND_SVG

# Dolphin/Qt font: intentionally NOT pinned. The source box has no font=
# override in qt6ct/kdeglobals/gtk, so Qt resolves fontconfig sans (Noto Sans).
# Icons: breeze-dark, exactly like the source box.
backup "$HOME/.config/kdeglobals"
cat > "$HOME/.config/kdeglobals" <<'KDEGLOBALS'
[Icons]
Theme=breeze-dark

[General]
ColorScheme=noctalia
TerminalApplication=foot
UseSystemBell=true

[KDE]
ShowDeleteCommand=false
contrast=4
KDEGLOBALS

# mpv + mpv-mpris (media player widget): hardware decode + yellow subtitles
# with a black drop shadow.
backup "$HOME/.config/mpv/mpv.conf"
cat > "$HOME/.config/mpv/mpv.conf" <<'MPV'
hwdec=auto
sub-color=#ffff00
sub-shadow-color=#000000
sub-shadow-offset=1
sub-blur=0
MPV

backup "$HOME/.config/dolphinrc"
cat > "$HOME/.config/dolphinrc" <<'DOLPHIN'
[UiSettings]
ColorScheme=noctalia
DOLPHIN

# Write a user portal-backend override that routes ScreenCast/Screenshot to the
# wlr portal and disables Secret/Inhibit, named for the selected WM.
PORTALS_FILE="$HOME/.config/xdg-desktop-portal/${WM}-portals.conf"
backup "$PORTALS_FILE"
cat > "$PORTALS_FILE" <<'PORTALS'
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.Secret=none
org.freedesktop.impl.portal.Inhibit=none
PORTALS

# ------------------------------------------------------------------------------
# greetd (+ noctalia-greeter or agreety fallback)
# ------------------------------------------------------------------------------
say "Configuring greetd as the login manager"

# Provide a dedicated greeter account for graphical greetd greeters (noctalia
# greeter expects one); create it silently if missing.
if ! id greeter >/dev/null 2>&1; then
    sudo useradd --system --shell /usr/sbin/nologin \
        --comment "greetd greeter" --create-home greeter 2>/dev/null || true
fi

if [ -n "$GREETER_SESSION" ]; then
    GREETER_CMD="$GREETER_SESSION"
    GREETER_USER="greeter"
    say "   greeter: $GREETER_SESSION (noctalia-greeter)"
else
    # Arch's greetd-agreety package ships the binary as /usr/bin/agreety; resolve
    # the real path so greetd can exec it (hardcoding the package name broke the
    # first-run boot with "greetd-agreety not found").
    GREETER_BIN="$(command -v agreety || command -v greetd-agreety || echo agreety)"
    GREETER_CMD="$GREETER_BIN --cmd $WM_SESSION_BIN"
    GREETER_USER="greeter"
    say "   greeter: $GREETER_BIN (noctalia-greeter not in your repos) — launching $WM_SESSION_BIN"
fi

sudo install -d /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<GREETD_TMPL
[terminal]
vt = 1

[default_session]
command = "$GREETER_CMD"
user = "$GREETER_USER"
GREETD_TMPL

# seatd: the selected WM (a wlroots compositor) needs compositor seat access;
# enable it and add the user + greeter to the seat group.
sudo systemctl enable --now seatd
sudo usermod -aG seat "$USER"
sudo usermod -aG seat greeter 2>/dev/null || true

# Disable any legacy display manager, enable greetd, and log in graphically.
sudo systemctl disable sddm 2>/dev/null || true
sudo systemctl enable greetd
sudo systemctl set-default graphical.target

# ------------------------------------------------------------------------------
# Services
# ------------------------------------------------------------------------------
say "Enabling services"
sys_enable NetworkManager bluetooth systemd-timesyncd power-profiles-daemon \
           avahi-daemon fstrim.timer

# User services (guarded: may have no session during a bare-metal setup).
usr_enable pipewire.socket pipewire-pulse.socket wireplumber \
           xdg-user-dirs.service

# Optional mirror ranking (uncomment):
# sudo systemctl enable --now reflector.timer

# ------------------------------------------------------------------------------
# UFW: firewall for a desktop workstation
# ------------------------------------------------------------------------------
# Default-deny incoming, allow outgoing. SSH is allowed (22) so remote admin
# over SSH keeps working after the script disables/enables ufw; comment it out
# if this box must not accept any inbound connections at all.
say "Configuring UFW firewall"
sudo systemctl enable ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
say "Setup complete"

if [ "$WM" = "labwc" ]; then
cat <<EOF

  Reboot. greetd (with the Noctalia greeter when available, otherwise the
  plain greetd-agreety) will present the login screen, then start labwc.

  First-run notes:
    - On the first login Noctalia fetches the plugins from git (needs network)
      and regenerates the foot/gtk/qt themes (builtin_ids) from the config.
    - Workspaces: SUPER+1..8 switch, SUPER+SHIFT+1..8 move a window, and the
      bar's 'workspaces' widget shows them.
    - SUPER+w opens the wallhaven plugin to grab a wallpaper once plugins load.
    - SUPER+r reloads the noctalia config and re-reads labwc.
    - Validate noctalia config any time with:  noctalia config validate
    - Edit the window manager with: ~/.config/labwc/rc.xml  (reload: labwc --reconfigure)
    - Your old copies of everything lived in: $HOME_BAK
EOF
else
cat <<EOF

  Reboot. greetd (with the Noctalia greeter when available, otherwise the
  plain greetd-agreety) will present the login screen, then start mango.

  First-run notes:
    - On the first login Noctalia fetches the plugins from git (needs network)
      and generates the foot/gtk/qt themes (builtin_ids).
    - SUPER+w opens the wallhaven plugin to grab a wallpaper once plugins load.
    - SUPER+r reloads the mangowm config after editing files in
      ~/.config/mango/cfg/ and ~/.config/noctalia/config.toml.
    - Validate noctalia config any time with:  noctalia config validate
    - Your old copies of everything lived in: $HOME_BAK
    - AUR was used only for: ${AUR_PACKAGES[*]}
EOF
fi
