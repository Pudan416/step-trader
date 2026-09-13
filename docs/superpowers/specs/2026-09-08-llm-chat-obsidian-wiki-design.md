# LLM Chat Obsidian Wiki — Design

Date: 2026-09-08

## Purpose

Turn the existing local-first chat archive into one navigable Obsidian wiki. Historical ChatGPT, Claude, Claude Code, and Codex conversations become canonical Markdown documents with consistent properties, clean dialogue bodies, project/topic/type links, and evidence-aware related-chat navigation.

The first semantic layer is deterministic and local. It uses source identifiers, explicit aliases, existing archive metadata, titles, user-authored text, and controlled keyword rules. It does not send chats to a hosted model, install embeddings, or claim to have semantically reviewed every conversation.

## Confirmed project aliases

These names all identify one canonical project:

```text
StepTrader
StepsTrader
step-trader
Step4
Steps4
→ Nowhere
```

They link to `[[Wiki/Projects/Nowhere]]`. Matching is case-insensitive and separator-insensitive. The alias table is explicit and user-editable; automatic title similarity must never create a project alias.

## Current source inventory

The migration starts from these observed sources in the `Kosta P` Obsidian vault:

- 1,017 top-level Markdown conversations in `LLM CHATS`, currently using primarily `## user` and `## assistant` headings;
- 415 official Claude conversations under `LLM CHATS/Claude Official Export 2026-09-08/conversations`, plus its README and index;
- 277 enriched Codex Markdown conversations under `Codex history/2026`, plus `Index.md` and `Chats.base`;
- 347 generated Codex Markdown files under `LLM CHATS/_Unified/codex` from two Macs;
- 45 generated Claude Code Markdown files under `LLM CHATS/_Unified/claude-code` from two Macs.

The 277 enriched Codex conversations overlap with 224 `_Unified/codex` IDs. Fifty-three enriched Codex conversations are not currently represented in `_Unified`; 123 `_Unified` Codex IDs are not in the enriched archive. The canonical union is therefore 400 unique Codex conversation IDs at this snapshot.

Counts are acceptance baselines, not permanent constants. New local sessions may appear while migration is running.

## Canonical structure

```text
LLM CHATS/
  Home.md
  Chats.base
  Chats/
    ChatGPT/
    Claude/
    Claude Code/
    Codex/
  Wiki/
    Projects/
      Nowhere.md
    Topics/
    Ideas/
    Types/
  _Config/
    aliases.json
    taxonomy.json
    curations.json
  _Sources/
    migration-manifest.json
```

`Chats/` is the only canonical retrieval root. The local `chat-index search` command searches it when present and falls back to the legacy `LLM CHATS` layout only before migration.

`_Sources/migration-manifest.json` records original paths, source hashes, canonical IDs, selected versions, duplicates, and migration errors. It does not contain message bodies. Original source files are preserved during migration. They are not deleted or overwritten automatically.

Local recovery ZIP files remain outside iCloud under:

`~/Library/Application Support/LLMChatIndexLite/backups`

## Canonical chat document

Every canonical chat is valid Obsidian Markdown with a small consistent property block and a dialogue-only body:

```yaml
---
type: chat
source: codex
conversation_id: "019f1ed8-5f7f-70b0-9cf7-e93b207a867d"
created: 2026-07-01T20:02:04+02:00
updated: 2026-07-01T20:02:06+02:00
projects:
  - "[[Wiki/Projects/Nowhere]]"
project_candidates: []
topics:
  - "[[Wiki/Topics/Automation]]"
types:
  - research
related_chats:
  - "[[Chats/Codex/Related conversation]]"
classification_status: auto
summary_method: existing-extractive
source_hash: "sha256:..."
---
```

The body contains only:

```markdown
# Conversation title

## Запрос

Visible user text

## Ответ

Visible assistant text
```

Additional request/answer pairs repeat the same headings. Headings, lists, code blocks, links, and images inside a message remain intact. Timestamps, reasoning, system/developer prompts, tool calls, tool results, command output, and raw attachment bodies do not appear in the body.

Properties are navigation data, not transcript content. Empty or unknown values remain empty or absent; the migration never invents dates or identities from filesystem timestamps.

## Identity and deduplication

Deduplication never uses title alone.

Source identity rules:

