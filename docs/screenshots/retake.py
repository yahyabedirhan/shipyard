#!/usr/bin/env python3
"""Retake screenshots from site/shots.json on this Mac.

Run from the repository root, after `make install`:

    python3 docs/screenshots/retake.py                 # every shot but cli-help-dark
    python3 docs/screenshots/retake.py panel-list-dark view-cli-dark

Each shot runs its own `capture` steps from site/shots.json, with these changes:
the demo folder is `.scratch/shots-demo` rather than `~/shipyard-demo`, because
the app's socket path must stay under 104 bytes; the lease is taken again
before each shot, since a long batch outlives one lease; and the app quits
before the demo folder is replaced, so the CLI never loses a running demo.
At the end the maintainer's own app runs again and the lease is released.
"""

import json
import os
import shutil
import subprocess
import sys
import time

CLI = "/Applications/Shipyard.app/Contents/Helpers/shipyard"
SKIP_BY_DEFAULT = {"cli-help-dark"}  # a terminal drawing, made by site/scripts/terminal.mjs
DEMO = os.path.join(".scratch", "shots-demo")


def run(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    return result.returncode, (result.stderr or result.stdout).strip()


def retake(shot):
    demo = os.path.abspath(DEMO)
    run(f'{CLI} lease take --wait 120 --for "retake site screenshots"')
    run(f"{CLI} app quit")
    if os.path.exists(demo):
        shutil.move(demo, f"{demo}-old-{int(time.time())}")
    if any("cp -R assets/demo" in step for step in shot["capture"]):
        shutil.copytree("assets/demo", demo)
    os.makedirs(os.path.join(demo, "shipyard"), exist_ok=True)
    with open(os.path.join(demo, "shipyard", "config.toml"), "w") as file:
        file.write(shot["demo"])

    # Demo items read at once; live GitHub needs its first refresh, and
    # `app status` doesn't say when that ends, so a live shot waits longer.
    settle = 12 if os.path.exists(os.path.join(demo, "demo-items.json")) else 60

    failures = []
    for step in shot["capture"]:
        if step.startswith(("#", "mkdir")) or "shipyard lease" in step or step.strip() == "shipyard app open":
            continue
        command = step.replace("~/shipyard-demo", demo)
        if command.startswith("shipyard "):
            command = CLI + command[len("shipyard"):]
        command = command.replace(" shipyard ping ", f" {CLI} ping ")
        code, output = run(command)
        time.sleep(settle if "app open --demo" in command else 1.5)
        if code:
            failures.append(f"{command}: {output[:300]}")
    return failures


def main():
    shots = json.load(open("site/shots.json"))["shots"]
    by_id = {shot["id"]: shot for shot in shots}
    wanted = sys.argv[1:] or [shot["id"] for shot in shots if shot["id"] not in SKIP_BY_DEFAULT]
    unknown = [name for name in wanted if name not in by_id]
    if unknown:
        sys.exit(f"no such shot: {', '.join(unknown)}")

    failed = {}
    try:
        for name in wanted:
            failures = retake(by_id[name])
            print(f"{name}: {'FAILED' if failures else 'ok'}", flush=True)
            for failure in failures:
                print(f"  {failure}", flush=True)
            if failures:
                failed[name] = failures
    finally:
        run(f"{CLI} app open")
        run(f"{CLI} lease release")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
