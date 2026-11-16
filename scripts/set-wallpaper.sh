#!/bin/sh
# Set the wallpaper and re-theme everything from it.
# Usage: set-wallpaper.sh /path/to/image
#
# 1. ~/.cache/current-wallpaper -> image (hyprlock and the matugen hook read this)
# 2. Shows it with whichever daemon is running: hyprpaper, swww / awww, or swaybg
# 3. Re-themes: ~/.config/matugen/apply.sh if you have one, else `matugen image`
set -e
WP=$(readlink -f "$1")
[ -f "$WP" ] || { echo "no such file: $1" >&2; exit 1; }
ln -sfn "$WP" "$HOME/.cache/current-wallpaper"

if pidof hyprpaper >/dev/null; then
    conf="$HOME/.config/hypr/hyprpaper.conf"          # keep it for the next login
    [ -f "$conf" ] && sed -i "s|^\(\s*path\s*=\s*\).*|\1$WP|" "$conf"
    hyprctl hyprpaper wallpaper ",$WP,cover" >/dev/null 2>&1 || true
elif command -v awww >/dev/null && pidof awww-daemon >/dev/null; then
    awww img "$WP" --transition-type grow
elif command -v swww >/dev/null && pidof swww-daemon >/dev/null; then
    swww img "$WP" --transition-type grow
elif command -v swaybg >/dev/null; then
    pkill -x swaybg 2>/dev/null || true
    setsid -f swaybg -m fill -i "$WP" >/dev/null 2>&1
fi

if [ -x "$HOME/.config/matugen/apply.sh" ]; then
    "$HOME/.config/matugen/apply.sh" "$WP"
elif command -v matugen >/dev/null; then
    matugen image "$WP" -m dark -q
fi