- Codex: full `codex_thread_id` from enriched frontmatter or full session UUID from `_Unified` filename/state;
- Claude official: exported conversation UUID from the existing conversion manifest or filename;
- Claude Code: source session UUID;
- legacy top-level ChatGPT Markdown: existing source ID when available, otherwise `chatgpt-legacy:` plus SHA-256 of normalized relative path and content.

For two Codex documents with the same full thread ID, the canonical builder selects the version with the greatest number of non-empty request/answer messages. Ties prefer the newer explicit `updated` value, then the enriched `Codex history` version, then the lexicographically smallest source path. Every rejected duplicate remains recorded in the migration manifest.

Exact cross-source body matches are recorded as possible duplicates but are not automatically merged, because the same dialogue may have been intentionally copied between products.

Canonical filenames use a readable sanitized title plus the last eight characters of the stable ID. Filename collisions append a longer ID suffix; they never overwrite an unrelated chat.

## Taxonomy

### Projects

A project is a sustained body of work, not any named entity in a conversation. A chat receives a confirmed `projects` link only when at least one of these holds:

- an explicit alias in `_Config/aliases.json` matches the title, user-authored message, source project path, or source workspace;
- `_Config/curations.json` assigns it manually;
- an already reviewed source property assigns it to a canonical project.

Other plausible names go into `project_candidates` with `classification_status: auto`; they do not create canonical project pages until confirmed. `unknown` is valid.

The Nowhere mapping may use Codex/Claude Code workspace paths containing `step-trader`, `StepsTrader`, `Step4`, or `Steps4` as explicit evidence even when the visible dialogue omits the project name.

### Topics

Topics are broad reusable subjects. Phase one bootstraps a controlled vocabulary from:

- existing `topics` in the enriched Codex archive;
- repeated high-signal title terms;
- explicit rules in `_Config/taxonomy.json`.

A chat receives at most three topic links automatically. Topic aliases normalize spelling and language variants to one page. Low-signal stop words and one-off proper nouns do not create topics.

### Types

A chat may have one to three controlled types:

- `idea` — the user explicitly develops or requests an idea;
- `decision` — the transcript contains an explicit user acceptance or choice;
- `code` — implementation, debugging, or repository work;
- `research` — investigation, comparison, or evidence gathering;
- `personal` — explicitly personal planning or reflection;
- `one-off` — a bounded request with no durable project/topic role.

An assistant proposal alone is not a user decision. A request to implement is not proof that implementation occurred. Missing later replies do not make a historical task currently open.

### Ideas

Idea pages are intentionally sparse. An automatic idea page is created only when:

- the user explicitly names an idea, concept, campaign, feature, or experiment; and
- it appears in at least two conversations or is manually confirmed in `curations.json`.

Assistant-only suggestions may be listed as candidates but never become attributed user ideas automatically.

## Related-chat links

No embedding model is used in phase one. Candidate relationships receive deterministic scores:

1. same confirmed project;
2. explicit wikilink or shared stable entity;
3. at least two shared controlled topics;
4. same project candidate plus one shared topic;
5. closely dated chats with the same source and high-signal title term.

Each chat receives at most five `related_chats` links. A relationship must be reciprocal in canonical metadata. Ties sort by updated date and stable ID for repeatable builds. Chats connected only by one broad topic such as `AI` are not linked automatically.

## Wiki pages

### Home

`Home.md` links to the global Base, sources, recently updated chats, confirmed projects, topic index, idea index, unclassified chats, and items awaiting review.

### Project pages

Each confirmed project page contains:

- canonical name and aliases;
- a human-editable overview;
- a generated block listing linked chats by date and type;
- automatically detected open questions and decisions only when they have message-level evidence;
- links to related topics and ideas.

Generated content is bounded by explicit markers. Rebuilds replace only the generated block and preserve text outside it.

### Topic, idea, and type pages

These pages provide a short definition and a generated list of linked chats. Automatically inferred descriptions are labeled as generated. Pages never present assistant output as independently verified fact.

### Chats Base

`Chats.base` reads only `LLM CHATS/Chats` and provides views for:

- all chats;
- source;
- project;
- topic;
- type;
- unclassified/project candidates;
- recently updated;
- review required.

Missing optional properties render as empty cells and do not exclude a chat.

## Evidence and review state

Automatic classification is navigation assistance, not a semantic claim about the user.

Every nontrivial project, idea, decision, outcome, or open-question record stores evidence in the local build manifest: conversation ID, role, message ordinal, explicit/inferred strength, source timestamp when known, and source hash. Generated wiki pages link back to the supporting chat heading.

