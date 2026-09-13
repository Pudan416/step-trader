# LLM Chat Obsidian Wiki Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one local, deterministic, self-updating Obsidian wiki containing canonical ChatGPT, Claude, Claude Code, and Codex conversations from both Macs.

**Architecture:** Extend the dependency-free `LLMChatIndex` tool with focused source, classification, relationship, rendering, and build modules. The builder reads preserved archives, selects one canonical document per stable source identity, renders the whole wiki into staging, validates it, and then publishes only generated paths; `sync` continues collecting machine-local Codex and Claude Code logs into host namespaces.

**Tech Stack:** Python 3 standard library, `unittest`, Markdown, JSON configuration/manifests, Obsidian properties/wikilinks/Bases, macOS iCloud Drive and LaunchAgent.

**Spec:** `docs/superpowers/specs/2026-09-08-llm-chat-obsidian-wiki-design.md`

## Global Constraints

- All chat parsing, classification, linking, and rendering stays local; no network, hosted LLM, embeddings, or vector database.
- Canonical transcript bodies contain visible user and assistant dialogue only: no system/developer messages, reasoning, tool calls/results, command output, timestamps, or raw attachment bodies.
- Preserve every original source file and record its SHA-256 in `_Sources/migration-manifest.json`; never derive unknown dates or identities from filesystem timestamps.
- `Chats/` is the only canonical retrieval root after migration; legacy locations remain source inputs and are excluded from canonical search results.
- `StepTrader`, `StepsTrader`, `step-trader`, `Step4`, and `Steps4` resolve to the single project page `Wiki/Projects/Nowhere.md` using case- and separator-insensitive aliases.
- Automatic classification is deterministic, evidence-aware, and conservative: at most three topics, one to three controlled types, and no automatic idea page unless the user names the idea and it occurs in two chats.
- Related links are reciprocal, deterministic, limited to five per chat, and never arise from one broad topic alone.
- One configured wiki-owner Mac publishes canonical output; other Macs only synchronize their local `_Unified` sources.
- All writes use a sibling staging directory, validation, and atomic replacement; a failed build leaves the last complete wiki active.
- A no-op rebuild changes neither canonical file bytes nor modification times.
- Remain compatible with `/usr/bin/python3` and add no third-party dependency.

---

## File map

- `Tools/LLMChatIndex/chat_index.py` — existing CLI, local-session synchronization, search routing, and command wiring.
- `Tools/LLMChatIndex/wiki_models.py` — immutable source/canonical/classification/evidence records shared by all wiki modules.
- `Tools/LLMChatIndex/wiki_sources.py` — bounded reads, frontmatter/dialogue parsing, source discovery, source IDs, and hashes.
- `Tools/LLMChatIndex/wiki_canonical.py` — source identity normalization, duplicate selection, collision-safe filenames, and canonical selections.
- `Tools/LLMChatIndex/wiki_classify.py` — JSON configuration defaults/loading, aliases, project/topic/type/idea rules, and evidence records.
- `Tools/LLMChatIndex/wiki_links.py` — deterministic candidate scoring and bounded reciprocal related-chat links.
- `Tools/LLMChatIndex/wiki_render.py` — canonical chat Markdown, generated wiki pages, `Home.md`, `Chats.base`, and generated-block preservation.
- `Tools/LLMChatIndex/wiki_builder.py` — inventory orchestration, staging validation, owner/lock checks, manifest rendering, and publication.
- `Tools/LLMChatIndex/tests/test_wiki_sources.py` — source-format and bounded-read tests.
- `Tools/LLMChatIndex/tests/test_wiki_canonical.py` — identity, duplicate, and filename tests.
- `Tools/LLMChatIndex/tests/test_wiki_classify.py` — taxonomy, alias, type, idea, evidence, and override tests.
- `Tools/LLMChatIndex/tests/test_wiki_links.py` — relationship scoring, reciprocity, limits, and deterministic ordering tests.
- `Tools/LLMChatIndex/tests/test_wiki_render.py` — Obsidian properties, dialogue-only bodies, links, Base, and human-text preservation tests.
- `Tools/LLMChatIndex/tests/test_wiki_builder.py` — staging, rollback, owner behavior, source preservation, and idempotence tests.
- `Tools/LLMChatIndex/tests/test_cli_and_install.py` — CLI and shared-installer integration tests.
- `Tools/LLMChatIndex/README.md` — human instructions for building, searching, reviewing, and operating on two Macs.

---

### Task 1: Read every preserved archive format into one source model

**Files:**
- Create: `Tools/LLMChatIndex/wiki_models.py`
- Create: `Tools/LLMChatIndex/wiki_sources.py`
- Create: `Tools/LLMChatIndex/tests/test_wiki_sources.py`
- Modify: `Tools/LLMChatIndex/chat_index.py`

