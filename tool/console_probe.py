#!/usr/bin/env python3
"""Read a page's console output over CDP.

Two traps this is built to avoid, both observed in this repo:

  * TARGET REUSE. Reusing a page target leaves the PREVIOUS navigation's app
    running and writing into the same console, so a build can appear to emit
    lines it is structurally incapable of printing. A fresh browser with a
    fresh user-data-dir and a target created for this run only.
  * A BLIND INSTRUMENT READING AS SILENCE. Zero event lines has two causes --
    the app printed nothing, or this script never saw anything at all. The
    run reports TOTAL console lines alongside matching ones; total==0 is an
    instrument failure and is named as such, never reported as "app silent".
"""
import json
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import websocket  # websocket-client

URL = sys.argv[1]
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 45.0
PORT = 9339
profile = tempfile.mkdtemp(prefix="cdpprobe-")

# A previous run still holding the port makes /json/version answer from the
# STALE browser -- the same reuse hazard as a stale page target, one level up.
# Fail loudly rather than silently probing the wrong Chrome.
try:
    busy = subprocess.run(["lsof", "-ti", f":{PORT}"], capture_output=True, text=True).stdout.split()
except FileNotFoundError:
    busy = []
if busy:
    raise SystemExit(f"port {PORT} already held by pid(s) {busy} -- kill them first; "
                     "otherwise this probes a browser it did not launch")

chrome = subprocess.Popen([
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    f"--remote-debugging-port={PORT}", f"--user-data-dir={profile}",
    "--headless=new", "--no-first-run", "--no-default-browser-check",
    "--remote-allow-origins=*",
    "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
    "--autoplay-policy=no-user-gesture-required", "--window-size=1440,900",
    "about:blank",
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def browser_ws():
    for _ in range(60):
        try:
            v = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/version"))
            return v["webSocketDebuggerUrl"]
        except Exception:
            time.sleep(0.5)
    raise SystemExit("chrome never exposed CDP")

ws = websocket.create_connection(browser_ws(), timeout=SECONDS + 60)
_id = [0]
def send(method, params=None, session=None):
    _id[0] += 1
    m = {"id": _id[0], "method": method, "params": params or {}}
    if session: m["sessionId"] = session
    ws.send(json.dumps(m)); return _id[0]

def wait_for(mid):
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == mid: return m

# A target created for THIS run only -- never an inherited page.
tid = wait_for(send("Target.createTarget", {"url": "about:blank"}))["result"]["targetId"]
sess = wait_for(send("Target.attachToTarget", {"targetId": tid, "flatten": True}))["result"]["sessionId"]
send("Runtime.enable", session=sess); send("Log.enable", session=sess)
send("Page.enable", session=sess)
send("Page.navigate", {"url": URL}, session=sess)

def text_of(msg):
    p = msg.get("params", {})
    if msg.get("method") == "Runtime.consoleAPICalled":
        return " ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", []))
    if msg.get("method") == "Log.entryAdded":
        return p.get("entry", {}).get("text", "")
    return None

lines, deadline = [], time.time() + SECONDS
ws.settimeout(2.0)
while time.time() < deadline:
    try: msg = json.loads(ws.recv())
    except Exception: continue
    if msg.get("sessionId") != sess: continue
    t = text_of(msg)
    if t is not None: lines.append(t)

# Prove we looked at the page we meant to look at.
loc = wait_for(send("Runtime.evaluate", {"expression": "location.href", "returnByValue": True}, session=sess))
actual = loc.get("result", {}).get("result", {}).get("value")

subprocess.run(["kill", str(chrome.pid)], check=False); shutil.rmtree(profile, ignore_errors=True)

evt = [l for l in lines if "[event]" in l]
print(f"target url      : {actual}")
print(f"console lines   : {len(lines)}   <- total, ANY source")
print(f"'[event]' lines : {len(evt)}")
if not lines:
    print("\nINSTRUMENT BLIND: zero console lines of any kind. This is NOT evidence")
    print("the app is silent -- the probe saw nothing at all.")
else:
    print("\nprobe is live (it saw non-event console output), so an [event] count")
    print("of zero would be a real negative.\n")
    for l in evt[:25]: print("  ", l[:160])
