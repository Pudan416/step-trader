#!/usr/bin/env python3
"""Postgres regression; NOWHERE_TEST_PG_DSN must point at an empty local fixture DB."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('NOWHERE_TEST_PG_DSN') and shutil.which('psql'),
                     'Set NOWHERE_TEST_PG_DSN to an empty local fixture database and provide psql')
class AnalyticsPostgresTests(unittest.TestCase):
    def test_replay_target_batch_and_account_isolation(self):
        baseline = (ROOT / 'supabase/migrations/00000000000000_baseline_schema.sql').read_text()
        start = baseline.index('CREATE TABLE IF NOT EXISTS public.user_analytics_events (')
        end = baseline.index('-- Growth note:', start)
        # Extract the production table, unique constraint, and ownership policies.
        sql = '''BEGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
END $$;
'''
        sql += baseline[start:end]
        sql += (ROOT / 'supabase/tests/analytics_idempotency.sql').read_text()
        sql += '\nROLLBACK;\n'
        result = subprocess.run(['psql', '-X', os.environ['NOWHERE_TEST_PG_DSN'], '-v', 'ON_ERROR_STOP=1'],
                                input=sql, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
