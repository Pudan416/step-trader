# LLM Chat Ingestion and iCloud Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert new Claude Code and Codex transcripts into stable, readable Markdown under the shared iCloud `LLM CHATS/_Unified` store without modifying source logs or duplicating unchanged conversations.

**Architecture:** A standalone Python package reads each product through a source adapter, normalizes only visible user/assistant text, and writes one atomic Markdown file per stable conversation. A generated host ID owns one iCloud namespace and manifest; a local state file stores parsing checkpoints and failures. This plan deliberately stops at the portable archive boundary—SQLite, embeddings, MCP, and installation are later plans.

**Tech Stack:** Python 3.11+, standard library (`argparse`, `dataclasses`, `hashlib`, `json`, `pathlib`, `tempfile`, `unittest`), `uv` for the reproducible environment, Markdown with YAML-compatible frontmatter.

**Spec:** `docs/superpowers/specs/2026-09-08-local-llm-chat-knowledge-base-design.md`

## Global Constraints

- Treat `~/.claude/projects`, `~/.codex/sessions`, `~/.codex/archived_sessions`, and `~/.codex/session_index.jsonl` as read-only forensic sources.
- Write generated conversations only below `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS/_Unified/<source>/<host-id>/`.
- Keep mutable checkpoints, locks, logs, and errors outside iCloud under `~/Library/Application Support/LLMChatIndex`.
- Preserve a normalized conversation when its source disappears; mark it missing in the manifest instead of deleting it.
- Exclude system/meta records, hidden thinking, tool calls/results, command output, and attachment bodies.
- Use sibling temporary files, `fsync`, mode `0600`, and `os.replace` for every generated conversation, local state file, and manifest.
- Preserve unrelated working-tree changes. Stage only `Tools/LLMChatIndex` and this plan's named tests/docs.
- Run focused tests after every red/green step and the complete ingestion suite before each task commit.

---

## Task 1: Scaffold the package and resolve deterministic paths

**Files:**

- Create: `Tools/LLMChatIndex/pyproject.toml`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/__init__.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/config.py`
- Create: `Tools/LLMChatIndex/tests/test_config.py`

- [ ] **Step 1: Write failing configuration tests**

Test the public contract:

~~~python
from pathlib import Path
from llm_chat_index.config import AppPaths, load_or_create_host_id

paths = AppPaths.for_home(Path("/Users/tester"))
assert paths.chat_root == Path("/Users/tester/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS")
assert paths.unified_root == paths.chat_root / "_Unified"
assert paths.state_root == Path("/Users/tester/Library/Application Support/LLMChatIndex")
assert paths.claude_projects == Path("/Users/tester/.claude/projects")
assert paths.codex_live == Path("/Users/tester/.codex/sessions")
assert paths.codex_archived == Path("/Users/tester/.codex/archived_sessions")
~~~

Also assert that `load_or_create_host_id(path)` creates a lowercase UUID once, returns the same value on the second call, rejects malformed existing text, and creates the file with mode `0600`.

Run:

~~~bash
cd Tools/LLMChatIndex
python3 -m unittest tests.test_config -v
~~~

Expected: FAIL because the package does not exist.

- [ ] **Step 2: Add the minimal package configuration**

Set `requires-python = ">=3.11"`, use a `src/` layout, and expose one console script:

~~~toml
[project.scripts]
chat-index = "llm_chat_index.cli:main"
~~~

Do not add third-party runtime dependencies in this plan.

- [ ] **Step 3: Implement `AppPaths` and host identity**

Use an immutable dataclass. Support explicit path overrides in tests and environment overrides named `LLM_CHAT_ROOT` and `LLM_CHAT_STATE_ROOT`; never reinterpret `HOME`. Create the state directory with mode `0700`. Create `host-id` by atomically writing `str(uuid.uuid4()) + "\n"`.

- [ ] **Step 4: Run the focused test**

Expected: PASS on Python 3.11 or newer.

- [ ] **Step 5: Commit the scaffold**

~~~bash
git add Tools/LLMChatIndex/pyproject.toml Tools/LLMChatIndex/src/llm_chat_index/__init__.py Tools/LLMChatIndex/src/llm_chat_index/config.py Tools/LLMChatIndex/tests/test_config.py
git commit -m "build: scaffold local chat archive importer"
~~~

## Task 2: Define the normalized conversation contract and atomic writer

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/models.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/markdown.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/atomic.py`
- Create: `Tools/LLMChatIndex/tests/test_markdown.py`
- Create: `Tools/LLMChatIndex/tests/fixtures/normalized_conversation.md`

