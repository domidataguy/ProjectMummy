# Ask for an Ollama key, install or update Claude Code, and copy the Cursor hook.
param(
    [string]$TargetHomePath = $env:USERPROFILE
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Convert-SecureStringToText {
    param([Security.SecureString]$Secure)
    if ($null -eq $Secure) { return "" }
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Get-SavedKey {
    param([string]$TargetHome)
    $path = Join-Path $TargetHome ".claude\settings.json"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $token = [string]$settings.env.ANTHROPIC_AUTH_TOKEN
        if ($token.Length -ge 8) { return $token }
    } catch {
        return $null
    }
    return $null
}

function Get-KeyTail {
    param([string]$Key)
    if ($Key.Length -ge 4) { return $Key.Substring($Key.Length - 4) }
    return "...."
}

function Test-OllamaKey {
    param([string]$Key)
    $request = [System.Net.HttpWebRequest]::Create("https://ollama.com/api/tags")
    $request.Method = "GET"
    $request.Timeout = 30000
    $request.Headers.Add("Authorization", "Bearer $Key")
    try {
        $response = $request.GetResponse()
        $ok = [int]$response.StatusCode -eq 200
        $response.Close()
        return $ok
    } catch [System.Net.WebException] {
        return $false
    }
}

function Read-OllamaKey {
    param([string]$TargetHome)
    $saved = Get-SavedKey -TargetHome $TargetHome
    $fromEnv = $env:OLLAMA_KEY
    if (-not $fromEnv) { $fromEnv = $env:OLLAMA_API_KEY }

    Write-Host ""
    Write-Host "Ollama API key"
    Write-Host "Create or copy one at https://ollama.com/settings/keys"
    Write-Host "The key is saved only on this PC. It is not stored in git."
    if ($saved) {
        Write-Host ("A key ending in {0} is already saved on this PC." -f (Get-KeyTail $saved))
    }
    if ($fromEnv) {
        Write-Host ("This terminal already has a key ending in {0}." -f (Get-KeyTail $fromEnv))
    }
    Write-Host ""

    while ($true) {
        if ($saved -or $fromEnv) {
            Write-Host "Press Enter to keep the saved key, or paste a new key. Input stays hidden."
        } else {
            Write-Host "Paste your Ollama API key. Input stays hidden."
        }
        $typed = Convert-SecureStringToText (Read-Host -AsSecureString)
        $typed = $typed.Trim()
        if ($typed.Length -eq 0) {
            if ($saved) { return $saved }
            if ($fromEnv) { return $fromEnv }
            Write-Host "A key is required."
            continue
        }
        Write-Host "Checking the key with Ollama..."
        if (Test-OllamaKey -Key $typed) {
            Write-Host ("Key accepted. It ends in {0}." -f (Get-KeyTail $typed))
            return $typed
        }
        Write-Host "Ollama rejected that key. Paste it again."
    }
}

function Write-ClaudeSettings {
    param([string]$TargetHome, [string]$Key)
    $dir = Join-Path $TargetHome ".claude"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $settings = @{
        model = "glm-5.3"
        env = @{
            ANTHROPIC_BASE_URL = "https://ollama.com"
            ANTHROPIC_AUTH_TOKEN = $Key
            ANTHROPIC_API_KEY = ""
            ANTHROPIC_MODEL = "glm-5.3"
            ANTHROPIC_DEFAULT_OPUS_MODEL = "glm-5.3"
            ANTHROPIC_DEFAULT_SONNET_MODEL = "glm-5.3"
            ANTHROPIC_DEFAULT_HAIKU_MODEL = "glm-5.3-flash"
            ANTHROPIC_DEFAULT_FABLE_MODEL = "glm-5.3"
            CLAUDE_CODE_SUBAGENT_MODEL = "glm-5.3"
        }
    }
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $json = $serializer.Serialize($settings)
    [System.IO.File]::WriteAllText((Join-Path $dir "settings.json"), $json + "`n")
}

function Install-CursorHook {
    param([string]$TargetHome)
    $cursor = Join-Path $TargetHome ".cursor"
    $hookDir = Join-Path $cursor "hooks"
    $templateDir = Join-Path $cursor "templates\.claude"
    New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
    New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $ScriptDir "hooks\ensure-claude-setup.ps1") -Destination (Join-Path $hookDir "ensure-claude-setup.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $ScriptDir "templates\.claude\settings.json") -Destination (Join-Path $templateDir "settings.json") -Force

    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./hooks/ensure-claude-setup.ps1"
    $hooksPath = Join-Path $cursor "hooks.json"
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = 10485760

    $config = @{ version = 1; hooks = @{ workspaceOpen = @(); sessionStart = @() } }
    if (Test-Path -LiteralPath $hooksPath) {
        try {
            $config = $serializer.DeserializeObject([System.IO.File]::ReadAllText($hooksPath))
        } catch {
            $backup = "$hooksPath.bak"
            Copy-Item -LiteralPath $hooksPath -Destination $backup -Force
            Write-Host "Existing hooks.json could not be read. A backup is at $backup"
            $config = @{ version = 1; hooks = @{} }
        }
    }
    if (-not $config.ContainsKey("hooks") -or $null -eq $config["hooks"]) {
        $config["hooks"] = @{}
    }
    foreach ($eventName in @("workspaceOpen", "sessionStart")) {
        $existing = @()
        if ($config["hooks"].ContainsKey($eventName) -and $null -ne $config["hooks"][$eventName]) {
            $existing = @($config["hooks"][$eventName])
        }
        $already = $false
        foreach ($entry in $existing) {
            if ($entry -and $entry["command"] -eq $command) { $already = $true }
        }
        if (-not $already) {
            $existing += @{ command = $command }
        }
        $config["hooks"][$eventName] = $existing
    }
    if (-not $config.ContainsKey("version")) { $config["version"] = 1 }
    [System.IO.File]::WriteAllText($hooksPath, $serializer.Serialize($config) + "`n")
}

function Test-ProjectName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name.Length -gt 80) { return $false }
    if ($Name -match '[\\/:*?"<>|]') { return $false }
    if ($Name.EndsWith('.') -or $Name.EndsWith(' ')) { return $false }
    if ($Name -eq '.' -or $Name -eq '..') { return $false }
    $reserved = @(
        'CON','PRN','AUX','NUL',
        'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
        'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'
    )
    $base = ($Name -split '\.')[0].ToUpper()
    if ($reserved -contains $base) { return $false }
    return $true
}