**Interfaces:**
- Produces: `SourceChat`, `Evidence`, and `BuildIssue` dataclasses in `wiki_models.py`.
- Produces: `read_text_bounded(path: Path, timeout_seconds: float) -> str`.
- Produces: `parse_markdown_chat(path: Path, source: str, source_id: Optional[str] = None) -> Optional[SourceChat]`.
- Produces: `discover_source_chats(vault_root: Path, chat_root: Path, timeout_seconds: float = 5.0) -> Tuple[Tuple[SourceChat, ...], Tuple[BuildIssue, ...]]`.
- Consumes: existing `Message`, `_clean_text`, `_chat_role_heading`, and fence-aware role parsing behavior from `chat_index.py`; move the shared records/helpers rather than duplicating their behavior.

- [ ] **Step 1: Write failing source-parser tests**

Create fixtures inline for all archive shapes and assert dialogue filtering, inherited properties, stable source IDs, and hashing:

```python
def test_discovers_legacy_official_claude_enriched_codex_and_unified(self):
    vault = self.root / "Kosta P"
    chats = vault / "LLM CHATS"
    self.write(chats / "Legacy.md", "## user\n\nВопрос\n\n## assistant\n\nОтвет\n")
    self.write(
        chats / "Claude Official Export 2026-09-08/conversations/claude-42.md",
        "# Claude export\n\n## Пользователь — 2026-03-01T10:00:00Z\n\nЗапрос\n\n"
        "## Claude — 2026-03-01T10:01:00Z\n\nОтвет Claude\n",
    )
    self.write(
        vault / "Codex history/2026/July/Task — abcdef12.md",
        "---\ncodex_thread_id: 11111111-2222-3333-4444-abcdefabcdef\n"
        "created: 2026-07-01T10:00:00Z\ntopics:\n  - automation\n---\n"
        "# Codex enriched\n\n## Запрос 1\n\nСделай\n\n## Ответ 1\n\nГотово\n",
    )
    self.write(
        chats / "_Unified/codex/host-a/11111111-2222-3333-4444-abcdefabcdef.md",
        "# Codex generated\n\n## Запрос\n\nСделай\n\n## Ответ\n\nГотово\n",
    )

    found, issues = discover_source_chats(vault, chats, timeout_seconds=0.2)

    self.assertEqual({chat.source for chat in found}, {"chatgpt", "claude", "codex"})
    self.assertEqual(len(found), 4)
    self.assertEqual(issues, ())
    enriched = next(chat for chat in found if chat.source_path.parts[-4] == "Codex history")
    self.assertEqual(enriched.source_id, "11111111-2222-3333-4444-abcdefabcdef")
    self.assertEqual(enriched.inherited_topics, ("automation",))
    self.assertRegex(enriched.source_hash, r"^sha256:[0-9a-f]{64}$")
    self.assertEqual([(m.role, m.text) for m in enriched.messages], [("user", "Сделай"), ("assistant", "Готово")])
```

Also add tests proving that YAML frontmatter is not copied into a message, role-like headings inside fenced code are preserved as content, README/index/service notes are ignored, unknown dates stay `None`, and a mocked `ReadTimeout` returns one `BuildIssue(code="read-timeout")` while discovery continues.

- [ ] **Step 2: Run the new source tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_sources -v
```

Expected: import failure for `wiki_sources` or missing `discover_source_chats`.

- [ ] **Step 3: Add shared immutable records**

Implement these exact records in `wiki_models.py`:

```python
@dataclass(frozen=True)
class Message:
    role: str
    text: str
    timestamp: Optional[str] = None

@dataclass(frozen=True)
class Evidence:
    conversation_key: str
    role: str
    message_ordinal: int
    field: str
    value: str
    strength: str
    source_timestamp: Optional[str]
    source_hash: str

@dataclass(frozen=True)
class BuildIssue:
    code: str
    source_path: str
    detail: str

@dataclass(frozen=True)
class SourceChat:
    source: str
    source_id: str
    host_id: Optional[str]
    source_path: Path
    workspace_path: Optional[str]
    title: str
    created_at: Optional[str]
    updated_at: Optional[str]
    messages: Tuple[Message, ...]
    source_hash: str
    inherited_topics: Tuple[str, ...] = ()
    inherited_types: Tuple[str, ...] = ()
    inherited_status: Optional[str] = None

    @property
    def identity_key(self) -> str:
        return self.source + ":" + self.source_id
