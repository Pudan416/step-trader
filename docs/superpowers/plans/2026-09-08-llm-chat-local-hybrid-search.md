# LLM Chat Local Hybrid Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a rebuildable per-Mac SQLite index over the shared chat Markdown and provide private Russian/English lexical plus semantic retrieval using `intfloat/multilingual-e5-small` locally.

**Architecture:** A Markdown scanner recognizes normalized `llm-chat/v1` files and the existing official Claude export, converts messages into bounded chunks, and stores metadata plus FTS5 text in SQLite. A pinned local E5 model generates 384-dimensional vectors cached by content hash. Query-time BM25 and cosine rankings are fused with reciprocal-rank fusion; the system remains usable in lexical-only degraded mode.

**Tech Stack:** Python 3.11+, SQLite/FTS5, NumPy, Sentence Transformers with ONNX Runtime, Hugging Face Hub pinned snapshots, `unittest`, `uv` lockfile.

**Spec:** `docs/superpowers/specs/2026-09-08-local-llm-chat-knowledge-base-design.md`

## Global Constraints

- Complete `2026-09-08-llm-chat-ingestion-and-icloud-archive.md` first.
- Keep `index.sqlite3`, vectors, model cache, checkpoints, and query text out of iCloud.
- Index the existing `Claude Official Export 2026-09-08` in place and `_Unified/**/*.md`; do not duplicate either tree.
- Use exact model ID `intfloat/multilingual-e5-small`, 384 dimensions, `query: ` prefix for queries, and `passage: ` prefix for chunks.
- Pin the resolved model commit in `model-lock.json` during installation and reject an unexpected revision on later runs.
- Do not log queries or excerpts. Logs may contain hashes, counts, timings, paths, and errors.
- If embeddings cannot load, keep FTS5 indexing/search available and clearly report semantic status as degraded.
- Preserve unrelated changes and run focused tests before full search tests.

---

## Task 1: Create and migrate the local SQLite schema

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/db.py`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/schema.sql`
- Create: `Tools/LLMChatIndex/tests/test_db.py`

- [ ] **Step 1: Write failing schema tests**

Open a temporary database and assert `PRAGMA user_version = 1`, WAL mode, foreign keys, and tables `conversations`, `messages`, `chunks`, `chunk_fts`, `embeddings`, `documents`, `index_errors`, and `metadata`. Assert FTS5 is available and deleting a conversation cascades through messages, chunks, FTS rows, and embeddings.

Run `python3 -m unittest tests.test_db -v`; expected FAIL.

- [ ] **Step 2: Define exact stable keys**

Use `(logical_id, version_hash, markdown_path)` for physical conversation versions. Store source, host ID, title, timestamps, message count, and document hash. `chunks.id` is SHA-256 of `conversation_pk`, first/last message ordinals, and normalized chunk text. `embeddings` uses `chunk_id`, `model_id`, `model_revision`, `dimension`, and little-endian float32 BLOB.

- [ ] **Step 3: Implement schema creation, migration transaction, and integrity check**

Expose:

~~~python
def open_database(path: Path) -> sqlite3.Connection: ...
def migrate(connection: sqlite3.Connection) -> None: ...
def integrity_check(connection: sqlite3.Connection) -> tuple[bool, str]: ...
~~~

On failed integrity, close the database and raise `CorruptIndexError`; quarantine/rebuild is added in Task 6.

- [ ] **Step 4: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/db.py Tools/LLMChatIndex/src/llm_chat_index/schema.sql Tools/LLMChatIndex/tests/test_db.py
git commit -m "feat: add local chat search schema"
~~~

## Task 2: Discover and parse both Markdown archive formats

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/documents.py`
- Create: `Tools/LLMChatIndex/tests/test_documents.py`
- Create: `Tools/LLMChatIndex/tests/fixtures/official_claude_chat.md`

- [ ] **Step 1: Write failing discovery/parser tests**

Assert deterministic discovery of `_Unified/**/*.md` and `Claude Official Export */**/*.md`, ignoring temporary/hidden files and unrelated Markdown. Parse `llm-chat/v1` frontmatter exactly. Parse the official-export format into the same `ConversationDocument` shape with a stable logical ID derived from its exported conversation UUID, not its filename.

The public interface is:

~~~python
def discover_documents(chat_root: Path) -> list[Path]: ...
def parse_document(path: Path) -> ConversationDocument: ...
~~~

Run `python3 -m unittest tests.test_documents -v`; expected FAIL.

- [ ] **Step 2: Implement bounded frontmatter and message parsing**

Read UTF-8 with replacement for invalid bytes, cap a single document at 64 MiB, and produce a typed error for larger or structurally invalid files. Retain role, timestamp, ordinal, title, source, host ID, and path. Official Claude documents use source `claude-official` and host ID `official-export`.

- [ ] **Step 3: Test logical duplicate/version classification**

Identical `(logical_id, content_hash)` files from two host paths are one logical conversation with multiple locations. Divergent hashes remain distinct versions. Assert deterministic preferred path: official in-place path first, then lexicographically smallest normalized path.

- [ ] **Step 4: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/documents.py Tools/LLMChatIndex/tests/test_documents.py Tools/LLMChatIndex/tests/fixtures/official_claude_chat.md
git commit -m "feat: read shared chat markdown archives"
~~~

## Task 3: Chunk messages without losing traceability

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/chunking.py`
- Create: `Tools/LLMChatIndex/tests/test_chunking.py`

