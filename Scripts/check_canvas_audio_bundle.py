#!/usr/bin/env python3
"""Verify the production Canvas audio payload in a built .app bundle."""
import json
from pathlib import Path
import sys


def check(bundle):
    required = {
        "SoundWorlds": ("synth-recipes-v1.json", "world-groups-v1.json"),
        "SynthOnePresets": (),
        "Drums": (),
        "FeltPiano": (),
    }
    for directory, catalogs in required.items():
        root = bundle / directory
        if not root.is_dir() or not any(path.is_file() for path in root.rglob("*")):
            raise ValueError(f"Canvas audio resource missing or empty: {directory}")
        for name in catalogs:
            json.loads((root / name).read_text())
    json.loads((bundle / "audio-assets-manifest.json").read_text())


if __name__ == "__main__":
    try:
        check(Path(sys.argv[1]))
    except (ValueError, OSError, IndexError) as error:
        sys.exit(f"FAIL: {error}")
    print("PASS: Canvas audio resources are present in the built app")
