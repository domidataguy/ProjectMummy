#!/usr/bin/env bash
# Project Mummy. Name the project, pick an API that is not a Claude account, install Claude Code.
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

write_settings() {
  HOME_PATH="$HOME_PATH" OLLAMA_KEY_CHECK="$1" \
  MUMMY_BASE="$2" MUMMY_MODEL="$3" MUMMY_FAST="$4" MUMMY_DISCOVER="$5" \
  python3 -c '
import json, os
from pathlib import Path
home = Path(os.environ["HOME_PATH"])
dest = home / ".claude"
dest.mkdir(parents=True, exist_ok=True)
model = os.environ["MUMMY_MODEL"]
fast = os.environ["MUMMY_FAST"]
env = {
    "ANTHROPIC_BASE_URL": os.environ["MUMMY_BASE"],
    "ANTHROPIC_AUTH_TOKEN": os.environ["OLLAMA_KEY_CHECK"],
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": model,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": fast,
    "ANTHROPIC_DEFAULT_FABLE_MODEL": model,
    "CLAUDE_CODE_SUBAGENT_MODEL": model,
}
if os.environ.get("MUMMY_DISCOVER") == "1":
    env["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
settings = {"model": model, "env": env}
(dest / "settings.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
'
  unset OLLAMA_KEY_CHECK MUMMY_BASE MUMMY_MODEL MUMMY_FAST MUMMY_DISCOVER
}

install_hook() {
  local cursor hook_dir template_dir command
  cursor="$HOME_PATH/.cursor"
  hook_dir="$cursor/hooks"
  template_dir="$cursor/templates/.claude"
  mkdir -p "$hook_dir" "$template_dir"
  cp "$SCRIPT_DIR/hooks/ensure-claude-setup.sh" "$hook_dir/ensure-claude-setup.sh"
  chmod +x "$hook_dir/ensure-claude-setup.sh"
  MUMMY_MODEL="$1" MUMMY_TEMPLATE="$template_dir/settings.json" python3 -c '
import json, os
from pathlib import Path
dest = Path(os.environ["MUMMY_TEMPLATE"])
dest.write_text(json.dumps({"model": os.environ["MUMMY_MODEL"]}) + "\n", encoding="utf-8")
'
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

valid_project_name() {
  HOME_PATH="$1" python3 -c '
import os, sys
name = os.environ["HOME_PATH"]
reserved = {
    "CON","PRN","AUX","NUL",
    "COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9",
    "LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9",
}
if not name or len(name) > 80 or name in {".", ".."} or name.endswith(".") or name.endswith(" "):
    raise SystemExit(1)
if any(ch in name for ch in "\\/:*?\"<>|"):
    raise SystemExit(1)
if name.split(".", 1)[0].upper() in reserved:
    raise SystemExit(1)
'
}

prompt_project_name() {
  local current parent name dest
  current=$(basename "$SCRIPT_DIR")
  parent=$(dirname "$SCRIPT_DIR")
  echo "" >&2
  echo "New project" >&2
  echo "The setup folder will be renamed. It is currently:" >&2
  echo "  $SCRIPT_DIR" >&2
  while true; do
    echo "Local repo name:" >&2
    IFS= read -r name || true
    name=$(printf '%s' "$name" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if ! valid_project_name "$name"; then
      echo "Use one folder name: letters, numbers, dot, dash, and underscore. No slashes." >&2
      continue
    fi
    if [ "$name" = "$current" ]; then
      printf '%s' "$SCRIPT_DIR"
      return
    fi
    dest="$parent/$name"
    if [ -e "$dest" ]; then
      echo "That folder already exists: $dest" >&2
      continue
    fi
    printf '%s' "$dest"
    return
  done
}

rename_project_folder() {
  local new_path="$1"
  if [ "$new_path" = "$SCRIPT_DIR" ]; then
    echo "Folder name unchanged: $SCRIPT_DIR" >&2
    printf '%s' "$SCRIPT_DIR"
    return
  fi
  case "$SCRIPT_DIR" in
    "/"|"/Users"|"/home"|"$HOME_PATH")
      echo "Refusing to rename this folder. Claude Code setup is still in place at $SCRIPT_DIR" >&2
      printf '%s' "$SCRIPT_DIR"
      return
      ;;
  esac
  if mv "$SCRIPT_DIR" "$new_path"; then
    git -C "$new_path" remote remove origin >/dev/null 2>&1 || true
    echo "Renamed the project folder to $new_path" >&2
    echo "The Project Mummy git remote was removed so this project does not push back to it." >&2
    printf '%s' "$new_path"
    return
  fi
  echo "Claude Code is ready. The folder is in use, so it was not renamed." >&2
  echo "Close programs using it, then run:" >&2
  echo "mv $(printf '%q' "$SCRIPT_DIR") $(printf '%q' "$new_path")" >&2
  printf '%s' "$SCRIPT_DIR"
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

prompt_service() {
  local choice model base fast
  echo "" >&2
  echo "API service" >&2
  echo "Claude Code will use this key. A Claude account is not required." >&2
  echo "  1  Ollama Cloud     glm-5.3, no Claude account" >&2
  echo "  2  OpenRouter       your model, OpenRouter credits" >&2
  echo "  3  Other            any service that speaks the Anthropic Messages API" >&2
  while true; do
    echo "Choose 1, 2, or 3:" >&2
    IFS= read -r choice || true
    choice=$(printf '%s' "$choice" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$choice" = "1" ]; then
      printf '%s\n' "Ollama Cloud" "https://ollama.com" "glm-5.3" "glm-5.3-flash" "https://ollama.com/settings/keys" "https://ollama.com/api/tags" "0"
      return
    fi
    if [ "$choice" = "2" ]; then
      echo "OpenRouter model id (Enter for openrouter/auto):" >&2
      IFS= read -r model || true
      model=$(printf '%s' "$model" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$model" ]; then model="openrouter/auto"; fi
      printf '%s\n' "OpenRouter" "https://openrouter.ai/api" "$model" "$model" "https://openrouter.ai/settings/keys" "https://openrouter.ai/api/v1/key" "1"
      return
    fi
    if [ "$choice" = "3" ]; then
      echo "Base URL, including https://:" >&2
      IFS= read -r base || true
      base=$(printf '%s' "$base" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s:/*$::')
      case "$base" in
        https://*) ;;
        *) echo "The base URL has to start with https://" >&2; continue ;;
      esac
      echo "Model id:" >&2
      IFS= read -r model || true
      model=$(printf '%s' "$model" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$model" ]; then echo "A model id is required." >&2; continue; fi
      echo "Smaller model for background calls (Enter to reuse $model):" >&2
      IFS= read -r fast || true
      fast=$(printf '%s' "$fast" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$fast" ]; then fast="$model"; fi
      printf '%s\n' "Custom" "$base" "$model" "$fast" "" "$base" "0"
      return
    fi
    echo "Type 1, 2, or 3." >&2
  done
}

key_ok_url() {
  OLLAMA_KEY_CHECK="$1" MUMMY_CHECK_URL="$2" python3 -c '
import os, urllib.request
key = os.environ.get("OLLAMA_KEY_CHECK") or ""
url = os.environ["MUMMY_CHECK_URL"]
req = urllib.request.Request(url, headers={"Authorization": "Bearer " + key})
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        raise SystemExit(0 if resp.status == 200 else 1)
except Exception:
    raise SystemExit(1)
'
}

prompt_service_key() {
  local name="$1" base="$2" key_url="$3" check_url="$4"
  local saved saved_base typed allow
  saved=$(saved_key || true)
  saved_base=$(HOME_PATH="$HOME_PATH" python3 -c '
import json, os
from pathlib import Path
path = Path(os.environ["HOME_PATH"]) / ".claude" / "settings.json"
if not path.is_file():
    raise SystemExit(0)
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)
print(str((data.get("env") or {}).get("ANTHROPIC_BASE_URL") or ""))
')
  echo "" >&2
  echo "API key for $name" >&2
  if [ -n "$key_url" ]; then echo "Create or copy one at $key_url" >&2; fi
  echo "The key is saved only on this computer. It is not stored in git." >&2
  if [ -n "$saved" ] && [ "$saved_base" = "$base" ]; then
    echo "A key ending in $(key_tail "$saved") is already saved for this service." >&2
  fi
  echo "" >&2
  while true; do
    if [ -n "$saved" ] && [ "$saved_base" = "$base" ]; then
      echo "Press Enter to keep the saved key, or paste a new key. Input stays hidden." >&2
    else
      echo "Paste the API key. Input stays hidden." >&2
    fi
    IFS= read -r -s typed || true
    echo "" >&2
    typed=$(printf '%s' "$typed" | tr -d '\r')
    if [ -z "$typed" ]; then
      if [ -n "$saved" ] && [ "$saved_base" = "$base" ]; then
        printf '%s' "$saved"
        return
      fi
      echo "A key is required." >&2
      continue
    fi
    echo "Checking the key..." >&2
    if key_ok_url "$typed" "$check_url"; then
      echo "Key accepted. It ends in $(key_tail "$typed")." >&2
      printf '%s' "$typed"
      return
    fi
    if [ "$name" = "Custom" ]; then
      echo "The check did not succeed. Type yes to save this key anyway:" >&2
      IFS= read -r allow || true
      allow=$(printf '%s' "$allow" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ "$allow" = "yes" ]; then
        printf '%s' "$typed"
        return
      fi
    fi
    echo "That key was rejected. Paste it again." >&2
  done
}

PROJECT_PATH=$(prompt_project_name)
SERVICE_LINES=$(prompt_service)
SERVICE_NAME=$(printf '%s\n' "$SERVICE_LINES" | sed -n '1p')
SERVICE_BASE=$(printf '%s\n' "$SERVICE_LINES" | sed -n '2p')
SERVICE_MODEL=$(printf '%s\n' "$SERVICE_LINES" | sed -n '3p')
SERVICE_FAST=$(printf '%s\n' "$SERVICE_LINES" | sed -n '4p')
SERVICE_KEY_URL=$(printf '%s\n' "$SERVICE_LINES" | sed -n '5p')
SERVICE_CHECK=$(printf '%s\n' "$SERVICE_LINES" | sed -n '6p')
SERVICE_DISCOVER=$(printf '%s\n' "$SERVICE_LINES" | sed -n '7p')
KEY=$(prompt_service_key "$SERVICE_NAME" "$SERVICE_BASE" "$SERVICE_KEY_URL" "$SERVICE_CHECK")
write_settings "$KEY" "$SERVICE_BASE" "$SERVICE_MODEL" "$SERVICE_FAST" "$SERVICE_DISCOVER"
unset KEY
install_hook "$SERVICE_MODEL"
install_claude
PROJECT_PATH=$(rename_project_folder "$PROJECT_PATH")
echo ""
echo "Ready. Project Mummy wrapped this project."
echo "Claude Code uses $SERVICE_MODEL at $SERVICE_BASE."
echo "Settings: $HOME_PATH/.claude/settings.json"
echo "Project folder: $PROJECT_PATH"
echo "Open a new terminal in that folder, then run: claude"