- [ ] **Step 1: Write failing boundary tests**

Define:

~~~python
def chunk_document(document: ConversationDocument, target_chars: int = 2400, max_chars: int = 3600, overlap_chars: int = 240) -> tuple[Chunk, ...]: ...
~~~

Assert short adjacent messages group until the target, role boundaries and ordinals remain recorded, long messages split below `max_chars` with 240-character overlap, empty messages disappear, Unicode remains intact, and repeated runs produce identical chunk IDs.

- [ ] **Step 2: Implement paragraph-aware splitting**

Prefer paragraph, then sentence, then whitespace boundaries. Hard-split only unbroken tokens over the maximum. Each chunk stores logical/version ID, first/last ordinal, roles, start/end timestamps, title, source, host IDs, Markdown paths, and plain retrieval text.

- [ ] **Step 3: Test retrieval text composition**

Include title once and role labels in the embedded/FTS text, but never frontmatter, source paths, or content hashes. Assert message body reconstruction remains possible through ordinals rather than chunk overlap.

- [ ] **Step 4: Run tests and commit**

~~~bash
git add Tools/LLMChatIndex/src/llm_chat_index/chunking.py Tools/LLMChatIndex/tests/test_chunking.py
git commit -m "feat: chunk chat messages for retrieval"
~~~

## Task 4: Add pinned local multilingual embeddings

**Files:**

- Modify: `Tools/LLMChatIndex/pyproject.toml`
- Create: `Tools/LLMChatIndex/uv.lock`
- Create: `Tools/LLMChatIndex/src/llm_chat_index/embeddings.py`
- Create: `Tools/LLMChatIndex/tests/test_embeddings.py`
- Create: `Tools/LLMChatIndex/tests/fixtures/fake_embedder.py`

- [ ] **Step 1: Write failing backend-independent cache tests**

Define protocols and interfaces:

~~~python
class Embedder(Protocol):
    model_id: str
    revision: str
    dimension: int
    def encode_passages(self, texts: Sequence[str]) -> np.ndarray: ...
    def encode_query(self, text: str) -> np.ndarray: ...

def ensure_embeddings(db: Connection, chunks: Sequence[Chunk], embedder: Embedder) -> EmbeddingStats: ...
~~~

With the deterministic fake embedder, assert caching by chunk hash/model/revision, float32 dimension validation, L2 normalization, batched inserts, changed-text re-embedding, and zero model calls on a no-op rebuild.

- [ ] **Step 2: Add and lock local model dependencies**

Add `numpy`, `sentence-transformers`, `onnxruntime`, and `huggingface-hub`; resolve and commit `uv.lock`. Configure Sentence Transformers' ONNX backend and CPU execution provider. Do not install a network client for remote embeddings.

- [ ] **Step 3: Implement `MultilingualE5SmallEmbedder`**

Load only from the pinned snapshot directory after installation. Validate model ID, revision, dimension 384, and normalized outputs. Prefix passages with `passage: ` and queries with `query: `. Raise `EmbeddingUnavailableError` without crashing lexical indexing.

- [ ] **Step 4: Add an opt-in real-model smoke test**

When `LLM_CHAT_MODEL_DIR` is set, encode Russian and English paraphrases and assert each vector is finite, normalized, and 384-dimensional; assert a simple paraphrase pair scores above an unrelated pair. Skip when the pinned model is not installed.

- [ ] **Step 5: Run tests and commit**

~~~bash
uv run python -m unittest tests.test_embeddings -v
git add Tools/LLMChatIndex/pyproject.toml Tools/LLMChatIndex/uv.lock Tools/LLMChatIndex/src/llm_chat_index/embeddings.py Tools/LLMChatIndex/tests/test_embeddings.py Tools/LLMChatIndex/tests/fixtures/fake_embedder.py
git commit -m "feat: add private multilingual chat embeddings"
~~~

