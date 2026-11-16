#!/usr/bin/env python3
"""What is using the mic / camera / screen right now (for the Quickshell bar).
Prints JSON: {"mic": [apps], "camera": [apps], "screen": [apps]}"""
import json, os, subprocess

def app_name(props):
    a = props.get("application.name") or ""
    b = props.get("application.process.binary") or ""
    if not a or "webrtc" in a.lower() or "chromium" in a.lower():
        a = b or a or props.get("node.name") or "?"
    a = a.split("_")[0]          # helpers like "Discord_capture" -> "Discord"
    return a[:1].upper() + a[1:]

try:
    graph = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
except Exception:
    graph = []

nodes = {o["id"]: o for o in graph if o.get("type") == "PipeWire:Interface:Node"}
links = [o.get("info", {}) for o in graph if o.get("type") == "PipeWire:Interface:Link"]
def props(n): return n.get("info", {}).get("props", {})
def state(n): return n.get("info", {}).get("state", "")

mic, camera, screen = [], [], []
for nid, n in nodes.items():
    p = props(n); mc = p.get("media.class", "")
    if mc == "Stream/Input/Audio" and state(n) == "running":          # an app recording audio
        mic.append(app_name(p))
    if mc == "Stream/Input/Video" and state(n) == "running":          # an app receiving video
        srcs = [nodes.get(l.get("output-node-id")) for l in links if l.get("input-node-id") == nid]
        for s in filter(None, srcs):
            sn = props(s).get("node.name", "")
            if "xdg-desktop-portal" in sn: screen.append(app_name(p))
            elif sn.startswith("v4l2") or "camera" in sn.lower(): camera.append(app_name(p))

# Screen capture through the portal even when the consumer isn't linked yet
if not screen and any("xdg-desktop-portal" in props(n).get("node.name", "") and state(n) == "running" for n in nodes.values()):
    screen.append("Screen share")

# Apps that opened the webcam directly (V4L2), outside PipeWire
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            if os.readlink(f"/proc/{pid}/fd/{fd}").startswith("/dev/video"):
                name = open(f"/proc/{pid}/comm").read().strip()
                if name not in ("pipewire", "wireplumber"):
                    camera.append(name[:1].upper() + name[1:])
                break
    except Exception:
        pass

uniq = lambda xs: list(dict.fromkeys(xs))
print(json.dumps({"mic": uniq(mic), "camera": uniq(camera), "screen": uniq(screen)}))
