#!/usr/bin/env python3
"""Compile and execute the production analytics flush against an isolated HTTP double."""
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
    return source[start:end].removeprefix('private ')


@unittest.skipUnless(shutil.which('swiftc'), 'Swift is required')
class AnalyticsFlushTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='nowhere-analytics-flush-')
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        analytics = (ROOT / 'Nowhere/Services/SupabaseSyncService+Analytics.swift').read_text()
        dtos = (ROOT / 'Nowhere/Services/SupabaseSyncDTOs.swift').read_text()
        harness = (ROOT / 'Scripts/Fixtures/AnalyticsFlushHarness.swift').read_text()
        for key, value in [
            ('FLUSH', declaration(analytics, 'private func flushAnalyticsEvents()')),
            ('PAYLOAD', declaration(dtos, 'struct AnalyticsEventPayload:')),
            ('ROW', declaration(dtos, 'struct AnalyticsEventInsertRow:')),
        ]:
            harness = harness.replace('/*__' + key + '__*/', value)
        source = folder / 'main.swift'
        source.write_text(harness)
        cls.binary = folder / 'analytics'
        result = subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(folder / 'modules'), str(source), '-o', str(cls.binary)], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_retry_after_lost_acknowledgement(self):
        self.run_case('replay')

    def test_mixed_duplicate_and_new_events(self):
        self.run_case('mixed')

    def test_other_account_events_stay_queued(self):
        self.run_case('ownership')

    def test_unrelated_conflict_does_not_acknowledge_queue(self):
        self.run_case('409')

    def test_permission_denied_does_not_acknowledge_queue(self):
        self.run_case('403')

    def test_transport_error_does_not_acknowledge_queue(self):
        self.run_case('transport')


if __name__ == '__main__':
    unittest.main()