Classification states:

- `structural` — only source/ID/date/body normalization;
- `auto` — deterministic rule or inherited unreviewed metadata;
- `reviewed` — confirmed through `_Config/curations.json`;
- `review-required` — conflicting or ambiguous evidence.

Historical statements default to historical/unknown current validity. Newer timestamps do not automatically supersede older decisions. Privacy defaults to `personal`; automatic processing does not create public labels.

## Human edits and generated data

- Canonical transcript bodies and generated property fields are rebuildable; users should not edit them directly.
- Project/topic/idea page text outside generated markers is human-owned and never overwritten.
- Manual aliases, merges, classifications, exclusions, and privacy corrections live in `_Config/aliases.json`, `taxonomy.json`, and `curations.json`.
- Configuration edits take precedence over automatic classification.
- A changed source hash marks reviewed semantic records stale; rebuilding never silently clears that state.

## Build workflow

The lightweight tool gains one command:

```text
chat-index build-wiki
```

It performs:

1. inventory and hash all known source Markdown without modifying it;
2. parse source-specific dialogue and properties;
3. assign stable IDs and select canonical versions;
4. apply explicit aliases and manual curations;
5. classify topics/types and create project/idea candidates;
6. compute bounded reciprocal related-chat links;
7. render the complete result to a sibling staging directory;
8. validate counts, links, properties, and source preservation;
9. atomically publish `Chats`, generated wiki blocks, `Home.md`, `Chats.base`, and the migration manifest.

A no-op rebuild changes no canonical file bytes or modification times.

## Two-Mac ownership

Both Macs continue contributing local Codex and Claude Code source sessions to their host namespaces. Only one configured wiki-owner host publishes the canonical `Chats/` and generated wiki indexes, preventing concurrent iCloud rewrites. The other Mac reads the canonical wiki and runs only local-source synchronization.

The initial wiki owner is the current `Konstantins-MacBook-Pro.local` host ID unless the user changes `_Config/curations.json` explicitly.

## Failure handling

- Unreadable or currently syncing iCloud files are reported and skipped; a build never waits forever on one file.
- The last complete canonical wiki remains active if staging validation fails.
- Malformed frontmatter falls back to structural parsing when dialogue headings remain readable.
- Unresolved duplicate identities remain separate and appear in a review report.
- Broken wikilinks fail validation before publication.
- Recovery ZIPs and source manifests allow every migration write to be traced back to preserved originals.

## Privacy

- All parsing, classification, linking, and rendering occur locally.
- Phase one uses no LLM, embedding model, remote vector service, or network API.
- Chat text, summaries, queries, classifications, and excerpts are not uploaded as part of the build.
- Logs contain paths, IDs, hashes, counts, timings, and errors, never full message bodies.
- Potential secrets and personal-sensitive text are not copied into summaries, topic descriptions, or generated wiki pages.

## Testing and acceptance

Fixtures cover all four source formats, malformed files, code fences containing role-like headings, numbered request/answer headings, frontmatter preservation rules, stable IDs, aliases, controlled topics/types, evidence roles, duplicate selection, filename collisions, reciprocal links, manual overrides, generated-block preservation, iCloud read timeouts, staging rollback, and idempotent rebuilds.

Real-data acceptance must establish:

- source files and their hashes remain unchanged;
- 277 enriched Codex files plus 347 `_Unified` Codex files resolve to 400 canonical Codex IDs at the current snapshot;
- `StepTrader`, `StepsTrader`, `step-trader`, `Step4`, and `Steps4` resolve only to `Wiki/Projects/Nowhere.md`;
- every canonical chat begins with valid Obsidian properties and contains only visible dialogue in its body;
- every `projects`, `topics`, `ideas`, and `related_chats` wikilink resolves;
- every generated decision, outcome, open question, and idea has message-level evidence or is labeled a candidate;
- `Chats.base` excludes `_Sources`, `_Unified`, legacy locations, README files, and indexes;
- a second build produces zero changes;
- representative Russian and English searches retrieve canonical files rather than legacy duplicates;
- manual text outside generated wiki markers survives rebuild.

## Deferred extensions

- Local-LLM semantic classification for chats left unclassified by deterministic rules;
- embeddings and cross-language semantic retrieval;
- automatic processing of future official Claude or ChatGPT exports;
- attachment OCR and media indexing;
- visual graph layouts beyond Obsidian's native links and graph view.
