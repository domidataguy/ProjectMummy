# Project Mummy hook. Copies the model pin into a project .claude folder.
# The API key is never written here. setup.ps1 asks for it.
$ErrorActionPreference = "Stop"

function Test-SavedKey {
    $path = Join-Path $env:USERPROFILE ".claude\settings.json"
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $token = [string]$settings.env.ANTHROPIC_AUTH_TOKEN
        return $token.Length -ge 8
    } catch {
        return $false
    }
}

try {
    $raw = [Console]::In.ReadToEnd()
    $payload = $null
    if ($raw -and $raw.Trim().Length -gt 0) {
        $payload = $raw | ConvertFrom-Json
    }

    $roots = @()
    if ($payload -and $payload.workspace_roots) {
        $roots = @($payload.workspace_roots)
    } elseif ($env:CURSOR_PROJECT_DIR) {
        $roots = @($env:CURSOR_PROJECT_DIR)
    }

    $template = Join-Path $env:USERPROFILE ".cursor\templates\.claude\settings.json"
    if (Test-Path -LiteralPath $template) {
        foreach ($root in $roots) {
            if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
            $destDir = Join-Path $root ".claude"
            $dest = Join-Path $destDir "settings.json"
            if (Test-Path -LiteralPath $dest) { continue }
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir | Out-Null
            }
            Copy-Item -LiteralPath $template -Destination $dest
        }
    }

    $eventName = ""
    if ($payload -and $payload.hook_event_name) { $eventName = [string]$payload.hook_event_name }
    if ($eventName -eq "sessionStart") {
        if (Test-SavedKey) {
            $message = "Project Mummy has set up Claude Code on this PC. The API key stays in the user profile .claude settings. Do not print or copy API keys."
        } else {
            $message = "Project Mummy has not saved an API key yet. Tell the user to run setup.ps1 on Windows, or setup.sh on Mac or Linux. That script asks for the key in the terminal. Do not ask them to paste the key into chat."
        }
        @{ additional_context = $message } | ConvertTo-Json -Compress
    } else {
        Write-Output '{"pluginPaths":[]}'
    }
} catch {
    Write-Output '{"pluginPaths":[]}'
    exit 0
}
