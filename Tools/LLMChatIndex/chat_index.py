#!/usr/bin/env python3
"""Lightweight local chat archive and search tool."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import tempfile
import unicodedata
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Optional, Tuple


DEFAULT_CHAT_RELATIVE = Path("Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS")
DEFAULT_STATE_RELATIVE = Path("Library/Application Support/LLMChatIndexLite")


@dataclass(frozen=True)
class Message:
    role: str
    text: str
    timestamp: Optional[str] = None


@dataclass(frozen=True)
class Conversation:
    conversation_id: str
    source: str
    host_id: str
    source_path: Path
    title: str
    created_at: Optional[str]
    updated_at: Optional[str]
    messages: Tuple[Message, ...]


@dataclass(frozen=True)
class RenderedMarkdown:
    text: str
    content_hash: str


def _clean_text(value: object) -> str:
    if not isinstance(value, str):
        return ""
    value = unicodedata.normalize("NFC", value).replace("\r\n", "\n").replace("\r", "\n")
    value = "\n".join(line.rstrip() for line in value.split("\n")).strip()
    return re.sub(r"\n{4,}", "\n\n\n", value)


def _visible_content(content: object, role: str) -> str:
    if isinstance(content, str):
        return _clean_text(content)
    if not isinstance(content, list):
        return ""
    wanted = "input_text" if role == "user" else "output_text"
    allowed = {"text", wanted}
    parts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") in allowed:
            text = _clean_text(block.get("text"))
            if text:
                parts.append(text)
    return "\n\n".join(parts)


def _read_jsonl(path: Path) -> Iterable[dict]:
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                value = json.loads(line)
            except (json.JSONDecodeError, UnicodeError):
                continue
            if isinstance(value, dict):
                yield value


def _fallback_title(messages: Iterable[Message]) -> str:
    for message in messages:
        if message.role == "user" and message.text:
            return message.text.splitlines()[0][:120]
    return "Untitled conversation"


def parse_claude(path: Path, host_id: str) -> Conversation:
    session_id = path.stem
    title = ""
    messages = []
    for record in _read_jsonl(path):
        session_id = str(record.get("sessionId") or session_id)
        if record.get("type") == "custom-title":
            title = _clean_text(record.get("customTitle")) or title
            continue
        if record.get("type") == "ai-title" and not title:
            title = _clean_text(record.get("aiTitle"))
            continue
        if record.get("type") not in {"user", "assistant"} or record.get("isMeta"):
            continue
        message = record.get("message")
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        if role not in {"user", "assistant"}:
            continue
        text = _visible_content(message.get("content"), role)
        if text:
            messages.append(Message(role, text, record.get("timestamp")))
    created = next((m.timestamp for m in messages if m.timestamp), None)
    updated = next((m.timestamp for m in reversed(messages) if m.timestamp), created)
    return Conversation(
        "claude-code:" + session_id,
        "claude-code",
        host_id,
        path,
        title or _fallback_title(messages),
        created,
        updated,
        tuple(messages),
    )


def parse_codex(path: Path, host_id: str, titles: Mapping[str, str]) -> Conversation:
    session_id = path.stem
    messages = []
    for record in _read_codex_jsonl(path):
        payload = record.get("payload")
        if not isinstance(payload, dict):
            continue
        if record.get("type") == "session_meta":
            session_id = str(payload.get("id") or payload.get("session_id") or session_id)
            continue
        if record.get("type") != "response_item" or payload.get("type") != "message":
            continue
        role = payload.get("role")
        if role not in {"user", "assistant"}:
            continue
        text = _visible_content(payload.get("content"), role)
        if text:
            messages.append(Message(role, text, record.get("timestamp")))
    created = next((m.timestamp for m in messages if m.timestamp), None)
    updated = next((m.timestamp for m in reversed(messages) if m.timestamp), created)
    return Conversation(
        "codex:" + session_id,
        "codex",
        host_id,
        path,
        _clean_text(titles.get(session_id)) or _fallback_title(messages),
        created,
        updated,
        tuple(messages),
    )


def render_markdown(conversation: Conversation, imported_at: str) -> RenderedMarkdown:
    body_parts = ["# " + conversation.title.replace("\n", " ").strip(), ""]
    for message in conversation.messages:
        body_parts.append("## " + ("Запрос" if message.role == "user" else "Ответ"))
        body_parts.extend(["", message.text, ""])
    body = "\n".join(body_parts).rstrip() + "\n"
    content_hash = hashlib.sha256(body.encode("utf-8")).hexdigest()
    return RenderedMarkdown(body, content_hash)


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".tmp-", dir=str(path.parent), text=True)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.replace(temporary_name, path)
        except PermissionError:
            # Some macOS File Provider locations allow a background process to
            # create and edit files but reject replacing an existing item.
            with open(temporary_name, "rb") as source, path.open("wb") as destination:
                while True:
                    block = source.read(1024 * 1024)
                    if not block:
                        break
                    destination.write(block)
                destination.flush()
                os.fsync(destination.fileno())
            path.chmod(0o600)
            os.unlink(temporary_name)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise


def _load_json(path: Path, default: object) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return default


def _write_json_if_changed(path: Path, value: object) -> bool:
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    try:
        if path.read_text(encoding="utf-8") == text:
            return False
    except OSError:
        pass
    _atomic_write(path, text)
    return True


def load_titles(path: Path) -> Dict[str, str]:
    titles = {}
    if not path.is_file():
        return titles
    for record in _read_jsonl(path):
        session_id = record.get("id")
        title = record.get("thread_name")
        if isinstance(session_id, str) and isinstance(title, str) and title.strip():
            titles[session_id] = title.strip()
    return titles


def _read_codex_jsonl(path: Path) -> Iterable[dict]:
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            prefix = line[:2048]
            if '"type":"session_meta"' not in prefix and '"type": "session_meta"' not in prefix:
                if '"type":"response_item"' not in prefix and '"type": "response_item"' not in prefix:
                    continue
                payload_type = re.search(r'"payload"\s*:\s*\{\s*"type"\s*:\s*"([^"]+)"', prefix)
                if payload_type is None or payload_type.group(1) != "message":
                    continue
            try:
                value = json.loads(line)
            except (json.JSONDecodeError, UnicodeError):
                continue
            if isinstance(value, dict):
                yield value


def _safe_filename(conversation_id: str) -> str:
    raw = conversation_id.split(":", 1)[-1]
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", raw).strip("-.")
    if not safe or len(safe) > 140:
        safe = hashlib.sha256(conversation_id.encode("utf-8")).hexdigest()[:32]
    return safe + ".md"


def _codex_session_info(path: Path) -> Tuple[Optional[str], bool]:
    try:
        for index, record in enumerate(_read_codex_jsonl(path)):
            if record.get("type") == "session_meta" and isinstance(record.get("payload"), dict):
                payload = record["payload"]
                value = payload.get("id") or payload.get("session_id")
                return (str(value) if value else None, payload.get("source") == "vscode")
            if index >= 4:
                break
    except OSError:
        return (None, False)
    return (None, False)


def _source_paths(home: Path, codex_ids: Iterable[str]) -> List[Tuple[str, Path]]:
    found = []
    claude_root = home / ".claude/projects"
    if claude_root.is_dir():
        found.extend(
            ("claude-code", path)
            for path in claude_root.rglob("*.jsonl")
            if "subagents" not in path.parts
        )
    allowed_codex_ids = set(codex_ids)
    for root in (home / ".codex/sessions", home / ".codex/archived_sessions"):
        if root.is_dir():
            for path in root.rglob("*.jsonl"):
                session_id, is_user_session = _codex_session_info(path)
                if is_user_session or session_id in allowed_codex_ids:
                    found.append(("codex", path))
    return sorted(found, key=lambda item: (item[0], str(item[1])))


def _sync_unlocked(
    home: Path,
    chat_root: Path,
    state_root: Path,
    host_id: Optional[str] = None,
    imported_at: Optional[str] = None,
) -> Dict[str, int]:
    state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    host_file = state_root / "host-id"
    if host_id is None:
        try:
            host_id = host_file.read_text(encoding="utf-8").strip()
        except OSError:
            host_id = str(uuid.uuid4())
            _atomic_write(host_file, host_id + "\n")
    imported_at = imported_at or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    state_path = state_root / "state.json"
    loaded = _load_json(state_path, {"sources": {}})
    state = loaded if isinstance(loaded, dict) else {"sources": {}}
    entries = state.get("sources")
    if not isinstance(entries, dict):
        entries = {}
    titles = load_titles(home / ".codex/session_index.jsonl")
    current_paths = set()
    written = unchanged = errors = skipped = 0

    for source, path in _source_paths(home, titles):
        source_key = str(path)
        current_paths.add(source_key)
        try:
            stat = path.stat()
            fingerprint = [stat.st_size, stat.st_mtime_ns]
            previous = entries.get(source_key)
            needs_migration = False
            if isinstance(previous, dict) and isinstance(previous.get("output"), str):
                try:
                    with Path(previous["output"]).open("r", encoding="utf-8", errors="replace") as existing:
                        needs_migration = existing.readline() == "---\n"
                except OSError:
                    pass
            if isinstance(previous, dict) and previous.get("fingerprint") == fingerprint and not needs_migration:
                unchanged += 1
                continue
            conversation = (
                parse_claude(path, host_id)
                if source == "claude-code"
                else parse_codex(path, host_id, titles)
            )
            if not conversation.messages:
                skipped += 1
                entries[source_key] = {"source": source, "fingerprint": fingerprint, "status": "empty"}
                continue
            rendered = render_markdown(conversation, imported_at)
            output = chat_root / "_Unified" / source / host_id / _safe_filename(conversation.conversation_id)
            old_hash = previous.get("content_hash") if isinstance(previous, dict) else None
            if old_hash != rendered.content_hash or not output.is_file() or needs_migration:
                _atomic_write(output, rendered.text)
                written += 1
            else:
                unchanged += 1
            entries[source_key] = {
                "source": source,
                "fingerprint": fingerprint,
                "conversation_id": conversation.conversation_id,
                "content_hash": rendered.content_hash,
                "output": str(output),
                "status": "active",
            }
        except (OSError, ValueError, TypeError):
            errors += 1

    missing = 0
    for source_key, entry in entries.items():
        if source_key not in current_paths and isinstance(entry, dict) and entry.get("status") != "missing":
            entry["status"] = "missing"
            missing += 1

    state["schema"] = "llm-chat-lite-state/v1"
    state["host_id"] = host_id
    state["sources"] = entries
    _write_json_if_changed(state_path, state)
    manifest = {
        "schema": "llm-chat-lite-manifest/v1",
        "host_id": host_id,
        "conversations": sorted(
            [
                {
                    "id": entry.get("conversation_id"),
                    "source": entry.get("source"),
                    "path": entry.get("output"),
                    "content_hash": entry.get("content_hash"),
                    "status": entry.get("status"),
                }
                for entry in entries.values()
                if isinstance(entry, dict) and entry.get("conversation_id")
            ],
            key=lambda item: (str(item["source"]), str(item["id"]), str(item["path"])),
        ),
    }
    _write_json_if_changed(chat_root / "_Unified/_manifests" / (host_id + ".json"), manifest)
    return {
        "discovered": len(current_paths),
        "written": written,
        "unchanged": unchanged,
        "skipped": skipped,
        "errors": errors,
        "missing": missing,
        "locked": 0,
    }


def sync(
    home: Path,
    chat_root: Path,
    state_root: Path,
    host_id: Optional[str] = None,
    imported_at: Optional[str] = None,
) -> Dict[str, int]:
    state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state_root / "sync.lock").open("a+") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {
                "discovered": 0,
                "written": 0,
                "unchanged": 0,
                "skipped": 0,
                "errors": 0,
                "missing": 0,
                "locked": 1,
            }
        return _sync_unlocked(home, chat_root, state_root, host_id, imported_at)


def _title_from_markdown(text: str, fallback: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip() or fallback
    return fallback


def search_chats(chat_root: Path, query: str, limit: int = 10) -> List[Dict[str, object]]:
    tokens = list(dict.fromkeys(re.findall(r"[\w-]{2,}", query.casefold(), flags=re.UNICODE)))
    if not tokens:
        return []
    results = []
    for path in chat_root.rglob("*.md") if chat_root.is_dir() else ():
        if "_Tools" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        folded = text.casefold()
        words = re.findall(r"[\w-]{2,}", folded, flags=re.UNICODE)
        matches = {}
        for token in tokens:
            prefix = token[:5] if len(token) >= 6 else token
            matching_word = next((word for word in words if word.startswith(prefix)), None)
            if matching_word:
                matches[token] = matching_word
        matched = list(matches)
        required = len(tokens) if len(tokens) <= 3 else max(2, (len(tokens) * 3 + 4) // 5)
        if len(matched) < required:
            continue
        title = _title_from_markdown(text, path.stem)
        title_folded = title.casefold()
        score = sum(folded.count(matches[token][:5]) for token in matched) + 5 * sum(
            (token[:5] if len(token) >= 6 else token) in title_folded for token in tokens
        )
        phrase = query.casefold().strip()
        if phrase and phrase in folded:
            score += 20
        first_positions = [folded.find(matches[token][:5]) for token in matched]
        position = min(value for value in first_positions if value >= 0)
        start = max(0, position - 180)
        end = min(len(text), start + 500)
        excerpt = text[start:end].strip()
        results.append(
            {
                "score": score,
                "title": title,
                "path": str(path),
                "excerpt": excerpt,
            }
        )
    results.sort(key=lambda item: (-int(item["score"]), str(item["title"]), str(item["path"])))
    return results[: max(1, min(limit, 50))]


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Archive and search local Codex and Claude Code chats")
    default_home = Path.home()
    parser.add_argument("--home", type=Path, default=default_home)
    parser.add_argument("--chat-root", type=Path, default=default_home / DEFAULT_CHAT_RELATIVE)
    parser.add_argument("--state-root", type=Path, default=default_home / DEFAULT_STATE_RELATIVE)
    commands = parser.add_subparsers(dest="command", required=True)
    sync_parser = commands.add_parser("sync", help="Import changed local chats into iCloud Markdown")
    sync_parser.add_argument("--json", action="store_true")
    search_parser = commands.add_parser("search", help="Search all Markdown chats")
    search_parser.add_argument("query")
    search_parser.add_argument("--limit", type=int, default=10)
    search_parser.add_argument("--json", action="store_true")
    status_parser = commands.add_parser("status", help="Show local importer state")
    status_parser.add_argument("--json", action="store_true")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.command == "sync":
        result = sync(args.home, args.chat_root, args.state_root)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        else:
            print(
                "Imported {written}; unchanged {unchanged}; skipped {skipped}; errors {errors}; missing {missing}.".format(
                    **result
                )
            )
        return 1 if result["errors"] else 0
    if args.command == "search":
        results = search_chats(args.chat_root, args.query, args.limit)
        if args.json:
            print(json.dumps(results, ensure_ascii=False, indent=2))
        elif not results:
            print("Nothing found.")
        else:
            for index, result in enumerate(results, 1):
                print("{0}. {1}\n   {2}\n   {3}\n".format(index, result["title"], result["path"], result["excerpt"]))
        return 0
    loaded = _load_json(args.state_root / "state.json", {})
    state = loaded if isinstance(loaded, dict) else {}
    entries = state.get("sources", {}) if isinstance(state.get("sources", {}), dict) else {}
    statuses = {}
    by_source = {}
    for entry in entries.values():
        if isinstance(entry, dict):
            status = str(entry.get("status", "unknown"))
            statuses[status] = statuses.get(status, 0) + 1
            source = str(entry.get("source", "unknown"))
            by_source[source] = by_source.get(source, 0) + 1
    result = {
        "host_id": state.get("host_id"),
        "chat_root": str(args.chat_root),
        "sources": len(entries),
        "by_source": by_source,
        "statuses": statuses,
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    else:
        print("Host: {0}\nChats: {1}\nSources: {2}\nBy source: {3}\nStatuses: {4}".format(result["host_id"] or "not initialized", result["chat_root"], result["sources"], result["by_source"], result["statuses"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
