<p align="center">
  <img src="https://img.shields.io/badge/Project-Mummy-1a1a1a?style=for-the-badge" alt="Project Mummy">
  <img src="https://img.shields.io/badge/Claude%20Code-wrapped-c4a574?style=for-the-badge" alt="Claude Code wrapped">
  <img src="https://img.shields.io/badge/Claude%20account-not%20required-2f6f4e?style=for-the-badge" alt="Claude account not required">
</p>

<h1 align="center">Project Mummy</h1>

<p align="center">
  <strong>A new project, wrapped and ready.</strong><br>
  Clone once. Name it. Point Claude Code at an API you can actually use.
</p>

---

Project Mummy is the first commit of a new piece of work. It installs or updates [Claude Code](https://code.claude.com), asks which API service you have, and saves that key on your computer. It then renames the folder to the project name you chose.

No Claude account. No key in git. The linen stays here. The project walks out with its own name.

## Unwrap

**Windows**

```powershell
git clone https://github.com/domidataguy/ProjectMummy.git
cd ProjectMummy
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

**Mac or Linux**

```bash
git clone https://github.com/domidataguy/ProjectMummy.git
cd ProjectMummy
chmod +x setup.sh hooks/ensure-claude-setup.sh
./setup.sh
```

The script asks four things, in this order:

1. **Local repo name.** The folder `ProjectMummy` is renamed to that name.
2. **API service.** Ollama Cloud, OpenRouter, or another Anthropic-compatible URL.
3. **API key.** Typed blind. Checked before it is saved. Press Enter only when a key for that same service is already on this computer.
4. **Model test.** A short tool-call on at most four models. The one that calls the tool, highest on the coding list, becomes the model. A passing `flash` model handles background calls.
5. **Claude Code.** Installed when it is missing. Updated when a newer build exists.

Then run `claude` in the renamed folder. On Windows that works in the same window. On Mac or Linux, open a new terminal if this one was started before Claude Code was installed.

## The cloth it weaves

| | |
|---|---|
| Project folder | Renamed to the name you typed |
| Claude Code settings | `%USERPROFILE%\.claude\settings.json` on Windows, `~/.claude/settings.json` on Mac and Linux |
| Cursor hook | Copies a model pin into each new project's `.claude` folder |
| Git remote | The link back to Project Mummy is removed, so the new project cannot be pushed here by accident |
| Main model | Chosen by the tool-call test. Preference is `glm-5.3`, then `kimi-k2.7-code`, then `minimax-m3`, then `glm-5.3-flash` |

## Services

Claude Code speaks the Anthropic Messages API. Project Mummy points it at a service that speaks that same API. You bring a key from that service. You do not log in with a Claude account.

| Choice | What you need | Where it sends Claude Code |
|---|---|---|
| **1. Ollama Cloud** | An [Ollama key](https://ollama.com/settings/keys) | `https://ollama.com` |
| **2. OpenRouter** | An [OpenRouter key](https://openrouter.ai/settings/keys) | `https://openrouter.ai/api` |
| **3. Other** | A base URL from any service that speaks the Anthropic Messages API | The URL you type |

The test lists models on that endpoint, then tries at most four: `glm-5.3`, `kimi-k2.7-code`, `minimax-m3`, and `glm-5.3-flash`, when the key can see them. Each try asks the model to call one tiny tool and stops at 512 tokens. The highest one that succeeds is saved. If a `flash` model also succeeds, it is used for background calls. If the list is empty, the script asks for one model id and tests that. For choice 3, the URL has to start with `https://`. If that service does not answer a simple key check, type `yes` to save the key anyway.

A plain OpenAI-style chat URL is not enough on its own. Claude Code will not speak that protocol until something in front of it translates to the Anthropic Messages API.

## What never leaves the tomb

- The API key is written only into your user profile.
- It is not committed, not printed in full, and not copied into the project folder.
- Do not paste a key into chat, an issue, or a pull request.
- This repository does not contain a key.

## After the wrap

```text
claude
```

Inside Claude Code, `/status` shows the base URL. If it still names a Claude account, quit and open a new terminal so the new settings load.

Cursor, on the same computer, gets a small hook. The next folder you open receives a `.claude/settings.json` that pins the model. The key stays in your user profile.

## Author

Originally written by Dominic Yu (dominic@data-science-hk.org). Contact that address if you need help.