```

Import `Message` back into `chat_index.py` so existing local JSONL parser tests remain unchanged.

- [ ] **Step 4: Implement bounded parsing and source discovery**

In `wiki_sources.py`, implement:

- byte-preserving SHA-256 before text normalization;
- a main-thread `signal.setitimer` guard that restores the previous handler/timer in `finally` and raises `ReadTimeout`;
- a small YAML-subset reader supporting quoted scalars, booleans, integers, `null`, and indented scalar lists used by the enriched archive;
- fence-aware recognition of `## user`, `## assistant`, `## Запрос`, `## Ответ`, numbered Russian headings, and timestamped official-Claude headings;
- source roots exactly matching the inventory in the spec;
- source-ID extraction from enriched `codex_thread_id`, `_Unified` names, official-export filename/manifest metadata, and legacy `chatgpt-legacy:` content/path hash fallback;
- `_Unified/_manifests/*.json` lookup of the original local `source_path`/workspace path, carried as navigation evidence but never rendered into chat frontmatter;
- explicit exclusion of `Home.md`, `Chats.base`, README/index files, `_Tools`, `_Config`, `_Sources`, `Wiki`, and canonical `Chats`.

Keep malformed files as `BuildIssue(code="parse-error")` when they cannot yield dialogue. Do not infer dates from `stat()`.

Extend the existing `sync` manifest entry with `source_path: str(path)` so the wiki builder can recover workspace evidence from both Macs. This field contains only a local path, never message content. Preserve compatibility with older manifests where it is absent.

- [ ] **Step 5: Run source and existing parser tests**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_sources tests.test_chat_index -v
```

Expected: all tests pass; existing Codex/Claude Code dialogue filtering remains unchanged.

- [ ] **Step 6: Commit the source layer**

```bash
git add Tools/LLMChatIndex/wiki_models.py Tools/LLMChatIndex/wiki_sources.py Tools/LLMChatIndex/chat_index.py Tools/LLMChatIndex/tests/test_wiki_sources.py
git commit -m "feat: parse chat archive sources for wiki"
```

---

### Task 2: Select stable canonical chats and record duplicate provenance

**Files:**
- Create: `Tools/LLMChatIndex/wiki_canonical.py`
- Create: `Tools/LLMChatIndex/tests/test_wiki_canonical.py`
- Modify: `Tools/LLMChatIndex/wiki_models.py`

**Interfaces:**
- Consumes: `SourceChat.identity_key` from Task 1.
- Produces: `CanonicalChat` and `CanonicalSelection` dataclasses.
- Produces: `canonicalize_sources(chats: Iterable[SourceChat]) -> CanonicalSelection`.
- Produces: `canonical_filename(chat: CanonicalChat, occupied: Mapping[str, str]) -> str`.

- [ ] **Step 1: Write failing canonicalization tests**

Cover the observed 277/347 overlap pattern with compact fixtures:

```python
def test_same_codex_id_selects_most_complete_version_and_records_duplicate(self):
    short = source_chat("codex", CODEX_ID, "_Unified/codex/host-a/id.md", [("user", "Q")])
    enriched = source_chat(
        "codex", CODEX_ID, "Codex history/2026/July/id.md",
        [("user", "Q"), ("assistant", "A")], updated="2026-07-02T00:00:00Z",
    )

    result = canonicalize_sources([short, enriched])

    self.assertEqual(len(result.chats), 1)
    self.assertEqual(result.chats[0].selected_source_path, enriched.source_path)
    self.assertEqual(result.duplicates[CODEX_KEY], (str(short.source_path),))
```

Add tests for tie order (explicit `updated`, enriched Codex path, lexical path), 53 history-only plus 123 unified-only identities staying separate, exact body matches across different products becoming `possible_duplicates` without merging, readable title plus ID suffix filenames, and unrelated filename collisions gaining a longer stable suffix.

- [ ] **Step 2: Run canonicalization tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_canonical -v
```

Expected: import failure for `wiki_canonical`.

- [ ] **Step 3: Implement canonical records and selection**

Add these records to `wiki_models.py`:

```python
@dataclass(frozen=True)
class CanonicalChat:
    key: str
    source: str
    source_id: str
    title: str
    created_at: Optional[str]
    updated_at: Optional[str]
    messages: Tuple[Message, ...]
    source_hash: str
    selected_source_path: Path
    workspace_path: Optional[str]
    all_source_paths: Tuple[Path, ...]
    inherited_topics: Tuple[str, ...] = ()
    inherited_types: Tuple[str, ...] = ()
    inherited_status: Optional[str] = None

@dataclass(frozen=True)
class CanonicalSelection:
    chats: Tuple[CanonicalChat, ...]
    duplicates: Mapping[str, Tuple[str, ...]]
    possible_duplicates: Tuple[Tuple[str, str], ...]
```

Implement selection using non-empty message count, explicit updated value, enriched-path preference, and lexical-path order exactly as specified. Use a normalized dialogue hash only to report cross-source possible duplicates. Never merge on title.

- [ ] **Step 4: Implement deterministic filename allocation**

