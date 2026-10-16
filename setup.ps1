# Project Mummy. Name the project, pick an API that is not a Claude account, install Claude Code.
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

function Get-SavedBaseUrl {
    param([string]$TargetHome)
    $path = Join-Path $TargetHome ".claude\settings.json"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $base = [string]$settings.env.ANTHROPIC_BASE_URL
        if ($base) { return $base }
    } catch {
        return $null
    }
    return $null
}

function Test-UrlKey {
    param([string]$Url, [string]$Key)
    $request = [System.Net.HttpWebRequest]::Create($Url)
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

function Read-Service {
    Write-Host ""
    Write-Host "API service"
    Write-Host "Claude Code will use this key. A Claude account is not required."
    Write-Host "  1  Ollama Cloud     a short test picks the model"
    Write-Host "  2  OpenRouter       a short test picks the model"
    Write-Host "  3  Other            any service that speaks the Anthropic Messages API"
    while ($true) {
        $choice = (Read-Host "Choose 1, 2, or 3").Trim()
        if ($choice -eq "1") {
            return @{
                Name = "Ollama Cloud"
                BaseUrl = "https://ollama.com"
                Model = "glm-5.3"
                FastModel = "glm-5.3-flash"
                KeyUrl = "https://ollama.com/settings/keys"
                CheckUrl = "https://ollama.com/api/tags"
                Discover = $false
            }
        }
        if ($choice -eq "2") {
            return @{
                Name = "OpenRouter"
                BaseUrl = "https://openrouter.ai/api"
                Model = ""
                FastModel = ""
                KeyUrl = "https://openrouter.ai/settings/keys"
                CheckUrl = "https://openrouter.ai/api/v1/key"
                Discover = $true
            }
        }
        if ($choice -eq "3") {
            $base = (Read-Host "Base URL, including https://").Trim().TrimEnd("/")
            if ($base -notmatch '^https://') {
                Write-Host "The base URL has to start with https://"
                continue
            }
            return @{
                Name = "Custom"
                BaseUrl = $base
                Model = ""
                FastModel = ""
                KeyUrl = ""
                CheckUrl = $base
                Discover = $false
            }
        }
        Write-Host "Type 1, 2, or 3."
    }
}

function Read-ServiceKey {
    param([string]$TargetHome, $Service)
    $saved = Get-SavedKey -TargetHome $TargetHome
    $savedBase = Get-SavedBaseUrl -TargetHome $TargetHome
    $sameService = $saved -and $savedBase -eq $Service.BaseUrl

    Write-Host ""
    Write-Host ("API key for {0}" -f $Service.Name)
    if ($Service.KeyUrl) { Write-Host ("Create or copy one at {0}" -f $Service.KeyUrl) }
    Write-Host "The key is saved only on this PC. It is not stored in git."
    if ($sameService) {
        Write-Host ("A key ending in {0} is already saved for this service." -f (Get-KeyTail $saved))
    }
    Write-Host ""

    while ($true) {
        if ($sameService) {
            Write-Host "Press Enter to keep the saved key, or paste a new key. Input stays hidden."
        } else {
            Write-Host "Paste the API key. Input stays hidden."
        }
        $typed = Convert-SecureStringToText (Read-Host -AsSecureString)
        $typed = $typed.Trim()
        if ($typed.Length -eq 0) {
            if ($sameService) { return $saved }
            Write-Host "A key is required."
            continue
        }
        Write-Host "Checking the key..."
        if (Test-UrlKey -Url $Service.CheckUrl -Key $typed) {
            Write-Host ("Key accepted. It ends in {0}." -f (Get-KeyTail $typed))
            return $typed
        }
        if ($Service.Name -eq "Custom") {
            $allow = (Read-Host "The check did not succeed. Type yes to save this key anyway").Trim()
            if ($allow -eq "yes") { return $typed }
        }
        Write-Host "That key was rejected. Paste it again."
    }
}

$script:RankedModels = @("glm-5.3", "kimi-k2.7-code", "minimax-m3", "glm-5.3-flash")

function Get-MessagesUrl {
    param([string]$BaseUrl)
    $base = $BaseUrl.TrimEnd("/")
    if ($base.EndsWith("/v1")) { return "$base/messages" }
    return "$base/v1/messages"
}

function Read-AuthorizedJson {
    param([string]$Url, [string]$Key, [string]$Method = "GET", [string]$Body = $null)
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = $Method
    $request.Timeout = 45000
    $request.Accept = "application/json"
    $request.Headers.Add("Authorization", "Bearer $Key")
    $request.Headers.Add("anthropic-version", "2023-06-01")
    if ($Body) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentType = "application/json"
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
    }
    try {
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $text = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        return $text
    } catch [System.Net.WebException] {
        return $null
    }
}

