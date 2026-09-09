[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$EdtExecutable,
    [string]$WorkspacePath,
    [int]$Port = 8765,
    [string]$Token = "",
    [string]$ServerName = "edt_mcp_server",
    [string]$ChecksFolder = "",
    [ValidateSet("on_startup", "hourly", "daily", "never")]
    [string]$UpdateCheckInterval = "on_startup",
    [switch]$EnableAutoStart,
    [switch]$EnablePlainTextMode,
    [switch]$AllowRemoteAccess,
    [switch]$SkipEdtInstall,
    [switch]$SkipJvmFlag,
    [switch]$SkipPluginConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PluginRoot = Split-Path -Parent $PSScriptRoot
$PluginManifestPath = Join-Path $PluginRoot ".codex-plugin\plugin.json"
$PluginMcpConfigPath = Join-Path $PluginRoot ".mcp.json"
$UpdateSiteUrl = "https://ditrixnew.github.io/EDT-MCP/"
$InstallUnit = "com.ditrix.edt.mcp.server.feature.feature.group"
$PreferenceFileName = "com.ditrix.edt.mcp.server.prefs"
$NativeRenderFlag = "-DnativeFormBufferedLayoutRender=true"

function Write-Info {
    param([string]$Message)
    Write-Host "[edt-mcp-setup] $Message"
}

function Resolve-ExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-DefaultEdtExecutable {
    $searchRoots = @(
        (Join-Path $env:ProgramFiles "1C\1CE\components"),
        (Join-Path ${env:ProgramFiles(x86)} "1C\1CE\components")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $candidates = @()

    foreach ($root in $searchRoots) {
        $dirs = Get-ChildItem -LiteralPath $root -Directory -Filter "1c-edt-*" -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            $exePath = Join-Path $dir.FullName "1cedt.exe"
            $iniPath = Join-Path $dir.FullName "1cedt.ini"
            if (Test-Path -LiteralPath $exePath) {
                $versionToken = $dir.Name.Substring(7)
                $candidates += [pscustomobject]@{
                    Executable  = $exePath
                    IniPath     = $iniPath
                    VersionText = $versionToken
                }
            }
        }
    }

    if (-not $candidates) {
        return $null
    }

    return $candidates |
        Sort-Object VersionText -Descending |
        Select-Object -First 1
}

function Get-EdtInstallInfo {
    param([string]$RequestedExecutable)

    if ($RequestedExecutable) {
        $resolvedExe = Resolve-ExistingPath -Path $RequestedExecutable
        return [pscustomobject]@{
            Executable  = $resolvedExe
            IniPath     = Join-Path (Split-Path -Parent $resolvedExe) "1cedt.ini"
            VersionText = Split-Path -Leaf (Split-Path -Parent $resolvedExe)
        }
    }

    $detected = Get-DefaultEdtExecutable
    if ($null -eq $detected) {
        throw "Unable to detect 1cedt.exe automatically. Re-run with -EdtExecutable 'C:\path\to\1cedt.exe'."
    }

    return $detected
}

function Ensure-NativeRenderFlag {
    param([Parameter(Mandatory = $true)][string]$IniPath)

    if (-not (Test-Path -LiteralPath $IniPath)) {
        throw "EDT ini file not found: $IniPath"
    }

    $lines = Get-Content -LiteralPath $IniPath
    if ($lines -contains $NativeRenderFlag) {
        Write-Info "Native render flag is already present in $IniPath"
        return
    }

    $updatedLines = New-Object System.Collections.Generic.List[string]
    $inserted = $false

    foreach ($line in $lines) {
        [void]$updatedLines.Add($line)
        if (-not $inserted -and $line -eq "-vmargs") {
            [void]$updatedLines.Add($NativeRenderFlag)
            $inserted = $true
        }
    }

    if (-not $inserted) {
        [void]$updatedLines.Add("-vmargs")
        [void]$updatedLines.Add($NativeRenderFlag)
    }

    if ($PSCmdlet.ShouldProcess($IniPath, "Add $NativeRenderFlag")) {
        Set-Content -LiteralPath $IniPath -Value $updatedLines -Encoding utf8
        Write-Info "Patched $IniPath with $NativeRenderFlag"
    }
}

function Install-EdtMcpFeature {
    param([Parameter(Mandatory = $true)][string]$EdtPath)

    $arguments = @(
        "-nosplash"
        "-application", "org.eclipse.equinox.p2.director"
        "-repository", $UpdateSiteUrl
        "-installIU", $InstallUnit
        "-profileProperties", "org.eclipse.update.reconcile=true"
    )

    if ($PSCmdlet.ShouldProcess($EdtPath, "Install EDT-MCP from $UpdateSiteUrl")) {
        Write-Info "Installing EDT-MCP via p2 director"
        & $EdtPath @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "EDT-MCP installation failed with exit code $LASTEXITCODE."
        }
    }
}

