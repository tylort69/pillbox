import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Start menu (the Arch button at the end of the bar; right-click it for the power menu).
//  · Search box: fuzzy or regex (Ctrl+R), over apps and every file/folder in $HOME
//    (fd index in ~/.cache/pillbox, ranked by fzf; regex matches the file name, or the whole
//    path if the pattern has a "/"). Ctrl+F also searches inside files and logs (ripgrep,
//    scripts/search-contents.sh); the gear chip sets which files, a size limit, hidden folders,
//    /var/log and a journal search.
//  · Hotbar: default terminal, file manager and web browser.
//  · Pinned apps / files / folders, plus named groups (right-click anything to pin or group it).
//  · All apps, A–Z.
// Saved in settings.json: startPins, startGroups, startSearchMode, startSearchContents, startSearchOptions.
Scope {
    id: sm
    required property var theme
    required property var settings
    property var panelScreen: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/pillbox"
    // Search options (gear chip): settings.startSearchOptions overrides these defaults
    readonly property string defaultExts: "txt,md,markdown,org,rst,tex,csv,tsv,json,jsonc,toml,yaml,yml,ini,conf,cfg,env,xml,html,htm,css,scss,js,mjs,cjs,ts,tsx,jsx,qml,py,sh,bash,zsh,fish,lua,rs,go,c,h,cc,cpp,hpp,java,kt,rb,php,pl,sql,nix,vim,el,desktop,service,srt"
    readonly property var opts: Object.assign({ scope: "textlogs", maxMB: 10, hidden: false, systemLogs: true, journal: true, exts: defaultExts },
                                              settings.startSearchOptions ?? {})
    function setOpt(k, v) { const o = Object.assign({}, settings.startSearchOptions ?? {}); o[k] = v; settings.startSearchOptions = o }
    property bool optionsOpen: false
    // File-name index; a separate one when hidden folders are included (.git and .cache always skipped)
    readonly property string indexFile: cacheDir + (opts.hidden ? "/files-hidden.txt" : "/files.txt")
    readonly property string fdIndex: opts.hidden ? "fd -H --exclude .git --exclude .cache . --type f --type d" : "fd . --type f --type d"

    property string query: ""
    readonly property string mode: settings.startSearchMode === "regex" ? "regex" : "fuzzy"
    readonly property bool contents: settings.startSearchContents === true
    property var fileHits: []          // [{ kind: "path", path, dir }]
    property var contentHits: []
    property var logHits: []
    property bool searchingFiles: false
    property bool searchingContents: false
    property int sel: 0
    property var ctx: null             // context menu: { x, y, item, where }  where = "list" | "pins" | group index
    property int renaming: -1          // group whose name is being edited
    property double ctxClosedAt: 0
    onCtxChanged: if (ctx === null) ctxClosedAt = Date.now()
    // True while the context menu is open or was just closed: a click then only dismisses the menu,
    // so pinning and grouping items never launches them
    function menuBusy() { return ctx !== null || optionsOpen || Date.now() - ctxClosedAt < 400 }
    function tapOpen(it) { if (!menuBusy()) open(it) }

    function togglePanel(screen) {
        panelScreen = (panelScreen === screen) ? null : screen
        if (panelScreen !== null) { search.text = ""; query = ""; optionsOpen = false; sel = 0; ctx = null; renaming = -1; refreshIndex(); defaultsProc.running = true }
    }
    function close() { panelScreen = null }
    onPanelScreenChanged: if (panelScreen === null) { contentProc.pending = false; contentProc.running = false }

    // ── Apps ─────────────────────────────────────────────────────────────────
    readonly property var apps: {
        const seen = {}
        return DesktopEntries.applications.values
            .filter(a => !a.noDisplay && !seen[a.id] && (seen[a.id] = true))
            .sort((a, b) => a.name.localeCompare(b.name))
    }
    function entry(id) { return DesktopEntries.byId(id) }

    // Subsequence match with bonuses for runs and word starts; -1 = no match
    function fuzzy(q, s) {
        if (!s) return -1
        s = s.toLowerCase()
        const at = s.indexOf(q)
        if (at >= 0) return 1000 + (at === 0 ? 300 : 0) - at * 4 - (s.length - q.length)
        let score = 0, j = 0, last = -2, first = -1
        for (let i = 0; i < s.length && j < q.length; i++) {
            if (s[i] !== q[j]) continue
            if (first < 0) first = i
            score += (i === last + 1) ? 16 : 4
            if (i === 0 || " -_./".includes(s[i - 1])) score += 12
            last = i; j++
        }
        return j === q.length ? score - (last - first) : -1
    }
    readonly property var regex: {
        if (mode !== "regex" || !query) return null
        try { return new RegExp(query, "i") } catch (e) { return undefined }
    }
    readonly property var appHits: {
        const q = query.trim().toLowerCase()
        if (!q) return []
        const out = []
        for (const a of apps) {
            let s = -1
            if (mode === "regex") {
                if (!regex) break
                const m = regex.exec(a.name)
                s = m ? 1000 - m.index : [a.genericName, a.id, a.keywords.join(" "), a.comment].some(t => t && regex.test(t)) ? 100 : -1
            } else {
                s = Math.max(fuzzy(q, a.name), fuzzy(q, a.genericName) * 0.7, fuzzy(q, a.id) * 0.6,
                             a.keywords.reduce((m, k) => Math.max(m, fuzzy(q, k) * 0.5), -1),
                             a.comment && a.comment.toLowerCase().includes(q) ? 50 : -1)
            }
            if (s >= 0) out.push({ s: s, a: a })
        }
        return out.sort((x, y) => y.s - x.s).slice(0, 8).map(h => ({ kind: "app", id: h.a.id }))
    }
    // Flat list for the results view; headers are skipped by keyboard selection
    readonly property var results: {
        let r = []
        if (appHits.length) r = r.concat([{ kind: "header", text: "Apps" }], appHits)
        // With "In files" on, keep file-name hits short so content and log matches stay in view
        if (fileHits.length) r = r.concat([{ kind: "header", text: "Files and folders" }], fileHits.slice(0, contents ? 12 : 40))
        if (contents && contentHits.length) r = r.concat([{ kind: "header", text: "Inside files" }], contentHits)
        const logs = contents ? logHits.concat(journalItem ? [journalItem] : []) : []
        if (logs.length) r = r.concat([{ kind: "header", text: "In logs" }], logs)
        return r
    }
    onResultsChanged: fixSel()
    function fixSel() { if (sel < 0 || sel >= results.length || results[sel].kind === "header") sel = firstSelectable(0, 1) }
    function firstSelectable(from, step) {
        for (let i = from; i >= 0 && i < results.length; i += step) if (results[i].kind !== "header") return i
        return -1
    }
    function moveSel(step) {
        const n = firstSelectable(sel + step, step)
        if (n >= 0) sel = n
    }

    // "Search the journal" result (opens journalctl --grep in a terminal)
    readonly property var journalItem: opts.journal && contents && query.trim().length >= 3 ? { kind: "journal", text: query.trim() } : null
    function openJournal(q) {
        const pat = mode === "regex" ? q : q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        Quickshell.execDetached(theme.term("journal-search", "Journal: " + q, ["sh", "-c",
            'journalctl --grep "$1" --case-sensitive=false -r -o short-iso --no-pager 2>&1 | less -R', "sh", pat]))
    }

    // ── Items: { kind: "app", id } or { kind: "path", path, dir } ────────────
    function same(a, b) { return a.kind === b.kind && (a.kind === "app" ? a.id === b.id : a.path === b.path) }
    function clean(it) { return it.kind === "app" ? { kind: "app", id: it.id } : { kind: "path", path: it.path, dir: !!it.dir } }
    function baseName(p) { const t = p.replace(/\/+$/, ""); return t.slice(t.lastIndexOf("/") + 1) || "/" }
    function tilde(p) { return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p }
    function name(it) {
        if (it.kind === "journal") return "Search the system journal for “" + it.text + "”"
        if (it.kind === "app") { const e = entry(it.id); return e ? e.name : it.id }
        return baseName(it.path)
    }
    function subtitle(it) {
        if (it.kind === "journal") return "journalctl --grep, newest first"
        if (it.kind === "app") { const e = entry(it.id); return e ? (e.genericName || e.comment || "") : "Not installed" }
        return tilde(it.path.replace(/\/[^/]*\/?$/, "")) || "/"
    }
    readonly property var extIcons: ({
        png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic", gif: "image-x-generic", webp: "image-x-generic", svg: "image-x-generic",
        mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic", mov: "video-x-generic", avi: "video-x-generic",
        mp3: "audio-x-generic", flac: "audio-x-generic", ogg: "audio-x-generic", wav: "audio-x-generic", m4a: "audio-x-generic", opus: "audio-x-generic",
        pdf: "application-pdf", zip: "package-x-generic", tar: "package-x-generic", gz: "package-x-generic", xz: "package-x-generic",
        zst: "package-x-generic", "7z": "package-x-generic", rar: "package-x-generic",
        sh: "text-x-script", fish: "text-x-script", py: "text-x-script", js: "text-x-script", ts: "text-x-script", qml: "text-x-script",
        lua: "text-x-script", rs: "text-x-script", c: "text-x-script", cpp: "text-x-script", h: "text-x-script", go: "text-x-script",
        json: "text-x-script", toml: "text-x-script", yaml: "text-x-script", yml: "text-x-script", conf: "text-x-script", ini: "text-x-script",
        desktop: "application-x-desktop", iso: "media-optical", html: "text-html"
    })
    function icon(it) {
        if (it.kind === "journal") return Quickshell.iconPath("utilities-system-monitor", "text-x-generic")
        if (it.kind === "app") { const e = entry(it.id); return e ? Quickshell.iconPath(e.icon, "application-x-executable") : "" }
        if (it.dir) return Quickshell.iconPath(it.path === home || it.path === home + "/" ? "user-home" : "folder", "folder")
        const dot = it.path.lastIndexOf(".")
        return Quickshell.iconPath((dot > it.path.lastIndexOf("/") && extIcons[it.path.slice(dot + 1).toLowerCase()]) || "text-x-generic", "text-x-generic")
    }
    function glyph(it) { return it.kind === "journal" ? "󰌱" : it.kind === "app" ? "󰀻" : it.dir ? "󰉋" : "󰈔" }

    // ── Launching ────────────────────────────────────────────────────────────
    function launchEntry(e, args) {
        if (!e) return
        const cmd = (e.command ?? []).concat(args ?? [])
        const wrap = argv => ["sh", "-c", 'cd "$1" 2>/dev/null || cd; shift; exec "$@"', "sh", e.workingDirectory || home].concat(argv)
        if (e.runInTerminal) Quickshell.execDetached(wrap(theme.term(e.id, e.name, cmd)))
        else if (args && args.length) Quickshell.execDetached(wrap(cmd))
        else e.execute()
    }
    function open(it) {
        if (!it || it.kind === "header") return
        if (it.kind === "journal") openJournal(it.text)
        else if (it.kind === "app") launchEntry(entry(it.id))
        else if (it.dir && fileManager) launchEntry(fileManager, [it.path])
        else { openProc.target = it.path; openProc.running = true }
        close()
    }
    function openFolderOf(it) { open({ kind: "path", dir: true, path: it.path.replace(/\/[^/]*\/?$/, "") || "/" }) }
    // Files: default app from xdg-mime, so terminal apps (nvim, yazi…) still open in a terminal
    Process {
        id: openProc
        property string target: ""
        command: ["sh", "-c", 'xdg-mime query default "$(xdg-mime query filetype "$1")"', "sh", target]
        stdout: StdioCollector {
            onStreamFinished: {
                const e = sm.entry(text.trim().replace(/\.desktop$/, ""))
                if (e) sm.launchEntry(e, [openProc.target])
                else Quickshell.execDetached(["xdg-open", openProc.target])
            }
        }
    }

    // ── Hotbar: default terminal, file manager, browser ──────────────────────
    property var fileManager: null
    property var browser: null
    readonly property var terminalEntry: DesktopEntries.heuristicLookup(theme.terminal.split("/").pop())
    Process {
        id: defaultsProc
        running: true
        command: ["sh", "-c", "xdg-mime query default inode/directory; xdg-settings get default-web-browser 2>/dev/null || xdg-mime query default x-scheme-handler/https"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").map(s => s.trim().replace(/\.desktop$/, ""))
                sm.fileManager = l[0] ? sm.entry(l[0]) : null
                sm.browser = l[1] ? sm.entry(l[1]) : null
            }
        }
    }
    readonly property var hotbar: [
        { label: "Terminal", e: terminalEntry, run: () => Quickshell.execDetached(["sh", "-c", 'cd; exec "$@"', "sh", theme.terminal]) },
        { label: "Files",    e: fileManager,   run: () => fileManager ? launchEntry(fileManager, [home]) : Quickshell.execDetached(["xdg-open", home]) },
        { label: "Browser",  e: browser,       run: () => browser ? launchEntry(browser) : Quickshell.execDetached(["xdg-open", "about:blank"]) }
    ]

    // ── File search (fd index + fzf / grep) and content search (ripgrep) ─────
    Process {
        id: indexProc
        command: ["sh", "-c", 'f="$1"; [ -n "$(find "$f" -mmin -10 2>/dev/null)" ] && exit 0; mkdir -p "${f%/*}"; cd && $2 > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"', "sh", sm.indexFile, sm.fdIndex]
    }
    function refreshIndex() { if (!indexProc.running) indexProc.running = true }

    function restart(proc) {
        if (proc.running) { proc.pending = true; proc.running = false } else { proc.forQuery = sm.query; proc.running = true }
    }
    function pathHits(text, max) {
        return text.split("\n").filter(l => l).slice(0, max).map(l => ({ kind: "path", dir: l.endsWith("/"), path: sm.home + "/" + l.replace(/\/$/, "") }))
    }
    Timer {
        id: searchDelay
        interval: 120
        onTriggered: {
            if (!sm.query.trim()) return
            sm.searchingFiles = true
            sm.restart(fileProc)
            if (sm.contents && sm.query.trim().length >= 3) { sm.searchingContents = true; contentDelay.restart() }
        }
    }
    Timer { id: contentDelay; interval: 250; onTriggered: { sm.contentHits = []; sm.logHits = []; sm.restart(contentProc) } }
    onQueryChanged: { sel = 0; fixSel(); ctx = null; if (!query.trim()) { fileHits = []; contentHits = []; logHits = []; contentProc.pending = false; contentProc.running = false } searchDelay.restart() }
    onOptsChanged: { refreshIndex(); searchDelay.restart() }
    onModeChanged: searchDelay.restart()
    onContentsChanged: searchDelay.restart()

    Process {
        id: fileProc
        property string forQuery: ""
        property bool pending: false
        command: ["sh", "-c",
            'q="$1" f="$2"; cd; [ -s "$f" ] || { mkdir -p "${f%/*}"; $5 > "$f"; }; ' +
            'if [ "$3" = regex ]; then python3 -I "$4" "$q" "$f" 40; ' +
            'else fzf --filter "$q" --scheme=path < "$f" | head -n 40; fi',
            "sh", sm.query.trim(), sm.indexFile, sm.mode, Quickshell.shellDir + "/scripts/regex-files.py", sm.fdIndex]
        onRunningChanged: if (!running && pending) { pending = false; forQuery = sm.query; running = true }
        stdout: StdioCollector {
            onStreamFinished: if (!fileProc.pending && fileProc.forQuery === sm.query) { sm.fileHits = sm.pathHits(text, 40); sm.searchingFiles = false }
        }
    }
    // Streams matches as they are found (scripts/search-contents.sh); "All files" can take a while
    Process {
        id: contentProc
        property string forQuery: ""
        property bool pending: false
        command: ["sh", Quickshell.shellDir + "/scripts/search-contents.sh", sm.query.trim(), sm.mode, sm.indexFile,
                  sm.opts.scope, String(sm.opts.maxMB), sm.opts.hidden ? "1" : "0", sm.opts.systemLogs ? "1" : "0", sm.opts.exts]
        onRunningChanged: {
            if (!running && pending) { pending = false; forQuery = sm.query; running = true }
            else if (!running) sm.searchingContents = false
        }
        stdout: SplitParser {
            onRead: (line) => {
                if (contentProc.pending || contentProc.forQuery !== sm.query) return
                const tab = line.indexOf("\t")
                if (tab < 0) return
                const it = { kind: "path", dir: false, path: line.slice(tab + 1) }
                if (line.startsWith("L")) { if (sm.logHits.length < 30) sm.logHits = sm.logHits.concat([it]) }
                else if (sm.contentHits.length < 30) sm.contentHits = sm.contentHits.concat([it])
            }
        }
    }

    // ── Pins and groups ──────────────────────────────────────────────────────
    readonly property var pins: settings.startPins ?? []
    readonly property var groups: settings.startGroups ?? []
    function copyGroups() { return JSON.parse(JSON.stringify(groups)) }
    function isPinned(it) { return pins.some(p => same(p, it)) }
    function pin(it) { if (!isPinned(it)) settings.startPins = pins.concat([clean(it)]) }
    function unpin(it) { settings.startPins = pins.filter(p => !same(p, it)) }
    function newGroup(it) {
        const g = copyGroups()
        g.push({ name: "New group", items: it ? [clean(it)] : [] })
        settings.startGroups = g
        renaming = g.length - 1
    }
    function addToGroup(gi, it) {
        const g = copyGroups()
        if (!g[gi].items.some(x => same(x, it))) g[gi].items.push(clean(it))
        settings.startGroups = g
    }
    function removeFromGroup(gi, it) {
        const g = copyGroups()
        g[gi].items = g[gi].items.filter(x => !same(x, it))
        settings.startGroups = g
    }
    function renameGroup(gi, n) { const g = copyGroups(); g[gi].name = n.trim() || "Group"; settings.startGroups = g }
    function deleteGroup(gi) { const g = copyGroups(); g.splice(gi, 1); settings.startGroups = g }
    function moveGroup(gi, d) {
        const g = copyGroups(), j = gi + d
        if (j < 0 || j >= g.length) return
        const t = g[gi]; g[gi] = g[j]; g[j] = t
        settings.startGroups = g
    }
    // Move an item one step within pins (where = "pins") or a group (where = index)
    function shift(where, it, d) {
        const list = where === "pins" ? pins.slice() : copyGroups()[where].items
        const i = list.findIndex(x => same(x, it)), j = i + d
        if (i < 0 || j < 0 || j >= list.length) return
        const t = list[i]; list[i] = list[j]; list[j] = t
        if (where === "pins") settings.startPins = list
        else { const g = copyGroups(); g[where].items = list; settings.startGroups = g }
    }
    function removeFrom(where, it) { if (where === "pins") unpin(it); else removeFromGroup(where, it) }
    function moveTo(where, dest, it) {
        if (dest === "pins") pin(it); else if (dest === "new") newGroup(it); else addToGroup(dest, it)
        removeFrom(where, it)
    }

    // Context menu entries for the item under ctx
    function ctxOptions() {
        if (!ctx) return []
        const it = ctx.item, w = ctx.where, o = []
        if (it.kind === "journal") return [{ text: "Open", icon: "󰏌", run: () => open(it) }]
        o.push({ text: it.kind === "app" ? "Open" : it.dir ? "Open folder" : "Open", icon: "󰏌", run: () => open(it) })
        if (it.kind === "path" && !it.dir) o.push({ text: "Open containing folder", icon: "󰉋", run: () => openFolderOf(it) })
        if (it.kind === "app") {
            const e = entry(it.id)
            for (const a of (e?.actions ?? [])) o.push({ text: a.name, icon: "󰁔", run: () => { a.execute(); close() } })
        }
        if (w === "list") {
            if (!isPinned(it)) o.push({ text: "Pin to Start", icon: "󰐃", run: () => pin(it) })
            else o.push({ text: "Unpin", icon: "󰐄", run: () => unpin(it) })
            groups.forEach((g, gi) => { if (!g.items.some(x => same(x, it))) o.push({ text: "Add to “" + g.name + "”", icon: "󰉖", run: () => addToGroup(gi, it) }) })
            o.push({ text: "Add to a new group", icon: "󰉗", run: () => newGroup(it) })
        } else {
            o.push({ text: "Move earlier", icon: theme.vertical ? "󰁝" : "󰁍", run: () => shift(w, it, -1) })
            o.push({ text: "Move later", icon: theme.vertical ? "󰁅" : "󰁔", run: () => shift(w, it, 1) })
            if (w !== "pins") o.push({ text: "Move to Pinned", icon: "󰐃", run: () => moveTo(w, "pins", it) })
            groups.forEach((g, gi) => { if (gi !== w) o.push({ text: "Move to “" + g.name + "”", icon: "󰉖", run: () => moveTo(w, gi, it) }) })
            o.push({ text: "Move to a new group", icon: "󰉗", run: () => moveTo(w, "new", it) })
            o.push({ text: w === "pins" ? "Unpin" : "Remove from group", icon: "󰆴", danger: true, run: () => removeFrom(w, it) })
        }
        return o
    }

    IpcHandler {
        target: "start"
        function toggle(): void { sm.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        // Pin an app (desktop id, e.g. "firefox") or an absolute path; group = "" pins to the top area
        function pin(target: string, group: string): void {
            const it = target.startsWith("/") ? { kind: "path", path: target.replace(/\/+$/, "") || "/", dir: target.endsWith("/") }
                                              : { kind: "app", id: target.replace(/\.desktop$/, "") }
            if (!group) { sm.pin(it); return }
            let gi = sm.groups.findIndex(g => g.name === group)
            if (gi < 0) { sm.newGroup(it); sm.renameGroup(sm.groups.length - 1, group); sm.renaming = -1 }
            else sm.addToGroup(gi, it)
        }
    }

    HyprlandFocusGrab {
        active: smPanel.visible
        windows: [smPanel].concat(theme.barWindows)
        onCleared: sm.close()
    }

    // ── Panel ────────────────────────────────────────────────────────────────
    PanelWindow {
        id: smPanel
        screen: sm.panelScreen ?? Quickshell.screens[0]
        visible: sm.panelScreen !== null
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 780
        implicitHeight: Math.min(640, (screen?.height ?? 1080) - 120)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-start"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible) search.forceActiveFocus()

        // Reusable icon: theme icon, or a Nerd Font glyph if the theme has none
        component ItemIcon: Item {
            property var item
            property int size: 24
            implicitWidth: size; implicitHeight: size
            Image {
                id: img
                anchors.fill: parent
                source: parent.item ? sm.icon(parent.item) : ""
                sourceSize: Qt.size(parent.size * 2, parent.size * 2)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
            Text {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: parent.item ? sm.glyph(parent.item) : ""
                font.family: theme.fontFamily; font.pixelSize: parent.size * 0.8
                color: theme.clrFgMuted
            }
        }
        // Small round icon button
        component IconButton: Rectangle {
            property string glyph
            property color tint: theme.clrFg
            signal clicked()
            implicitWidth: 28; implicitHeight: 28; radius: 14
            color: ibHover.hovered ? Qt.alpha(theme.clrFg, 0.1) : "transparent"
            Text { anchors.centerIn: parent; text: parent.glyph; font.family: theme.fontFamily; font.pixelSize: 15; color: parent.tint }
            HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: parent.clicked() }
        }
        // Tile for pinned items and groups
        component Tile: Rectangle {
            id: tile
            property var item
            property var where
            implicitWidth: 84; implicitHeight: 84; radius: 18
            color: tileHover.hovered ? theme.clrBgAlt : "transparent"
            ColumnLayout {
                anchors { fill: parent; margins: 6 }
                spacing: 4
                ItemIcon { Layout.alignment: Qt.AlignHCenter; item: tile.item; size: 34 }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: sm.name(tile.item)
                    elide: Text.ElideRight
                    font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFg
                }
            }
            HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { acceptedButtons: Qt.LeftButton; onTapped: sm.tapOpen(tile.item) }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (ev) => { const p = tile.mapToItem(panelBg, ev.position.x, ev.position.y); sm.ctx = { x: p.x, y: p.y, item: tile.item, where: tile.where } }
            }
        }

        Rectangle {
            id: panelBg
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                // ── Search ───────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48; radius: 24
                    color: theme.clrBgAlt
                    border.width: search.activeFocus ? 2 : 0
                    border.color: theme.clrAccent
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 8 }
                        spacing: 10
                        Text { text: "󰍉"; font.family: theme.fontFamily; font.pixelSize: 18; color: theme.clrFgMuted }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            onTextChanged: sm.query = text
                            font.family: theme.fontFamily; font.pixelSize: 14
                            color: theme.clrFg
                            selectionColor: theme.clrAccent
                            selectedTextColor: theme.clrOnAccent
                            clip: true
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !search.text
                                text: sm.mode === "regex" ? "Regex search: apps and files in your home…" : "Search apps, files and folders…"
                                font: search.font; color: theme.clrFgMuted
                            }
                            Keys.onPressed: (ev) => {
                                if (ev.key === Qt.Key_Escape) { if (sm.ctx) sm.ctx = null; else if (sm.optionsOpen) sm.optionsOpen = false; else if (search.text) search.text = ""; else sm.close() }
                                else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) sm.moveSel(1)
                                else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) sm.moveSel(-1)
                                else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) sm.open(sm.results[sm.sel])
                                else if (ev.key === Qt.Key_R && (ev.modifiers & Qt.ControlModifier)) sm.settings.startSearchMode = sm.mode === "regex" ? "fuzzy" : "regex"
                                else if (ev.key === Qt.Key_F && (ev.modifiers & Qt.ControlModifier)) sm.settings.startSearchContents = !sm.contents
                                else if (ev.key === Qt.Key_O && (ev.modifiers & Qt.ControlModifier)) { sm.ctx = null; sm.optionsOpen = !sm.optionsOpen }
                                else return
                                ev.accepted = true
                            }
                        }
                        // Mode chips
                        Repeater {
                            model: [
                                { label: sm.mode === "regex" ? "Regex" : "Fuzzy", icon: sm.mode === "regex" ? "󰑑" : "󰈲", on: sm.mode === "regex",
                                  tip: "Ctrl+R", run: () => sm.settings.startSearchMode = sm.mode === "regex" ? "fuzzy" : "regex" },
                                { label: "In files", icon: "󰈞", on: sm.contents, tip: "Ctrl+F", run: () => sm.settings.startSearchContents = !sm.contents },
                                { label: "", icon: "󰒓", on: sm.optionsOpen, tip: "Ctrl+O", run: () => { sm.ctx = null; sm.optionsOpen = !sm.optionsOpen } }
                            ]
                            Rectangle {
                                required property var modelData
                                implicitWidth: chipRow.implicitWidth + 20; implicitHeight: 32; radius: 16
                                color: modelData.on ? theme.clrAccentC : chipHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                                border.width: modelData.on ? 0 : 1
                                border.color: theme.clrBorder
                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: modelData.icon; font.family: theme.fontFamily; font.pixelSize: 13; color: modelData.on ? theme.clrOnAccentC : theme.clrFg }
                                    Text { visible: modelData.label !== ""; text: modelData.label; font.family: theme.fontFamily; font.pixelSize: 11; color: modelData.on ? theme.clrOnAccentC : theme.clrFg }
                                }
                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { modelData.run(); search.forceActiveFocus() } }
                            }
                        }
                    }
                }

                // ── Search results ───────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: sm.query.trim() !== ""

                    ListView {
                        id: resultList
                        anchors.fill: parent
                        clip: true
                        model: sm.results
                        currentIndex: sm.sel
                        highlightFollowsCurrentItem: false
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool header: modelData.kind === "header"
                            width: resultList.width
                            height: header ? 30 : 48
                            Text {
                                visible: row.header
                                anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
                                text: row.header ? row.modelData.text : ""
                                font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent
                            }
                            Rectangle {
                                visible: !row.header
                                anchors.fill: parent
                                radius: 16
                                color: sm.sel === row.index ? theme.clrAccentC : resHover.hovered ? theme.clrBgAlt : "transparent"
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 12
                                    ItemIcon { item: row.header ? null : row.modelData; size: 28 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.header ? "" : sm.name(row.modelData)
                                            elide: Text.ElideRight
                                            font.family: theme.fontFamily; font.pixelSize: 13
                                            color: sm.sel === row.index ? theme.clrOnAccentC : theme.clrFg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: row.header ? "" : sm.subtitle(row.modelData)
                                            visible: text !== ""
                                            elide: Text.ElideMiddle
                                            font.family: theme.fontFamily; font.pixelSize: 10
                                            color: sm.sel === row.index ? Qt.alpha(theme.clrOnAccentC, 0.8) : theme.clrFgMuted
                                        }
                                    }
                                    Text {
                                        visible: !row.header && sm.isPinned(row.modelData)
                                        text: "󰐃"; font.family: theme.fontFamily; font.pixelSize: 13
                                        color: sm.sel === row.index ? theme.clrOnAccentC : theme.clrFgMuted
                                    }
                                }
                                HoverHandler { id: resHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { acceptedButtons: Qt.LeftButton; onTapped: sm.tapOpen(row.modelData) }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: (ev) => {
                                        sm.sel = row.index
                                        const p = row.mapToItem(panelBg, ev.position.x, ev.position.y)
                                        sm.ctx = { x: p.x, y: p.y, item: row.modelData, where: "list" }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: sm.results.length === 0
                        text: sm.regex === undefined ? "That isn't a valid regular expression"
                            : (sm.searchingFiles || sm.searchingContents) ? "Searching…" : "Nothing found"
                        font.family: theme.fontFamily; font.pixelSize: 13; color: theme.clrFgMuted
                    }
                }

                // ── Home view: all apps | hotbar, pins, groups ───────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: sm.query.trim() === ""
                    spacing: 14

                    // All apps
                    Rectangle {
                        Layout.preferredWidth: 270
                        Layout.fillHeight: true
                        radius: 20
                        color: Qt.alpha(theme.clrBgAlt, 0.5)
                        ColumnLayout {
                            anchors { fill: parent; margins: 8 }
                            spacing: 4
                            Text {
                                Layout.leftMargin: 8; Layout.topMargin: 4
                                text: "All apps  ·  " + sm.apps.length
                                font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent
                            }
                            ListView {
                                id: appList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: sm.apps
                                section.property: "name"
                                section.criteria: ViewSection.FirstCharacter
                                section.delegate: Text {
                                    required property string section
                                    width: appList.width
                                    leftPadding: 10; topPadding: 6; bottomPadding: 2
                                    text: section.toUpperCase()
                                    font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true; color: theme.clrFgMuted
                                }
                                delegate: Rectangle {
                                    id: appRow
                                    required property var modelData
                                    readonly property var item: ({ kind: "app", id: modelData.id })
                                    width: appList.width
                                    height: 38; radius: 14
                                    color: appHover.hovered ? theme.clrBgAlt : "transparent"
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                        spacing: 10
                                        ItemIcon { item: appRow.item; size: 24 }
                                        Text {
                                            Layout.fillWidth: true
                                            text: appRow.modelData.name
                                            elide: Text.ElideRight
                                            font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFg
                                        }
                                    }
                                    HoverHandler { id: appHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: sm.tapOpen(appRow.item) }
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: (ev) => { const p = appRow.mapToItem(panelBg, ev.position.x, ev.position.y); sm.ctx = { x: p.x, y: p.y, item: appRow.item, where: "list" } }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        // Hotbar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: sm.hotbar
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 64; radius: 20
                                    color: hotHover.hovered ? theme.clrAccentC : theme.clrBgAlt
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                                        spacing: 10
                                        ItemIcon { item: modelData.e ? { kind: "app", id: modelData.e.id } : null; size: 32 }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: modelData.label
                                                font.family: theme.fontFamily; font.pixelSize: 13; font.bold: true
                                                color: hotHover.hovered ? theme.clrOnAccentC : theme.clrFg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.e ? modelData.e.name : "Default"
                                                elide: Text.ElideRight
                                                font.family: theme.fontFamily; font.pixelSize: 10
                                                color: hotHover.hovered ? theme.clrOnAccentC : theme.clrFgMuted
                                            }
                                        }
                                    }
                                    HoverHandler { id: hotHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: if (!sm.menuBusy()) { modelData.run(); sm.close() } }
                                }
                            }
                        }

                        // Pinned + groups
                        Flickable {
                            id: pinFlick
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: pinCol.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            ColumnLayout {
                                id: pinCol
                                width: pinFlick.width
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Pinned"
                                        font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: sm.pins
                                        Tile { required property var modelData; item: modelData; where: "pins" }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: sm.pins.length === 0
                                    wrapMode: Text.Wrap
                                    text: "Right-click an app, file or folder (in All apps or in search results) to pin it here or add it to a group."
                                    font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                                }

                                // Groups
                                Repeater {
                                    model: sm.groups
                                    ColumnLayout {
                                        id: grp
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.topMargin: 6
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Item {
                                                Layout.fillWidth: true
                                                implicitHeight: 28
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: sm.renaming !== grp.index
                                                    text: grp.modelData.name
                                                    font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent
                                                    TapHandler { onDoubleTapped: sm.renaming = grp.index }
                                                }
                                                Rectangle {
                                                    visible: sm.renaming === grp.index
                                                    anchors.fill: parent
                                                    radius: 10
                                                    color: theme.clrBgAlt
                                                    border.width: 2; border.color: theme.clrAccent
                                                    TextInput {
                                                        id: nameEdit
                                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true
                                                        color: theme.clrFg
                                                        selectByMouse: true
                                                        onVisibleChanged: if (visible) { text = grp.modelData.name; selectAll(); forceActiveFocus() }
                                                        function done() { if (sm.renaming === grp.index) { sm.renameGroup(grp.index, text); sm.renaming = -1; search.forceActiveFocus() } }
                                                        Keys.onReturnPressed: done()
                                                        Keys.onEnterPressed: done()
                                                        Keys.onEscapePressed: { sm.renaming = -1; search.forceActiveFocus() }
                                                        onActiveFocusChanged: if (!activeFocus) done()
                                                    }
                                                }
                                            }
                                            IconButton { glyph: "󰏫"; tint: theme.clrFgMuted; onClicked: sm.renaming = grp.index }
                                            IconButton { glyph: "󰁝"; tint: theme.clrFgMuted; visible: grp.index > 0; onClicked: sm.moveGroup(grp.index, -1) }
                                            IconButton { glyph: "󰁅"; tint: theme.clrFgMuted; visible: grp.index < sm.groups.length - 1; onClicked: sm.moveGroup(grp.index, 1) }
                                            IconButton { glyph: "󰅖"; tint: theme.clrUrgent; onClicked: sm.deleteGroup(grp.index) }
                                        }
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Repeater {
                                                model: grp.modelData.items
                                                Tile { required property var modelData; item: modelData; where: grp.index }
                                            }
                                        }
                                        Text {
                                            visible: grp.modelData.items.length === 0
                                            text: "Empty: right-click something and choose Add to “" + grp.modelData.name + "”"
                                            font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                                        }
                                    }
                                }

                                // New group
                                Rectangle {
                                    Layout.topMargin: 6
                                    implicitWidth: ngRow.implicitWidth + 24; implicitHeight: 34; radius: 17
                                    color: ngHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                                    border.width: 1; border.color: theme.clrBorder
                                    RowLayout {
                                        id: ngRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰐕"; font.family: theme.fontFamily; font.pixelSize: 14; color: theme.clrFg }
                                        Text { text: "New group"; font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFg }
                                    }
                                    HoverHandler { id: ngHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: sm.newGroup(null) }
                                }
                            }
                        }
                    }
                }

                // ── Footer: user + power ─────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        implicitWidth: 32; implicitHeight: 32; radius: 16
                        color: theme.clrAccentC
                        Text { anchors.centerIn: parent; text: "󰀄"; font.family: theme.fontFamily; font.pixelSize: 16; color: theme.clrOnAccentC }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Quickshell.env("USER")
                        font.family: theme.fontFamily; font.pixelSize: 13; color: theme.clrFg
                    }
                    Text {
                        text: sm.query ? "↑↓ select  ·  Enter open  ·  right-click to pin" : ""
                        font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                    }
                    Rectangle {
                        implicitWidth: pwrRow.implicitWidth + 24; implicitHeight: 34; radius: 17
                        color: pwrHover.hovered ? Qt.alpha(theme.clrUrgent, 0.18) : "transparent"
                        RowLayout {
                            id: pwrRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "󰐥"; font.family: theme.fontFamily; font.pixelSize: 15; color: pwrHover.hovered ? theme.clrUrgent : theme.clrFg }
                            Text { text: "Power"; font.family: theme.fontFamily; font.pixelSize: 12; color: pwrHover.hovered ? theme.clrUrgent : theme.clrFg }
                        }
                        HoverHandler { id: pwrHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                sm.close()
                                Quickshell.execDetached(["sh", "-c", "[ -x ~/.config/wlogout/launch.sh ] && exec ~/.config/wlogout/launch.sh || exec wlogout"])
                            }
                        }
                    }
                }
            }

            // ── Context menu ─────────────────────────────────────────────
            MouseArea {
                anchors.fill: parent
                visible: sm.ctx !== null || sm.optionsOpen
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: { sm.ctx = null; sm.optionsOpen = false; search.forceActiveFocus() }
            }

            // ── Search options ───────────────────────────────────────
            Rectangle {
                id: optPanel
                visible: sm.optionsOpen
                width: 400
                height: optCol.implicitHeight + 28
                x: panelBg.width - width - 16
                y: 72
                radius: 22
                color: theme.clrBgAlt
                border.width: 1; border.color: theme.clrBorder
                MouseArea { anchors.fill: parent }       // clicks inside never fall through to the dismiss area

                ColumnLayout {
                    id: optCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 8

                    Text { text: "Search options"; font.family: theme.fontFamily; font.pixelSize: 15; font.bold: true; color: theme.clrFg }

                    Text { text: "Search inside (with “In files” on)"; font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true; color: theme.clrAccent }
                    ChoiceRow {
                        theme: sm.theme
                        Layout.fillWidth: true
                        value: sm.opts.scope
                        options: [{ v: "text", t: "Text files" }, { v: "textlogs", t: "Text + logs" }, { v: "all", t: "All files" }]
                        onPicked: (v) => sm.setOpt("scope", v)
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: sm.opts.scope === "text" ? "Files with the text types below, from the file index."
                            : sm.opts.scope === "textlogs" ? "Text files, plus every .log file in your home, hidden folders included."
                            : "Every readable file in your home (binary files are skipped). Slow on big folders: results appear as they're found, for up to 30 s."
                        font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                    }

                    Text { Layout.topMargin: 4; text: "Skip files larger than"; font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true; color: theme.clrAccent }
                    ChoiceRow {
                        theme: sm.theme
                        Layout.fillWidth: true
                        value: sm.opts.maxMB
                        options: [{ v: 1, t: "1 MB" }, { v: 10, t: "10 MB" }, { v: 100, t: "100 MB" }, { v: 0, t: "No limit" }]
                        onPicked: (v) => sm.setOpt("maxMB", v)
                    }

                    OptSwitch {
                        theme: sm.theme
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        label: "Hidden folders"; sub: "~/.config, ~/.local… in file names and All files"
                        on: sm.opts.hidden; onToggled: sm.setOpt("hidden", !sm.opts.hidden)
                    }
                    OptSwitch {
                        theme: sm.theme
                        Layout.fillWidth: true
                        label: "System logs"; sub: "Also search /var/log (pacman.log, snapper.log…)"
                        on: sm.opts.systemLogs; onToggled: sm.setOpt("systemLogs", !sm.opts.systemLogs)
                    }
                    OptSwitch {
                        theme: sm.theme
                        Layout.fillWidth: true
                        label: "Journal"; sub: "Offer a journalctl search in the results"
                        on: sm.opts.journal; onToggled: sm.setOpt("journal", !sm.opts.journal)
                    }

                    RowLayout {
                        Layout.topMargin: 4
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: "Text file types"; font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true; color: theme.clrAccent }
                        Text {
                            visible: sm.opts.exts !== sm.defaultExts
                            text: "Reset"
                            font.family: theme.fontFamily; font.pixelSize: 11; font.underline: true; color: theme.clrFgMuted
                            TapHandler { onTapped: sm.setOpt("exts", sm.defaultExts) }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: extEdit.contentHeight + 16
                        radius: 12
                        color: theme.clrBg
                        border.width: extEdit.activeFocus ? 2 : 1
                        border.color: extEdit.activeFocus ? theme.clrAccent : theme.clrBorder
                        TextEdit {
                            id: extEdit
                            anchors { fill: parent; margins: 8 }
                            text: sm.opts.exts
                            wrapMode: TextEdit.Wrap
                            font.family: theme.fontFamily; font.pixelSize: 10
                            color: theme.clrFg
                            selectByMouse: true
                            function save() { const v = text.replace(/[\s.]+/g, "").replace(/,+/g, ",").replace(/^,|,$/g, ""); if (v !== sm.opts.exts) sm.setOpt("exts", v) }
                            onActiveFocusChanged: if (!activeFocus) save()
                            Keys.onReturnPressed: { save(); search.forceActiveFocus() }
                            Keys.onEscapePressed: { text = sm.opts.exts; search.forceActiveFocus() }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Comma-separated extensions. README, Makefile, PKGBUILD and *rc files always count as text."
                        font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                    }
                }
            }
            Rectangle {
                id: ctxMenu
                visible: sm.ctx !== null
                readonly property var options: sm.ctxOptions()
                width: 250
                height: ctxCol.implicitHeight + 12
                x: sm.ctx ? Math.min(sm.ctx.x, panelBg.width - width - 8) : 0
                y: sm.ctx ? Math.min(sm.ctx.y, panelBg.height - height - 8) : 0
                radius: 16
                color: theme.clrBgAlt
                border.width: 1; border.color: theme.clrBorder
                ColumnLayout {
                    id: ctxCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                    spacing: 0
                    Repeater {
                        model: ctxMenu.options
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 32; radius: 10
                            color: optHover.hovered ? Qt.alpha(modelData.danger ? theme.clrUrgent : theme.clrFg, 0.1) : "transparent"
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 10
                                Text { text: modelData.icon; font.family: theme.fontFamily; font.pixelSize: 14; color: modelData.danger ? theme.clrUrgent : theme.clrFg }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    elide: Text.ElideRight
                                    font.family: theme.fontFamily; font.pixelSize: 12; color: modelData.danger ? theme.clrUrgent : theme.clrFg
                                }
                            }
                            HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                // Take the click so it never reaches the item underneath (which would open it)
                                gesturePolicy: TapHandler.WithinBounds
                                grabPermissions: PointerHandler.TakeOverForbidden
                                // Read everything first: clearing sm.ctx destroys this delegate (and its scope)
                                onTapped: { const run = modelData.run, field = search; sm.ctx = null; run(); field.forceActiveFocus() }
                            }
                        }
                    }
                }
            }
        }
    }
}
