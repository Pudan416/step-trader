# Lightweight local chat archive

This small, dependency-free tool copies the visible user/assistant dialogue from local Codex and Claude Code JSONL logs into readable Markdown in the Obsidian iCloud folder. It does not copy system prompts, thinking, tool calls, tool results, or command output.

It also searches all Markdown below `LLM CHATS`, including the existing official Claude export:

```bash
chat-index search "история iCloud"
chat-index status
chat-index sync
```

Original source logs are read-only. If a source disappears, its normalized Markdown remains in the archive.

The installer prepares a LaunchAgent that can run `sync` at login and every five minutes, but does not enable it by default. macOS blocks an unattended Python process from updating existing files inside Obsidian's iCloud container unless that process has been explicitly granted access. Until background access is enabled, run `chat-index sync` manually; Codex and Claude Code can also run that command when asked.

## Second Mac

After iCloud has downloaded the folder, run:

```bash
python3 "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS/_Tools/LLMChatIndexLite/install_lite.py"
```

The second Mac gets its own local host ID and writes into its own `_Unified` namespace. The Markdown is shared through iCloud; local importer state is not.

## Asking an agent

Tell Codex or Claude Code: `Use chat-index search to find relevant conversations in my local chat archive, then open the returned Markdown files and cite their paths.`