## Task 5: Implement filtered lexical, semantic, and hybrid search

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/search.py`
- Create: `Tools/LLMChatIndex/tests/test_search.py`

- [ ] **Step 1: Write failing lexical and filter tests**

Index a small bilingual fixture corpus. Assert quoted phrases and identifiers are found by FTS5, results include title/source/date/excerpt/logical ID/path, and source/host/date filters are parameterized rather than interpolated SQL. Empty queries must return a validation error.

- [ ] **Step 2: Implement bounded FTS retrieval**

Escape user syntax into a safe token-and-prefix FTS query, retrieve at most `max(limit * 8, 40)` lexical candidates, convert lower BM25 values to rank order, and create excerpts no longer than 800 characters.

- [ ] **Step 3: Write failing semantic and fusion tests**

Use the fake embedder to assert cosine ordering and reciprocal-rank fusion with constant `k = 60`. A chunk ranked in both lists must outrank a chunk present in only one equal-depth list. Return at most two chunks per logical conversation unless fewer distinct conversations exist.

- [ ] **Step 4: Implement brute-force local vector ranking and RRF**

Load only filtered candidate vectors from SQLite into NumPy; this avoids a native vector extension in v1 and keeps the index portable. Retrieve at most `max(limit * 8, 40)` semantic candidates, fuse deterministic ties by updated date then chunk ID, and expose `mode` values `hybrid`, `lexical`, or `semantic`.

- [ ] **Step 5: Test degraded behavior**

When the embedder is unavailable, `hybrid` falls back to lexical results and returns `semantic_status: "degraded"`; explicit `semantic` returns a typed unavailable error. No test should find query text in logs, metadata, or the database after the call.

- [ ] **Step 6: Run tests and commit**

~~~bash
uv run python -m unittest tests.test_search -v
git add Tools/LLMChatIndex/src/llm_chat_index/search.py Tools/LLMChatIndex/tests/test_search.py
git commit -m "feat: search chats with local hybrid retrieval"
~~~

## Task 6: Build incremental indexing, rebuild, and CLI search commands

**Files:**

- Create: `Tools/LLMChatIndex/src/llm_chat_index/indexer.py`
- Modify: `Tools/LLMChatIndex/src/llm_chat_index/cli.py`
- Create: `Tools/LLMChatIndex/tests/test_indexer.py`
- Create: `Tools/LLMChatIndex/tests/test_cli_search.py`
- Create: `Tools/LLMChatIndex/scripts/accept_search.py`

- [ ] **Step 1: Write failing incremental-index tests**

Assert first build indexes all documents; second build parses/embeds none; one changed file replaces only its physical version; a missing path removes only that location and retains an identical logical duplicate; malformed files are recorded while good files commit; a transaction failure leaves the last usable version intact.

- [ ] **Step 2: Implement document-hash checkpoints and transactions**

Hash files while streaming. For each changed document, parse and chunk outside the write transaction, then replace its rows in one transaction. Update `documents` only after all rows succeed. Remove stale database paths only after a complete scan of an available chat root; never infer deletion when iCloud root is unavailable.

- [ ] **Step 3: Add corruption quarantine and rebuild**

`chat-index rebuild` closes the index, moves a corrupt file to `index.sqlite3.corrupt-<UTC timestamp>`, builds `index.sqlite3.building`, runs `PRAGMA integrity_check`, and atomically replaces the final path. Never remove the quarantined file automatically.

- [ ] **Step 4: Add CLI commands**

Implement `rebuild`, `search`, `open`, `recent`, and `sources` with human and `--json` output. `open` accepts logical ID plus optional `--around-chunk` and `--message-radius` (default 3, maximum 20). `search --limit` defaults to 10 and caps at 50.

- [ ] **Step 5: Run real-data acceptance**

The acceptance script builds a temporary index from the actual iCloud archive, records conversation/message/chunk counts, checks integrity, runs exact Russian and English keyword queries, runs cross-language semantic queries with the installed pinned model, verifies every result path exists, deletes the temporary database, and proves a rebuild returns the same logical conversation count.

- [ ] **Step 6: Run all tests and commit**

~~~bash
cd Tools/LLMChatIndex
uv run python -m unittest discover -s tests -v
git add Tools/LLMChatIndex/src/llm_chat_index/indexer.py Tools/LLMChatIndex/src/llm_chat_index/cli.py Tools/LLMChatIndex/tests/test_indexer.py Tools/LLMChatIndex/tests/test_cli_search.py Tools/LLMChatIndex/scripts/accept_search.py
git commit -m "feat: build and query local chat index"
~~~

## Plan Verification

- [ ] Confirm the SQLite database and model cache resolve below `~/Library/Application Support/LLMChatIndex`, never iCloud.
- [ ] Confirm official Claude export and normalized files are both searchable without duplication.
- [ ] Confirm every result retains a readable Markdown path and message ordinals.
- [ ] Confirm FTS search works with the network disabled and embeddings unavailable.
- [ ] Confirm the pinned model works with the network disabled after installation.
- [ ] Confirm representative Russian-to-English and English-to-Russian queries retrieve relevant fixtures.
- [ ] Confirm deleting the local database and rebuilding restores the same logical conversation count.