Sanitize `/\\:*?"<>|#[]` and control characters, collapse whitespace, cap the title segment at 100 characters, and append ` — <last-eight-id-chars>.md`. If `occupied[casefolded_name]` belongs to another key, expand to 12 ID characters and finally append the first 12 SHA-256 characters of the key. Return Unicode NFC filenames.

- [ ] **Step 5: Run canonicalization and full existing tests**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest discover -s tests -v
```

Expected: all tests pass.

- [ ] **Step 6: Commit canonical identity handling**

```bash
git add Tools/LLMChatIndex/wiki_models.py Tools/LLMChatIndex/wiki_canonical.py Tools/LLMChatIndex/tests/test_wiki_canonical.py
git commit -m "feat: canonicalize and deduplicate chat identities"
```

---

### Task 3: Apply conservative projects, topics, types, ideas, and evidence

**Files:**
- Create: `Tools/LLMChatIndex/wiki_classify.py`
- Create: `Tools/LLMChatIndex/tests/test_wiki_classify.py`
- Modify: `Tools/LLMChatIndex/wiki_models.py`

**Interfaces:**
- Consumes: `CanonicalChat` from Task 2.
- Produces: `WikiConfig`, `Classification`, and `ClassifiedChat` dataclasses.
- Produces: `ensure_default_config(config_root: Path, wiki_owner: str) -> WikiConfig`.
- Produces: `load_config(config_root: Path) -> WikiConfig`.
- Produces: `classify_chats(chats: Iterable[CanonicalChat], config: WikiConfig) -> tuple[ClassifiedChat, ...]`.

- [ ] **Step 1: Write failing classification tests**

Create deterministic fixtures that prove all aliases land only on Nowhere:

```python
def test_nowhere_aliases_match_titles_messages_and_workspace_paths(self):
    config = default_config(self.root, owner="host-a")
    chats = [
        canonical_chat(key="codex:1", title="StepTrader risk model"),
        canonical_chat(key="codex:2", title="Без названия", user="Продолжим Steps4"),
        canonical_chat(key="claude-code:3", title="Работа", path="/dev local/step-trader/session.md"),
    ]

    classified = classify_chats(chats, config)

    self.assertEqual(
        [item.classification.projects for item in classified],
        [("Wiki/Projects/Nowhere",)] * 3,
    )
    self.assertTrue(all(item.classification.status == "auto" for item in classified))
```

Also assert separator/case normalization; maximum three topics; controlled type values; assistant-only acceptance does not create `decision`; a user statement like “выбираю второй вариант” does; an implementation request alone creates `code` but not an outcome; one-chat ideas stay candidates; a user-named repeated idea becomes a page; inherited topics are `auto`; manual curations override automation and become `reviewed`; conflicting assignments become `review-required`; and every non-structural fact has an evidence record pointing to a user message, reviewed property, title, or workspace path.

- [ ] **Step 2: Run classification tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_classify -v
```

Expected: import failure for `wiki_classify`.

- [ ] **Step 3: Define configuration and output records**

Use these shapes:

```python
@dataclass(frozen=True)
class WikiConfig:
    wiki_owner: str
    project_aliases: Mapping[str, Tuple[str, ...]]
    topic_rules: Mapping[str, Tuple[str, ...]]
    topic_aliases: Mapping[str, str]
    stop_words: Tuple[str, ...]
    curations: Mapping[str, Mapping[str, object]]

@dataclass(frozen=True)
class Classification:
    projects: Tuple[str, ...]
    project_candidates: Tuple[str, ...]
    topics: Tuple[str, ...]
    types: Tuple[str, ...]
    ideas: Tuple[str, ...]
    idea_candidates: Tuple[str, ...]
    decisions: Tuple[Evidence, ...]
    outcomes: Tuple[Evidence, ...]
    open_questions: Tuple[Evidence, ...]
    privacy: str
    status: str
    evidence: Tuple[Evidence, ...]

@dataclass(frozen=True)
class ClassifiedChat:
    chat: CanonicalChat
    classification: Classification
    related_keys: Tuple[str, ...] = ()
```

Initialize JSON files only when absent. `aliases.json` must contain the five confirmed aliases under canonical project `Nowhere`; `taxonomy.json` must contain the six controlled types and explicit Russian/English keyword rules; `curations.json` must contain `wiki_owner`, empty `chats`, empty `topic_merges`, and empty `idea_confirmations`. Existing files are human-owned and must never be rewritten merely to sort or reformat them. Set `privacy` to `personal` unless a manual curation supplies another value; automatic rules must never emit `public`.

- [ ] **Step 4: Implement deterministic classification**

Normalize matching with Unicode NFC, `casefold()`, and removal of spaces, `_`, and `-` for project aliases. Search title, user messages, and selected source/workspace path; do not classify from assistant messages except inherited source metadata. Generate evidence with zero-based message ordinal and source timestamp/hash.

