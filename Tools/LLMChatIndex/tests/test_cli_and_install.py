import contextlib
import io
import json
import plistlib
import tempfile
import unittest
from pathlib import Path


class CliAndInstallTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self):
        self.tempdir.cleanup()

    def test_cli_sync_and_search_emit_machine_readable_results(self):
        from chat_index import main

        home = self.root / "home"
        source = home / ".claude/projects/p/session.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text(
            json.dumps({"type": "user", "sessionId": "s1", "message": {"role": "user", "content": "Локальный архив заметок"}}) + "\n",
            encoding="utf-8",
        )
        chat_root = self.root / "LLM CHATS"
        state_root = self.root / "state"
        common = ["--home", str(home), "--chat-root", str(chat_root), "--state-root", str(state_root)]

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(main(common + ["sync", "--json"]), 0)
        self.assertEqual(json.loads(output.getvalue())["written"], 1)

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(main(common + ["search", "локальные заметки", "--json"]), 0)
        results = json.loads(output.getvalue())
        self.assertEqual(len(results), 1)
        self.assertTrue(Path(results[0]["path"]).is_file())

    def test_installer_creates_local_runtime_launch_agent_and_icloud_copy(self):
        from install_lite import install

        home = self.root / "home"
        chat_root = self.root / "LLM CHATS"
        source_dir = Path(__file__).resolve().parents[1]

        result = install(source_dir, home, chat_root, load_agent=False)

        runtime_script = home / ".local/share/llm-chat-index-lite/chat_index.py"
        launcher = home / ".local/bin/chat-index"
        plist_path = home / "Library/LaunchAgents/com.kostapudan.llm-chat-index-lite.plist"
        shared_installer = chat_root / "_Tools/LLMChatIndexLite/install_lite.py"
        self.assertTrue(runtime_script.is_file())
        self.assertTrue(launcher.is_file())
        self.assertTrue(shared_installer.is_file())
        plist = plistlib.loads(plist_path.read_bytes())
        self.assertTrue(plist["RunAtLoad"])
        self.assertEqual(plist["StartInterval"], 300)
        self.assertIn(str(runtime_script), plist["ProgramArguments"])
        self.assertEqual(result["loaded"], False)

    def test_installer_cli_does_not_enable_background_access_without_explicit_flag(self):
        from install_lite import main

        home = self.root / "home"
        chat_root = self.root / "LLM CHATS"
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = main(["--home", str(home), "--chat-root", str(chat_root)])

        self.assertEqual(exit_code, 0)
        printed = output.getvalue()
        self.assertEqual(json.loads(printed[printed.index("{") :])["loaded"], False)


if __name__ == "__main__":
    unittest.main()
