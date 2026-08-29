#!/usr/bin/env bash
# ==============================================================================
# dotarch — setup for a vanilla Arch Linux (core+extra) install:
#   Mangowm (mangowm-git, AUR), Noctalia v5, foot, SDDM (archlinux-simplyblack)
#
# Replacements applied vs the CachyOS Mango/Noctalia defaults:
#   - no custom cachyos wallpapers/icons (can't exist here) -> solid color bg
#   - alacritty -> foot everywhere (mango keybind, TERMINAL, kdeglobals, foot template)
#   - adw-gtk-theme (official) provides the adw-gtk3 GTK theme name
#
# AUR is used only for mangowm-git (+ its AUR-only build prerequisites:
# wlroots0.20 provider + scenefx0.5), and for the archlinux-simplyblack sddm
# theme via archlinux-themes-sddm (the theme is not in the official repos).
# Everything else comes from official repos.
#
# Usage:  ./setup.sh   (as your normal user; sudo is requested internally)
# ==============================================================================

set -euo pipefail


HOME_BAK="$HOME/.dotarch-backup-$(date +%Y%m%d%H%M%S)"

# ------------------------------------------------------------------------------
# EDIT ME — application list (official repos only).
# ------------------------------------------------------------------------------
PACKAGES=(
    # -- desktop / wm (official) ---------------------------------------------
    breeze noctalia foot sddm sddm-kcm qt5-declarative

    # -- gpu: intel (change/comment for amd/nvidia) ----------------------------
    mesa vulkan-intel intel-media-driver libva-utils intel-ucode xorg-xwayland

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
    chromium dolphin dolphin-plugins ark ffmpegthumbnailer xdg-user-dirs
    zathura zathura-pdf-mupdf foliate imv micro btop fastfetch
    gnome-disk-utility gnome-system-monitor qbittorrent gnome-keyring
    # firefox

    # -- wayland / clipboard / portals ------------------------------------------
    wl-clipboard wlr-randr xdg-desktop-portal xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk

    # -- power / system tools -----------------------------------------------------
    power-profiles-daemon upower git rsync wget ripgrep unzip unrar p7zip zip
    bash-completion pacman-contrib reflector openssh polkit-kde-agent
)

# AUR-only: mangowm + its build deps (wlroots0.20 provider + scenefx0.5),
# and the simply-black login theme (archlinux-themes-sddm is AUR-only).
AUR_PACKAGES=(
    wlroots0.20-hidpi-xprop   # libwlroots-0.20.so (AUR-only build dep of mangowm-git)
    scenefx0.5                # scenefx 0.5 (AUR-only build dep of mangowm-git)
    mangowm-git               # the WM itself (rolling/development build)
    archlinux-themes-sddm     # archlinux-simplyblack + archlinux-soft-grey sddm themes
    numix-circle-icon-theme-git  # Numix Circle icon theme (dolphin, gtk, qt)
)

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
say()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m== %s ==\033[0m\n' "$*" >&2; exit 1; }

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
# yay (only ever used for mangowm below)
# ------------------------------------------------------------------------------
if ! command -v yay >/dev/null 2>&1; then
    say "Building yay from AUR"
    sudo pacman -S --noconfirm --needed base-devel git
    tmp="$(mktemp -d)"
    git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm --needed)
fi

# ------------------------------------------------------------------------------
# Base packages (official repos)
# ------------------------------------------------------------------------------
say "Installing packages from official repos"
sudo pacman -S --noconfirm --needed "${PACKAGES[@]}"

# ------------------------------------------------------------------------------
# AUR: mangowm-git + simply-black sddm theme
# ------------------------------------------------------------------------------
say "Installing mangowm-git and the sddm theme from AUR"
yay -S --noconfirm --needed "${AUR_PACKAGES[@]}"