For topics, apply manual values first, then normalized inherited topics, then repeated high-signal title terms and explicit keyword rules; discard stop words and cap automatic topics at three using score then lexical order. For types, evaluate the controlled rule table and cap at three. For ideas, first collect user-named candidates across the full corpus, then promote only candidates present in at least two distinct chat keys or listed in `idea_confirmations`.

Extract `decisions`, `outcomes`, and `open_questions` only when a matching user message supplies the record text. A user acceptance phrase can create a decision; an explicit user report of a completed result can create an outcome; a user question unresolved by later visible dialogue can create an open-question candidate. Store the matching excerpt in `Evidence.value`, preserve historical timestamps, and never treat assistant claims or absence of later messages as current truth.

- [ ] **Step 5: Run classification and full tests**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest discover -s tests -v
```

Expected: all tests pass and classification order is stable across shuffled input.

- [ ] **Step 6: Commit the semantic rules**

```bash
git add Tools/LLMChatIndex/wiki_models.py Tools/LLMChatIndex/wiki_classify.py Tools/LLMChatIndex/tests/test_wiki_classify.py
git commit -m "feat: classify chat wiki with local rules"
```

---

### Task 4: Build deterministic reciprocal related-chat links

**Files:**
- Create: `Tools/LLMChatIndex/wiki_links.py`
- Create: `Tools/LLMChatIndex/tests/test_wiki_links.py`

**Interfaces:**
- Consumes: `ClassifiedChat` from Task 3.
- Produces: `link_related_chats(chats: Iterable[ClassifiedChat], max_links: int = 5) -> Tuple[ClassifiedChat, ...]`.

- [ ] **Step 1: Write failing relationship tests**

```python
def test_links_are_reciprocal_bounded_and_ignore_one_broad_topic(self):
    chats = [
        classified("codex:a", project="Wiki/Projects/Nowhere", topics=("Automation", "Trading"), updated="2026-08-03"),
        classified("codex:b", project="Wiki/Projects/Nowhere", topics=("Automation", "Risk"), updated="2026-08-02"),
        classified("claude:c", topics=("AI",), updated="2026-08-01"),
        classified("chatgpt:d", topics=("AI",), updated="2026-08-01"),
    ]

    linked = {item.chat.key: item for item in link_related_chats(chats, max_links=1)}

    self.assertEqual(linked["codex:a"].related_keys, ("codex:b",))
    self.assertEqual(linked["codex:b"].related_keys, ("codex:a",))
    self.assertEqual(linked["claude:c"].related_keys, ())
    self.assertEqual(linked["chatgpt:d"].related_keys, ())
```

Add cases for explicit wikilinks/shared stable entities, two shared controlled topics, project candidate plus topic, closely dated same-source high-signal title terms, five-link degree limits, and identical output after input shuffling.

- [ ] **Step 2: Run relationship tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_links -v
```

Expected: import failure for `wiki_links`.

- [ ] **Step 3: Implement candidate scoring and reciprocal degree limits**

Generate pair candidates only when one of the five spec rules matches. Represent the score as a tuple ordered by rule priority, number of shared topics/entities, negative day distance, newer update timestamp, and stable key. Sort all undirected edges deterministically and greedily accept an edge only when both endpoints remain below `max_links`. Finally, set each endpoint’s `related_keys` in score/date/key order.

Do not link pairs whose only evidence is one broad topic. Treat dates as comparable only when both parse as ISO-8601; an absent/malformed date contributes no recency score.

- [ ] **Step 4: Run relationship and full tests**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest discover -s tests -v
```

Expected: all tests pass; every emitted edge is reciprocal and every degree is at most five.

- [ ] **Step 5: Commit related-chat linking**

```bash
git add Tools/LLMChatIndex/wiki_links.py Tools/LLMChatIndex/tests/test_wiki_links.py
git commit -m "feat: link related chats deterministically"
```

---

### Task 5: Render canonical chats and navigable Obsidian pages

**Files:**
- Create: `Tools/LLMChatIndex/wiki_render.py`
- Create: `Tools/LLMChatIndex/tests/test_wiki_render.py`

**Interfaces:**
- Consumes: linked `ClassifiedChat` records and canonical filename mapping.
- Produces: `render_chat(chat: ClassifiedChat, filenames: Mapping[str, str]) -> str`.
- Produces: `render_wiki_files(chats: Iterable[ClassifiedChat], filenames: Mapping[str, str], existing_pages: Mapping[str, str]) -> Mapping[str, str]`.
- Produces: `replace_generated_block(existing: str, generated: str) -> str`.

- [ ] **Step 1: Write failing rendering tests**

Assert exact properties and clean dialogue:

```python
def test_chat_markdown_has_properties_links_and_visible_dialogue_only(self):
    rendered = render_chat(self.classified_chat(), {"codex:id-1": "Codex/Архив — id-1.md"})

    self.assertTrue(rendered.startswith("---\ntype: chat\nsource: codex\n"))
    self.assertIn('  - "[[Wiki/Projects/Nowhere]]"', rendered)
    self.assertIn('  - "[[Chats/Codex/Связанный чат — id-2]]"', rendered)
    self.assertIn("# Архив решений\n\n## Запрос\n\nПервый вопрос", rendered)
    self.assertIn("## Ответ\n\nПервый ответ", rendered)
    self.assertNotIn("source_path", rendered)
    self.assertNotIn("REASONING_SENTINEL", rendered)
    self.assertNotIn("TOOL_SENTINEL", rendered)