- [ ] **Step 1: Test the pure model and exact serialized form**

Define and test these immutable interfaces:

~~~python
@dataclass(frozen=True)
class VisibleMessage:
    role: Literal["user", "assistant"]
    text: str
    timestamp: datetime | None
    attachments: tuple[AttachmentRef, ...] = ()

@dataclass(frozen=True)
class Conversation:
    stable_id: str
    source: Literal["claude-code", "codex"]
    host_id: str
    source_path: Path
    title: str
    created_at: datetime | None
    updated_at: datetime | None
    messages: tuple[VisibleMessage, ...]
~~~

Assert that rendering emits the required `llm-chat/v1` frontmatter, a deterministic `content_hash`, headings for visible messages, normalized LF newlines, escaped scalar values, and no absolute source content beyond the `source_path` field. Compare the complete output with the fixture.

Run `python3 -m unittest tests.test_markdown -v`; expected FAIL.

- [ ] **Step 2: Implement normalization and hashing**

Normalize Unicode to NFC, convert CRLF/CR to LF, trim trailing whitespace per line, collapse more than three blank lines to two, and reject empty messages. Compute SHA-256 from the canonical message body—not `imported_at`—so a no-op sync remains byte-for-byte unchanged.

- [ ] **Step 3: Implement dependency-free frontmatter rendering**

Emit frontmatter fields in this order: `schema`, `id`, `title`, `source`, `host_id`, `source_path`, `created_at`, `updated_at`, `imported_at`, `message_count`, `content_hash`. Quote all strings with JSON string syntax, which YAML accepts. Render message headings as `## User` and `## Assistant`, adding an ISO-8601 timestamp on the next italicized line when present.

- [ ] **Step 4: Test atomic file replacement**

Patch `os.replace` to fail and assert the old destination survives intact and the temporary sibling is removed. On success assert the destination is mode `0600`, its directory is `0700`, and no `.tmp-*` file remains.

- [ ] **Step 5: Implement `atomic_write_text` and rerun tests**

Expected: all model, renderer, and failure-path tests PASS.

- [ ] **Step 6: Commit the normalized boundary**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/models.py Tools/LLMChatIndex/src/llm_chat_index/markdown.py Tools/LLMChatIndex/src/llm_chat_index/atomic.py Tools/LLMChatIndex/tests/test_markdown.py Tools/LLMChatIndex/tests/fixtures/normalized_conversation.md
git commit -m "feat: define normalized chat markdown contract"
~~~

