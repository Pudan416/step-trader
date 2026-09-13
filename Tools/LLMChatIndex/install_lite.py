#!/usr/bin/env python3
"""Install the lightweight chat importer and its five-minute LaunchAgent."""

import argparse
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional


LABEL = "com.kostapudan.llm-chat-index-lite"
DEFAULT_CHAT_RELATIVE = Path("Library/Mobile Documents/iCloud~md~obsidian/Documents/Kosta P/LLM CHATS")


def _write(path: Path, data: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name("." + path.name + ".new")
    temporary.write_bytes(data)
    temporary.chmod(mode)
    os.replace(str(temporary), str(path))


def _plist(runtime_script: Path, home: Path, chat_root: Path) -> bytes:
    state_root = home / "Library/Application Support/LLMChatIndexLite"
    logs = state_root / "logs"
    value = {
        "Label": LABEL,
        "ProgramArguments": [
            "/usr/bin/python3",
            str(runtime_script),
            "--home",
            str(home),
            "--chat-root",
            str(chat_root),
            "--state-root",
            str(state_root),
            "sync",
        ],
        "RunAtLoad": True,
        "StartInterval": 300,
        "StandardOutPath": str(logs / "sync.log"),
        "StandardErrorPath": str(logs / "sync-error.log"),
        "ProcessType": "Background",
    }
    return plistlib.dumps(value, sort_keys=True)


def install(source_dir: Path, home: Path, chat_root: Path, load_agent: bool = True) -> Dict[str, object]:
    source_dir = source_dir.resolve()
    runtime = home / ".local/share/llm-chat-index-lite"
    runtime_script = runtime / "chat_index.py"
    launcher = home / ".local/bin/chat-index"
    plist_path = home / "Library/LaunchAgents" / (LABEL + ".plist")
    state_root = home / "Library/Application Support/LLMChatIndexLite"
    shared = chat_root / "_Tools/LLMChatIndexLite"
    logs = state_root / "logs"
    for directory in (runtime, launcher.parent, plist_path.parent, logs, shared):
        directory.mkdir(parents=True, exist_ok=True)
    _write(runtime_script, (source_dir / "chat_index.py").read_bytes(), 0o700)
    _write(runtime / "install_lite.py", (source_dir / "install_lite.py").read_bytes(), 0o700)
    launcher_text = '#!/bin/sh\nexec /usr/bin/python3 "{0}" "$@"\n'.format(runtime_script)
    _write(launcher, launcher_text.encode("utf-8"), 0o700)
    _write(plist_path, _plist(runtime_script, home, chat_root), 0o600)
    for name in ("chat_index.py", "install_lite.py", "README.md"):
        source = source_dir / name
        if source.is_file():
            _write(shared / name, source.read_bytes(), 0o700 if name.endswith(".py") else 0o600)
    loaded = False
    if load_agent:
        domain = "gui/{0}".format(os.getuid())
        subprocess.run(["launchctl", "bootout", domain, str(plist_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        subprocess.run(["launchctl", "bootstrap", domain, str(plist_path)], check=True)
        loaded = True
    subprocess.run(
        [
            "/usr/bin/python3",
            str(runtime_script),
            "--home",
            str(home),
            "--chat-root",
            str(chat_root),
            "--state-root",
            str(state_root),
            "sync",
        ],
        check=False,
    )
    return {
        "runtime": str(runtime),
        "launcher": str(launcher),
        "launch_agent": str(plist_path),
        "shared_installer": str(shared / "install_lite.py"),
        "loaded": loaded,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Install the lightweight local chat archive")
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--chat-root", type=Path)
    parser.add_argument("--enable-background", action="store_true", help="Load the five-minute LaunchAgent after macOS access is granted")
    parser.add_argument("--no-load", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    chat_root = args.chat_root or args.home / DEFAULT_CHAT_RELATIVE
    result = install(
        Path(__file__).resolve().parent,
        args.home,
        chat_root,
        load_agent=args.enable_background and not args.no_load,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
