# LLM Chat MCP and Two-Mac Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the local chat archive available to Codex and Claude Code through one stdio MCP server, automatically refresh it every five minutes, and install the same private setup safely on both Apple Silicon Macs.

**Architecture:** The official Python MCP SDK wraps the tested search service with four bounded read-only tools. A reversible installer copies the locked runtime into `~/.local/share/llm-chat-index`, installs a `~/.local/bin/chat-index` launcher, edits each agent's existing MCP configuration without replacing unrelated entries, installs a per-user LaunchAgent, pins the local model snapshot, and verifies privacy plus retrieval. iCloud carries only Markdown and manifests; each Mac owns its local runtime/index/model/state.

**Tech Stack:** Python 3.11+, official MCP Python SDK v2 over stdio, `uv`, macOS `launchd`, JSON/TOML configuration editing, SQLite/FTS5, local ONNX embeddings.

**Spec:** `docs/superpowers/specs/2026-09-08-local-llm-chat-knowledge-base-design.md`

## Global Constraints

- Complete both ingestion and hybrid-search plans first.
- MCP is stdio-only and must not bind a TCP/Unix listening socket or make HTTP requests during queries.
- Tool responses are bounded and evidence-only; the calling agent synthesizes answers.
- Install into `~/.local/share/llm-chat-index`; put only the launcher in `~/.local/bin`; keep state under `~/Library/Application Support/LLMChatIndex`.
- Preserve all existing Codex and Claude configuration keys. Back up changed files before atomic replacement and support dry-run plus uninstall.
- Use MCP server name `local-chat-history` in both products.
- Run at login and every 300 seconds. A single lock must make overlapping manual/LaunchAgent syncs harmless.
- The installer must show exact paths it will modify before applying them and never print secrets from existing config.
- The second Mac must generate its own host ID and local index; never copy the first Mac's state directory.

---

## Task 1: Expose four bounded MCP tools

**Files:**

- Modify: `Tools/LLMChatIndex/pyproject.toml`
- Modify: `Tools/LLMChatIndex/uv.lock`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/mcp_server.py`
- Create: `Tools/LLMChatIndex/tests/test_mcp_server.py`

- [ ] **Step 1: Add the official SDK and write failing schema tests**

Add `mcp` v2 through the package's locked dependencies. Instantiate the v2 `MCPServer` in-process and assert exactly these tools exist: `search_chats`, `open_chat`, `recent_chats`, `chat_sources`.

Required inputs:

~~~text
search_chats(query, sources?, host_ids?, date_from?, date_to?, limit=10)
open_chat(conversation_id, around_chunk?, message_radius=3)
recent_chats(source?, host_id?, date_from?, date_to?, limit=10)
chat_sources()
~~~

Cap `limit` at 50 and `message_radius` at 20. Reject unknown sources, malformed ISO dates, an empty query, and unbounded requests.

Run `uv run python -m unittest tests.test_mcp_server -v`; expected FAIL.

- [ ] **Step 2: Implement thin async tool adapters**

Call existing synchronous index/search functions through `asyncio.to_thread`. Return structured objects containing scores, excerpts, title, source, host IDs, dates, logical/version IDs, message ordinals, and Markdown paths. `open_chat` returns only the selected bounded message window unless no anchor is supplied, in which case cap total output at 60,000 characters and report truncation.

- [ ] **Step 3: Test error redaction and degraded mode**

Inject failures containing fake chat text and secrets. MCP errors must return a stable error code plus a short operational description without echoing query, transcript content, environment, OAuth data, or stack trace. `chat_sources` may report error paths/counts but not bodies.

- [ ] **Step 4: Add stdio entry point and protocol smoke test**

Expose `chat-index-mcp = "llm_chat_index.mcp_server:main"`. Spawn it as a subprocess, complete MCP initialization, list tools, execute one fixture search, and close stdin. Assert stdout contains protocol frames only; diagnostics go to stderr.

- [ ] **Step 5: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/pyproject.toml Tools/LLMChatIndex/uv.lock Tools/LLMChatIndex/src/llm_chat_index/mcp_server.py Tools/LLMChatIndex/tests/test_mcp_server.py
git commit -m "feat: expose local chat search over MCP"
~~~

## Task 2: Generate safe Codex and Claude Code configuration patches

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/agent_config.py`
- Create: `Tools/LLMChatIndex/tests/test_agent_config.py`
- Create: `Tools/LLMChatIndex/tests/fixtures/config/codex.toml`
- Create: `Tools/LLMChatIndex/tests/fixtures/config/claude.json`

- [ ] **Step 1: Write failing preservation/idempotence tests**

For Codex, add/update only `[mcp_servers.local-chat-history]` in `~/.codex/config.toml`. For Claude Code, add/update only top-level `mcpServers["local-chat-history"]` in `~/.claude.json`; if Claude's installed version requires a user-scoped CLI registration instead, the adapter must detect that capability and produce the equivalent command in dry-run output. Assert unrelated nested tables, project entries, comments where supported, and arbitrary JSON keys survive.

