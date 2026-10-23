#!/usr/bin/env python3
"""Execute production Canvas writes and export queue across a delayed account switch."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('    private func ', '    func ', 1)


@unittest.skipUnless(shutil.which('swiftc'), 'Swift is required')
class CanvasWriteEpochTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='nowhere-canvas-epoch-')
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        production = (ROOT / 'Nowhere/Services/CanvasStorageService.swift').read_text()
        source = (ROOT / 'Scripts/Fixtures/CanvasWriteEpochHarness.swift').read_text()
        state = ''
        for marker in ['struct CanvasStorageWriteEpoch:', 'final class CanvasStorageWriteBarrier:']:
            if marker in production: state += declaration(production, marker) + '\n'
        if not state:
            state = 'struct CanvasStorageWriteEpoch {}\n'
        methods = []
        for marker in [
            '    func saveCanvas(_ canvas: DayCanvas)',
            '    private func writeCanvas(',
            '    func saveSnapshot(',
            '    func saveWidgetSnapshot(',
        ]:
            methods.append(declaration(production, marker))
        for marker in [
            '    func captureWriteEpoch()',
            '    func invalidatePendingWritesForAccountSwitch()',
            '    func resumeWritesAfterAccountSwitch()',
            '    func saveCanvas(_ canvas: DayCanvas, expectedEpoch:',
        ]:
            if marker in production: methods.append(declaration(production, marker))
        if '    func captureWriteEpoch()' not in production:
            methods += ['func captureWriteEpoch() -> CanvasStorageWriteEpoch { .init() }',
                        'func invalidatePendingWritesForAccountSwitch() async {}',
                        'func resumeWritesAfterAccountSwitch() {}',
                        'func saveCanvas(_ canvas: DayCanvas, expectedEpoch: CanvasStorageWriteEpoch?) -> Bool { saveCanvas(canvas) }']
        source = source.replace('/*__STATE__*/', state)
        source = source.replace('/*__BARRIER_PROPERTY__*/', 'let writeBarrier = CanvasStorageWriteBarrier()' if 'final class CanvasStorageWriteBarrier:' in production else '')
        source = source.replace('/*__METHODS__*/', '\n'.join(methods))
        source = source.replace('/*__QUEUE__*/', declaration(production, 'final class CanvasWidgetSnapshotQueue'))
        swift = folder / 'main.swift'
        swift.write_text(source)
        cls.binary = folder / 'check'
        result = subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(folder / 'modules'), str(swift), '-o', str(cls.binary)], capture_output=True, text=True, timeout=60)
        if result.returncode: raise AssertionError(result.stdout + result.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_delayed_png_export_cannot_overwrite_incoming_account(self): self.run_case('png')
    def test_delayed_widget_export_cannot_overwrite_incoming_account(self): self.run_case('widget')
    def test_stale_json_callback_and_during_swap_writes_are_rejected(self): self.run_case('json')
    def test_canceled_widget_worker_cannot_clobber_incoming_queue(self): self.run_case('queue-switch')
    def test_normal_widget_queue_still_serializes_and_coalesces(self): self.run_case('queue-normal')
    def test_invalidation_drains_active_disk_write_before_swap(self): self.run_case('active-write')


if __name__ == '__main__': unittest.main()
