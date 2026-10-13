#!/usr/bin/env python3
"""Drives the perf session's variants through the same phases and prints
what each phase cost, from the meter's log (`PerfLog` in kit/Perf).

Each phase runs on the variant's real window in background placement,
through `swiftlab interact`, under one held lease:

  idle-all-pulse   All, untouched, with running workflow runs pulsing
  idle-all         All, untouched, every run finished
  hover            the pointer moved down All's rows, one row at a time
  scroll           All scrolled down in steps
  switch-tabs      the window's own "Switch tabs x10": All and a project in turn
  idle-project     a project's tab, untouched, every run finished
  reload           the same volume loaded again, as a refresh does

Usage: swift-lab/perf/stress.py [component/variant ...]
       (default: each before variant next to its after variant, then the list layout)
Run it from the worktree whose sessions it should drive.
"""
import glob
import json
import os
import subprocess
import sys
import time

PROJECT = "shipyard"
SESSION = "perf"
ENV = dict(os.environ, SWIFTLAB_WINDOWS="background", SWIFTLAB_CONTROL_KEY="perf-stress")
# Where the first rows and the list sit in the window, in points.
ROW_X, FIRST_ROW_Y, ROW_STEP, ROWS = 220, 210, 41, 14
SCROLL_AT = (220, 450)


def lab(*args, check=True):
    result = subprocess.run(["swiftlab", *args, "--project", PROJECT, "--wait", "120"] if args[0] == "interact" else ["swiftlab", *args, "--project", PROJECT], env=ENV, capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.exit(f"swiftlab {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def log_path():
    paths = glob.glob("/var/folders/*/*/T/shipyard-lab-perf.jsonl") + glob.glob("/private/var/folders/*/*/T/shipyard-lab-perf.jsonl")
    return max(paths, key=os.path.getmtime) if paths else None


def entries(since, until):
    path = log_path()
    if not path:
        return []
    with open(path) as handle:
        lines = [json.loads(line) for line in handle if line.strip()]
    return [entry for entry in lines if since <= entry["time"] <= until]


def summarise(readings):
    readings = [r for r in readings if "busy" in r]
    if not readings:
        return {"busy": 0, "stall": 0, "late": 0, "bodies": 0}
    return {
        "busy": sum(r["busy"] for r in readings) / len(readings),
        "stall": max(r["worstStall"] for r in readings),
        "late": sum(r["framesLate"] for r in readings) / (len(readings) / 2),
        "bodies": sum(r["counts"].get("TabRow.body", 0) + r["counts"].get("ItemRow.body", 0) for r in readings) / len(readings),
    }


def phase(name, action, settle=3.0):
    action()
    start = time.time()
    time.sleep(settle)
    return name, summarise(entries(start, time.time()))


def run(variant):
    component, label = variant.split("/")
    # One runner draws every window of the session: close it first, so no
    # other variant's window (a pulsing one) shares the main thread.
    lab("session", "close", SESSION, check=False)
    lab("show", SESSION, component, label, "--background")
    time.sleep(6)
    lab("control", "take", SESSION, "--wait", "120")
    results = []
    try:
        interact = lambda *g: lab("interact", SESSION, component, label, *g)
        results.append(phase("idle-all-pulse", lambda: interact("leave")))
        results.append(phase("idle-all", lambda: interact("click", "running-runs")))

        def hover():
            for row in range(ROWS):
                interact("hover", f"{ROW_X},{FIRST_ROW_Y + row * ROW_STEP}")
        start = time.time()
        hover()
        results.append(("hover", summarise(entries(start, time.time() + 0.6))))

        def scroll():
            for _ in range(8):
                interact("scroll", f"{SCROLL_AT[0]},{SCROLL_AT[1]}", "--dy", "-240")
        start = time.time()
        scroll()
        time.sleep(0.6)
        results.append(("scroll", summarise(entries(start, time.time()))))

        interact("leave")
        start = time.time()
        if component == "tabs-panel":
            interact("click", "switch-tabs")
            # Ten switches 450 ms apart, each as slow as the volume makes it.
            for _ in range(180):
                time.sleep(1)
                if any(e.get("scenario") == "switch-tabs" for e in entries(start, time.time())):
                    break
            switch = [e for e in entries(start, time.time()) if e.get("scenario") == "switch-tabs"]
            if switch:
                s = switch[-1]
                results.append(("switch→All", {"stall": sum(s["toAll"]) / len(s["toAll"]), "worst": max(s["toAll"])}))
                results.append(("switch→project", {"stall": sum(s["toProject"]) / len(s["toProject"]), "worst": max(s["toProject"])}))
            results.append(phase("idle-project", lambda: interact("click", "show-project")))
        start = time.time()
        interact("click", "reload")
        time.sleep(1.5)
        reload = [e for e in entries(start, time.time()) if e.get("scenario") == "reload"]
        if reload:
            results.append(("reload", {"stall": reload[-1]["worstStall"]}))
        # Leave it as found: runs pulsing, on All.
        interact("click", "running-runs")
        if component == "tabs-panel":
            interact("click", "show-all")
    finally:
        lab("control", "release", SESSION, check=False)
        lab("session", "close", SESSION, check=False)
    return results


def main():
    variants = sys.argv[1:] or ["tabs-panel/V1", "tabs-panel/V4", "tabs-panel/V2", "tabs-panel/V5", "tabs-panel/V3", "tabs-panel/V6", "list-panel/V1", "list-panel/V2"]
    for variant in variants:
        print(f"\n{variant}")
        print(f"  {'phase':16} {'busy %':>7} {'worst stall ms':>15} {'late frames/s':>14} {'row bodies/s':>13}")
        for name, s in run(variant):
            if "busy" in s:
                print(f"  {name:16} {s['busy']:7.0f} {s['stall']:15.0f} {s['late']:14.0f} {s['bodies']:13.0f}")
            elif "worst" in s:
                print(f"  {name:16} {'':7} {s['worst']:15.0f}   (avg {s['stall']:.0f} ms per switch)")
            else:
                print(f"  {name:16} {'':7} {s['stall']:15.0f}")


if __name__ == "__main__":
    main()