## Task 3: Parse Claude Code transcripts without technical payloads

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/sources/__init__.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/sources/claude_code.py`
- Create: `Tools/LLMChatIndex/tests/test_claude_code.py`
- Create: `Tools/LLMChatIndex/tests/fixtures/claude_code/session.jsonl`
- Create: `Tools/LLMChatIndex/tests/fixtures/claude_code/subagent.jsonl`

- [ ] **Step 1: Capture representative JSONL variants in synthetic fixtures**

Include user text, assistant text blocks, an assistant `thinking` block, `tool_use`, `tool_result`, command output, a content array, a duplicate streamed partial followed by its final message, an attachment reference, malformed JSON, and a subagent transcript. Use invented text only; never commit real chats.

- [ ] **Step 2: Write failing discovery and extraction tests**

The adapter interface is:

~~~python
def discover(root: Path) -> list[Path]: ...
def parse(path: Path, host_id: str) -> Conversation: ...
~~~

Assert deterministic path ordering, stable ID `claude-code:<session-uuid>`, visible message order, title derived from the first non-empty user line (maximum 120 characters), timestamp bounds, attachment metadata only, and complete absence of fixture thinking/tool/output sentinel strings. `discover` must ignore `subagents/` paths in v1.

Run `python3 -m unittest tests.test_claude_code -v`; expected FAIL.

- [ ] **Step 3: Implement tolerant Claude Code parsing**

Parse JSONL line-by-line. Continue past malformed lines while returning structured warnings. Accept visible strings and `type == "text"` content blocks only. Treat the final assistant record for a message UUID as authoritative; otherwise keep only the longest monotonically growing streamed value. Do not deserialize or log excluded payload bodies.

- [ ] **Step 4: Make the tests pass and inspect the rendered fixture**

Run the test plus `python3 -m unittest discover -s tests -v`. Expected: PASS and no technical sentinel in generated Markdown.

- [ ] **Step 5: Commit the Claude Code adapter**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/sources Tools/LLMChatIndex/tests/test_claude_code.py Tools/LLMChatIndex/tests/fixtures/claude_code
git commit -m "feat: import visible Claude Code conversations"
~~~

## Task 4: Parse live and archived Codex transcripts

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/sources/codex.py`
- Create: `Tools/LLMChatIndex/tests/test_codex.py`
- Create: `Tools/LLMChatIndex/tests/fixtures/codex/session.jsonl`
- Create: `Tools/LLMChatIndex/tests/fixtures/codex/session_index.jsonl`

- [ ] **Step 1: Write synthetic Codex fixtures and failing tests**

Cover `session_meta`, `response_item` user/assistant messages, developer/system content, reasoning summaries, function/tool calls and outputs, duplicated event projections, malformed JSON, and title metadata. The adapter contract is:

~~~python
def load_titles(index_path: Path) -> dict[str, str]: ...
def discover(live_root: Path, archived_root: Path) -> list[Path]: ...
def parse(path: Path, host_id: str, titles: Mapping[str, str]) -> Conversation: ...
~~~

Assert stable ID `codex:<session-uuid>`, preference for `session_index.jsonl` title, fallback first-user title, archive/live discovery without duplicate paths, and exclusion of all technical sentinels.

Run `python3 -m unittest tests.test_codex -v`; expected FAIL.

- [ ] **Step 2: Implement Codex title and transcript parsing**

Read only JSONL and the title index. Never open `~/.codex/*.sqlite`. Deduplicate repeated projections using `(role, normalized_text, timestamp)` while preserving genuinely repeated user messages at different event IDs or times.

- [ ] **Step 3: Verify schema drift is non-fatal**

Unknown record types must increment a warning count and be skipped. A transcript with no visible messages returns a typed `EmptyConversationError`, which the orchestrator can report without stopping other imports.

- [ ] **Step 4: Run focused and complete ingestion tests**

Expected: PASS; no system/developer/reasoning/tool sentinel appears in any rendered output.

- [ ] **Step 5: Commit the Codex adapter**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/sources/codex.py Tools/LLMChatIndex/tests/test_codex.py Tools/LLMChatIndex/tests/fixtures/codex
git commit -m "feat: import visible Codex conversations"
~~~

