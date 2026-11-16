#!/usr/bin/env python3
"""CPU / RAM / temps / disks / uptime for the Quickshell bar (JSON). CPU usage is the
delta since the previous call (state kept in $XDG_RUNTIME_DIR)."""
import json, os, glob, shutil

state_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-cpu-prev.json")

def cpu_times():
    out = {}
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("cpu"):
                name, *vals = line.split()
                vals = list(map(int, vals))
                idle = vals[3] + vals[4]
                out[name] = (sum(vals), idle)
    return out

now = cpu_times()
try:
    prev = {k: tuple(v) for k, v in json.load(open(state_file)).items()}
except Exception:
    prev = {}
json.dump(now, open(state_file, "w"))

def usage(name):
    if name not in prev: return 0.0
    dt = now[name][0] - prev[name][0]; di = now[name][1] - prev[name][1]
    return round(100 * (1 - di / dt), 1) if dt > 0 else 0.0

cores = sorted((k for k in now if k != "cpu"), key=lambda k: int(k[3:]))

mem = {}
with open("/proc/meminfo") as f:
    for line in f:
        k, v = line.split(":"); mem[k] = int(v.split()[0])   # kB

def coretemp():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(f"{h}/name").read().strip() == "coretemp":
                return round(int(open(f"{h}/temp1_input").read()) / 1000)
        except Exception:
            pass
    return None

disks = []
for mount in ("/", "/home"):
    try:
        u = shutil.disk_usage(mount)
        disks.append({"mount": mount, "used": u.used, "total": u.total})
    except Exception:
        pass
# /home on the same filesystem as / -> show once
if len(disks) == 2 and disks[0]["total"] == disks[1]["total"] and disks[0]["used"] == disks[1]["used"]:
    disks = disks[:1]

print(json.dumps({
    "cpu": usage("cpu"),
    "cores": [usage(c) for c in cores],
    "cpuTemp": coretemp(),
    "memUsed": (mem["MemTotal"] - mem["MemAvailable"]) * 1024, "memTotal": mem["MemTotal"] * 1024,
    "swapUsed": (mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)) * 1024, "swapTotal": mem.get("SwapTotal", 0) * 1024,
    "load": open("/proc/loadavg").read().split()[:3],
    "uptime": int(float(open("/proc/uptime").read().split()[0])),
    "disks": disks,
}))