function Get-CatalogNames {
    param([string]$Url, [string]$Key)
    $text = Read-AuthorizedJson -Url $Url -Key $Key
    if (-not $text) { return @() }
    try {
        $data = $text | ConvertFrom-Json
    } catch {
        return @()
    }
    $names = @()
    foreach ($item in @($data.models)) {
        if ($item.name) { $names += [string]$item.name }
        elseif ($item.model) { $names += [string]$item.model }
        elseif ($item.id) { $names += [string]$item.id }
    }
    foreach ($item in @($data.data)) {
        if ($item.id) { $names += [string]$item.id }
        elseif ($item.name) { $names += [string]$item.name }
    }
    return @($names | Where-Object { $_ } | Select-Object -Unique)
}

function Get-ModelCatalog {
    param($Service, [string]$Key)
    $urls = @()
    if ($Service.Name -eq "Ollama Cloud") {
        $urls += "https://ollama.com/api/tags"
    } elseif ($Service.Name -eq "OpenRouter") {
        $urls += "https://openrouter.ai/api/v1/models"
    } else {
        $base = $Service.BaseUrl.TrimEnd("/")
        $urls += "$base/api/tags"
        $urls += "$base/v1/models"
    }
    foreach ($url in $urls) {
        $names = @(Get-CatalogNames -Url $url -Key $Key)
        if ($names.Count -gt 0) { return $names }
    }
    return @()
}

function Get-ProbeCandidates {
    param([string[]]$Catalog, [string]$Fallback)
    $picked = New-Object System.Collections.Generic.List[string]
    foreach ($want in $script:RankedModels) {
        foreach ($name in $Catalog) {
            if ($name -eq $want -or $name.EndsWith("/$want")) {
                if (-not $picked.Contains($name)) { $picked.Add($name) }
                break
            }
        }
        if ($picked.Count -ge 4) { break }
    }
    if ($picked.Count -eq 0 -and $Fallback -and $Fallback -ne "openrouter/auto") {
        $picked.Add($Fallback)
    }
    return @($picked)
}

function Test-ModelTool {
    param([string]$Url, [string]$Key, [string]$Model)
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $body = $serializer.Serialize(@{
        model = $Model
        max_tokens = 512
        tools = @(@{
            name = "ping"
            description = "Return ok"
            input_schema = @{
                type = "object"
                properties = @{ value = @{ type = "string" } }
                required = @("value")
            }
        })
        messages = @(@{ role = "user"; content = "Call the ping tool with value ok." })
    })
    $text = Read-AuthorizedJson -Url $Url -Key $Key -Method "POST" -Body $body
    if (-not $text) { return $false }
    try {
        $data = $text | ConvertFrom-Json
    } catch {
        return $false
    }
    foreach ($block in @($data.content)) {
        if ([string]$block.type -eq "tool_use" -and [string]$block.name -eq "ping") { return $true }
    }
    return $false
}

