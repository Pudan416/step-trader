#!/usr/bin/env python3
"""Replay via the real Supabase CLI in disposable localhost PostgreSQL databases."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
host = os.environ.get('PGHOST', '127.0.0.1')
if host not in ('localhost', '127.0.0.1', '::1'):
    raise SystemExit('Migration replay requires a localhost PostgreSQL server')
env = {**os.environ, 'PGHOST': host}
cli = os.environ.get('SUPABASE_CLI', 'supabase')

def sql(database, *, source=None, command=None):
    args = ['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-q', '-d', database]
    args += ['-f', str(source)] if source else ['-c', command]
    result = subprocess.run(args, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{source or command}:\n{result.stderr}')

migrations = sorted((ROOT / 'migrations').glob('*.sql'))
repair = ROOT / 'migrations/20261022191514_repair_legacy_trigger_permissions.sql'
repair_index = migrations.index(repair)
with tempfile.TemporaryDirectory(prefix='nowhere-cli-') as temporary:
    project = Path(temporary)
    subprocess.run([cli, 'init', '--workdir', temporary, '--yes'], env=env, check=True)
    directory = project / 'supabase/migrations'
    directory.mkdir(exist_ok=True)
    for migration in migrations:
        shutil.copy(migration, directory)
    # Both historical names are valid deployed history for the same version.
    for old_name in (None, 'drop_public_leaderboard_read_policy', 'revoke_trigger_function_rest_exposure'):
        database = 'nowhere_replay_' + uuid.uuid4().hex
        subprocess.run(['createdb', database], env=env, check=True)
        try:
            sql(database, source=ROOT / 'tests/Fixtures/platform-schema.sql')
            if old_name:
                sql(database, command='CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations '
                    '(version text PRIMARY KEY, statements text[], name text);')
                for migration in migrations[:repair_index]:
                    sql(database, source=migration)
                    version, name = migration.stem.split('_', 1)
                    if version == '20260711':
                        name = old_name
                    sql(database, command=f"INSERT INTO supabase_migrations.schema_migrations(version,name) VALUES ('{version}','{name}');")
                sql(database, source=ROOT / 'tests/Fixtures/legacy-auth-trigger.sql')
                sql(database, command='CREATE POLICY "Public leaderboard read" ON public.users FOR SELECT TO anon USING (true);'
                    'GRANT EXECUTE ON FUNCTION public.handle_new_user(), public.handle_user_updated() TO PUBLIC, anon, authenticated;')
            # The URL contains no credentials; libpq environment supplies local auth.
            port = os.environ.get('PGPORT', '5432')
            user = os.environ.get('PGUSER', 'postgres')
            url_host = f'[{host}]' if ':' in host else host
            url = f'postgresql://{user}@{url_host}:{port}/{database}?sslmode=disable'
            subprocess.run([cli, 'migration', 'up', '--workdir', temporary, '--db-url', url, '--yes'], env=env, check=True)
            sql(database, source=ROOT / 'tests/Fixtures/assert-trigger-permissions.sql')
            # Idempotent repair and no legacy helper invented for fresh databases.
            sql(database, source=repair)
            sql(database, command="DO $$ BEGIN IF (to_regprocedure('public.handle_new_auth_user()') IS NOT NULL) <> "
                + ('true' if old_name else 'false') + " THEN RAISE EXCEPTION 'Unexpected legacy helper state'; END IF; "
                "IF EXISTS (SELECT FROM pg_policies WHERE schemaname='public' AND tablename='users' AND policyname='Public leaderboard read') "
                "THEN RAISE EXCEPTION 'Public profile policy retained'; END IF; "
                + (f"IF (SELECT name FROM supabase_migrations.schema_migrations WHERE version='20260711') <> '{old_name}' THEN RAISE EXCEPTION 'Historical ledger rewritten'; END IF; " if old_name else '')
                + f"IF (SELECT count(*) FROM supabase_migrations.schema_migrations) <> {len(migrations)} THEN RAISE EXCEPTION 'Incomplete CLI history'; END IF; END $$")
            print(f'PASS: {len(migrations)} CLI migration versions + permissions/auth triggers ({old_name or "fresh"})', flush=True)
        finally:
            subprocess.run(['dropdb', database], env=env, check=True)