```

Add exact-output tests for YAML escaping, absent unknown values, repeated request/answer headings, project/topic/idea/type pages, human prose preserved outside `<!-- BEGIN GENERATED -->` markers, `Home.md`, and a valid `Chats.base` whose only file scope is `Kosta P/LLM CHATS/Chats` and whose views cover all/source/project/topic/type/unclassified/recent/review-required.

- [ ] **Step 2: Run render tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_render -v
```

Expected: import failure for `wiki_render`.

- [ ] **Step 3: Implement canonical chat rendering**

Write frontmatter fields in this stable order: `type`, `source`, `conversation_id`, `created`, `updated`, `projects`, `project_candidates`, `topics`, `types`, `ideas`, `related_chats`, `classification_status`, `privacy`, `summary_method`, `source_hash`. Omit empty scalar/list fields except `projects`, `project_candidates`, `topics`, `types`, and `related_chats`, which render as `[]` for predictable Base columns.

Quote every wikilink and user-derived scalar through one `yaml_quote(value: str) -> str` helper. Render dialogue exclusively from the already filtered `Message` tuple. Preserve Markdown inside each message verbatim after newline normalization.

- [ ] **Step 4: Implement indexes, generated blocks, and Base**

Use exact markers:

```markdown
<!-- BEGIN GENERATED: LLMChatIndex -->
generated content
<!-- END GENERATED: LLMChatIndex -->
```

If markers exist, replace only their interior. If absent, append the block after existing human text. Generate `Wiki/Projects/Nowhere.md`, controlled topic/type pages, promoted idea pages, and index pages under `Wiki/Topics/Index.md`, `Wiki/Types/Index.md`, and `Wiki/Ideas/Index.md`. Each generated list sorts chats by explicit updated/created date descending and then stable key, and links to the canonical filename without `.md`.

Render evidence-backed decision/open-question sections only from classification evidence; candidate items must say `автоматически найдено — требуется проверка`. Do not synthesize factual summaries from assistant prose.

- [ ] **Step 5: Run render and full tests**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest discover -s tests -v
```

Expected: all tests pass and every fixture wikilink resolves inside the rendered file map.

- [ ] **Step 6: Commit Obsidian rendering**

```bash
git add Tools/LLMChatIndex/wiki_render.py Tools/LLMChatIndex/tests/test_wiki_render.py
git commit -m "feat: render canonical Obsidian chat wiki"
```

---

### Task 6: Stage, validate, publish, search, and enforce the wiki owner

**Files:**
- Create: `Tools/LLMChatIndex/wiki_builder.py`
- Create: `Tools/LLMChatIndex/tests/test_wiki_builder.py`
- Modify: `Tools/LLMChatIndex/chat_index.py`
- Modify: `Tools/LLMChatIndex/tests/test_cli_and_install.py`

**Interfaces:**
- Consumes: discovery, canonicalization, classification, linking, and rendering functions from Tasks 1–5.
- Produces: `build_wiki(vault_root: Path, chat_root: Path, state_root: Path, wiki_host: str, dry_run: bool = False, timeout_seconds: float = 5.0) -> Mapping[str, object]`.
- Produces: `validate_staging(staging_root: Path, manifest: Mapping[str, object]) -> Tuple[BuildIssue, ...]`.
- Modifies: `search_chats` to select `chat_root / "Chats"` when that directory exists.
- Adds CLI: `chat-index build-wiki [--dry-run] [--json]`.

- [ ] **Step 1: Write failing builder transaction tests**

```python
def test_build_publishes_only_after_validation_and_second_build_is_noop(self):
    fixture = make_complete_archive(self.root)

    first = build_wiki(fixture.vault, fixture.chat_root, fixture.state, "host-a")
    mtimes = tree_mtimes(fixture.chat_root / "Chats")
    second = build_wiki(fixture.vault, fixture.chat_root, fixture.state, "host-a")

    self.assertEqual(first["published"], True)
    self.assertEqual(second["changed_files"], 0)
    self.assertEqual(tree_mtimes(fixture.chat_root / "Chats"), mtimes)
    self.assertEqual(file_hashes(fixture.source_paths), fixture.original_hashes)