function New-McpConfigObject {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$McpPort,
        [string]$AuthToken
    )

    $server = [ordered]@{
        type = "sse"
        url  = "http://localhost:$McpPort/mcp"
    }

    if ($AuthToken) {
        $server.headers = [ordered]@{
            Authorization = "Bearer $AuthToken"
        }
    }

    return [ordered]@{
        mcpServers = [ordered]@{
            $Name = $server
        }
    }
}

function Write-PluginMcpConfig {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][hashtable]$ConfigObject
    )

    $json = $ConfigObject | ConvertTo-Json -Depth 8

    if ($PSCmdlet.ShouldProcess($OutputPath, "Write plugin MCP configuration")) {
        Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
        Write-Info "Updated plugin MCP config: $OutputPath"
    }
}

function ConvertTo-PreferenceValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("\", "\\").Replace(":", "\:")
}

function Write-WorkspacePreferences {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedWorkspacePath,
        [Parameter(Mandatory = $true)][int]$McpPort,
        [string]$AuthToken,
        [string]$ChecksOverride,
        [Parameter(Mandatory = $true)][string]$Interval,
        [Parameter(Mandatory = $true)][bool]$AutoStartEnabled,
        [Parameter(Mandatory = $true)][bool]$PlainTextEnabled,
        [Parameter(Mandatory = $true)][bool]$RemoteAccessEnabled
    )

    $settingsDir = Join-Path $ResolvedWorkspacePath ".metadata\.plugins\org.eclipse.core.runtime\.settings"
    $preferencePath = Join-Path $settingsDir $PreferenceFileName

    $content = @(
        "eclipse.preferences.version=1"
        "mcpServerPort=$McpPort"
        "mcpServerAutoStart=$($AutoStartEnabled.ToString().ToLowerInvariant())"
        "mcpChecksFolder=$(ConvertTo-PreferenceValue -Value $ChecksOverride)"
        "mcpPlainTextMode=$($PlainTextEnabled.ToString().ToLowerInvariant())"
        "mcpUpdateCheckInterval=$Interval"
        "navigator.enhance=true"
        "tags.showInNavigator=true"
        "tags.decorationStyle=suffix"
        "mcpAllowRemoteAccess=$($RemoteAccessEnabled.ToString().ToLowerInvariant())"
        "mcpAuthToken=$(ConvertTo-PreferenceValue -Value $AuthToken)"
        "mcpDestructiveConsentLevel=ask_always"
        "mcpDestructiveAllowedTools="
    )

    if ($PSCmdlet.ShouldProcess($preferencePath, "Write EDT-MCP workspace preferences")) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        Set-Content -LiteralPath $preferencePath -Value $content -Encoding utf8
        Write-Info "Wrote workspace preferences: $preferencePath"
    }
}

if (-not (Test-Path -LiteralPath $PluginManifestPath)) {
    throw "Plugin manifest not found: $PluginManifestPath"
}

if ($AllowRemoteAccess.IsPresent -and [string]::IsNullOrWhiteSpace($Token)) {
    throw "AllowRemoteAccess requires a non-empty -Token."
}

$edtInfo = $null
if (-not $SkipEdtInstall.IsPresent -or -not $SkipJvmFlag.IsPresent) {
    $edtInfo = Get-EdtInstallInfo -RequestedExecutable $EdtExecutable
    Write-Info "Using EDT executable: $($edtInfo.Executable)"
}

if (-not $SkipEdtInstall.IsPresent) {
    Install-EdtMcpFeature -EdtPath $edtInfo.Executable
}

if (-not $SkipJvmFlag.IsPresent) {
    Ensure-NativeRenderFlag -IniPath $edtInfo.IniPath
}

if (-not $SkipPluginConfig.IsPresent) {
    $pluginConfig = New-McpConfigObject -Name $ServerName -McpPort $Port -AuthToken $Token
    Write-PluginMcpConfig -OutputPath $PluginMcpConfigPath -ConfigObject $pluginConfig
}

if ($WorkspacePath) {
    $resolvedWorkspacePath = Resolve-ExistingPath -Path $WorkspacePath
    Write-WorkspacePreferences `
        -ResolvedWorkspacePath $resolvedWorkspacePath `
        -McpPort $Port `
        -AuthToken $Token `
        -ChecksOverride $ChecksFolder `
        -Interval $UpdateCheckInterval `
        -AutoStartEnabled $EnableAutoStart.IsPresent `
        -PlainTextEnabled $EnablePlainTextMode.IsPresent `
        -RemoteAccessEnabled $AllowRemoteAccess.IsPresent
}

$summary = [ordered]@{
    pluginRoot      = $PluginRoot
    manifest        = $PluginManifestPath
    mcpConfig       = if ($SkipPluginConfig.IsPresent) { $null } else { $PluginMcpConfigPath }
    edtExecutable   = if ($edtInfo) { $edtInfo.Executable } else { $null }
    workspacePath   = if ($WorkspacePath) { (Resolve-Path -LiteralPath $WorkspacePath).Path } else { $null }
    port            = $Port
    serverName      = $ServerName
    tokenConfigured = -not [string]::IsNullOrWhiteSpace($Token)
}

Write-Output ($summary | ConvertTo-Json -Depth 4)
