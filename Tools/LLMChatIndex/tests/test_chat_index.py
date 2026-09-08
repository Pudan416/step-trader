import json
import os
import fcntl
import tempfile
import time
import unittest
from unittest import mock
from pathlib import Path


class ChatIndexTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self):
        self.tempdir.cleanup()

    def write_jsonl(self, relative_path, records):
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
            encoding="utf-8",
        )
        return path

    def test_claude_parser_keeps_visible_dialogue_and_drops_technical_blocks(self):
        from chat_index import parse_claude

        path = self.write_jsonl(
            "claude/session.jsonl",
            [
                {"type": "custom-title", "sessionId": "claude-1", "customTitle": "Важный разговор"},
                {
                    "type": "user",
                    "sessionId": "claude-1",
                    "uuid": "u1",
                    "timestamp": "2026-09-01T10:00:00Z",
                    "message": {"role": "user", "content": "Как устроить архив?"},
                },
                {
                    "type": "assistant",
                    "sessionId": "claude-1",
                    "uuid": "a1",
                    "timestamp": "2026-09-01T10:00:01Z",
                    "message": {
                        "role": "assistant",
                        "content": [
                            {"type": "thinking", "thinking": "HIDDEN_SENTINEL"},
                            {"type": "tool_use", "name": "Shell", "input": {"command": "TOOL_SENTINEL"}},
                            {"type": "text", "text": "Сохранять читаемый Markdown."},
                        ],
                    },
                },
                {
                    "type": "user",
                    "sessionId": "claude-1",
                    "uuid": "tool-result",
                    "timestamp": "2026-09-01T10:00:02Z",
                    "message": {
                        "role": "user",
                        "content": [{"type": "tool_result", "content": "RESULT_SENTINEL"}],
                    },
                },
            ],
        )

        conversation = parse_claude(path, "host-a")

        self.assertEqual(conversation.conversation_id, "claude-code:claude-1")
        self.assertEqual(conversation.title, "Важный разговор")
        self.assertEqual(
            [(message.role, message.text) for message in conversation.messages],
            [
                ("user", "Как устроить архив?"),
                ("assistant", "Сохранять читаемый Markdown."),
            ],
        )
        self.assertNotIn("SENTINEL", "\n".join(message.text for message in conversation.messages))

    def test_codex_parser_uses_title_index_and_only_message_items(self):
        from chat_index import parse_codex

        path = self.write_jsonl(
            "codex/session.jsonl",
            [
                {"type": "session_meta", "timestamp": "2026-09-02T10:00:00Z", "payload": {"id": "codex-1"}},
                {
                    "type": "response_item",
                    "timestamp": "2026-09-02T10:00:01Z",
                    "payload": {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": "Найди старое решение"}],
                    },
                },
                {
                    "type": "response_item",
                    "timestamp": "2026-09-02T10:00:02Z",
                    "payload": {
                        "type": "reasoning",
                        "summary": [{"type": "summary_text", "text": "REASONING_SENTINEL"}],
                    },
                },
                {
                    "type": "response_item",
                    "timestamp": "2026-09-02T10:00:03Z",
                    "payload": {
                        "type": "message",
                        "role": "assistant",
                        "content": [{"type": "output_text", "text": "Вот нужный подход."}],
                    },
                },
                {
                    "type": "response_item",
                    "timestamp": "2026-09-02T10:00:04Z",
                    "payload": {"type": "function_call_output", "output": "OUTPUT_SENTINEL"},
                },
            ],
        )

        conversation = parse_codex(path, "host-a", {"codex-1": "Архив решений"})

        self.assertEqual(conversation.conversation_id, "codex:codex-1")
        self.assertEqual(conversation.title, "Архив решений")
        self.assertEqual(
            [(message.role, message.text) for message in conversation.messages],
            [("user", "Найди старое решение"), ("assistant", "Вот нужный подход.")],
        )

    def test_render_markdown_contains_only_title_requests_and_answers(self):
        from chat_index import Conversation, Message, render_markdown

        conversation = Conversation(
            conversation_id="codex:id-1",
            source="codex",
            host_id="host-a",
            source_path=Path("/tmp/source.jsonl"),
            title="План: локально",
            created_at="2026-09-02T10:00:00Z",
            updated_at="2026-09-02T10:00:03Z",
            messages=(
                Message("user", "Первый вопрос", "2026-09-02T10:00:01Z"),
                Message("assistant", "Первый ответ", "2026-09-02T10:00:03Z"),
            ),
        )

        first = render_markdown(conversation, "2026-09-08T12:00:00Z")
        second = render_markdown(conversation, "2026-09-09T12:00:00Z")

        self.assertEqual(first.content_hash, second.content_hash)
        self.assertTrue(first.text.startswith("# План: локально\n"))
        self.assertIn("# План: локально", first.text)
        self.assertIn("## Запрос", first.text)
        self.assertIn("## Ответ", first.text)
        self.assertIn("Первый ответ", first.text)
        self.assertNotIn("llm-chat/v1", first.text)
        self.assertNotIn("source_path", first.text)
        self.assertNotIn("2026-09-02", first.text)
        self.assertNotIn("codex:id-1", first.text)

    def test_sync_writes_each_source_once_and_preserves_archive_when_source_disappears(self):
        from chat_index import sync

        home = self.root / "home"
        chat_root = self.root / "icloud" / "LLM CHATS"
        state_root = self.root / "state"
        claude_path = home / ".claude/projects/project/session.jsonl"
        claude_path.parent.mkdir(parents=True)
        claude_path.write_text(
            "\n".join(
                [
                    json.dumps({"type": "custom-title", "sessionId": "c1", "customTitle": "Claude title"}),
                    json.dumps(
                        {
                            "type": "user",
                            "sessionId": "c1",
                            "timestamp": "2026-09-01T10:00:00Z",
                            "message": {"role": "user", "content": "Claude visible"},
                        }
                    ),
                ]
            )
            + "\n"
        )
        codex_path = home / ".codex/sessions/2026/09/session.jsonl"
        codex_path.parent.mkdir(parents=True)
        codex_path.write_text(
            "\n".join(
                [
                    json.dumps({"type": "session_meta", "payload": {"id": "x1"}}),
                    json.dumps(
                        {
                            "type": "response_item",
                            "timestamp": "2026-09-02T10:00:00Z",
                            "payload": {
                                "type": "message",
                                "role": "user",
                                "content": [{"type": "input_text", "text": "Codex visible"}],
                            },
                        }
                    ),
                ]
            )
            + "\n"
        )
        (home / ".codex/session_index.jsonl").write_text(
            json.dumps({"id": "x1", "thread_name": "Indexed task"}) + "\n",
            encoding="utf-8",
        )
        internal_path = home / ".codex/sessions/2026/09/internal.jsonl"
        internal_path.write_text(
            "\n".join(
                [
                    json.dumps({"type": "session_meta", "payload": {"id": "internal-1"}}),
                    json.dumps(
                        {
                            "type": "response_item",
                            "payload": {
                                "type": "message",
                                "role": "assistant",
                                "content": [{"type": "output_text", "text": "Internal agent output"}],
                            },
                        }
                    ),
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        unindexed_main_path = home / ".codex/sessions/2026/09/unindexed-main.jsonl"
        unindexed_main_path.write_text(
            "\n".join(
                [
                    json.dumps(
                        {
                            "type": "session_meta",
                            "payload": {"id": "main-without-title", "source": "vscode", "originator": "Codex Desktop"},
                        }
                    ),
                    json.dumps(
                        {
                            "type": "response_item",
                            "payload": {
                                "type": "message",
                                "role": "user",
                                "content": [{"type": "input_text", "text": "Visible unindexed Codex task"}],
                            },
                        }
                    ),
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        first = sync(home, chat_root, state_root, host_id="host-a", imported_at="2026-09-08T12:00:00Z")
        outputs = sorted((chat_root / "_Unified").rglob("*.md"))
        self.assertEqual(first["written"], 3)
        self.assertEqual(len(outputs), 3)
        self.assertIn("Claude visible", "\n".join(path.read_text() for path in outputs))
        self.assertIn("Visible unindexed Codex task", "\n".join(path.read_text() for path in outputs))
        mtimes = {path: path.stat().st_mtime_ns for path in outputs}

        time.sleep(0.01)
        second = sync(home, chat_root, state_root, host_id="host-a", imported_at="2026-09-09T12:00:00Z")
        self.assertEqual(second["written"], 0)
        self.assertEqual(mtimes, {path: path.stat().st_mtime_ns for path in outputs})

        claude_path.unlink()
        third = sync(home, chat_root, state_root, host_id="host-a", imported_at="2026-09-10T12:00:00Z")
        self.assertEqual(third["missing"], 1)
        self.assertEqual(len(list((chat_root / "_Unified").rglob("*.md"))), 3)

    def test_search_ranks_matching_markdown_and_returns_a_bounded_excerpt(self):
        from chat_index import search_chats

        chat_root = self.root / "LLM CHATS"
        (chat_root / "Claude Official Export").mkdir(parents=True)
        (chat_root / "Claude Official Export/one.md").write_text(
            "# Архив решений\n\nОбсуждали синхронизацию истории через iCloud и Markdown.\n",
            encoding="utf-8",
        )
        (chat_root / "Claude Official Export/two.md").write_text(
            "# Рецепт\n\nОбсуждали кофе и завтрак.\n",
            encoding="utf-8",
        )

        results = search_chats(chat_root, "история iCloud", limit=5)

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["title"], "Архив решений")
        self.assertLessEqual(len(results[0]["excerpt"]), 500)
        self.assertTrue(Path(results[0]["path"]).is_file())

    def test_sync_exits_cleanly_when_another_sync_holds_the_lock(self):
        from chat_index import sync

        state_root = self.root / "state"
        state_root.mkdir()
        lock_path = state_root / "sync.lock"
        with lock_path.open("w") as held_lock:
            fcntl.flock(held_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = sync(self.root / "home", self.root / "chats", state_root, host_id="host-a")

        self.assertEqual(result["locked"], 1)
        self.assertEqual(result["written"], 0)

    def test_sync_rewrites_legacy_markdown_that_contains_service_frontmatter(self):
        from chat_index import sync

        home = self.root / "home"
        source = home / ".claude/projects/p/session.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text(
            json.dumps({"type": "user", "sessionId": "s1", "message": {"role": "user", "content": "Чистый диалог"}}) + "\n",
            encoding="utf-8",
        )
        chat_root = self.root / "chats"
        state_root = self.root / "state"
        sync(home, chat_root, state_root, host_id="host-a")
        output = next((chat_root / "_Unified").rglob("*.md"))
        output.write_text('---\nschema: "llm-chat/v1"\nsource_path: "/tmp/source"\n---\n' + output.read_text(), encoding="utf-8")

        result = sync(home, chat_root, state_root, host_id="host-a")

        self.assertEqual(result["written"], 1)
        self.assertTrue(output.read_text(encoding="utf-8").startswith("# "))
        self.assertNotIn("source_path", output.read_text(encoding="utf-8"))

    def test_atomic_writer_falls_back_when_icloud_rejects_replacement(self):
        from chat_index import _atomic_write

        destination = self.root / "iCloud" / "chat.md"
        destination.parent.mkdir()
        destination.write_text("old", encoding="utf-8")

        with mock.patch("chat_index.os.replace", side_effect=PermissionError("provider rejected replace")):
            _atomic_write(destination, "new content")

        self.assertEqual(destination.read_text(encoding="utf-8"), "new content")
        self.assertEqual(list(destination.parent.glob(".tmp-*")), [])


if __name__ == "__main__":
    unittest.main()
