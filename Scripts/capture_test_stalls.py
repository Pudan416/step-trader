#!/usr/bin/env python3
"""Capture macOS process stacks after quiet output or a test marker; never kill tests."""

import argparse
import pathlib
import subprocess
import time


def capture(directory: pathlib.Path, process_names: list[str], use_sudo: bool = False) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / "processes.txt").open("w") as output:
        subprocess.run(["ps", "-axo", "pid,ppid,%cpu,%mem,etime,command"],
                       stdout=output, stderr=subprocess.STDOUT, timeout=15)
    for name in process_names:
        result = subprocess.run(["pgrep", "-x", name], capture_output=True,
                                text=True, timeout=15)
        for pid in result.stdout.split():
            if pid.isdigit():
                with (directory / f"{name}-{pid}-sample.log").open("w") as output:
                    try:
                        subprocess.run(
                            (["sudo", "-n"] if use_sudo else [])
                            + ["sample", pid, "5", "-file", str(directory / f"{name}-{pid}.txt")],
                            stdout=output, stderr=subprocess.STDOUT, timeout=20)
                    except subprocess.TimeoutExpired:
                        output.write("sample timed out\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("diagnostics", type=pathlib.Path)
    parser.add_argument("--quiet-seconds", type=float, default=180)
    parser.add_argument("--capture-marker", help="Capture once as soon as this log text appears")
    parser.add_argument("--process-name", action="append", dest="process_names")
    parser.add_argument("--sudo", action="store_true", help="Use noninteractive sudo for daemon samples")
    args = parser.parse_args()
    process_names = args.process_names or ["Nowhere", "xcodebuild", "testmanagerd"]
    marker_captured = False
    log_offset = 0
    marker_tail = ""
    last_size = -1
    last_progress = time.monotonic()
    last_capture = float("-inf")
    while True:
        size = args.log.stat().st_size if args.log.exists() else 0
        now = time.monotonic()
        if size != last_size:
            last_size = size
            last_progress = now
        marker_seen = False
        if args.capture_marker and not marker_captured and args.log.exists():
            with args.log.open(errors="replace") as log:
                if size < log_offset:
                    log_offset = 0
                    marker_tail = ""
                log.seek(log_offset)
                text = marker_tail + log.read()
                log_offset = log.tell()
                marker_seen = args.capture_marker in text
                marker_tail = text[-len(args.capture_marker):]
        is_stalled = now - last_progress >= args.quiet_seconds and now - last_capture >= 300
        if marker_seen or is_stalled:
            marker_captured = marker_captured or marker_seen
            last_capture = now
            destination = args.diagnostics / time.strftime("%Y%m%d-%H%M%S", time.gmtime())
            reason = "Test marker reached" if marker_seen else f"No new test output for {now - last_progress:.0f}s"
            print(f"{reason}; capturing stacks in {destination}", flush=True)
            try:
                capture(destination, process_names, args.sudo)
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"Stack capture failed: {error}", flush=True)
        time.sleep(0.1 if args.capture_marker and not marker_captured else 15)


if __name__ == "__main__":
    main()