## Task 5: Add idempotent sync, state, manifests, and locking

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/state.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/manifest.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/locking.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/sync.py`
- Create: `Tools/LLMChatIndex/tests/test_sync.py`

- [ ] **Step 1: Write failing end-to-end sync tests in temporary homes**

Assert the first sync creates source/host directories, normalized files, local `state.json`, and `_manifests/<host-id>.json`; the second unchanged sync reports zero writes and preserves file mtimes; append updates exactly one conversation; truncation/rewrite reparses it; malformed input does not block good files; source deletion marks `status: "missing"` and retains Markdown; two host IDs never write the same manifest or conversation path.

Run `python3 -m unittest tests.test_sync -v`; expected FAIL.

- [ ] **Step 2: Define state and manifest version 1**

State entries contain `source_path`, `source`, `size`, `mtime_ns`, `last_safe_offset`, `stable_id`, `content_hash`, `status`, `last_seen_at`, and bounded warning/error summaries. The host manifest contains `schema: llm-chat-manifest/v1`, `host_id`, `updated_at`, and deterministic conversation entries sorted by `(source, stable_id, path)`.

- [ ] **Step 3: Implement one-process locking and transactional publication**

Acquire an exclusive non-blocking `fcntl.flock` on `state_root/sync.lock`. Parse all changed inputs first, atomically publish successful conversations, then atomically update local state, and update the host manifest last. A partial failure must never advertise an unpublished file.

- [ ] **Step 4: Implement append/rewrite classification**

Skip when size and `mtime_ns` match. Treat growth as append-only only when the prefix fingerprint and stored safe newline offset match; otherwise reparse the full file. The v1 parser may re-render the whole conversation after incremental reading—the optimization is avoiding rereading a verified prefix, not patching Markdown in place.

- [ ] **Step 5: Make sync tests pass**

Assert the JSON state contains no message bodies. Run `python3 -m unittest discover -s tests -v`; expected PASS.

- [ ] **Step 6: Commit the synchronization engine**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/state.py Tools/LLMChatIndex/src/llm_chat_index/manifest.py Tools/LLMChatIndex/src/llm_chat_index/locking.py Tools/LLMChatIndex/src/llm_chat_index/sync.py Tools/LLMChatIndex/tests/test_sync.py
git commit -m "feat: synchronize chat archives idempotently"
~~~

## Task 6: Expose sync/status CLI and run read-only real-data acceptance

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/cli.py`
- Create: `Tools/LLMChatIndex/tests/test_cli_ingestion.py`
- Create: `Tools/LLMChatIndex/scripts/accept_ingestion.py`
- Create: `Tools/LLMChatIndex/README.md`

- [ ] **Step 1: Write failing CLI tests**

Test `chat-index sync --json`, `chat-index status --json`, `--chat-root`, `--state-root`, and `--dry-run`. JSON output must include discovered/imported/updated/unchanged/error/missing counts by source and contain no chat body text. Human output must name the host ID, iCloud root, last success, and error count.

- [ ] **Step 2: Implement CLI wiring and exit codes**

Return `0` for success, `2` when another sync holds the lock, and `1` when one or more files failed while allowing successful files to publish. `--dry-run` performs parsing and reports proposed paths but writes nothing.

- [ ] **Step 3: Add a read-only acceptance script**

The script hashes source files before and after, runs import against a temporary chat/state root, asserts hashes are identical, reports discovered versus successfully normalized counts, scans outputs for fixture-independent technical record markers, and performs a second no-op sync. It must print counts and paths, never message bodies.

- [ ] **Step 4: Run acceptance on this Mac**

Run:

~~~bash
cd Tools/LLMChatIndex
python3 scripts/accept_ingestion.py --home /Users/kosta
~~~

Expected baseline: discovery sees the locally available Claude Code main-session JSONL files plus approximately 790 Codex live/archived JSONL files; exact counts may increase while the apps are used. The source before/after hashes must match and the second sync must write zero conversations.

- [ ] **Step 5: Run the real sync into iCloud**

First run `chat-index sync --dry-run`, inspect every destination, then run `chat-index sync`. Confirm generated Markdown is below `_Unified` and the existing `Claude Official Export 2026-09-08` directory is untouched.

- [ ] **Step 6: Run all tests and commit**

~~~bash
cd Tools/LLMChatIndex
python3 -m unittest discover -s tests -v
git add Tools/LLMChatIndex/src/llm_chat_index/cli.py Tools/LLMChatIndex/tests/test_cli_ingestion.py Tools/LLMChatIndex/scripts/accept_ingestion.py Tools/LLMChatIndex/README.md
git commit -m "feat: expose local chat archive sync commands"
~~~

## Plan Verification

- [ ] Compare every generated frontmatter field and path with the design spec.
- [ ] Confirm tests prove source deletion preserves the normalized archive.
- [ ] Confirm a no-op sync preserves bytes and mtimes.
- [ ] Confirm no real transcript, secret, OAuth value, or machine configuration is committed.
- [ ] Confirm original Claude Code/Codex files are unchanged after acceptance.
- [ ] Record the actual imported, skipped, warning, and error counts before beginning the search-index plan.