```

Add tests that validation failure keeps the old `Chats`, `Home.md`, `Chats.base`, and manifest byte-identical; a non-owner returns `published: false` and `reason: "not-wiki-owner"`; concurrent build lock returns `reason: "locked"`; dry-run writes nothing; unreadable sources appear in manifest errors; broken wikilinks prevent publication; stale reviewed source hashes become `review-required`; and manifest contains provenance/evidence but no message bodies.

- [ ] **Step 2: Write failing CLI/search tests**

Extend `test_cli_and_install.py` to call `build-wiki --dry-run --json`, assert machine-readable counts, and prove `search` ignores a matching legacy duplicate once `Chats/` exists:

```python
with contextlib.redirect_stdout(output):
    exit_code = main(common + ["build-wiki", "--dry-run", "--json"])
self.assertEqual(exit_code, 0)
self.assertIn("canonical_chats", json.loads(output.getvalue()))

results = search_chats(chat_root, "UNIQUE CANONICAL PHRASE")
self.assertTrue(all("/Chats/" in item["path"] for item in results))
```

- [ ] **Step 3: Run builder/CLI tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_builder tests.test_cli_and_install -v
```

Expected: missing builder and command failures.

- [ ] **Step 4: Implement orchestration and manifest**

The build order must be:

1. take `state_root/build-wiki.lock` non-blockingly;
2. load/create config and compare `current_wiki_host()` with `wiki_owner`;
3. discover and hash sources;
4. canonicalize, classify, and link;
5. allocate filenames and render the complete generated file map;
6. create staging beside `chat_root` using `tempfile.mkdtemp(prefix=".LLM-CHATS-staging-", dir=chat_root.parent)`;
7. copy human-owned project/topic/idea page text into the render inputs, then write staged generated files;
8. write `_Sources/migration-manifest.json` with schema `llm-chat-wiki-manifest/v1`, counts, provenance, duplicates, evidence, issues, and source hashes;
9. validate frontmatter delimiters, unique canonical keys/paths, resolved local wikilinks, source hashes, expected manifest/file counts, and absence of excluded sentinel block types;
10. if dry-run, delete staging and return counts;
11. publish changed files using `_atomic_write`, remove only generated canonical files listed by the previous manifest but absent from the new manifest, and preserve unchanged bytes/mtimes;
12. remove staging in `finally`.

Do not delete legacy sources. Do not use a broad directory swap that could remove human-owned wiki prose. Publication is a per-file reconciliation limited to `Chats`, generated wiki blocks, `Home.md`, `Chats.base`, `_Config` defaults when absent, and `_Sources/migration-manifest.json`.

- [ ] **Step 5: Wire CLI and canonical search routing**

Add `build-wiki` arguments `--dry-run`, `--timeout-seconds` (float, default `5.0`), and `--json`. Resolve `vault_root = args.chat_root.parent`; implement `current_wiki_host() -> str` with `socket.gethostname()` for ownership, while retaining the existing random host ID only for `_Unified` namespace isolation. Return exit code `1` on validation/build errors, but `0` for non-owner and locked no-op results because they preserve correct state.

Fix the two existing duplicate statements encountered in `chat_index.py`: call `_atomic_write` once in `_write_json_if_changed`, and compute `position` once in `search_chats`.

