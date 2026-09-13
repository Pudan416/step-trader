#!/usr/bin/env python3
"""Capture macOS process stacks after quiet test output; never kill tests."""

import argparse
import pathlib
import subprocess
import time


def capture(directory: pathlib.Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "processes.txt").open("w") as output:
        subprocess.run(["ps", "-axo", "pid,ppid,%cpu,%mem,etime,command"],
                       stdout=output, stderr=subprocess.STDOUT, timeout=15)
    for name in ("Nowhere", "xcodebuild", "testmanagerd"):
        result = subprocess.run(["pgrep", "-x", name], capture_output=True,
                                text=True, timeout=15)
        for pid in result.stdout.split():
            if pid.isdigit():
                with (directory / f"{name}-{pid}-sample.log").open("w") as output:
                    try:
                        subprocess.run(
                            ["sample", pid, "5", "-file", str(directory / f"{name}-{pid}.txt")],
                            stdout=output, stderr=subprocess.STDOUT, timeout=20)
                    except subprocess.TimeoutExpired:
                        output.write("sample timed out\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("diagnostics", type=pathlib.Path)
    parser.add_argument("--quiet-seconds", type=float, default=180)
    args = parser.parse_args()
    last_size = -1
    last_progress = time.monotonic()
    last_capture = float("-inf")
    while True:
        size = args.log.stat().st_size if args.log.exists() else 0
        now = time.monotonic()
        if size != last_size:
            last_size = size
            last_progress = now
        if now - last_progress >= args.quiet_seconds and now - last_capture >= 300:
            last_capture = now
            destination = args.diagnostics / time.strftime("%Y%m%d-%H%M%S", time.gmtime())
            print(f"No new test output for {now - last_progress:.0f}s; capturing stacks in {destination}",
                  flush=True)
            try:
                capture(destination)
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"Stack capture failed: {error}", flush=True)
        time.sleep(15)


if __name__ == "__main__":
    main()
