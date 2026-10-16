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
  (
    cd "$(dirname "$SCRIPT_DIR")" || exit 1
    mv "$SCRIPT_DIR" "$new_path" 2>/dev/null || {
      mkdir -p "$new_path"
      find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 -exec mv {} "$new_path"/ \; 2>/dev/null || true
    }
  )
  if [ -d "$new_path/.git" ]; then
    git -C "$new_path" remote remove origin >/dev/null 2>&1 || true
    rmdir "$SCRIPT_DIR" >/dev/null 2>&1 || true
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

find_claude_exe() {
  hit=$(command -v claude 2>/dev/null || true)
  if [ -n "$hit" ] && [ -f "$hit" ] && ! grep -q "Project Mummy Claude Code shim" "$hit" 2>/dev/null; then
    printf '%s\n' "$hit"
    return 0
  fi
  for candidate in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
    if [ -x "$candidate" ] && ! grep -q "Project Mummy Claude Code shim" "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

publish_claude_shim() {
  local exe=$1 dir oldifs
  [ -n "$exe" ] && [ -x "$exe" ] || return 1
  oldifs=$IFS
  IFS=:
  for dir in $PATH; do
    case "$dir" in
      "$HOME"|"$HOME"/*|/usr/local/bin)
        [ -d "$dir" ] && [ -w "$dir" ] || continue
        if [ -e "$dir/claude" ] && ! grep -q "Project Mummy Claude Code shim" "$dir/claude" 2>/dev/null; then
          continue
        fi
        printf '#!/bin/sh\n# Project Mummy Claude Code shim\nexec %s "$@"\n' "$exe" > "$dir/claude"
        chmod +x "$dir/claude"
        IFS=$oldifs
        return 0
        ;;
    esac
  done
  IFS=$oldifs
  return 1
}

install_claude() {
  CLAUDE_SAME_WINDOW=0
  exe=$(find_claude_exe | sed -n '1p')
  if [ -z "$exe" ]; then
    echo "Installing Claude Code..."
    uname_s=$(uname -s)
    if [ "$uname_s" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
      brew install --cask claude-code
    else
      curl -fsSL https://claude.ai/install.sh | bash
    fi
    exe=$(find_claude_exe | sed -n '1p')
    if [ -z "$exe" ]; then
      echo "Claude Code install finished, but the claude program was not found." >&2
      return
    fi
  else
    echo "Checking Claude Code for updates..."
    "$exe" update || echo "The installed copy is still in place."
  fi
  if publish_claude_shim "$exe"; then
    CLAUDE_SAME_WINDOW=1
  fi
}

prompt_service() {
  local choice model base fast
  echo "" >&2
  echo "API service" >&2
  echo "Claude Code will use this key. A Claude account is not required." >&2
  echo "  1  Ollama Cloud     a short test picks the model" >&2
    echo "  2  OpenRouter       a short test picks the model" >&2
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
      printf '%s\n' "OpenRouter" "https://openrouter.ai/api" "" "" "https://openrouter.ai/settings/keys" "https://openrouter.ai/api/v1/key" "1"
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
      printf '%s\n' "Custom" "$base" "" "" "" "$base" "0"
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

pick_best_model() {
  MUMMY_BASE="$1" MUMMY_NAME="$2" MUMMY_FALLBACK="$3" OLLAMA_KEY_CHECK="$4" python3 -c '
import json, os, re, sys, time, urllib.request
base = os.environ["MUMMY_BASE"].rstrip("/")
name = os.environ["MUMMY_NAME"]
fallback = os.environ.get("MUMMY_FALLBACK") or ""
key = os.environ.get("OLLAMA_KEY_CHECK") or ""

def fetch(url, method="GET", body=None):
    data = body.encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return resp.read().decode("utf-8", "replace")
    except Exception:
        return ""

def parse_params(raw):
    text = str(raw or "").strip()
    sci = re.fullmatch(r"[0-9]*\.?[0-9]+[eE][+-]?[0-9]+", text)
    if sci:
        return float(text)
    match = re.fullmatch(r"([0-9]*\.?[0-9]+)\s*([KkMmGgTt])?", text)
    if not match:
        return 0.0
    count = float(match.group(1))
    suffix = (match.group(2) or "").upper()
    return count * {"K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12}.get(suffix, 1.0)

def skipped(model):
    if model.startswith("~"):
        return True
    if re.search(r"embed|rerank|whisper|\btts\b|\bclip\b|guard|moderation", model, re.I):
        return True
    if re.search(r"(:batch|:free|:extended|:online)$", model, re.I):
        return True
    return False

def fast_name(model):
    return re.search(r"(?:^|[/:._-])(?:flashx?|highspeed|haiku)(?:[/:._-]|$)", model, re.I) is not None

def context_of(info):
    best = 0.0
    if not isinstance(info, dict):
        return best
    for key, value in info.items():
        if str(key).endswith("context_length"):
            try:
                best = max(best, float(value))
            except Exception:
                pass
    return best

def entry(model, params, context, tools, created, price):
    return {"name": model, "params": params, "context": context, "tools": tools, "created": created, "price": price}

def show_entry(show_url, model, size_bytes):
    raw = fetch(show_url, "POST", json.dumps({"model": model}))
    params = float(size_bytes or 0)
    context = 0.0
    tools = None
    if raw:
        try:
            shown = json.loads(raw)
            counted = parse_params((shown.get("details") or {}).get("parameter_size"))
            if counted > 0:
                params = counted
            context = context_of(shown.get("model_info"))
            caps = shown.get("capabilities")
            if isinstance(caps, list):
                tools = "tools" in caps
        except Exception:
            tools = None
    return entry(model, params, context, tools, 0.0, 0.0)

def catalog_entries():
    if name == "OpenRouter":
        raw = fetch("https://openrouter.ai/api/v1/models")
        try:
            data = json.loads(raw) if raw else {}
        except Exception:
            data = {}
        found = []
        for item in data.get("data") or []:
            if not isinstance(item, dict):
                continue
            model = str(item.get("id") or item.get("name") or "")
            if not model:
                continue
            caps = item.get("supported_parameters")
            tools = ("tools" in caps) if isinstance(caps, list) else None
            leaf = model.split("/")[-1]
            found.append(entry(model, parse_params(leaf), float(item.get("context_length") or 0), tools, float(item.get("created") or 0), float((item.get("pricing") or {}).get("prompt") or 0)))
        return found
    tags_url = "https://ollama.com/api/tags"
    show_url = "https://ollama.com/api/show"
    if name != "Ollama Cloud":
        tags_url = base + "/api/tags"
        show_url = base + "/api/show"
    raw = fetch(tags_url)
    models = []
    if raw:
        try:
            models = json.loads(raw).get("models") or []
        except Exception:
            models = []
    if not models:
        other = fetch(base + "/v1/models")
        found = []
        if other:
            try:
                payload = json.loads(other)
            except Exception:
                payload = {}
            for item in (payload.get("data") or payload.get("models") or []):
                if isinstance(item, dict):
                    model = str(item.get("id") or item.get("name") or "")
                    if model:
                        found.append(entry(model, 0.0, float(item.get("context_length") or 0), None, 0.0, 0.0))
        return found
    print("Reading the live catalog...", file=sys.stderr)
    found = []
    for item in models[:40]:
        if not isinstance(item, dict):
            continue
        model = str(item.get("name") or item.get("model") or "")
        if not model:
            continue
        found.append(show_entry(show_url, model, item.get("size") or 0))
    return found

def probe_plan(entries):
    usable = [item for item in entries if item["name"] and not skipped(item["name"]) and item["tools"] is not False]
    mains = [item for item in usable if not fast_name(item["name"])]
    mains.sort(key=lambda item: item["name"])
    mains.sort(key=lambda item: (item["params"], item["context"], item["created"]), reverse=True)
    background = [item for item in usable if fast_name(item["name"])]
    background.sort(key=lambda item: item["name"])
    background.sort(key=lambda item: item["params"] if item["params"] > 0 else (item["price"] if item["price"] > 0 else 10**30))
    return {
        "main": [item["name"] for item in mains[:3]],
        "background": background[0]["name"] if background else "",
    }

entries = catalog_entries()
plan = probe_plan(entries)
mains = plan["main"]
background = plan["background"]
if not mains and not background:
    if fallback and fallback != "openrouter/auto":
        mains = [fallback]
    else:
        print("NEED")
        print(fallback)
        raise SystemExit(0)

def messages_url():
    if base.endswith("/v1"):
        return base + "/messages"
    return base + "/v1/messages"

def tool_ok(model):
    body = json.dumps({
        "model": model,
        "max_tokens": 512,
        "tools": [{
            "name": "ping",
            "description": "Return ok",
            "input_schema": {
                "type": "object",
                "properties": {"value": {"type": "string"}},
                "required": ["value"],
            },
        }],
        "messages": [{"role": "user", "content": "Call the ping tool with value ok."}],
    })
    raw = fetch(messages_url(), "POST", body)
    if not raw:
        return False
    try:
        data = json.loads(raw)
    except Exception:
        return False
    for block in data.get("content") or []:
        if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "ping":
            return True
    return False

print("Quick model test", file=sys.stderr)
print("Candidates come from the live catalog, ranked by parameter count.", file=sys.stderr)
print("Up to 4 short tool-call requests. Each one stops at 512 tokens.", file=sys.stderr)
if mains:
    print("Largest tool models: " + ", ".join(mains), file=sys.stderr)
if background:
    print("Background candidate: " + background, file=sys.stderr)

def probe(model):
    print("Trying " + model + "...", file=sys.stderr)
    started = time.time()
    ok = tool_ok(model)
    elapsed = time.time() - started
    if ok:
        print("  tool call ok ({0:.1f}s)".format(elapsed), file=sys.stderr)
    else:
        print("  no tool call", file=sys.stderr)
    return ok

best = ""
for model in mains:
    if probe(model):
        best = model
        break
fast = ""
if background and background != best and probe(background):
    fast = background
if not best:
    best = fast
if not best:
    keep = fallback or (mains[0] if mains else "")
    print("No model passed the tool-call test. Keeping " + keep + ".", file=sys.stderr)
    print(keep)
    print(keep)
    raise SystemExit(0)
if not fast:
    fast = best
print("Best model: " + best, file=sys.stderr)
print("Background model: " + fast, file=sys.stderr)
print(best)
print(fast)
'
  unset OLLAMA_KEY_CHECK
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
PICKED=$(pick_best_model "$SERVICE_BASE" "$SERVICE_NAME" "$SERVICE_MODEL" "$KEY")
if [ "$(printf '%s\n' "$PICKED" | sed -n '1p')" = "NEED" ]; then
  echo "No model list came back. Type one model id to test:" >&2
  IFS= read -r SERVICE_MODEL || true
  SERVICE_MODEL=$(printf '%s' "$SERVICE_MODEL" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  PICKED=$(pick_best_model "$SERVICE_BASE" "$SERVICE_NAME" "$SERVICE_MODEL" "$KEY")
fi
SERVICE_MODEL=$(printf '%s\n' "$PICKED" | sed -n '1p')
SERVICE_FAST=$(printf '%s\n' "$PICKED" | sed -n '2p')
if [ -z "$SERVICE_FAST" ]; then SERVICE_FAST="$SERVICE_MODEL"; fi
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
if [ "$CLAUDE_SAME_WINDOW" = "1" ]; then
  echo "In this window, run:"
  printf "cd %q\n" "$PROJECT_PATH"
  echo "claude"
else
  echo "Open a new terminal in that folder, then run: claude"
fi
