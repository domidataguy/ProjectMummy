# Claude Code + Ollama setup

Clone this repo on a PC, then run one command. The script asks for an Ollama API key in the terminal, checks it, saves it on that PC, installs or updates Claude Code, and copies the Cursor hook.

The key is not stored in this repo. Do not paste it into chat.

## Windows

```powershell
git clone https://github.com/domidataguy/claude-ollama-setup.git
cd claude-ollama-setup
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

## Mac or Linux

```bash
git clone https://github.com/domidataguy/claude-ollama-setup.git
cd claude-ollama-setup
chmod +x setup.sh hooks/ensure-claude-setup.sh
./setup.sh
```

Press Enter to keep a key that is already saved on that computer. Otherwise paste a key from https://ollama.com/settings/keys. The input stays hidden.

Claude Code is installed only when it is missing. When it is already installed, `claude update` runs and installs a new version only if one is available.

The main model is `glm-5.3`. Background calls use `glm-5.3-flash`.
