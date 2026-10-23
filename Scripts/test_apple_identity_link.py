#!/usr/bin/env python3
"""Execute production Apple exchange and link-context logic without Keychain or network."""
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
    return source[start:end]


@unittest.skipUnless(shutil.which('swiftc'), 'Swift is required')
class AppleIdentityLinkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='nowhere-apple-link-')
        cls.addClassCleanup(cls.directory.cleanup)
        folder = Path(cls.directory.name)
        rest = (ROOT / 'Nowhere/Services/AuthenticationService+SupabaseREST.swift').read_text()
        core = (ROOT / 'Nowhere/Services/AuthenticationService.swift').read_text()
        dto = (ROOT / 'Nowhere/Services/AuthSupportTypes.swift').read_text()
        source = (ROOT / 'Scripts/Fixtures/AppleIdentityLinkHarness.swift').read_text()
        source = source.replace('/*__DTO__*/', '\n'.join(declaration(dto, marker) for marker in [
            'enum AuthError:', 'struct SupabaseIdTokenGrantRequest:',
            'struct SupabaseAuthUser:', 'struct SupabaseSessionResponse:'
        ]))
        for key, value in [
            ('EXCHANGE', declaration(rest, '    func supabaseSignInWithApple(')),
            ('REQUEST', declaration(rest, '    func makeJSONRequest(')),
            ('CONTEXT', declaration(core, '    func anonymousAppleLinkContext(') if '    func anonymousAppleLinkContext(' in core else ''),
        ]:
            source = source.replace('/*__' + key + '__*/', value)
        swift = folder / 'main.swift'
        swift.write_text(source)
        cls.binary = folder / 'check'
        result = subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(folder / 'modules'), str(swift), '-o', str(cls.binary)], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_anonymous_upgrade_keeps_uid_and_uses_refreshed_bearer(self): self.run_case('new')
    def test_existing_apple_identity_falls_back_to_normal_sign_in(self): self.run_case('existing')
    def test_registered_account_relogin_does_not_link(self): self.run_case('registered')
    def test_missing_anonymous_session_cannot_fork_user(self): self.run_case('missing')
    def test_refresh_failure_cannot_fork_user(self): self.run_case('refresh-failure')
    def test_refresh_owner_mismatch_cannot_link(self): self.run_case('refresh-owner')
    def test_link_response_cannot_change_uid(self): self.run_case('fork')
    def test_arbitrary_422_does_not_fall_back(self): self.run_case('other-422')
    def test_link_transport_error_does_not_fall_back(self): self.run_case('transport')
    def test_identity_switch_during_refresh_aborts_exchange(self): self.run_case('switch')
    def test_identity_switch_during_link_aborts_response(self): self.run_case('link-switch')
    def test_signed_out_login_uses_normal_exchange(self): self.run_case('signed-out')
    def test_pending_initialization_cannot_fork_stored_guest(self): self.run_case('initializing')
    def test_unpublished_stored_guest_is_still_linked(self): self.run_case('unpublished')
    def test_published_and_stored_owners_must_agree(self): self.run_case('conflicting-owner')


if __name__ == '__main__': unittest.main()