- [ ] **Step 6: Run focused and full tests**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_wiki_builder tests.test_cli_and_install -v
PYTHONPATH=. /usr/bin/python3 -m unittest discover -s tests -v
```

Expected: all tests pass; dry-run and non-owner paths make no writes.

- [ ] **Step 7: Commit the transactional builder**

```bash
git add Tools/LLMChatIndex/wiki_builder.py Tools/LLMChatIndex/chat_index.py Tools/LLMChatIndex/tests/test_wiki_builder.py Tools/LLMChatIndex/tests/test_cli_and_install.py
git commit -m "feat: build and publish chat wiki safely"
```

---

### Task 7: Install, migrate the real archive, and verify both-Mac operation

**Files:**
- Modify: `Tools/LLMChatIndex/install_lite.py`
- Modify: `Tools/LLMChatIndex/README.md`
- Modify: `Tools/LLMChatIndex/tests/test_cli_and_install.py`
- Generated outside repository: `LLM CHATS/_Tools/LLMChatIndexLite/*`
- Generated outside repository: `LLM CHATS/Chats/**`, `LLM CHATS/Wiki/**`, `LLM CHATS/Home.md`, `LLM CHATS/Chats.base`, `LLM CHATS/_Config/*.json`, `LLM CHATS/_Sources/migration-manifest.json`

**Interfaces:**
- Consumes: completed `chat-index build-wiki`, `sync`, `search`, and installer behavior.
- Produces: installed runtime containing all `wiki_*.py` modules on each Mac.
- Produces: a verified real canonical archive and documented second-Mac workflow.

- [ ] **Step 1: Write failing installer packaging test**

Extend the installer test:

```python
for name in (
    "chat_index.py", "wiki_models.py", "wiki_sources.py", "wiki_canonical.py",
    "wiki_classify.py", "wiki_links.py", "wiki_render.py", "wiki_builder.py",
):
    self.assertTrue((runtime / name).is_file())
    self.assertTrue((chat_root / "_Tools/LLMChatIndexLite" / name).is_file())
```

Assert installation still leaves the LaunchAgent disabled unless `--enable-background` is explicit, and its scheduled command remains `sync`, not `build-wiki`, so only the owner’s deliberate build rewrites canonical pages.

- [ ] **Step 2: Run installer tests and verify failure**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest tests.test_cli_and_install -v
```

Expected: missing installed `wiki_*.py` files.

- [ ] **Step 3: Package the modules and document the workflow**

Update `install_lite.py` to copy the eight Python modules plus `README.md` to both the local runtime and shared iCloud installer folder using `_write`. Add the missing explicit parser flag `--enable-background`; keep `--no-load` as a hidden compatibility override, and calculate `load_agent=args.enable_background and not args.no_load`. Update `README.md` with these exact operational sequences:

Owner Mac:

```bash
chat-index sync
chat-index build-wiki --dry-run
chat-index build-wiki
chat-index search "вопрос пользователя"
```

Second Mac:

```bash
/usr/bin/python3 "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS/_Tools/LLMChatIndexLite/install_lite.py"
chat-index sync
```

Explain that the second Mac contributes `_Unified` source Markdown through iCloud and reads `Chats`, while the configured owner performs `build-wiki`. Document how to review `project_candidates`/`review-required`, edit `_Config/curations.json`, and rebuild.

- [ ] **Step 4: Run all automated tests before touching live archive output**

Run:

```bash
cd Tools/LLMChatIndex
PYTHONPATH=. /usr/bin/python3 -m unittest discover -s tests -v
```

Expected: all tests pass with zero failures/errors.

- [ ] **Step 5: Reinstall the owner runtime and capture the live preflight**

Run the shared installer without enabling background access, then run a dry build:

```bash
/usr/bin/python3 Tools/LLMChatIndex/install_lite.py --no-load
"$HOME/.local/bin/chat-index" sync --json
"$HOME/.local/bin/chat-index" build-wiki --dry-run --json
```

Save the JSON output in the implementation turn notes. Confirm `errors` is zero or inspect every listed path before publication. If iCloud reports a transient read timeout, wait for Finder to finish downloading that file and repeat the dry build; do not publish an incomplete snapshot silently.

- [ ] **Step 6: Publish the real canonical wiki**

Run:

```bash
"$HOME/.local/bin/chat-index" build-wiki --json
```

Expected at the recorded snapshot: 400 unique Codex IDs from the union of 277 enriched and 347 `_Unified` Codex files, with 224 duplicate IDs. Treat higher counts as valid when they are explained by new sessions; treat lower union/overlap counts as a blocker requiring manifest inspection.

- [ ] **Step 7: Verify real archive acceptance and idempotence**

Run a small read-only verification script from the repository test environment that:

- hashes all manifest source paths again and compares them with recorded hashes;
- counts canonical chats by source;
- verifies all local wikilinks resolve;
- verifies every canonical file starts with `---`, has `type: chat`, and has at least one `## Запрос` or `## Ответ`;
- searches canonical files for known technical sentinels/metadata keys such as `reasoning`, `tool_result`, `source_path`, and raw JSONL record prefixes, reviewing matches because those words may legitimately occur in visible user text;
- records mtimes, runs `build-wiki` again, and asserts `changed_files == 0` with unchanged mtimes.

Then manually open `LLM CHATS/Home.md`, `LLM CHATS/Chats.base`, `LLM CHATS/Wiki/Projects/Nowhere.md`, one ChatGPT chat, one official Claude chat, one Claude Code chat, and one Codex chat in Obsidian. Confirm navigation and readable Russian/English dialogue.

- [ ] **Step 8: Commit installer and documentation**

```bash
git add Tools/LLMChatIndex/install_lite.py Tools/LLMChatIndex/README.md Tools/LLMChatIndex/tests/test_cli_and_install.py
git commit -m "docs: install and operate the chat wiki"
```

- [ ] **Step 9: Report second-Mac action without changing ownership**

Tell the user to let iCloud finish downloading `_Tools/LLMChatIndexLite`, run the documented installer and `chat-index sync` on the second Mac, then run `chat-index build-wiki` once on the owner Mac. Verify the next owner build adds only genuinely new source identities and retains all manual curations and human text.
