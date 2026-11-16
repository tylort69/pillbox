#!/usr/bin/env python3
"""Network info for the Quickshell bar (systemd-networkd + optional iwd).

  net.py info     -> interfaces, addresses, route, DNS, Wi-Fi (JSON)
  net.py checks   -> router / internet / DNS reachability with latency (JSON)
  net.py wifi-scan | wifi-connect <ssid> [passphrase] | wifi-disconnect | wifi-power on|off
"""
import json, os, re, shutil, socket, subprocess, sys, time

def run(*cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""

def jrun(*cmd):
    try:
        return json.loads(run(*cmd) or "null")
    except Exception:
        return None

def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return default

ANSI = re.compile(r"\x1b\[[0-9;]*m")

def iwctl(*args):
    return ANSI.sub("", run("iwctl", *args, timeout=8))

def wifi_station(iface):
    """Current Wi-Fi connection via iwd: ssid, signal (dBm), state."""
    out = iwctl("station", iface, "show")
    info = {}
    for line in out.splitlines():
        m = re.match(r"\s+(\S.*?)\s{2,}(\S.*)$", line)
        if m:
            info[m.group(1).strip()] = m.group(2).strip()
    rssi = info.get("RSSI", "") or info.get("AverageRSSI", "")
    m = re.search(r"-?\d+", rssi)
    return {"state": info.get("State", ""), "ssid": info.get("Connected network", ""),
            "rssi": int(m.group()) if m else None}

def info():
    addrs = jrun("ip", "-j", "addr") or []
    routes = jrun("ip", "-j", "route", "show", "default") or []
    default = routes[0] if routes else {}
    links = []
    for a in addrs:
        name = a.get("ifname", "")
        if name == "lo":
            continue
        wireless = os.path.isdir(f"/sys/class/net/{name}/wireless") or os.path.isdir(f"/sys/class/net/{name}/phy80211")
        v4 = [f'{x["local"]}/{x["prefixlen"]}' for x in a.get("addr_info", []) if x.get("family") == "inet"]
        v6 = [x["local"] for x in a.get("addr_info", []) if x.get("family") == "inet6" and x.get("scope") == "global"]
        speed = read(f"/sys/class/net/{name}/speed", "")
        driver = os.path.basename(os.path.realpath(f"/sys/class/net/{name}/device/driver")) if os.path.exists(f"/sys/class/net/{name}/device/driver") else ""
        link = {"name": name, "type": "wifi" if wireless else "ethernet",
                "state": a.get("operstate", "UNKNOWN").lower(), "mac": a.get("address", ""),
                "ipv4": v4, "ipv6": v6, "driver": driver,
                "speed": int(speed) if speed.lstrip("-").isdigit() and int(speed) > 0 else None,
                "default": name == default.get("dev")}
        if wireless and shutil.which("iwctl"):
            link["wifi"] = wifi_station(name)
        links.append(link)
    # DNS servers in resolved's order (continuation lines included) and the one in use now
    dns, current = [], ""
    status = run("resolvectl", "status")
    key = None
    for line in status.splitlines():
        m = re.match(r"\s*([A-Za-z ]+?):\s*(.*)$", line)
        if m and not re.match(r"^\s*[\d.:a-f]+#", line.strip()):
            key, rest = m.group(1).strip(), m.group(2)
        else:
            rest = line
        if key == "DNS Servers":
            dns += rest.split()
        elif key == "Current DNS Server" and not current:
            current = rest.strip()
    def pretty(d):
        ip, _, name = d.partition("#")
        return f"{ip} ({name})" if name else ip
    has_wifi_hw = bool(os.listdir("/sys/class/ieee80211")) if os.path.isdir("/sys/class/ieee80211") else False
    return {"links": links, "gateway": default.get("gateway", ""), "iface": default.get("dev", ""),
            "dns": [pretty(d) for d in dict.fromkeys(dns)], "dnsCurrent": pretty(current) if current else "",
            "wifiHardware": has_wifi_hw,
            "iwd": bool(shutil.which("iwctl")), "hostname": socket.gethostname()}

def ping(host):
    out = run("ping", "-c", "1", "-W", "2", host, timeout=4)
    m = re.search(r"time=([\d.]+)", out)
    return round(float(m.group(1))) if m else None

def checks():
    routes = jrun("ip", "-j", "route", "show", "default") or []
    gw = routes[0].get("gateway", "") if routes else ""
    t = time.time()
    try:
        socket.getaddrinfo("archlinux.org", 443)
        dns_ms = round((time.time() - t) * 1000)
    except Exception:
        dns_ms = None
    # Two independent targets so one lost ping isn't reported as "no internet"
    internet = ping("1.1.1.1")
    if internet is None:
        internet = ping("9.9.9.9")
    return {"router": ping(gw) if gw else None, "internet": internet, "dns": dns_ms,
            "hasGateway": bool(gw), "time": int(time.time())}

def wifi_iface():
    for name in os.listdir("/sys/class/net"):
        if os.path.isdir(f"/sys/class/net/{name}/wireless"):
            return name
    return ""

def wifi_scan():
    iface = wifi_iface()
    if not iface:
        return {"networks": [], "error": "no-adapter"}
    iwctl("station", iface, "scan")
    time.sleep(2)
    nets = []
    for line in iwctl("station", iface, "get-networks").splitlines()[4:]:
        line = line.rstrip()
        if not line.strip():
            continue
        connected = line.lstrip().startswith(">")
        parts = re.split(r"\s{2,}", line.replace(">", " ").strip())
        if len(parts) >= 3:
            nets.append({"ssid": parts[0], "security": parts[1], "bars": parts[2].count("*"), "connected": connected})
    known = set(l.split("  ")[0].strip() for l in iwctl("known-networks", "list").splitlines()[4:] if l.strip())
    for n in nets:
        n["known"] = n["ssid"] in known
    return {"networks": nets, "iface": iface}

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "info"
    if cmd == "info":
        out = info()
    elif cmd == "checks":
        out = checks()
    elif cmd == "wifi-scan":
        out = wifi_scan()
    elif cmd == "wifi-connect":
        iface, ssid = wifi_iface(), sys.argv[2]
        args = ["station", iface, "connect", ssid]
        if len(sys.argv) > 3 and sys.argv[3]:
            args = ["--passphrase", sys.argv[3]] + args
        r = subprocess.run(["iwctl"] + args, capture_output=True, text=True, timeout=30)
        out = {"ok": r.returncode == 0, "error": ANSI.sub("", (r.stdout + r.stderr).strip())}
    elif cmd == "wifi-disconnect":
        iwctl("station", wifi_iface(), "disconnect"); out = {"ok": True}
    elif cmd == "wifi-power":
        iwctl("device", wifi_iface(), "set-property", "Powered", sys.argv[2]); out = {"ok": True}
    else:
        out = {"error": "unknown command"}
    print(json.dumps(out))

if __name__ == "__main__":
    main()