The configured command is the absolute `~/.local/share/llm-chat-index/.venv/bin/chat-index-mcp`; arguments are empty; environment contains only explicit `LLM_CHAT_ROOT` and `LLM_CHAT_STATE_ROOT` paths.

- [ ] **Step 2: Implement structured, redacted edits**

Use a TOML round-trip library locked in `uv.lock` for Codex and standard JSON parsing for Claude. Never use regex replacement. Return a `ConfigChange` containing path, changed/not-changed, backup path, and redacted diff headings. Do not include values from unrelated keys in logs.

- [ ] **Step 3: Implement atomic backup/apply/remove**

Before the first change in a run, create mode-`0600` backups named `<filename>.llm-chat-index-backup-<UTC timestamp>`. Atomic replacement retains the original file mode. Uninstall removes only `local-chat-history`; it does not restore an old whole-file backup over newer user changes.

- [ ] **Step 4: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/agent_config.py Tools/LLMChatIndex/tests/test_agent_config.py Tools/LLMChatIndex/tests/fixtures/config
git commit -m "feat: configure local chat MCP safely"
~~~

## Task 3: Generate and manage the per-user LaunchAgent

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/launch_agent.py`
- Create: `Tools/LLMChatIndex/tests/test_launch_agent.py`

- [ ] **Step 1: Write failing plist tests**

Assert label `com.kostapudan.llm-chat-index`, `RunAtLoad = true`, `StartInterval = 300`, absolute program arguments ending in `chat-index sync`, and stdout/stderr paths below `~/Library/Application Support/LLMChatIndex/logs`. No shell, network command, or workspace path may appear.

- [ ] **Step 2: Implement deterministic plist generation**

Use `plistlib`. Install at `~/Library/LaunchAgents/com.kostapudan.llm-chat-index.plist` with mode `0600`. Provide dry-run, install, bootstrap/kickstart, status, bootout, and uninstall operations using the current GUI domain `gui/<uid>`.

- [ ] **Step 3: Bound logs and overlap behavior**

The scheduled CLI rotates `sync.log` and `sync-error.log` at 5 MiB, retaining two generations. It exits cleanly with the documented lock-held code when a prior sync is active. Tests must not call real `launchctl`; inject a command runner and assert exact argv arrays.

- [ ] **Step 4: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/launch_agent.py Tools/LLMChatIndex/tests/test_launch_agent.py
git commit -m "feat: schedule automatic local chat indexing"
~~~

## Task 4: Build a reversible one-command installer

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/installer.py`
- Create: `Tools/LLMChatIndex/scripts/install.sh`
- Create: `Tools/LLMChatIndex/tests/test_installer.py`
- Modify: `Tools/LLMChatIndex/README.md`

- [ ] **Step 1: Write failing install-plan tests**

Given a temporary home, assert `build_install_plan()` validates Darwin arm64, Python 3.11+, writable iCloud root, sufficient free space, and the presence/readability of agent config parents. The plan must enumerate every create/modify/download/action path before applying it. Assert `--dry-run` makes no filesystem or process changes.

- [ ] **Step 2: Implement staged runtime installation**

Copy only tracked package files and `uv.lock` into a temporary sibling of `~/.local/share/llm-chat-index`, create `.venv` from the locked environment, run unit smoke tests, then atomically swap the runtime directory. Preserve the previous runtime as `.previous` until final verification succeeds; restore it on failure.

- [ ] **Step 3: Pin and validate the embedding snapshot**

Resolve `intfloat/multilingual-e5-small` once during an online install, record its exact Hugging Face commit SHA and hashes for model/config/tokenizer files in `model-lock.json`, download into the local application state, and load with `local_files_only=True`. On the second Mac, use the committed installer logic to resolve the same recorded revision. Never store the model in iCloud.

- [ ] **Step 4: Apply local integration in dependency order**

Apply runtime, model, initial `chat-index sync`, initial `chat-index rebuild`, MCP configuration, then LaunchAgent. If a later step fails, remove only artifacts created by this install and restore config/runtime backups; never delete normalized chats or the local index.

- [ ] **Step 5: Implement uninstall and repair**

`install.sh --uninstall` unloads/removes the LaunchAgent, removes only the named MCP entries and launcher/runtime, and preserves `LLM CHATS`, model, database, state, and backups unless `--purge-local-state` is explicitly supplied. `--repair` reruns validation and replaces damaged runtime files without regenerating the host ID.

- [ ] **Step 6: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/installer.py Tools/LLMChatIndex/scripts/install.sh Tools/LLMChatIndex/tests/test_installer.py Tools/LLMChatIndex/README.md
git commit -m "feat: install local chat knowledge base"
~~~

