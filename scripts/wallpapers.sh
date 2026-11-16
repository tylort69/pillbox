#!/bin/bash
# List wallpapers as JSON lines {path, thumb}, making 400px thumbnails on first sight.
# Usage: wallpapers.sh [dir]   (default ~/Pictures/Wallpapers)
DIR="${1:-$HOME/Pictures/Wallpapers}"
CACHE="$HOME/.cache/wallpaper-thumbs"
mkdir -p "$CACHE"
find "$DIR" -maxdepth 2 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) -print0 |
sort -z |
while IFS= read -r -d '' f; do
    key=$(printf '%s' "$f" | sha1sum | cut -c1-16)
    t="$CACHE/$key.jpg"
    if [ ! -s "$t" ] || [ "$f" -nt "$t" ]; then
        magick "$f[0]" -thumbnail '400x250^' -gravity center -extent 400x250 -quality 85 "$t" 2>/dev/null ||
        ffmpeg -loglevel error -y -i "$f" -frames:v 1 -vf 'scale=400:250:force_original_aspect_ratio=increase,crop=400:250' "$t" 2>/dev/null
    fi
    python3 -I -c 'import json,sys; print(json.dumps({"path": sys.argv[1], "thumb": sys.argv[2]}))' "$f" "$t"
done
