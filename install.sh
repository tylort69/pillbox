#!/usr/bin/env bash
# Pillbox installer (Arch Linux + Hyprland).
#
#   ./install.sh            check dependencies, link the config, hook up matugen
#   ./install.sh --deps     also install missing packages (pacman, plus paru/yay for AUR)
#   ./install.sh --check    only report what is missing
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$CONF/quickshell"
MODE="${1:-}"

bold() { printf '\e[1m%s\e[0m\n' "$*"; }
ok()   { printf '  \e[32m✓\e[0m %s\n' "$*"; }
miss() { printf '  \e[31m✗\e[0m %s\n' "$*"; }
note() { printf '  \e[33m•\e[0m %s\n' "$*"; }

# ── Dependencies ─────────────────────────────────────────────────────────────
# Required: the bar does not start (or looks broken) without these.
REQUIRED=(quickshell hyprland ttf-firacode-nerd python pipewire wireplumber libnotify)

# Optional, by feature: "feature|packages (space separated)|AUR packages"
OPTIONAL=(
  "Colours from wallpaper (Material You)|matugen|"
  "Wallpaper picker thumbnails|imagemagick|"
  "Wallpaper daemon (or swww / awww / swaybg)|hyprpaper|"
  "Package updates panel|pacman-contrib|"
  "Night light|hyprsunset|"
  "Bluetooth panel|bluez bluez-utils|"
  "Wi-Fi in the network panel (systemd-networkd + iwd)|iwd|"
  "Snapshots panel (btrfs)|snapper|"
  "NVIDIA GPU stats|nvidia-utils|"
  "Timer alarm sound|sound-theme-freedesktop pipewire-audio|"
  "Polkit agent (Restart buttons in services panel)|hyprpolkitagent|"
  "Buttons: btop, nvtop, mixers, power menu, file manager|btop nvtop wiremix pavucontrol wlogout yazi|"
  "Clipboard history button|wl-clipboard|clipse"
)

have() { pacman -Q "$1" &>/dev/null; }
MISSING=(); MISSING_AUR=()

bold "Required"
for p in "${REQUIRED[@]}"; do
  if have "$p"; then ok "$p"; else miss "$p"; MISSING+=("$p"); fi
done

bold "Optional (the bar runs without these; only that feature is missing)"
for line in "${OPTIONAL[@]}"; do
  IFS='|' read -r feature pkgs aur <<<"$line"
  lacking=()
  for p in $pkgs; do have "$p" || { lacking+=("$p"); MISSING+=("$p"); }; done
  for p in $aur;  do have "$p" || { lacking+=("$p (AUR)"); MISSING_AUR+=("$p"); }; done
  if ((${#lacking[@]})); then miss "$feature: ${lacking[*]}"; else ok "$feature"; fi
done

if [[ "$MODE" == "--deps" ]]; then
  if ((${#MISSING[@]})); then
    bold "Installing: ${MISSING[*]}"
    sudo pacman -S --needed "${MISSING[@]}"
  fi
  if ((${#MISSING_AUR[@]})); then
    helper="$(command -v paru || command -v yay || true)"
    if [[ -n "$helper" ]]; then "$helper" -S --needed "${MISSING_AUR[@]}"
    else note "No AUR helper (paru / yay) found; skipped: ${MISSING_AUR[*]}"; fi
  fi
elif ((${#MISSING[@]} + ${#MISSING_AUR[@]})); then
  note "Run ./install.sh --deps to install the missing packages."
fi
[[ "$MODE" == "--check" ]] && exit 0

# ── Link the config to ~/.config/quickshell ─────────────────────────────────
bold "Config"
if [[ "$(readlink -f "$TARGET")" == "$HERE" ]]; then
  ok "$TARGET is this folder"
else
  if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    backup="$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$TARGET" "$backup"
    note "Moved your old config to $backup"
  fi
  mkdir -p "$CONF"
  ln -s "$HERE" "$TARGET"
  ok "Linked $TARGET -> $HERE"
fi

# ── matugen: write the bar's colours on every theme change ──────────────────
if command -v matugen &>/dev/null; then
  mcfg="$CONF/matugen/config.toml"
  mkdir -p "$(dirname "$mcfg")"
  if [[ -f "$mcfg" ]] && grep -q 'quickshell-colors.json' "$mcfg"; then
    ok "matugen already writes ~/.cache/quickshell-colors.json"
  else
    [[ -f "$mcfg" ]] || printf '[config]\n' >"$mcfg"
    printf '\n' >>"$mcfg"
    grep -v '^#' "$HERE/matugen/config-snippet.toml" >>"$mcfg"
    ok "Added the quickshell template to $mcfg"
  fi
  note "Pick a wallpaper in the bar (or run: matugen image /path/to/wallpaper) to generate colours."
else
  note "matugen not installed: the bar uses its built-in blue palette."
fi

mkdir -p "$HOME/Pictures/Wallpapers"

# ── Next steps ──────────────────────────────────────────────────────────────
bold "Done. Next:"
cat <<'EOF'
  1. Start it from Hyprland, e.g.
       hyprland.conf:  exec-once = quickshell
       hyprland.lua:   hl.exec_cmd("quickshell")
  2. Stop any other notification daemon (mako, dunst, swaync): the bar is the daemon.
  3. Optional keybinds (classic syntax shown):
       bind = SUPER, slash, exec, qs ipc call cheatsheet toggle
       bind = SUPER, N,     exec, qs ipc call notifs toggle
     Every panel has an IPC target; see README.md.
EOF
