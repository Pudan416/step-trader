#!/usr/bin/env python3
"""Run the production epoch/drain state and routines writer using synthetic owners."""
from pathlib import Path
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
    return source[start:end].replace('private func ', 'func ', 1)

class SyncTransitionTests(unittest.TestCase):
    def test_production_state_and_routines(self):
        core = (ROOT / 'Nowhere/Services/SupabaseSyncService.swift').read_text()
        routines = (ROOT / 'Nowhere/Services/SupabaseSyncService+Routines.swift').read_text()
        source = (ROOT / 'Scripts/Fixtures/SyncTransitionHarness.swift').read_text()
        source = source.replace('/*STATE*/', '\n'.join(declaration(core, marker) for marker in [
            'struct SupabaseSyncEpoch:', 'final class SupabaseSyncTransitionState:', 'final class SupabaseSyncOperation:']))
        source = source.replace('/*METHODS*/', '\n'.join(declaration(core, marker) for marker in [
            '    func acceptsScheduledHistoryWork()', '    func beginSyncOperation(writing:']) + '\n' + '\n'.join(
                declaration(routines, marker) for marker in ['    func syncSavedRoutines(', '    private func performSavedRoutinesSync(']))
        with tempfile.TemporaryDirectory(prefix='nowhere-sync-transition-') as folder:
            folder = Path(folder)
            swift = folder / 'main.swift'
            swift.write_text(source)
            binary = folder / 'tests'
            result = subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(folder/'modules'), str(swift), '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())

if __name__ == '__main__': unittest.main()