function Select-BestModel {
    param($Service, [string]$Key)
    Write-Host ""
    Write-Host "Quick model test"
    Write-Host "Up to 4 short tool-call requests. Each one stops at 512 tokens."
    $catalog = @(Get-ModelCatalog -Service $Service -Key $Key)
    $candidates = @(Get-ProbeCandidates -Catalog $catalog -Fallback $Service.Model)
    if ($candidates.Count -eq 0) {
        $typed = (Read-Host "No model list came back. Type one model id to test").Trim()
        if ($typed) { $candidates = @($typed) }
    }
    $passed = @()
    $messagesUrl = Get-MessagesUrl $Service.BaseUrl
    foreach ($model in $candidates) {
        Write-Host ("Trying {0}..." -f $model)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = Test-ModelTool -Url $messagesUrl -Key $Key -Model $model
        $watch.Stop()
        if ($ok) {
            Write-Host ("  tool call ok ({0:n1}s)" -f $watch.Elapsed.TotalSeconds)
            $passed += $model
        } else {
            Write-Host "  no tool call"
        }
    }
    $best = $null
    foreach ($want in $script:RankedModels) {
        foreach ($name in $passed) {
            if ($name -eq $want -or $name.EndsWith("/$want")) { $best = $name; break }
        }
        if ($best) { break }
    }
    if (-not $best -and $passed.Count -gt 0) { $best = $passed[0] }
    if (-not $best) {
        if ($candidates.Count -gt 0 -and -not $Service.Model) { $Service.Model = $candidates[0] }
        if (-not $Service.FastModel) { $Service.FastModel = $Service.Model }
        Write-Host ("No model passed the tool-call test. Keeping {0}." -f $Service.Model)
        return $Service
    }
    $fast = $best
    foreach ($name in $passed) {
        if ($name -match "flash") { $fast = $name; break }
    }
    $Service.Model = $best
    $Service.FastModel = $fast
    Write-Host "Best model: $best"
    Write-Host "Background model: $fast"
    return $Service
}

function Write-ClaudeSettings {
    param([string]$TargetHome, [string]$Key, $Service)
    $dir = Join-Path $TargetHome ".claude"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $envMap = @{
        ANTHROPIC_BASE_URL = $Service.BaseUrl
        ANTHROPIC_AUTH_TOKEN = $Key
        ANTHROPIC_API_KEY = ""
        ANTHROPIC_MODEL = $Service.Model
        ANTHROPIC_DEFAULT_OPUS_MODEL = $Service.Model
        ANTHROPIC_DEFAULT_SONNET_MODEL = $Service.Model
        ANTHROPIC_DEFAULT_HAIKU_MODEL = $Service.FastModel
        ANTHROPIC_DEFAULT_FABLE_MODEL = $Service.Model
        CLAUDE_CODE_SUBAGENT_MODEL = $Service.Model
    }
    if ($Service.Discover) {
        $envMap["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
    }
    $settings = @{
        model = $Service.Model
        env = $envMap
    }
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $json = $serializer.Serialize($settings)
    [System.IO.File]::WriteAllText((Join-Path $dir "settings.json"), $json + "`n")
}

function Install-CursorHook {
    param([string]$TargetHome, [string]$Model)
    $cursor = Join-Path $TargetHome ".cursor"
    $hookDir = Join-Path $cursor "hooks"
    $templateDir = Join-Path $cursor "templates\.claude"
    New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
    New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $ScriptDir "hooks\ensure-claude-setup.ps1") -Destination (Join-Path $hookDir "ensure-claude-setup.ps1") -Force
    Add-Type -AssemblyName System.Web.Extensions
    $templateSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    [System.IO.File]::WriteAllText((Join-Path $templateDir "settings.json"), $templateSerializer.Serialize(@{ model = $Model }) + "`n")

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
    Write-Host "The Project Mummy git remote was removed so this project does not push back to it."
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
$service = Read-Service
$key = Read-ServiceKey -TargetHome $TargetHomePath -Service $service
$service = Select-BestModel -Service $service -Key $key
Write-ClaudeSettings -TargetHome $TargetHomePath -Key $key -Service $service
Install-CursorHook -TargetHome $TargetHomePath -Model $service.Model
Install-ClaudeCode
$projectPath = Rename-ProjectFolder -NewPath $projectPath
Write-Host ""
Write-Host "Ready. Project Mummy wrapped this project."
Write-Host ("Claude Code uses {0} at {1}." -f $service.Model, $service.BaseUrl)
Write-Host "Settings: $(Join-Path $TargetHomePath '.claude\settings.json')"
Write-Host "Project folder: $projectPath"
Write-Host "Open a new terminal in that folder, then run: claude"