function Read-ProjectName {
    $current = Split-Path -Leaf $ScriptDir
    $parent = Split-Path -Parent $ScriptDir
    Write-Host ""
    Write-Host "New project"
    Write-Host "The setup folder will be renamed. It is currently:"
    Write-Host "  $ScriptDir"
    while ($true) {
        $name = (Read-Host "Local repo name").Trim()
        if (-not (Test-ProjectName $name)) {
            Write-Host "Use one folder name: letters, numbers, dot, dash, and underscore. No slashes."
            continue
        }
        if ($name -eq $current) { return $ScriptDir }
        $dest = Join-Path $parent $name
        if (Test-Path -LiteralPath $dest) {
            Write-Host "That folder already exists: $dest"
            continue
        }
        return $dest
    }
}

function Rename-ProjectFolder {
    param([string]$NewPath)
    if ($NewPath -eq $ScriptDir) {
        Write-Host "Folder name unchanged: $ScriptDir"
        return $ScriptDir
    }
    $parent = Split-Path -Parent $ScriptDir
    $scriptFull = [System.IO.Path]::GetFullPath($ScriptDir).TrimEnd('\')
    $homeFull = [System.IO.Path]::GetFullPath($TargetHomePath).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($parent) -or $scriptFull -eq $homeFull) {
        Write-Host "Refusing to rename this folder. Claude Code setup is still in place at $ScriptDir"
        return $ScriptDir
    }
    try {
        [System.IO.Directory]::Move($ScriptDir, $NewPath)
    } catch {
        Write-Host "Claude Code is ready. The folder is in use, so it was not renamed."
        Write-Host "Close programs using it, then run:"
        Write-Host ("Rename-Item -LiteralPath '{0}' -NewName '{1}'" -f $ScriptDir, (Split-Path -Leaf $NewPath))
        return $ScriptDir
    }
    & git -C $NewPath remote remove origin 2>$null
    Write-Host "Renamed the project folder to $NewPath"
    Write-Host "The setup-repo git remote was removed so this project does not push back to it."
    return $NewPath
}

function Install-ClaudeCode {
    $exe = $null
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { $exe = $cmd.Source }
    if (-not $exe) {
        $found = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") -Filter claude.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $exe = $found.FullName }
    }
    if (-not $exe) {
        Write-Host "Installing Claude Code..."
        & winget install --id Anthropic.ClaudeCode -e --disable-interactivity --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "Claude Code install failed (winget exit $LASTEXITCODE)."
        }
        Write-Host "Claude Code installed. Open a new terminal so claude is on PATH."
        return
    }
    Write-Host "Checking Claude Code for updates..."
    & $exe update
    if ($LASTEXITCODE -ne 0) {
        Write-Host "claude update exited $LASTEXITCODE. The installed copy is still in place."
    }
}

$projectPath = Read-ProjectName
$key = Read-OllamaKey -TargetHome $TargetHomePath
Write-ClaudeSettings -TargetHome $TargetHomePath -Key $key
Install-CursorHook -TargetHome $TargetHomePath
Install-ClaudeCode
$projectPath = Rename-ProjectFolder -NewPath $projectPath
Write-Host ""
Write-Host "Ready. Claude Code uses glm-5.3 through Ollama Cloud."
Write-Host "Settings: $(Join-Path $TargetHomePath '.claude\settings.json')"
Write-Host "Project folder: $projectPath"
Write-Host "Open a new terminal in that folder, then run: claude"