# ------------------------------------------------------------------------------
# Configs (with backups of whatever already exists)
# ------------------------------------------------------------------------------
say "Deploying configs (backups in $HOME_BAK)"
mkdir -p "$HOME_BAK" "$HOME/.config/mango/cfg" "$HOME/.config/noctalia" \
         "$HOME/.config/foot" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" \
         "$HOME/.config/qt6ct" "$HOME/.config/xdg-desktop-portal" \
         "$HOME/.config/dolphinrc.d" 2>/dev/null || true

backup() {   # backup <target-file>
    if [ -e "$1" ]; then
        mkdir -p "$HOME_BAK/$(dirname "${1#$HOME/}")"
        cp -a "$1" "$HOME_BAK/${1#$HOME/}"
        rm -rf "$1"
    fi
}

# ---------------- mangowm ----------------
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
env = QT_QPA_PLATFORMTHEME,qt6ct
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

cursor_theme = capitaine-cursors-light
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

# ---------------- noctalia ----------------
backup "$HOME/.config/noctalia/config.toml"
cat > "$HOME/.config/noctalia/config.toml" <<'NOCTALIA'
[bar.default]
background_opacity = 0.89999997988343239
center = [ "workspaces", "Spacer_2", "media", "Spacer_2", "cat", "temp" ]
end = [
    "tray",
    "Spacer_2",
    "notifications",
    "clipboard",
    "recorder",
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
radius_bottom_left = 0
radius_bottom_right = 0
radius_top_left = 0
radius_top_right = 0
start = [ "Spacer", "launcher", "Spacer_2", "active_window" ]
thickness = 40

# Solid color for now (CachyOS wallpaper paths do not exist on plain Arch);
# grab a real wallpaper later with the wallhaven plugin (SUPER+w).
[wallpaper.default]
path = "color:#201b14"

[idle]
behavior_order = [ "lock", "screen-off", "lock-and-suspend" ]

    [idle.behavior.Screen-off]
    action = "command"
    enabled = true
    timeout = 300.0

    [idle.behavior.lock]
    action = "lock"
    enabled = true
    timeout = 600.0

    [idle.behavior.lock-and-suspend]
    action = "suspend"
    enabled = true
    lock_before_suspend = false
    timeout = 900.0

[lockscreen_widgets]
enabled = false
schema_version = 2
widget_order = [ "lockscreen-login-box@DP-2", "lockscreen-login-box@DP-1" ]

    [lockscreen_widgets.grid]
    cell_size = 16
    major_interval = 4
    visible = true

    [lockscreen_widgets.widget."lockscreen-login-box@DP-1"]
    box_height = 70.0
    box_width = 400.0
    cx = 1280.0
    cy = 1321.0
    output = "DP-1"
    rotation = 0.0
    type = "login_box"

        [lockscreen_widgets.widget."lockscreen-login-box@DP-1".settings]
        background_color = "surface_variant"
        background_opacity = 0.88
        background_radius = 12.0
        input_opacity = 1.0
        input_radius = 6.0
        show_caps_lock = true
        show_keyboard_layout = true
        show_login_button = true

    [lockscreen_widgets.widget."lockscreen-login-box@DP-2"]
    box_height = 70.0
    box_width = 400.0
    cx = 1280.0
    cy = 1321.0
    output = "DP-2"
    rotation = 0.0
    type = "login_box"

        [lockscreen_widgets.widget."lockscreen-login-box@DP-2".settings]
        background_color = "surface_variant"
        background_opacity = 0.88
        background_radius = 12.0
        input_opacity = 1.0
        input_radius = 6.0
        show_caps_lock = true
        show_keyboard_layout = true
        show_login_button = true

[plugin_settings."noctalia/screen_recorder"]
restore_portal = false

[plugins]
enabled = [ "noctalia/screen_recorder", "dotnetrob/cat", "noctalia/wallhaven" ]

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

[theme]
builtin = "Noctalia"
mode = "light"
source = "wallpaper"

    [theme.templates]
    builtin_ids = [ "gtk3", "gtk4", "kcolorscheme", "qt", "foot" ]

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

# Launcher applet icon: arch logo from the Numix-Circle theme (same trick the
# source CachyOS box uses with org.cachyos.hello.svg).
[widget.launcher]
custom_image = "/usr/share/icons/Numix-Circle/48/apps/archlinux.svg"
scale = 1.45

[widget.network]
show_label = false

[widget.recorder]
type = "noctalia/screen_recorder:recorder"

[widget.workspaces]
anchor = true
show_labels = false
NOCTALIA

# ---------------- gtk / qt6ct / kde / dolphin / foot / portals ----------------
# foot.ini: Noctalia's "foot" template still owns the colors (it only touches
# ~/.config/foot/themes/noctalia because our include= references it), but foot's
# default terminal font is tiny (8pt), so we pin a readable size here.
backup "$HOME/.config/foot/foot.ini"
cat > "$HOME/.config/foot/foot.ini" <<'FOOT'
[main]
include=~/.config/foot/themes/noctalia
font=monospace:size=12
FOOT

backup "$HOME/.config/gtk-3.0/settings.ini"
cat > "$HOME/.config/gtk-3.0/settings.ini" <<'GTK3'
[Settings]
gtk-theme-name=adw-gtk3
gtk-icon-theme-name=Numix-Circle
gtk-cursor-theme-name=capitaine-cursors-light
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
GTK3

for v in 3.0 4.0; do
    backup "$HOME/.config/gtk-$v/gtk.css"
    printf '@import url("noctalia.css");\n' > "$HOME/.config/gtk-$v/gtk.css"
done

backup "$HOME/.config/qt6ct/qt6ct.conf"
# The rolling AUR noctalia regenerates ~/.local/share/color-schemes/noctalia.colors
# with its own (purple) palette, unlike the CachyOS-built noctalia on the source
# box (tan/orange) that dolphin must match. Ship the SOURCE palette under a
# different filename so noctalia cannot clobber it, and point qt6ct at that.
mkdir -p "$HOME/.local/share/color-schemes"
backup "$HOME/.local/share/color-schemes/noctalia-classic.colors"
cat > "$HOME/.local/share/color-schemes/noctalia-classic.colors" <<'NOCTALIA_CLASSIC'
[KDE]
contrast=4

[General]
ColorScheme=Noctalia
Name=noctalia

[ColorEffects:Disabled]
Color=255,255,255
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=226,226,226
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=243,243,243
BackgroundNormal=232,232,232
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=27,27,27
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[Colors:Complementary]
BackgroundAlternate=243,243,243
BackgroundNormal=249,249,249
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=113,55,0
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[Colors:Header]
BackgroundAlternate=249,249,249
BackgroundNormal=238,238,238
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=27,27,27
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[Colors:Header][Inactive]
BackgroundAlternate=238,238,238
BackgroundNormal=249,249,249
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=27,27,27
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[Colors:Selection]
BackgroundAlternate=243,243,243
BackgroundNormal=148,74,0
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=255,255,255
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=255,218,214
ForegroundNeutral=228,230,174
ForegroundNormal=255,255,255
ForegroundPositive=228,230,174
ForegroundVisited=91,65,47

[Colors:Tooltip]
BackgroundAlternate=249,249,249
BackgroundNormal=238,238,238
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=27,27,27
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[Colors:View]
BackgroundAlternate=238,238,238
BackgroundNormal=249,249,249
DecorationFocus=113,55,0
DecorationHover=255,255,255
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=27,27,27
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[Colors:Window]
BackgroundAlternate=255,220,197
BackgroundNormal=238,238,238
DecorationFocus=148,74,0
DecorationHover=148,74,0
ForegroundActive=148,74,0
ForegroundInactive=71,71,71
ForegroundLink=117,88,69
ForegroundNegative=186,26,26
ForegroundNeutral=95,97,53
ForegroundNormal=27,27,27
ForegroundPositive=95,97,53
ForegroundVisited=91,65,47

[WM]
activeBackground=255,220,197
activeBlend=113,55,0
activeForeground=113,55,0
inactiveBackground=249,249,249
inactiveBlend=71,71,71
inactiveForeground=71,71,71
NOCTALIA_CLASSIC
cat > "$HOME/.config/qt6ct/qt6ct.conf" <<'QT6CT'
[Appearance]
color_scheme_path=~/.local/share/color-schemes/noctalia-classic.colors
custom_palette=true
icon_theme=Numix-Circle
standard_dialogs=default
style=Breeze
QT6CT

# Dolphin/Qt font: intentionally NOT pinned. The source box has no font=
# override in qt6ct/kdeglobals/gtk, so Qt resolves fontconfig sans (Noto Sans)
# for both shell and apps; forcing an explicit face/size here is what kept
# dolphin looking different from the source.
backup "$HOME/.config/kdeglobals"
cat > "$HOME/.config/kdeglobals" <<'KDEGLOBALS'
[General]
ColorScheme=Noctalia
TerminalApplication=foot
UseSystemBell=true

[Icons]
Theme=Numix-Circle
KDEGLOBALS

backup "$HOME/.config/dolphinrc"
cat > "$HOME/.config/dolphinrc" <<'DOLPHIN'
[UiSettings]
ColorScheme=Noctalia
DOLPHIN

# Drop Dolphin's "Set Folder Icon" (Definir icono de carpeta) context-menu
# entry: it's useless with Numix icons and just clutters the right-click menu.
say "Removing the Dolphin 'Set Folder Icon' context-menu plugin"
sudo rm -f "$(command -v dolphin 2>/dev/null >/dev/null && find /usr/lib -name setfoldericonitemaction.so 2>/dev/null | head -1)"

backup "$HOME/.config/xdg-desktop-portal/mango-portals.conf"
cat > "$HOME/.config/xdg-desktop-portal/mango-portals.conf" <<'PORTALS'
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.Secret=gnome-keyring
org.freedesktop.impl.portal.Inhibit=none
PORTALS

# ------------------------------------------------------------------------------
# SDDM + archlinux-simplyblack theme (via AUR archlinux-themes-sddm)
# ------------------------------------------------------------------------------
# The simply-black theme ships only on AUR (archlinux-themes-sddm), which
# installs archlinux-simplyblack + archlinux-soft-grey to /usr/share/sddm/themes.
# qt5-declarative (installed above) provides the QtQuick runtime, since the
# current sddm is Qt6-based while the theme is a Qt5 QML theme.
say "Enabling the archlinux-simplyblack sddm theme"
[ -d /usr/share/sddm/themes/archlinux-simplyblack ] \
    || die "archlinux-simplyblack not found after AUR install"
sudo install -d /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/theme.conf >/dev/null <<'SDDM_THEME'
[Theme]
Current=archlinux-simplyblack
SDDM_THEME

# ------------------------------------------------------------------------------
# Services
# ------------------------------------------------------------------------------
say "Enabling services"
sys_enable NetworkManager bluetooth systemd-timesyncd power-profiles-daemon \
           avahi-daemon fstrim.timer

# SDDM is the login manager — enable it last, just enable, do not start here.
# Boot into graphical.target so SDDM actually greets us on the next start
# (vanilla Arch defaults to multi-user.target = plain TTY login).
sudo systemctl enable sddm
sudo systemctl set-default graphical.target

# User services (guarded: may have no session during a bare-metal setup).
usr_enable pipewire.socket pipewire-pulse.socket wireplumber \
           xdg-user-dirs.service gnome-keyring-daemon.socket

# Optional (uncomment to switch DNS to systemd-resolved):
# sudo pacman -S --noconfirm --needed systemd-resolvconf
# sudo systemctl enable --now systemd-resolved
# sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# printf '[main]\ndns=systemd-resolved\n' | sudo tee /etc/NetworkManager/conf.d/dns.conf

# Optional mirror ranking (uncomment):
# sudo systemctl enable --now reflector.timer

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
say "Setup complete"
cat <<EOF

  Reboot and choose "Mango" (mangowm-git) from the SDDM session menu.

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