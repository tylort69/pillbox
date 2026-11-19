#!/bin/sh
# Start menu "In files" search: prints one match per line as it is found:
#   F<TAB>/abs/path   a file whose contents match
#   L<TAB>/abs/path   a log file whose contents match
#
# usage: search-contents.sh QUERY MODE INDEX SCOPE MAX_MB HIDDEN SYSLOGS EXTS
#   MODE     fuzzy (plain text) | regex
#   INDEX    file list from fd, relative to $HOME (dirs end in /)
#   SCOPE    text (text types from the index) | textlogs (+ every *.log) | all (everything rg can read)
#   MAX_MB   skip files bigger than this; 0 = no limit
#   HIDDEN   1 = also look in hidden folders (only matters for SCOPE=all; the index already reflects it)
#   SYSLOGS  1 = also search the readable files in /var/log
#   EXTS     comma-separated "text" extensions, e.g. txt,md,conf

# Run the search in its own process group, so stopping this script (a new query) also stops
# every rg / fd / xargs it started instead of leaving them running for up to 30 s.
if [ -z "$PILLBOX_SEARCH_CHILD" ]; then
    PILLBOX_SEARCH_CHILD=1 setsid sh "$0" "$@" &
    pid=$!
    trap 'kill -TERM -- "-$pid" 2>/dev/null; exit 0' TERM INT HUP
    wait "$pid"
    exit 0
fi

q=$1 mode=$2 index=$3 scope=$4 max=$5 hidden=$6 syslogs=$7 exts=$8
cd "$HOME" || exit 0

set -- -l -i -m 1 --no-messages
[ "$mode" = regex ] || set -- "$@" -F
[ "${max:-0}" -gt 0 ] 2>/dev/null && set -- "$@" --max-filesize "${max}M"

abs() { sed -u "s|^\./||; s|^\([^/]\)|$HOME/\1|"; }
tag() { sed -u "s|^|$1	|"; }

{
    case $scope in
    all)
        h=; [ "$hidden" = 1 ] && h=--hidden
        timeout --foreground 30 rg "$@" $h -- "$q" . | abs | tag F
        ;;
    *)
        re=$(printf '%s' "$exts" | tr -c 'A-Za-z0-9,_+-' ',' | sed 's/,,*/,/g; s/^,//; s/,$//; s/,/|/g')
        [ -n "$re" ] && grep -i -E "(\.($re)|/(README|LICENSE|Makefile|Dockerfile|PKGBUILD|Justfile)[^/]*|/[^/.]*rc)\$" "$index" |
            timeout --foreground 10 xargs -r -d '\n' rg "$@" -- "$q" | abs | tag F
        ;;
    esac
    # Logs: every *.log / *.log.N in home, hidden folders included (that is where apps keep them)
    if [ "$scope" != text ]; then
        fd -H -I --type f '\.log(\.[0-9]+)?$' . 2>/dev/null |
            timeout --foreground 10 xargs -r -d '\n' rg "$@" -- "$q" | abs | tag L
    fi
    if [ "$syslogs" = 1 ]; then
        timeout --foreground 10 rg "$@" -uu -- "$q" /var/log | tag L
    fi
} | awk -F'\t' '!seen[$2]++ { if ($2 ~ /\.log(\.[0-9]+)?$/ || $2 ~ /^\/var\/log\//) $1 = "L"; print $1 "\t" $2; fflush() }'
