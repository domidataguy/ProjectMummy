#!/bin/sh
# Cursor user hook. Copies the model pin into a project .claude folder.
# The Ollama key is never written here. setup.sh asks for it.
input=$(cat)
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '{"pluginPaths":[]}'
  exit 0
fi

HOOK_INPUT="$input" python3 -c '
import json, os, shutil, sys
from pathlib import Path

raw = os.environ.get("HOOK_INPUT") or ""
try:
    payload = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    payload = {}

home = Path.home()
roots = payload.get("workspace_roots") or []
if not roots and os.environ.get("CURSOR_PROJECT_DIR"):
    roots = [os.environ["CURSOR_PROJECT_DIR"]]

template = home / ".cursor" / "templates" / ".claude" / "settings.json"
if template.is_file():
    for root in roots:
        if not root:
            continue
        project = Path(root)
        if not project.is_dir():
            continue
        dest = project / ".claude" / "settings.json"
        if dest.exists():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(template, dest)

event = payload.get("hook_event_name") or ""
if event == "sessionStart":
    settings = home / ".claude" / "settings.json"
    has_key = False
    if settings.is_file():
        try:
            data = json.loads(settings.read_text(encoding="utf-8"))
            token = str((data.get("env") or {}).get("ANTHROPIC_AUTH_TOKEN") or "")
            has_key = len(token) >= 8
        except Exception:
            has_key = False
    if has_key:
        message = "Claude Code on this PC uses Ollama Cloud. The main model is glm-5.3. Background calls use glm-5.3-flash. The API key stays in the user profile .claude settings. Do not print or copy API keys."
    else:
        message = "Claude Code has no Ollama key on this PC yet. Tell the user to run setup.ps1 on Windows, or setup.sh on Mac or Linux, from the claude-ollama-setup repo. That script asks for the key in the terminal. Do not ask them to paste the key into chat."
    print(json.dumps({"additional_context": message}))
else:
    print(json.dumps({"pluginPaths": []}))
'
