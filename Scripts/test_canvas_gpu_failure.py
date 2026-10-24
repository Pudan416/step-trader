#!/usr/bin/env python3
"""Exercise the production draw entry point with a failed GPU boundary."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


@unittest.skipUnless(shutil.which("swiftc"), "Swift is required")
class CanvasGPUFailureTests(unittest.TestCase):
    def test_failed_renderer_stops_before_acquiring_another_drawable(self):
        renderer = (ROOT / "Nowhere/Experiments/DayObjects/DayObjectsRenderer.swift").read_text()
        source = (ROOT / "Scripts/Fixtures/CanvasGPUFailureHarness.swift").read_text()
        source = source.replace("/*__DRAW__*/", declaration(renderer, "    func draw(in view: MTKView)"))
        source = source.replace("/*__STATE__*/", declaration(renderer, "final class DayObjectsGPUFailureState:"))
        source = source.replace("/*__TRACKED__*/", declaration(renderer, "    private func makeTrackedCommandBuffer()").replace("private ", "", 1))
        with tempfile.TemporaryDirectory(prefix="nowhere-gpu-failure-") as folder:
            folder = Path(folder)
            script = folder / "main.swift"
            script.write_text(source)
            binary = folder / "check"
            build = subprocess.run(["swiftc", "-D", "DEBUG", "-module-cache-path", str(folder / "modules"), str(script), "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
