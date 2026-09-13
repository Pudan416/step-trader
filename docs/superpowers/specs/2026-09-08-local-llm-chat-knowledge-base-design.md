# Local LLM Chat Knowledge Base — Design

Date: 2026-09-08

## Purpose

Build a private, local-first knowledge base that lets Codex and Claude Code answer questions using the user's historical conversations. Conversation sources synchronize through iCloud, while the search database and embedding model remain local to each Mac.

The first version covers:

- the existing official Claude export already converted to Markdown in the Obsidian vault;
- Claude Code JSONL sessions;
- Codex session logs;
- two Apple Silicon Macs signed into the same iCloud account.

Existing ChatGPT, Cursor, and miscellaneous Markdown chats in `LLM CHATS` are outside the first-version ingestion scope. They may be added later through the same normalized conversation contract.

## Goals

- Ask an agent natural-language questions across historical chats.
- Keep chat text, queries, embeddings, and retrieval results on the Mac.
- Automatically ingest new Claude Code and Codex sessions.
- Synchronize portable conversation documents through iCloud without synchronizing a live SQLite database.
- Avoid duplicates across repeated imports and across two Macs.
- Preserve archived conversations even if a local source log later disappears.
- Make the system inspectable through Markdown, a CLI, status logs, and source links.

## Non-goals

- Automatically downloading ordinary Claude.ai conversations. Future official exports remain a manual input.
- Synchronizing the SQLite index or model cache through iCloud.
- Indexing hidden reasoning, system prompts, tool payloads, or large command results.
- Replacing the original JSONL and official export files as the forensic source of truth.
- Providing a hosted web interface or sending content to an external vector service.

## Architecture

```text
~/.claude/projects ─────┐
                       ├── importer ──> iCloud/LLM CHATS/_Unified/
~/.codex/sessions ─────┘                    ├── claude-code/<host>/
                                            ├── codex/<host>/
Claude official Markdown ───────────────────┤
                                            └── _manifests/<host>.json
                                                          │
                                                          ▼
                                      local incremental indexer on each Mac
                                      SQLite FTS5 + local embeddings
                                                          │
                                                          ▼
                                      CLI and stdio MCP server
                                      search / open / recent / sources
```

### Shared source store

The canonical portable store is:

`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS`

Automatically normalized sessions are written below `_Unified`. Each Mac writes only inside a stable host namespace derived from a generated host ID, not from the mutable computer name. Per-host manifests avoid concurrent writes to one iCloud file:

```text
LLM CHATS/
  Claude Official Export 2026-09-08/
  _Unified/
    claude-code/<host-id>/<conversation-id>.md
    codex/<host-id>/<conversation-id>.md
    _manifests/<host-id>.json
```

The existing official Claude Markdown export is indexed in place and is not duplicated under `_Unified`.

The Codex adapter reads live JSONL transcripts recursively from `~/.codex/sessions`, archived JSONL transcripts from `~/.codex/archived_sessions`, and title/project metadata from `~/.codex/session_index.jsonl`. Codex SQLite files are not part of the first-version ingestion path because they are live mutable application databases; JSONL remains the read-only transcript boundary.

### Local runtime

Each Mac installs the runtime under:

`~/.local/share/llm-chat-index`

Local mutable state lives under:

`~/Library/Application Support/LLMChatIndex`

This directory contains the SQLite index, embedding cache, host ID, logs, and last-success state. It is never placed in iCloud.

## Normalized conversation contract

Each generated Markdown file has YAML frontmatter followed by readable user/assistant messages.

Required frontmatter:

```yaml
schema: llm-chat/v1
id: claude-code:<session-uuid>
source: claude-code
host_id: <stable-host-id>
source_path: <absolute-local-path>
created_at: <ISO-8601>
updated_at: <ISO-8601>
imported_at: <ISO-8601>
message_count: <integer>
content_hash: <sha256-of-normalized-content>
```

The stable conversation ID is the source name plus the source session UUID. If a source lacks a session UUID, the importer derives the ID from stable source metadata and records that derivation in the manifest.

Messages preserve role, timestamp, and visible text. The importer excludes:

- system and metadata records;
- hidden reasoning and thinking blocks;
- tool calls and tool results;
- command output and large diagnostic payloads;
- duplicate streamed assistant fragments when a final visible message is available.

Attachment bodies are not copied into normalized Markdown. Filename, media type, size, and an available source reference may be preserved.

## Incremental ingestion and synchronization

A macOS LaunchAgent runs at login and every five minutes.

For each supported source, the importer stores source path, size, modification time, last parsed offset where safe, and normalized content hash. An unchanged source is skipped. An append-only JSONL source is resumed incrementally; a rewritten or truncated source is parsed again and replaces the generated Markdown atomically.

Writes use a temporary sibling file followed by an atomic rename. The per-host manifest is updated only after all conversation writes succeed.

Repeated imports are idempotent. A conversation with the same stable ID and content hash causes no write. A changed conversation updates its existing Markdown. Source deletion does not delete normalized Markdown; the manifest marks the source as missing while retaining the archive.

Two Macs normally produce different host namespaces. If the same source conversation exists on both, the local indexer groups identical stable IDs and content hashes as one logical conversation. Divergent content for one stable ID remains as separate versions with both host IDs visible.

## Local search index

The local SQLite database contains:

- conversation metadata and source locations;
- normalized messages;
- retrieval chunks;
- an FTS5 table for exact and BM25-ranked text search;
- embedding vectors and model/version metadata;
- ingestion checkpoints and errors.

Chunks respect message boundaries. Short adjacent messages may be grouped up to a target retrieval size; long messages are split with a small overlap. Every chunk retains conversation ID, message range, roles, dates, source, host ID, and Markdown path.

The embedding model is `intfloat/multilingual-e5-small`, run locally through an ONNX-compatible runtime. Both Macs install the same pinned model revision. The first installation may download the model; indexing and querying require no network afterward.

Search is hybrid:

1. FTS5 returns exact/BM25 candidates.
2. The embedding index returns semantic candidates.
3. Reciprocal-rank fusion combines both rankings.
4. Optional filters apply source, host, and date constraints.
5. Results are grouped to avoid returning many adjacent chunks from one conversation.

Each result includes a score, title, source, date, excerpt, conversation ID, and local Markdown path. Answers remain the responsibility of the calling agent; the search service returns evidence, not generated prose.

## Agent interface

One local stdio MCP server is configured for both Codex and Claude Code. It exposes:

### `search_chats`

Inputs: query, optional source list, optional host IDs, optional date range, and limit.

Returns ranked excerpts with conversation metadata and local paths.

### `open_chat`

Inputs: conversation ID and optional chunk/message neighborhood.

Returns the selected conversation or a bounded context window around a matched passage.

### `recent_chats`

Inputs: optional source, host, date range, and limit.

Returns recently updated conversations.

### `chat_sources`

Returns source counts, host IDs, indexed date ranges, last sync times, and current ingestion errors.

The accompanying CLI provides equivalent commands:

```text
chat-index sync
chat-index rebuild
chat-index search <query>
chat-index open <conversation-id>
chat-index recent
chat-index sources
chat-index status
```

## Installation on two Macs

An installer performs these local steps:

1. Validate Apple Silicon macOS and Python/runtime prerequisites.
2. Install the application into `~/.local/share/llm-chat-index`.
3. Generate or reuse the stable host ID.
4. Download and pin the local embedding model.
5. Build the initial local index from the iCloud store and local session logs.
6. Install and load the per-user LaunchAgent.
7. Add the MCP server configuration for Codex and Claude Code without overwriting unrelated configuration.
8. Run a privacy and retrieval smoke test.

The second Mac runs the same installer. It receives normalized conversations through iCloud, builds its own SQLite and embedding index, and begins contributing its own locally generated Codex and Claude Code sessions under its host namespace.

## Failure handling

- If iCloud is unavailable, local import is deferred and retried; source logs are never modified.
- If an individual transcript is malformed, other transcripts continue and the error appears in `chat-index status`.
- If model loading fails, FTS5 search remains available and semantic indexing is marked degraded.
- If SQLite integrity checks fail, the local index is quarantined and can be rebuilt entirely from Markdown and local logs.
- A lock prevents two importer/indexer processes on one Mac from writing simultaneously.
- Stale temporary files are ignored and cleaned only after their destination and ownership are validated.
- LaunchAgent output is size-limited or rotated so logs cannot grow without bound.

## Privacy and security

- No chat text, search query, excerpt, or embedding is sent to an external service.
- The only expected network operation is the initial model download, with a pinned revision and checksum where the distribution mechanism supports it.
- MCP listens on stdio only; it opens no network port.
- Generated files inherit user-only permissions where possible.
- Logs contain identifiers, paths, counts, and errors but not full message bodies.
- The installer displays every directory and configuration file it will modify before applying changes.

## Testing strategy

Unit and integration fixtures cover:

- Claude Code and Codex schema variants;
- visible message extraction and technical-block exclusion;
- stable IDs and filename safety;
- append-only resume, rewrite detection, and truncation handling;
- idempotent repeated imports;
- atomic write failure behavior;
- per-host manifest isolation;
- same-content deduplication and divergent cross-host versions;
- chunk boundaries and metadata preservation;
- FTS5, semantic, hybrid, filtered, and multilingual retrieval;
- index corruption detection and rebuild;
- MCP tool schemas and bounded results;
- LaunchAgent generation and install/uninstall dry runs.

A real-data acceptance run uses read-only copies of the current Claude Code, Codex, and official Claude archives. It compares discovered session counts with imported counts, verifies that original files are unchanged, rebuilds the index from scratch, and runs representative Russian and English queries.

## Acceptance criteria

- New Claude Code and Codex visible messages become searchable within ten minutes under normal iCloud conditions.
- Re-running sync with no source changes produces no conversation rewrites or duplicates.
- Both Macs can retrieve synced conversations created on the other Mac.
- A Russian semantic query can find a relevant English conversation and vice versa.
- Every search result links back to a readable Markdown source and identifies its source and host.
- Disconnecting the network after model installation does not break ingestion or search.
- Deleting the local SQLite database and running `chat-index rebuild` restores a working index.
- No external network endpoint receives chat or query content during the privacy smoke test.

## Deferred extensions

- Automatic processing of newly downloaded official Claude exports.
- Existing ChatGPT Markdown, Cursor metadata, and other `LLM CHATS` content.
- Local summarization, topic clustering, and timeline views.
- Attachment text extraction and optional local OCR.
- A read-only Obsidian dashboard generated from the same manifests.
