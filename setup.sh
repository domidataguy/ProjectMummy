#!/usr/bin/env bash
# Ask for an Ollama key, install or update Claude Code, and copy the Cursor hook.
set -euo pipefail

HOME_PATH="${HOME_PATH:-$HOME}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required."
  exit 1
fi

key_tail() {
  printf '%s' "$1" | python3 -c 'import sys; s=sys.stdin.read(); print(s[-4:] if len(s)>=4 else "....")'
}

saved_key() {
  HOME_PATH="$HOME_PATH" python3 -c '
import json, os
from pathlib import Path
path = Path(os.environ["HOME_PATH"]) / ".claude" / "settings.json"
if not path.is_file():
    raise SystemExit(0)
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)
token = str((data.get("env") or {}).get("ANTHROPIC_AUTH_TOKEN") or "")
if len(token) >= 8:
    print(token)
'
}

key_ok() {
  OLLAMA_KEY_CHECK="$1" python3 -c '
import os, urllib.request
key = os.environ.get("OLLAMA_KEY_CHECK") or ""
req = urllib.request.Request(
    "https://ollama.com/api/tags",
    headers={"Authorization": "Bearer " + key},
)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        raise SystemExit(0 if resp.status == 200 else 1)
except Exception:
    raise SystemExit(1)
'
}

prompt_key() {
  local saved envkey typed
  saved=$(saved_key || true)
  envkey="${OLLAMA_KEY:-${OLLAMA_API_KEY:-}}"
  echo "" >&2
  echo "Ollama API key" >&2
  echo "Create or copy one at https://ollama.com/settings/keys" >&2
  echo "The key is saved only on this computer. It is not stored in git." >&2
  if [ -n "$saved" ]; then
    echo "A key ending in $(key_tail "$saved") is already saved on this computer." >&2
  fi
  if [ -n "$envkey" ]; then
    echo "This terminal already has a key ending in $(key_tail "$envkey")." >&2
  fi
  echo "" >&2
  while true; do
    if [ -n "$saved" ] || [ -n "$envkey" ]; then
      echo "Press Enter to keep the saved key, or paste a new key. Input stays hidden." >&2
    else
      echo "Paste your Ollama API key. Input stays hidden." >&2
    fi
    IFS= read -r -s typed || true
    echo "" >&2
    typed=$(printf '%s' "$typed" | tr -d '\r')
    if [ -z "$typed" ]; then
      if [ -n "$saved" ]; then
        printf '%s' "$saved"
        return
      fi
      if [ -n "$envkey" ]; then
        printf '%s' "$envkey"
        return
      fi
      echo "A key is required." >&2
      continue
    fi
    echo "Checking the key with Ollama..." >&2
    if key_ok "$typed"; then
      echo "Key accepted. It ends in $(key_tail "$typed")." >&2
      printf '%s' "$typed"
      return
    fi
    echo "Ollama rejected that key. Paste it again." >&2
  done
}

write_settings() {
  HOME_PATH="$HOME_PATH" OLLAMA_KEY_CHECK="$1" python3 -c '
import json, os
from pathlib import Path
home = Path(os.environ["HOME_PATH"])
dest = home / ".claude"
dest.mkdir(parents=True, exist_ok=True)
settings = {
    "model": "glm-5.3",
    "env": {
        "ANTHROPIC_BASE_URL": "https://ollama.com",
        "ANTHROPIC_AUTH_TOKEN": os.environ["OLLAMA_KEY_CHECK"],
        "ANTHROPIC_API_KEY": "",
        "ANTHROPIC_MODEL": "glm-5.3",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.3",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5.3",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5.3-flash",
        "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.3",
        "CLAUDE_CODE_SUBAGENT_MODEL": "glm-5.3",
    },
}
(dest / "settings.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
'
  unset OLLAMA_KEY_CHECK
}

install_hook() {
  local cursor hook_dir template_dir command
  cursor="$HOME_PATH/.cursor"
  hook_dir="$cursor/hooks"
  template_dir="$cursor/templates/.claude"
  mkdir -p "$hook_dir" "$template_dir"
  cp "$SCRIPT_DIR/hooks/ensure-claude-setup.sh" "$hook_dir/ensure-claude-setup.sh"
  chmod +x "$hook_dir/ensure-claude-setup.sh"
  cp "$SCRIPT_DIR/templates/.claude/settings.json" "$template_dir/settings.json"
  command="./hooks/ensure-claude-setup.sh"
  HOME_PATH="$HOME_PATH" HOOK_COMMAND="$command" python3 -c '
import json, os
from pathlib import Path
path = Path(os.environ["HOME_PATH"]) / ".cursor" / "hooks.json"
command = os.environ["HOOK_COMMAND"]
config = {"version": 1, "hooks": {}}
if path.is_file():
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        backup = path.with_name("hooks.json.bak")
        backup.write_bytes(path.read_bytes())
        print("Existing hooks.json could not be read. A backup is at " + str(backup))
        config = {"version": 1, "hooks": {}}
hooks = config.setdefault("hooks", {})
for event in ("workspaceOpen", "sessionStart"):
    entries = hooks.get(event) or []
    if isinstance(entries, dict):
        entries = [entries]
    if not any(isinstance(item, dict) and item.get("command") == command for item in entries):
        entries.append({"command": command})
    hooks[event] = entries
config["version"] = config.get("version") or 1
path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
'
}

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    echo "Checking Claude Code for updates..."
    claude update || echo "claude update did not install a new version. The installed copy is still in place."
    return
  fi
  echo "Installing Claude Code..."
  uname_s=$(uname -s)
  if [ "$uname_s" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    brew install --cask claude-code
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  echo "Claude Code installed. Open a new terminal so claude is on PATH."
}

KEY=$(prompt_key)
write_settings "$KEY"
unset KEY
install_hook
install_claude
echo ""
echo "Ready. Claude Code uses glm-5.3 through Ollama Cloud."
echo "Settings: $HOME_PATH/.claude/settings.json"
echo "Open a new terminal, then run: claude"