## Task 5: Verify privacy and end-to-end agent retrieval on the first Mac

**Files:**

- Create: `Tools/LLMChatIndex/scripts/privacy_smoke_test.py`
- Create: `Tools/LLMChatIndex/scripts/accept_mcp.py`
- Create: `Tools/LLMChatIndex/tests/test_privacy_smoke.py`
- Modify: `Tools/LLMChatIndex/README.md`

- [ ] **Step 1: Test privacy instrumentation with a fake socket layer**

Patch socket connection APIs and assert sync, rebuild, search, and all four MCP tools attempt no outbound connection when the model snapshot exists. Permit network only in the explicit installer model-download phase.

- [ ] **Step 2: Add read-only privacy and MCP acceptance scripts**

The privacy script runs representative queries with outbound connections blocked. The MCP script initializes the installed stdio server, calls every tool, validates response bounds, verifies every returned Markdown path exists, and confirms stdout is protocol-only. Neither script prints query text or excerpts.

- [ ] **Step 3: Dry-run, install, and inspect on this Mac**

Run:

~~~bash
cd Tools/LLMChatIndex
./scripts/install.sh --dry-run
./scripts/install.sh
~/.local/bin/chat-index status
python3 scripts/privacy_smoke_test.py
python3 scripts/accept_mcp.py
~~~

Inspect the named Codex/Claude configuration sections and LaunchAgent status. Restart both agent applications if required for MCP discovery, then call `chat_sources` and one Russian `search_chats` query from each.

- [ ] **Step 4: Verify automatic refresh**

Create one harmless new local test conversation through each supported app, record its source timestamp, and confirm it appears under `_Unified` and becomes searchable within ten minutes without manual sync. Remove only the test source if appropriate; confirm its normalized Markdown remains archived and the manifest marks it missing.

- [ ] **Step 5: Run complete tests and commit**

~~~bash
cd Tools/LLMChatIndex
uv run python -m unittest discover -s tests -v
git add Tools/LLMChatIndex/scripts/privacy_smoke_test.py Tools/LLMChatIndex/scripts/accept_mcp.py Tools/LLMChatIndex/tests/test_privacy_smoke.py Tools/LLMChatIndex/README.md
git commit -m "test: verify private agent chat retrieval"
~~~

## Task 6: Install and validate the second Mac

**Files:**

- Create: `Tools/LLMChatIndex/docs/SECOND_MAC.md`
- Modify: `Tools/LLMChatIndex/README.md`

- [ ] **Step 1: Document the exact transfer boundary**

State that the second Mac obtains the implementation from the same repository and the conversations from the same iCloud account. It must not copy `~/Library/Application Support/LLMChatIndex`, `.venv`, host ID, database, or model cache from Mac 1.

- [ ] **Step 2: Wait for iCloud convergence before install**

On Mac 2, verify the official Claude export directory, `_Unified`, and all host manifests are fully downloaded—not placeholder files. Record file count and total bytes on both Macs; retry after iCloud finishes if they differ.

- [ ] **Step 3: Run the same dry-run and installer on Mac 2**

Inspect proposed paths, install the pinned runtime/model, and confirm Mac 2 generates a different valid host ID. Initial rebuild must retrieve conversations authored on Mac 1 before Mac 2 contributes any new sessions.

- [ ] **Step 4: Test bidirectional archive synchronization**

Create a harmless test conversation on Mac 2, allow scheduled sync plus iCloud propagation, rebuild/incrementally index on Mac 1, and confirm both Macs return the same logical conversation ID with their local readable Markdown paths. Confirm the host manifests remain separate.

- [ ] **Step 5: Test offline operation and recovery**

Disconnect network access after model installation. On both Macs run lexical, semantic, hybrid, open, recent, sources, and MCP searches. Delete a temporary copy of the local index—not the live index—and prove rebuild from Markdown succeeds offline.

- [ ] **Step 6: Commit the runbook**

~~~bash
git add Tools/LLMChatIndex/docs/SECOND_MAC.md Tools/LLMChatIndex/README.md
git commit -m "docs: add second Mac chat index runbook"
~~~

## Plan Verification

- [ ] Confirm Codex and Claude Code both list exactly one `local-chat-history` MCP server.
- [ ] Confirm neither configuration file lost unrelated keys or entries.
- [ ] Confirm LaunchAgent runs at login and every 300 seconds on both Macs.
- [ ] Confirm both hosts have different host IDs and separate manifests.
- [ ] Confirm both Macs retrieve the other Mac's synced conversations.
- [ ] Confirm no query/chat/excerpt/embedding leaves the machine during privacy tests.
- [ ] Confirm uninstall preserves shared Markdown and local state by default.
- [ ] Record final source, conversation, message, chunk, embedding, error, and per-host counts from `chat-index sources`.
