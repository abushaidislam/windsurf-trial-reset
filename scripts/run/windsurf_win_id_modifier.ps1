# Set output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color definitions (compatible with PowerShell 5.1 and 7.x)
$ESC = [char]27
$RED = "$ESC[31m"
$GREEN = "$ESC[32m"
$YELLOW = "$ESC[33m"
$BLUE = "$ESC[34m"
$NC = "$ESC[0m"

# Try to resize terminal window to 120x40 (columns x rows) at startup; silently ignore if not supported/failed to avoid affecting script main flow
function Try-ResizeTerminalWindow {
    param(
        [int]$Columns = 120,
        [int]$Rows = 40
    )

    # Method 1: Adjust via PowerShell Host RawUI (traditional console, ConEmu, etc. may support)
    try {
        $rawUi = $null
        if ($Host -and $Host.UI -and $Host.UI.RawUI) {
            $rawUi = $Host.UI.RawUI
        }

        if ($rawUi) {
            try {
                # BufferSize must be >= WindowSize, otherwise it will throw an exception
                $bufferSize = $rawUi.BufferSize
                $newBufferSize = New-Object System.Management.Automation.Host.Size (
                    ([Math]::Max($bufferSize.Width, $Columns)),
                    ([Math]::Max($bufferSize.Height, $Rows))
                )
                $rawUi.BufferSize = $newBufferSize
            } catch {
                # Silently ignore
            }

            try {
                $rawUi.WindowSize = New-Object System.Management.Automation.Host.Size ($Columns, $Rows)
            } catch {
                # Silently ignore
            }
        }
    } catch {
        # Silently ignore
    }

    # Method 2: Try again via ANSI escape sequences (Windows Terminal, etc. may support)
    try {
        if (-not [Console]::IsOutputRedirected) {
            $escChar = [char]27
            [Console]::Out.Write("$escChar[8;${Rows};${Columns}t")
        }
    } catch {
        # Silently ignore
    }
}

Try-ResizeTerminalWindow -Columns 120 -Rows 40

# Path resolution: Prioritize using .NET to get system directories, avoiding path anomalies caused by missing environment variables
function Get-FolderPathSafe {
    param(
        [Parameter(Mandatory = $true)][System.Environment+SpecialFolder]$SpecialFolder,
        [Parameter(Mandatory = $true)][string]$EnvVarName,
        [Parameter(Mandatory = $true)][string]$FallbackRelative,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $path = [Environment]::GetFolderPath($SpecialFolder)
    if ([string]::IsNullOrWhiteSpace($path)) {
        $envValue = [Environment]::GetEnvironmentVariable($EnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            $path = $envValue
        }
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        $userProfile = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        if ([string]::IsNullOrWhiteSpace($userProfile)) {
            $userProfile = [Environment]::GetEnvironmentVariable("USERPROFILE")
        }
        if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
            $path = Join-Path $userProfile $FallbackRelative
        }
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "$YELLOW⚠️  [Path]$NC $Label cannot be resolved, will try other methods"
    } else {
        Write-Host "$BLUEℹ️  [Path]$NC ${Label}: $path"
    }
    return $path
}

function Initialize-WindsurfPaths {
    Write-Host "$BLUEℹ️  [Path]$NC Starting to resolve Windsurf related paths..."
    $global:WindsurfAppDataRoot = Get-FolderPathSafe `
        -SpecialFolder ([System.Environment+SpecialFolder]::ApplicationData) `
        -EnvVarName "APPDATA" `
        -FallbackRelative "AppData\Roaming" `
        -Label "Roaming AppData"
    $global:WindsurfLocalAppDataRoot = Get-FolderPathSafe `
        -SpecialFolder ([System.Environment+SpecialFolder]::LocalApplicationData) `
        -EnvVarName "LOCALAPPDATA" `
        -FallbackRelative "AppData\Local" `
        -Label "Local AppData"
    $global:WindsurfUserProfileRoot = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($global:WindsurfUserProfileRoot)) {
        $global:WindsurfUserProfileRoot = [Environment]::GetEnvironmentVariable("USERPROFILE")
    }
    if (-not [string]::IsNullOrWhiteSpace($global:WindsurfUserProfileRoot)) {
        Write-Host "$BLUEℹ️  [Path]$NC User directory: $global:WindsurfUserProfileRoot"
    }
    $global:WindsurfAppDataDir = if ($global:WindsurfAppDataRoot) { Join-Path $global:WindsurfAppDataRoot "Windsurf" } else { $null }
    $global:WindsurfLocalAppDataDir = if ($global:WindsurfLocalAppDataRoot) { Join-Path $global:WindsurfLocalAppDataRoot "Windsurf" } else { $null }
    $global:WindsurfStorageDir = if ($global:WindsurfAppDataDir) { Join-Path $global:WindsurfAppDataDir "User\globalStorage" } else { $null }
    $global:WindsurfStorageFile = if ($global:WindsurfStorageDir) { Join-Path $global:WindsurfStorageDir "storage.json" } else { $null }
    $global:WindsurfBackupDir = if ($global:WindsurfStorageDir) { Join-Path $global:WindsurfStorageDir "backups" } else { $null }

    if ($global:WindsurfStorageDir -and -not (Test-Path $global:WindsurfStorageDir)) {
        Write-Host "$YELLOW⚠️  [Path]$NC Global configuration directory does not exist: $global:WindsurfStorageDir"
    }
    if ($global:WindsurfStorageFile) {
        if (Test-Path $global:WindsurfStorageFile) {
            Write-Host "$GREEN✅ [Path]$NC Configuration file found: $global:WindsurfStorageFile"
        } else {
            Write-Host "$YELLOW⚠️  [Path]$NC Configuration file does not exist: $global:WindsurfStorageFile"
        }
    }
}

function Normalize-WindsurfInstallCandidate {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $candidate = $Path.Trim().Trim('"')
    if (Test-Path $candidate -PathType Leaf) {
        $candidate = Split-Path -Parent $candidate
    }
    return $candidate
}

function Test-WindsurfInstallPath {
    param([string]$Path)
    $candidate = Normalize-WindsurfInstallCandidate -Path $Path
    if (-not $candidate) {
        return $false
    }
    $exePath = Join-Path $candidate "Windsurf.exe"
    return (Test-Path $exePath)
}

function Get-WindsurfInstallPathFromRegistry {
    $results = @()
    $uninstallKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $uninstallKeys) {
        try {
            $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if (-not $item.DisplayName -or $item.DisplayName -notlike "*Windsurf*") {
                    continue
                }
                $candidate = $null
                if ($item.InstallLocation) {
                    $candidate = $item.InstallLocation
                } elseif ($item.DisplayIcon) {
                    $candidate = $item.DisplayIcon.Split(',')[0].Trim('"')
                } elseif ($item.UninstallString) {
                    $candidate = $item.UninstallString.Split(' ')[0].Trim('"')
                }
                if ($candidate) {
                    $results += $candidate
                }
            }
        } catch {
            Write-Host "$YELLOW⚠️  [Path]$NC Failed to read registry: $key"
        }
    }
    return $results | Where-Object { $_ } | Select-Object -Unique
}

function Request-WindsurfInstallPathFromUser {
    Write-Host "$YELLOW💡 [Tip]$NC Auto-detection failed, you can manually select Windsurf installation directory (containing Windsurf.exe)"
    $selectedPath = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Please select Windsurf installation directory (containing Windsurf.exe)"
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selectedPath = $dialog.SelectedPath
        }
    } catch {
        Write-Host "$YELLOW⚠️  [Tip]$NC Cannot open selection window, will use command line input"
    }
    if (-not $selectedPath) {
        $manualInput = Read-Host "Please enter Windsurf installation directory (containing Windsurf.exe), or press Enter to cancel"
        if (-not [string]::IsNullOrWhiteSpace($manualInput)) {
            $selectedPath = $manualInput
        }
    }
    if ($selectedPath) {
        $normalized = Normalize-WindsurfInstallCandidate -Path $selectedPath
        if ($normalized -and (Test-WindsurfInstallPath -Path $normalized)) {
            Write-Host "$GREEN✅ [Found]$NC Manually specified installation path: $normalized"
            return $normalized
        }
        Write-Host "$RED❌ [Error]$NC Manual path is invalid: $selectedPath"
    }
    return $null
}

function Resolve-WindsurfInstallPath {
    param([switch]$AllowPrompt)
    if ($global:WindsurfInstallPath -and (Test-WindsurfInstallPath -Path $global:WindsurfInstallPath)) {
        return $global:WindsurfInstallPath
    }

    Write-Host "$BLUE🔎 [Path]$NC Detecting Windsurf installation directory..."
    $candidates = @()
    if ($global:WindsurfLocalAppDataRoot) {
        $candidates += (Join-Path $global:WindsurfLocalAppDataRoot "Programs\Windsurf")
    }
    $programFiles = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFiles)
    if ($programFiles) {
        $candidates += (Join-Path $programFiles "Windsurf")
    }
    $programFilesX86 = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::ProgramFilesX86)
    if ($programFilesX86) {
        $candidates += (Join-Path $programFilesX86 "Windsurf")
    }

    $regCandidates = @(Get-WindsurfInstallPathFromRegistry)
    if ($regCandidates.Count -gt 0) {
        Write-Host "$BLUEℹ️  [Path]$NC Found candidate paths from registry: $($regCandidates -join '; ')"
        $candidates += $regCandidates
    }

    $fixedDrives = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' }
    foreach ($drive in $fixedDrives) {
        $root = $drive.RootDirectory.FullName
        $candidates += (Join-Path $root "Program Files\Windsurf")
        $candidates += (Join-Path $root "Program Files (x86)\Windsurf")
        $candidates += (Join-Path $root "Windsurf")
    }

    $candidates = $candidates | Where-Object { $_ } | Select-Object -Unique
    $totalCandidates = $candidates.Count
    for ($i = 0; $i -lt $totalCandidates; $i++) {
        $candidate = Normalize-WindsurfInstallCandidate -Path $candidates[$i]
        $attempt = $i + 1
        if (-not $candidate) {
            continue
        }
        Write-Host "$BLUE⏳ [Path]$NC ($attempt/$totalCandidates) Trying installation path: $candidate"
        if (Test-WindsurfInstallPath -Path $candidate) {
            $global:WindsurfInstallPath = $candidate
            Write-Host "$GREEN✅ [Found]$NC Found Windsurf installation path: $candidate"
            return $candidate
        }
    }

    if ($AllowPrompt) {
        $manualPath = Request-WindsurfInstallPathFromUser
        if ($manualPath) {
            $global:WindsurfInstallPath = $manualPath
            return $manualPath
        }
    }

    Write-Host "$RED❌ [Error]$NC Windsurf application installation path not found"
    Write-Host "$YELLOW💡 [Tip]$NC Please confirm Windsurf is properly installed or manually specify the path"
    return $null
}

# Configuration file paths (use global variables uniformly after initialization)
Initialize-WindsurfPaths
$STORAGE_FILE = $global:WindsurfStorageFile
$BACKUP_DIR = $global:WindsurfBackupDir

# PowerShell native method to generate random strings
function Generate-RandomString {
    param([int]$Length)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $result = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $result
}

# 🔍 Simple JavaScript brace matching (used to locate function boundaries within limited segments, avoiding regex cross-segment mis-replacement)
# Note: This is a lightweight parser, sufficient to handle minified function bodies in main.js (including try/catch, strings, comments).
function Find-JsMatchingBraceEnd {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$OpenBraceIndex,
        [int]$MaxScan = 20000
    )

    if ($OpenBraceIndex -lt 0 -or $OpenBraceIndex -ge $Text.Length) {
        return -1
    }

    $limit = [Math]::Min($Text.Length, $OpenBraceIndex + $MaxScan)

    $depth = 1
    $inSingle = $false
    $inDouble = $false
    $inTemplate = $false
    $inLineComment = $false
    $inBlockComment = $false
    $escape = $false

    for ($i = $OpenBraceIndex + 1; $i -lt $limit; $i++) {
        $ch = $Text[$i]
        $next = if ($i + 1 -lt $limit) { $Text[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($ch -eq "`n") { $inLineComment = $false }
            continue
        }
        if ($inBlockComment) {
            if ($ch -eq '*' -and $next -eq '/') { $inBlockComment = $false; $i++; continue }
            continue
        }

        if ($inSingle) {
            if ($escape) { $escape = $false; continue }
            if ($ch -eq '\') { $escape = $true; continue }
            if ($ch -eq "'") { $inSingle = $false }
            continue
        }
        if ($inDouble) {
            if ($escape) { $escape = $false; continue }
            if ($ch -eq '\') { $escape = $true; continue }
            if ($ch -eq '"') { $inDouble = $false }
            continue
        }
        if ($inTemplate) {
            if ($escape) { $escape = $false; continue }
            if ($ch -eq '\') { $escape = $true; continue }
            if ($ch -eq '`') { $inTemplate = $false }
            continue
        }

        # Comment detection (only in non-string state)
        if ($ch -eq '/' -and $next -eq '/') { $inLineComment = $true; $i++; continue }
        if ($ch -eq '/' -and $next -eq '*') { $inBlockComment = $true; $i++; continue }

        # Strings / template strings
        if ($ch -eq "'") { $inSingle = $true; continue }
        if ($ch -eq '"') { $inDouble = $true; continue }
        if ($ch -eq '`') { $inTemplate = $true; continue }

        # Brace depth
        if ($ch -eq '{') { $depth++; continue }
        if ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }

    return -1
}

# 🔧 Modify Windsurf core JS files to implement device identification bypass (enhanced triple-method approach)
# Method A: someValue placeholder replacement - stable anchor, does not depend on obfuscated function names
# Method B: b6 fixed-point rewrite - machine code source function directly returns fixed value
# Method C: Loader Stub + External Hook - main/shared processes only load external Hook file
function Modify-WindsurfJSFiles {
    Write-Host ""
    Write-Host "$BLUE🔧 [Kernel Modification]$NC Starting to modify Windsurf core JS files to implement device identification bypass..."
    Write-Host "$BLUE💡 [Method]$NC Using enhanced triple-method approach: placeholder replacement + b6 fixed-point rewrite + Loader Stub + External Hook"
    Write-Host ""

    # Windows version Windsurf application path (supports auto-detection + manual fallback)
    $windsurfAppPath = Resolve-WindsurfInstallPath -AllowPrompt
    if (-not $windsurfAppPath) {
        return $false
    }

    # Generate or reuse device identifiers (prioritize using values generated in configuration)
    $useConfigIds = $false
    if ($global:WindsurfIds -and $global:WindsurfIds.machineId -and $global:WindsurfIds.macMachineId -and $global:WindsurfIds.devDeviceId -and $global:WindsurfIds.sqmId) {
        $machineId = [string]$global:WindsurfIds.machineId
        $macMachineId = [string]$global:WindsurfIds.macMachineId
        $deviceId = [string]$global:WindsurfIds.devDeviceId
        $sqmId = [string]$global:WindsurfIds.sqmId
        # Machine GUID used to simulate registry/original machine code reading
        $machineGuid = if ($global:WindsurfIds.machineGuid) { [string]$global:WindsurfIds.machineGuid } else { [System.Guid]::NewGuid().ToString().ToLower() }
        $sessionId = if ($global:WindsurfIds.sessionId) { [string]$global:WindsurfIds.sessionId } else { [System.Guid]::NewGuid().ToString().ToLower() }
        # Use UTC time to generate/normalize firstSessionDate, avoiding semantic errors of local time with Z suffix; also compatible with ConvertFrom-Json possibly returning DateTime
        $firstSessionDateValue = if ($global:WindsurfIds.firstSessionDate) {
            $rawFirstSessionDate = $global:WindsurfIds.firstSessionDate
            if ($rawFirstSessionDate -is [DateTime]) {
                $rawFirstSessionDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            } elseif ($rawFirstSessionDate -is [DateTimeOffset]) {
                $rawFirstSessionDate.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            } else {
                [string]$rawFirstSessionDate
            }
        } else {
            (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        $macAddress = if ($global:WindsurfIds.macAddress) { [string]$global:WindsurfIds.macAddress } else { "00:11:22:33:44:55" }
        $useConfigIds = $true
    } else {
        $randomBytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        $rng.GetBytes($randomBytes)
        $machineId = [System.BitConverter]::ToString($randomBytes) -replace '-',''
        $rng.Dispose()
        $deviceId = [System.Guid]::NewGuid().ToString().ToLower()
        $randomBytes2 = New-Object byte[] 32
        $rng2 = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        $rng2.GetBytes($randomBytes2)
        $macMachineId = [System.BitConverter]::ToString($randomBytes2) -replace '-',''
        $rng2.Dispose()
        $sqmId = "{" + [System.Guid]::NewGuid().ToString().ToUpper() + "}"
        # Machine GUID used to simulate registry/original machine code reading
        $machineGuid = [System.Guid]::NewGuid().ToString().ToLower()
        $sessionId = [System.Guid]::NewGuid().ToString().ToLower()
        # Use UTC time to generate firstSessionDate, avoiding semantic errors of local time with Z suffix
        $firstSessionDateValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $macAddress = "00:11:22:33:44:55"
    }

    if ($useConfigIds) {
        Write-Host "$GREEN🔑 [Preparation]$NC Device identifiers from configuration have been used"
    } else {
        Write-Host "$GREEN🔑 [Generated]$NC New device identifiers have been generated"
    }
    Write-Host "   machineId: $($machineId.Substring(0,16))..."
    Write-Host "   machineGuid: $($machineGuid.Substring(0,16))..."
    Write-Host "   deviceId: $($deviceId.Substring(0,16))..."
    Write-Host "   macMachineId: $($macMachineId.Substring(0,16))..."
    Write-Host "   sqmId: $sqmId"

    # Save ID configuration to user directory (for Hook to read)
    # Delete old configuration and regenerate on each execution to ensure new device identifiers
    $idsConfigPath = "$env:USERPROFILE\.windsurf_ids.json"
    if (Test-Path $idsConfigPath) {
        Remove-Item -Path $idsConfigPath -Force
        Write-Host "$YELLOW🗑️  [Cleanup]$NC Old ID configuration file has been deleted"
    }
    $idsConfig = @{
        machineId = $machineId
        machineGuid = $machineGuid
        macMachineId = $macMachineId
        devDeviceId = $deviceId
        sqmId = $sqmId
        macAddress = $macAddress
        sessionId = $sessionId
        firstSessionDate = $firstSessionDateValue
        createdAt = $firstSessionDateValue
    }
    $idsConfig | ConvertTo-Json | Set-Content -Path $idsConfigPath -Encoding UTF8
    Write-Host "$GREEN💾 [Save]$NC New ID configuration has been saved to: $idsConfigPath"

    # Deploy external Hook file (for Loader Stub to load, supports multi-domain backup download)
    $hookTargetPath = "$env:USERPROFILE\.windsurf_hook.js"
    # Compatibility: When executing via `irm ... | iex`, $PSScriptRoot may be empty, Join-Path will directly error
    $hookSourceCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $hookSourceCandidates += (Join-Path $PSScriptRoot "..\hook\cursor_hook.js")
    } elseif ($MyInvocation.MyCommand.Path) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        if (-not [string]::IsNullOrWhiteSpace($scriptDir)) {
            $hookSourceCandidates += (Join-Path $scriptDir "..\hook\cursor_hook.js")
        }
    }
    $cwdPath = $null
    try { $cwdPath = (Get-Location).Path } catch { $cwdPath = $null }
    if (-not [string]::IsNullOrWhiteSpace($cwdPath)) {
        $hookSourceCandidates += (Join-Path $cwdPath "scripts\hook\cursor_hook.js")
    }
    $hookSourcePath = $hookSourceCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    $hookDownloadUrls = @(
        "https://wget.la/https://raw.githubusercontent.com/yuaotian/go-cursor-help/refs/heads/master/scripts/hook/windsurf_hook.js",
        "https://down.npee.cn/?https://raw.githubusercontent.com/yuaotian/go-cursor-help/refs/heads/master/scripts/hook/windsurf_hook.js",
        "https://xget.xi-xu.me/gh/yuaotian/go-cursor-help/refs/heads/master/scripts/hook/windsurf_hook.js",
        "https://gh-proxy.com/https://raw.githubusercontent.com/yuaotian/go-cursor-help/refs/heads/master/scripts/hook/windsurf_hook.js",
        "https://gh.chjina.com/https://raw.githubusercontent.com/yuaotian/go-cursor-help/refs/heads/master/scripts/hook/windsurf_hook.js"
    )
    # Support overriding download nodes via environment variables (comma-separated)
    if ($env:WINDSURF_HOOK_DOWNLOAD_URLS) {
        $hookDownloadUrls = $env:WINDSURF_HOOK_DOWNLOAD_URLS -split '\s*,\s*' | Where-Object { $_ }
        Write-Host "$BLUEℹ️  [Hook]$NC Custom download node list detected, will prioritize its use"
    }
    if ($hookSourcePath) {
        try {
            Copy-Item -Path $hookSourcePath -Destination $hookTargetPath -Force
            Write-Host "$GREEN✅ [Hook]$NC External Hook has been deployed: $hookTargetPath"
        } catch {
            Write-Host "$YELLOW⚠️  [Hook]$NC Local Hook copy failed, trying online download..."
        }
    }
    if (-not (Test-Path $hookTargetPath)) {
        Write-Host "$BLUEℹ️  [Hook]$NC Downloading external Hook for device identifier interception..."
        $originalProgressPreference = $ProgressPreference
        $ProgressPreference = 'Continue'
        try {
            if ($hookDownloadUrls.Count -eq 0) {
                Write-Host "$YELLOW⚠️  [Hook]$NC Download node list is empty, skipping online download"
            } else {
                $totalUrls = $hookDownloadUrls.Count
                for ($i = 0; $i -lt $totalUrls; $i++) {
                    $url = $hookDownloadUrls[$i]
                    $attempt = $i + 1
                    Write-Host "$BLUE⏳ [Hook]$NC ($attempt/$totalUrls) Current download node: $url"
                    try {
                        Invoke-WebRequest -Uri $url -OutFile $hookTargetPath -UseBasicParsing -ErrorAction Stop
                        Write-Host "$GREEN✅ [Hook]$NC External Hook has been downloaded online: $hookTargetPath"
                        break
                    } catch {
                        Write-Host "$YELLOW⚠️  [Hook]$NC External Hook download failed: $url"
                        if (Test-Path $hookTargetPath) {
                            Remove-Item -Path $hookTargetPath -Force
                        }
                    }
                }
            }
        } finally {
            $ProgressPreference = $originalProgressPreference
        }
        if (-not (Test-Path $hookTargetPath)) {
            Write-Host "$YELLOW⚠️  [Hook]$NC All external Hook downloads failed"
        }
    }

    # Target JS file list (Windows paths, sorted by priority)
    $jsFiles = @(
        "$windsurfAppPath\resources\app\out\main.js",
        # Shared process used for telemetry aggregation, needs synchronous injection
        "$windsurfAppPath\resources\app\out\vs\code\electron-utility\sharedProcess\sharedProcessMain.js"
    )

    $modifiedCount = 0

    # Close Windsurf processes
    Write-Host "$BLUE🔄 [Close]$NC Closing Windsurf processes for file modification..."
    Stop-AllWindsurfProcesses -MaxRetries 3 -WaitSeconds 3 | Out-Null

    # Create backup directory
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$windsurfAppPath\resources\app\out\backups"

    Write-Host "$BLUE💾 [Backup]$NC Creating Windsurf JS file backups..."
    try {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

        # Check if original backup exists
        $originalBackup = "$backupPath\main.js.original"

        foreach ($file in $jsFiles) {
            if (-not (Test-Path $file)) {
                Write-Host "$YELLOW⚠️  [Warning]$NC File does not exist: $(Split-Path $file -Leaf)"
                continue
            }

            $fileName = Split-Path $file -Leaf
            $fileOriginalBackup = "$backupPath\$fileName.original"

            # If original backup does not exist, create it first
            if (-not (Test-Path $fileOriginalBackup)) {
                # Check if current file has been modified before
                $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
                if ($content -and $content -match "__cursor_patched__") {
                    Write-Host "$YELLOW⚠️  [Warning]$NC File has been modified but no original backup exists, will use current version as base"
                }
                Copy-Item $file $fileOriginalBackup -Force
                Write-Host "$GREEN✅ [Backup]$NC Original backup created successfully: $fileName"
            } else {
                # Restore from original backup to ensure clean injection each time
                Write-Host "$BLUE🔄 [Restore]$NC Restoring from original backup: $fileName"
                Copy-Item $fileOriginalBackup $file -Force
            }
        }

        # Create timestamped backup (record state before each modification)
        foreach ($file in $jsFiles) {
            if (Test-Path $file) {
                $fileName = Split-Path $file -Leaf
                Copy-Item $file "$backupPath\$fileName.backup_$timestamp" -Force
            }
        }
        Write-Host "$GREEN✅ [Backup]$NC Timestamped backup created successfully: $backupPath"
    } catch {
        Write-Host "$RED❌ [Error]$NC Backup creation failed: $($_.Exception.Message)"
        return $false
    }

    # Modify JS files (re-inject each time since restored from original backup)
    Write-Host "$BLUE🔧 [Modify]$NC Starting to modify JS files (using device identifiers)..."

    foreach ($file in $jsFiles) {
        if (-not (Test-Path $file)) {
            Write-Host "$YELLOW⚠️  [Skip]$NC File does not exist: $(Split-Path $file -Leaf)"
            continue
        }

        Write-Host "$BLUE📝 [Processing]$NC Processing: $(Split-Path $file -Leaf)"

        try {
            $content = Get-Content $file -Raw -Encoding UTF8
            $replaced = $false
            $replacedB6 = $false

            # ========== Method A: someValue placeholder replacement (stable anchor) ==========
            # These strings are fixed placeholders, will not be modified by obfuscator, stable across versions
            # Important note:
            # In current Windsurf's main.js, placeholders usually appear as string literals, for example:
            #   this.machineId="someValue.machineId"
            # If directly replacing someValue.machineId with "\"<real value>\"", it will form ""<real value>"" causing JS syntax error (Invalid token).
            # Therefore, here we prioritize replacing complete string literals (including outer quotes) and use JSON string literals to ensure escape safety.

            # 🔧 Added: firstSessionDate (reset first session date)
            if (-not $firstSessionDateValue) {
                # Use UTC time to generate firstSessionDate, avoiding semantic errors of local time with Z suffix
                $firstSessionDateValue = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }

            $placeholders = @(
                @{ Name = 'someValue.machineId';         Value = [string]$machineId },
                @{ Name = 'someValue.macMachineId';      Value = [string]$macMachineId },
                @{ Name = 'someValue.devDeviceId';       Value = [string]$deviceId },
                @{ Name = 'someValue.sqmId';             Value = [string]$sqmId },
                @{ Name = 'someValue.sessionId';         Value = [string]$sessionId },
                @{ Name = 'someValue.firstSessionDate';  Value = [string]$firstSessionDateValue }
            )

            foreach ($ph in $placeholders) {
                $name = $ph.Name
                $jsonValue = ($ph.Value | ConvertTo-Json -Compress)  # Generate JSON string literal with double quotes

                $changed = $false

                # Prioritize replacing quoted placeholder literals to avoid ""abc"" breaking syntax
                $doubleLiteral = '"' + $name + '"'
                if ($content.Contains($doubleLiteral)) {
                    $content = $content.Replace($doubleLiteral, $jsonValue)
                    $changed = $true
                }
                $singleLiteral = "'" + $name + "'"
                if ($content.Contains($singleLiteral)) {
                    $content = $content.Replace($singleLiteral, $jsonValue)
                    $changed = $true
                }

                # Fallback: if placeholder appears in non-string literal form, replace with JSON string literal (with quotes)
                if (-not $changed -and $content.Contains($name)) {
                    $content = $content.Replace($name, $jsonValue)
                    $changed = $true
                }

                if ($changed) {
                    Write-Host "   $GREEN✓$NC [Method A] Replaced $name"
                    $replaced = $true
                }
            }

            # ========== Method B: b6 fixed-point rewrite (machine code source function, only main.js) ==========
            # Note: b6(t) is the core generation function for machineId, t=true returns original value, t=false returns hash
            if ((Split-Path $file -Leaf) -eq "main.js") {
                # ✅ 1+3 fusion: Limit feature matching within out-build/vs/base/node/id.js module + brace pairing to locate function boundaries
                # Purpose: Improve cross-version coverage while avoiding regex cross-module false positives causing main.js syntax damage.
                try {
                    $moduleMarker = "out-build/vs/base/node/id.js"
                    $markerIndex = $content.IndexOf($moduleMarker)
                    if ($markerIndex -lt 0) {
                        throw "id.js module marker not found"
                    }

                    $windowLen = [Math]::Min($content.Length - $markerIndex, 200000)
                    $windowText = $content.Substring($markerIndex, $windowLen)

                    $hashRegex = [regex]::new('createHash\(["'']sha256["'']\)')
                    $hashMatches = $hashRegex.Matches($windowText)
                    Write-Host "   $BLUEℹ️  $NC [Method B Diagnosis] id.js offset=$markerIndex | sha256 createHash hits=$($hashMatches.Count)"
                    $patched = $false
                    $diagLines = @()
                    # Compatibility: In PowerShell expandable strings, "$var:" will be parsed as scope/drive prefix, need to use "${var}" to clarify variable boundary
                    $candidateNo = 0

                    foreach ($hm in $hashMatches) {
                        $candidateNo++
                        $hashPos = $hm.Index
                        $funcStart = $windowText.LastIndexOf("async function", $hashPos)
                        if ($funcStart -lt 0) {
                            if ($candidateNo -le 3) { $diagLines += "Candidate #${candidateNo}: async function start point not found" }
                            continue
                        }

                        $openBrace = $windowText.IndexOf("{", $funcStart)
                        if ($openBrace -lt 0) {
                            if ($candidateNo -le 3) { $diagLines += "Candidate #${candidateNo}: Function starting brace not found" }
                            continue
                        }

                        $endBrace = Find-JsMatchingBraceEnd -Text $windowText -OpenBraceIndex $openBrace -MaxScan 20000
                        if ($endBrace -lt 0) {
                            if ($candidateNo -le 3) { $diagLines += "Candidate #${candidateNo}: Brace pairing failed (not closed within scan limit)" }
                            continue
                        }

                        $funcText = $windowText.Substring($funcStart, $endBrace - $funcStart + 1)
                        if ($funcText.Length -gt 8000) {
                            if ($candidateNo -le 3) { $diagLines += "Candidate #${candidateNo}: Function body too long len=$($funcText.Length), skipped" }
                            continue
                        }

                        $sig = [regex]::Match($funcText, '^async function (\w+)\((\w+)\)')
                        if (-not $sig.Success) {
                            if ($candidateNo -le 3) { $diagLines += "Candidate #${candidateNo}: Function signature not parsed (async function name(param))" }
                            continue
                        }
                        $fn = $sig.Groups[1].Value
                        $param = $sig.Groups[2].Value

                        # Feature validation: sha256 + hex digest + return param ? raw : hash
                        $hasDigest = ($funcText -match '\.digest\(["'']hex["'']\)')
                        $hasReturn = ($funcText -match ('return\s+' + [regex]::Escape($param) + '\?\w+:\w+\}'))
                        if ($candidateNo -le 3) {
                            $diagLines += "Candidate #${candidateNo}: $fn($param) len=$($funcText.Length) digest=$hasDigest return=$hasReturn"
                        }
                        if (-not $hasDigest) { continue }
                        if (-not $hasReturn) { continue }

                        $replacement = "async function $fn($param){return $param?'$machineGuid':'$machineId';}"
                        $absStart = $markerIndex + $funcStart
                        $absEnd = $markerIndex + $endBrace
                        $content = $content.Substring(0, $absStart) + $replacement + $content.Substring($absEnd + 1)

                        Write-Host "   $BLUEℹ️  $NC [Method B Diagnosis] Hit candidate #${candidateNo}: $fn($param) len=$($funcText.Length)"
                        Write-Host "   $GREEN✓$NC [Method B] Rewrote $fn($param) machine code source function (fusion version feature matching)"
                        $replacedB6 = $true
                        $patched = $true
                        break
                    }

                    if (-not $patched) {
                        Write-Host "   $YELLOW⚠️  $NC [Method B] Machine code source function feature not located, skipped"
                        foreach ($d in ($diagLines | Select-Object -First 3)) {
                            Write-Host "      $BLUEℹ️  $NC [Method B Diagnosis] $d"
                        }
                    }
                } catch {
                    Write-Host "   $YELLOW⚠️  $NC [Method B] Location failed, skipped: $($_.Exception.Message)"
                }
            }

            # ========== Method C: Loader Stub injection ==========
            # Note: Main/shared processes only inject loader, specific Hook logic maintained by external windsurf_hook.js

            $injectCode = @"
// ========== Cursor Hook Loader Start ==========
;(async function(){/*__cursor_patched__*/
'use strict';
if (globalThis.__cursor_hook_loaded__) return;
globalThis.__cursor_hook_loaded__ = true;

try {
    // Compatible with ESM/CJS: Avoid using import.meta (only ESM supported), use dynamic import to load Hook uniformly
    var fsMod = await import('fs');
    var pathMod = await import('path');
    var osMod = await import('os');
    var urlMod = await import('url');

    var fs = fsMod && (fsMod.default || fsMod);
    var path = pathMod && (pathMod.default || pathMod);
    var os = osMod && (osMod.default || osMod);
    var url = urlMod && (urlMod.default || urlMod);

    if (fs && path && os && url && typeof url.pathToFileURL === 'function') {
        var hookPath = path.join(os.homedir(), '.windsurf_hook.js');
        if (typeof fs.existsSync === 'function' && fs.existsSync(hookPath)) {
            await import(url.pathToFileURL(hookPath).href);
        }
    }
} catch (e) {
    // Fail silently to avoid affecting startup
}
})();
// ========== Cursor Hook Loader End ==========

"@

            # Find copyright declaration end position and inject after it (inject only once to avoid multiple insertions breaking syntax)
            if ($content -match "__windsurf_patched__") {
                Write-Host "   $YELLOW⚠️  $NC [Method C] Existing injection marker detected, skipping duplicate injection"
            } elseif ($content -match '(\*/\s*\n)') {
                $replacement = '$1' + $injectCode
                $content = [regex]::Replace($content, '(\*/\s*\n)', $replacement, 1)
                Write-Host "   $GREEN✓$NC [Method C] Loader Stub injected (after copyright, first time only)"
            } else {
                # If copyright declaration not found, inject at file beginning
                $content = $injectCode + $content
                Write-Host "   $GREEN✓$NC [Method C] Loader Stub injected (at file beginning)"
            }

            # Injection consistency check: Avoid syntax damage from duplicate injections
            $patchedCount = ([regex]::Matches($content, "__windsurf_patched__")).Count
            if ($patchedCount -gt 1) {
                throw "Duplicate injection marker detected: $patchedCount"
            }

            # Write modified content
            Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline

            # Summarize actually effective method combination for this injection
            $summaryParts = @()
            if ($replaced) { $summaryParts += "someValue replacement" }
            if ($replacedB6) { $summaryParts += "b6 fixed-point rewrite" }
            $summaryParts += "Hook loader"
            $summaryText = ($summaryParts -join " + ")
            Write-Host "$GREEN✅ [Success]$NC Enhanced method modification successful ($summaryText)"
            $modifiedCount++

        } catch {
            Write-Host "$RED❌ [Error]$NC File modification failed: $($_.Exception.Message)"
            # Try to restore from backup
            $fileName = Split-Path $file -Leaf
            $backupFile = "$backupPath\$fileName.original"
            if (Test-Path $backupFile) {
                Copy-Item $backupFile $file -Force
                Write-Host "$YELLOW🔄 [Restore]$NC File restored from backup"
            }
        }
    }

    if ($modifiedCount -gt 0) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Complete]$NC Successfully modified $modifiedCount JS files"
        Write-Host "$BLUE💾 [Backup]$NC Original file backup location: $backupPath"
        Write-Host "$BLUE💡 [Note]$NC Using enhanced triple-method approach:"
        Write-Host "   • Method A: someValue placeholder replacement (stable anchor, cross-version compatible)"
        Write-Host "   • Method B: b6 fixed-point rewrite (machine code source function)"
        Write-Host "   • Method C: Loader Stub + External Hook (windsurf_hook.js)"
        Write-Host "$BLUE📁 [Config]$NC ID configuration file: $idsConfigPath"
        return $true
    } else {
        Write-Host "$RED❌ [Failed]$NC No files were successfully modified"
        return $false
    }
}


# 🚀 Added Windsurf trial reset folder deletion function
function Remove-WindsurfTrialFolders {
    Write-Host ""
    Write-Host "$GREEN🎯 [Core Feature]$NC Executing Windsurf trial reset folder deletion..."
    Write-Host "$BLUE📋 [Description]$NC This function will delete specified Windsurf-related folders to reset trial status"
    Write-Host ""

    # Define folder paths to delete
    $foldersToDelete = @()

    # Windows Administrator user paths
    $adminPaths = @(
        "C:\Users\Administrator\.windsurf",
        "C:\Users\Administrator\AppData\Roaming\Windsurf"
    )

    # Current user paths (using resolved user directory and AppData)
    $currentUserPaths = @()
    $userProfileRoot = if ($global:WindsurfUserProfileRoot) { $global:WindsurfUserProfileRoot } else { [Environment]::GetEnvironmentVariable("USERPROFILE") }
    if ($userProfileRoot) {
        $currentUserPaths += (Join-Path $userProfileRoot ".windsurf")
    }
    if ($global:WindsurfAppDataDir) {
        $currentUserPaths += $global:WindsurfAppDataDir
    }

    # Merge all paths
    $foldersToDelete += $adminPaths
    $foldersToDelete += $currentUserPaths

    Write-Host "$BLUE📂 [Detection]$NC Will check the following folders:"
    foreach ($folder in $foldersToDelete) {
        Write-Host "   📁 $folder"
    }
    Write-Host ""

    $deletedCount = 0
    $skippedCount = 0
    $errorCount = 0

    # Delete specified folders
    foreach ($folder in $foldersToDelete) {
        Write-Host "$BLUE🔍 [Check]$NC Checking folder: $folder"

        if (Test-Path $folder) {
            try {
                Write-Host "$YELLOW⚠️  [Warning]$NC Folder exists, deleting..."
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Host "$GREEN✅ [Success]$NC Folder deleted: $folder"
                $deletedCount++
            }
            catch {
                Write-Host "$RED❌ [Error]$NC Folder deletion failed: $folder"
                Write-Host "$RED💥 [Details]$NC Error message: $($_.Exception.Message)"
                $errorCount++
            }
        } else {
            Write-Host "$YELLOW⏭️  [Skip]$NC Folder does not exist: $folder"
            $skippedCount++
        }
        Write-Host ""
    }

    # Display operation statistics
    Write-Host "$GREEN📊 [Statistics]$NC Operation completion statistics:"
    Write-Host "   ✅ Successfully deleted: $deletedCount folders"
    Write-Host "   ⏭️  Skipped: $skippedCount folders"
    Write-Host "   ❌ Deletion failed: $errorCount folders"
    Write-Host ""

    if ($deletedCount -gt 0) {
        Write-Host "$GREEN🎉 [Complete]$NC Windsurf trial reset folder deletion completed!"

        # 🔧 Pre-create necessary directory structure to avoid permission issues
        Write-Host "$BLUE🔧 [Fix]$NC Pre-creating necessary directory structure to avoid permission issues..."

        $windsurfAppData = $global:WindsurfAppDataDir
        $windsurfLocalAppData = $global:WindsurfLocalAppDataDir
        $windsurfUserProfile = if ($userProfileRoot) { Join-Path $userProfileRoot ".windsurf" } else { "$env:USERPROFILE\.windsurf" }

        # Create main directories
        try {
            if ($windsurfAppData -and -not (Test-Path $windsurfAppData)) {
                New-Item -ItemType Directory -Path $windsurfAppData -Force | Out-Null
            }
            if ($windsurfUserProfile -and -not (Test-Path $windsurfUserProfile)) {
                New-Item -ItemType Directory -Path $windsurfUserProfile -Force | Out-Null
            }
            Write-Host "$GREEN✅ [Complete]$NC Directory structure pre-creation completed"
        } catch {
            Write-Host "$YELLOW⚠️  [Warning]$NC Issue occurred during directory pre-creation: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW🤔 [Tip]$NC No folders found to delete, may have been cleaned already"
    }
    Write-Host ""
}

# 🔄 Restart Windsurf and wait for configuration file generation
function Restart-WindsurfAndWait {
    Write-Host ""
    Write-Host "$GREEN🔄 [Restart]$NC Restarting Windsurf to regenerate configuration files..."

    if (-not $global:WindsurfProcessInfo) {
        Write-Host "$RED❌ [Error]$NC Windsurf process information not found, cannot restart"
        return $false
    }

    $windsurfPath = $global:WindsurfProcessInfo.Path

    # Fix: Ensure path is string type
    if ($windsurfPath -is [array]) {
        $windsurfPath = $windsurfPath[0]
    }

    # Verify path is not empty
    if ([string]::IsNullOrEmpty($windsurfPath)) {
        Write-Host "$RED❌ [Error]$NC Windsurf path is empty"
        return $false
    }

    Write-Host "$BLUE📍 [Path]$NC Using path: $windsurfPath"

    if (-not (Test-Path $windsurfPath)) {
        Write-Host "$RED❌ [Error]$NC Windsurf executable does not exist: $windsurfPath"

        # Try to re-resolve installation path
        $installPath = Resolve-WindsurfInstallPath -AllowPrompt
        $foundPath = if ($installPath) { Join-Path $installPath "Windsurf.exe" } else { $null }
        if ($foundPath -and (Test-Path $foundPath)) {
            Write-Host "$GREEN💡 [Found]$NC Using backup path: $foundPath"
        } else {
            $foundPath = $null
        }

        if (-not $foundPath) {
            Write-Host "$RED❌ [Error]$NC Cannot find valid Windsurf executable"
            return $false
        }

        $windsurfPath = $foundPath
    }

    try {
        Write-Host "$GREEN🚀 [Start]$NC Starting Windsurf..."
        $process = Start-Process -FilePath $windsurfPath -PassThru -WindowStyle Hidden

        Write-Host "$YELLOW⏳ [Wait]$NC Waiting 20 seconds for Windsurf to fully start and generate configuration files..."
        Start-Sleep -Seconds 20

        # Check if configuration file is generated
        $configPath = $STORAGE_FILE
        if (-not $configPath) {
            Write-Host "$RED❌ [Error]$NC Cannot resolve configuration file path"
            return $false
        }
        $maxWait = 45
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting for configuration file generation... ($waited/$maxWait seconds)"
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN✅ [Success]$NC Configuration file generated: $configPath"

            # Additional wait to ensure file is fully written
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting 5 seconds to ensure configuration file is fully written..."
            Start-Sleep -Seconds 5
        } else {
            Write-Host "$YELLOW⚠️  [Warning]$NC Configuration file not generated within expected time"
            Write-Host "$BLUE💡 [Tip]$NC May need to manually start Windsurf once to generate configuration file"
        }

        # Force close Windsurf
        Write-Host "$YELLOW🔄 [Close]$NC Closing Windsurf for configuration modification..."
        if ($process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000)
        }

        # Ensure all Windsurf processes are closed
        Get-Process -Name "Windsurf" -ErrorAction SilentlyContinue | Stop-Process -Force
        Get-Process -Name "windsurf" -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-Host "$GREEN✅ [Complete]$NC Windsurf restart process completed"
        return $true

    } catch {
        Write-Host "$RED❌ [Error]$NC Windsurf restart failed: $($_.Exception.Message)"
        Write-Host "$BLUE💡 [Debug]$NC Error details: $($_.Exception.GetType().FullName)"
        return $false
    }
}

# 🔒 Force close all Windsurf processes (enhanced version)
function Stop-AllWindsurfProcesses {
    param(
        [int]$MaxRetries = 3,
        [int]$WaitSeconds = 5
    )

    Write-Host "$BLUE🔒 [Process Check]$NC Checking and closing all Windsurf-related processes..."

    # Define all possible Windsurf process names
    $windsurfProcessNames = @(
        "Windsurf",
        "windsurf",
        "Windsurf Helper",
        "Windsurf Helper (GPU)",
        "Windsurf Helper (Plugin)",
        "Windsurf Helper (Renderer)",
        "WindsurfUpdater"
    )

    for ($retry = 1; $retry -le $MaxRetries; $retry++) {
        Write-Host "$BLUE🔍 [Check]$NC Process check $retry/$MaxRetries..."

        $foundProcesses = @()
        foreach ($processName in $windsurfProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                $foundProcesses += $processes
                Write-Host "$YELLOW⚠️  [Found]$NC Process: $processName (PID: $($processes.Id -join ', '))"
            }
        }

        if ($foundProcesses.Count -eq 0) {
            Write-Host "$GREEN✅ [Success]$NC All Windsurf processes have been closed"
            return $true
        }

        Write-Host "$YELLOW🔄 [Close]$NC Closing $($foundProcesses.Count) Windsurf processes..."

        # First try graceful close
        foreach ($process in $foundProcesses) {
            try {
                $process.CloseMainWindow() | Out-Null
                Write-Host "$BLUE  • Graceful close: $($process.ProcessName) (PID: $($process.Id))$NC"
            } catch {
                Write-Host "$YELLOW  • Graceful close failed: $($process.ProcessName)$NC"
            }
        }

        Start-Sleep -Seconds 3

        # Force terminate still running processes
        foreach ($processName in $windsurfProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                foreach ($process in $processes) {
                    try {
                        Stop-Process -Id $process.Id -Force
                        Write-Host "$RED  • Force terminate: $($process.ProcessName) (PID: $($process.Id))$NC"
                    } catch {
                        Write-Host "$RED  • Force terminate failed: $($process.ProcessName)$NC"
                    }
                }
            }
        }

        if ($retry -lt $MaxRetries) {
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting $WaitSeconds seconds before rechecking..."
            Start-Sleep -Seconds $WaitSeconds
        }
    }

    Write-Host "$RED❌ [Failed]$NC After $MaxRetries attempts, Windsurf processes are still running"
    return $false
}

# 🔐 Check file permissions and lock status
function Test-FileAccessibility {
    param(
        [string]$FilePath
    )

    Write-Host "$BLUE🔐 [Permission Check]$NC Checking file access permissions: $(Split-Path $FilePath -Leaf)"

    if (-not (Test-Path $FilePath)) {
        Write-Host "$RED❌ [Error]$NC File does not exist"
        return $false
    }

    # Check if file is locked
    try {
        $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        $fileStream.Close()
        Write-Host "$GREEN✅ [Permission]$NC File is readable/writable, not locked"
        return $true
    } catch [System.IO.IOException] {
        Write-Host "$RED❌ [Locked]$NC File is locked by another process: $($_.Exception.Message)"
        return $false
    } catch [System.UnauthorizedAccessException] {
        Write-Host "$YELLOW⚠️  [Permission]$NC File permissions are restricted, trying to modify..."

        # Try to modify file permissions
        try {
            $file = Get-Item $FilePath
            if ($file.IsReadOnly) {
                $file.IsReadOnly = $false
                Write-Host "$GREEN✅ [Fix]$NC Read-only attribute removed"
            }

            # Test again
            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            Write-Host "$GREEN✅ [Permission]$NC Permission repair successful"
            return $true
        } catch {
            Write-Host "$RED❌ [Permission]$NC Cannot repair permissions: $($_.Exception.Message)"
            return $false
        }
    } catch {
        Write-Host "$RED❌ [Error]$NC Unknown error: $($_.Exception.Message)"
        return $false
    }
}

# 🧹 Windsurf initialization cleanup function (ported from old version)
function Invoke-WindsurfInitialization {
    Write-Host ""
    Write-Host "$GREEN🧹 [Initialization]$NC Executing Windsurf initialization cleanup..."
    $BASE_PATH = if ($global:WindsurfAppDataDir) { Join-Path $global:WindsurfAppDataDir "User" } else { $null }

        Write-Host "$RED❌ [Error]$NC Cannot resolve Windsurf user directory, initialization cleanup terminated"
        return
    }

    $filesToDelete = @(
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb"),
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb.backup")
    )

    $folderToCleanContents = Join-Path -Path $BASE_PATH -ChildPath "History"
    $folderToDeleteCompletely = Join-Path -Path $BASE_PATH -ChildPath "workspaceStorage"

    Write-Host "$BLUE🔍 [Debug]$NC Base path: $BASE_PATH"

    # Delete specified file
    foreach ($file in $filesToDelete) {
        Write-Host "$BLUE🔍 [Check]$NC Checking file: $file"
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force -ErrorAction Stop
                Write-Host "$GREEN✅ [Success]$NC File deleted: $file"
            }
            catch {
                Write-Host "$RED❌ [Error]$NC File deletion $file failed: $($_.Exception.Message)"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Skip]$NC File does not exist, skipping deletion: $file"
        }
    }

    # Clear specified folder contents
    Write-Host "$BLUE🔍 [Check]$NC Checking folder to clear: $folderToCleanContents"
    if (Test-Path $folderToCleanContents) {
        try {
            Get-ChildItem -Path $folderToCleanContents -Recurse | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-Host "$GREEN✅ [Success]$NC Folder contents cleared: $folderToCleanContents"
        }
        catch {
            Write-Host "$RED❌ [Error]$NC Folder clearing $folderToCleanContents failed: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW⚠️  [Skip]$NC Folder does not exist, skipping clear: $folderToCleanContents"
    }

    # Completely delete specified folders
    Write-Host "$BLUE🔍 [Check]$NC Checking folder to delete: $folderToDeleteCompletely"
    if (Test-Path $folderToDeleteCompletely) {
        try {
            Remove-Item -Path $folderToDeleteCompletely -Recurse -Force -ErrorAction Stop
            Write-Host "$GREEN✅ [Success]$NC Folder deleted: $folderToDeleteCompletely"
        }
        catch {
            Write-Host "$RED❌ [Error]$NC Folder deletion $folderToDeleteCompletely failed: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW⚠️  [Skip]$NC Folder does not exist, skipping deletion: $folderToDeleteCompletely"
    }

    Write-Host "$GREEN✅ [Complete]$NC Windsurf initialization cleanup completed"
    Write-Host ""
}

# 🔧 Modify system registry MachineGuid (ported from old version)
function Update-MachineGuid {
    try {
        Write-Host "$BLUE🔧 [Registry]$NC Modifying system registry MachineGuid..."

        # Check if registry path exists, create if not
        $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        if (-not (Test-Path $registryPath)) {
            Write-Host "$YELLOW⚠️  [Warning]$NC Registry path does not exist: $registryPath, creating..."
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "$GREEN✅ [Info]$NC Registry path created successfully"
        }

        # Get current MachineGuid, use empty string as default if not exists
        $originalGuid = ""
        try {
            $currentGuid = Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction SilentlyContinue
            if ($currentGuid) {
                $originalGuid = $currentGuid.MachineGuid
                Write-Host "$GREEN✅ [Info]$NC Current registry value:"
                Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
                Write-Host "    MachineGuid    REG_SZ    $originalGuid"
            } else {
                Write-Host "$YELLOW⚠️  [Warning]$NC MachineGuid value does not exist, will create new value"
            }
        } catch {
            Write-Host "$YELLOW⚠️  [Warning]$NC Failed to read registry: $($_.Exception.Message)"
            Write-Host "$YELLOW⚠️  [Warning]$NC Will try to create new MachineGuid value"
        }

        # Create backup file (only when original value exists)
        $backupFile = $null
        if ($originalGuid) {
            $backupFile = "$BACKUP_DIR\MachineGuid_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            Write-Host "$BLUE💾 [Backup]$NC Backing up registry..."
            $backupResult = Start-Process "reg.exe" -ArgumentList "export", "`"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography`"", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($backupResult.ExitCode -eq 0) {
                Write-Host "$GREEN✅ [Backup]$NC Registry entry backed up to: $backupFile"
            } else {
                Write-Host "$YELLOW⚠️  [Warning]$NC Backup creation failed, continuing..."
                $backupFile = $null
            }
        }

        # Generate new GUID
        $newGuid = [System.Guid]::NewGuid().ToString()
        Write-Host "$BLUE🔄 [Generate]$NC New MachineGuid: $newGuid"

        # Update or create registry value
        Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid -Force -ErrorAction Stop

        # Verify update
        $verifyGuid = (Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($verifyGuid -ne $newGuid) {
            throw "Registry verification failed: Updated value ($verifyGuid) does not match expected value ($newGuid)"
        }

        Write-Host "$GREEN✅ [Success]$NC Registry update successful:"
        Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
        Write-Host "    MachineGuid    REG_SZ    $newGuid"
        return $true
    }
    catch {
        Write-Host "$RED❌ [Error]$NC Registry operation failed: $($_.Exception.Message)"

        # Try to restore backup (if exists)
        if ($backupFile -and (Test-Path $backupFile)) {
            Write-Host "$YELLOW🔄 [Restore]$NC Restoring from backup..."
            $restoreResult = Start-Process "reg.exe" -ArgumentList "import", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($restoreResult.ExitCode -eq 0) {
                Write-Host "$GREEN✅ [Restore Success]$NC Original registry value restored"
            } else {
                Write-Host "$RED❌ [Error]$NC Restore failed, please manually import backup file: $backupFile"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Warning]$NC Backup file not found or backup creation failed, cannot auto-restore"
        }

        return $false
    }
}

# 🚫 Disable Windsurf auto-update (Windows)
function Disable-WindsurfAutoUpdate {
    Write-Host ""
    Write-Host "$BLUE🚫 [Disable Update]$NC Attempting to disable Windsurf auto-update..."

    # Detect Windsurf installation path (supports auto-detection + manual fallback)
    $windsurfAppPath = Resolve-WindsurfInstallPath -AllowPrompt
    if (-not $windsurfAppPath) {
        Write-Host "$YELLOW⚠️  [Warning]$NC Windsurf installation path not found, skipping update disable"
        return $false
    }

    $updateFiles += "$windsurfAppPath\resources\app-update.yml"
    $updateFiles += "$windsurfAppPath\resources\app\update-config.json"
    if ($global:WindsurfAppDataDir) {
        $updateFiles += (Join-Path $global:WindsurfAppDataDir "update-config.json")
        $updateFiles += (Join-Path $global:WindsurfAppDataDir "settings.json")
    }
    $updateFiles = $updateFiles | Where-Object { $_ }

    foreach ($file in $updateFiles) {
        if (-not (Test-Path $file)) { continue }

        try {
            Copy-Item $file "$file.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force
        } catch {
            Write-Host "$YELLOW⚠️  [Warning]$NC Backup failed: $file"
        }

        if ($file -like "*.yml") {
            Set-Content -Path $file -Value "# update disabled by script $(Get-Date)" -Encoding UTF8
            Write-Host "$GREEN✅ [Complete]$NC Update configuration processed: $file"
            continue
        }

        if ($file -like "*update-config.json") {
            $config = @{ autoCheck = $false; autoDownload = $false }
            $config | ConvertTo-Json -Depth 5 | Set-Content -Path $file -Encoding UTF8
            Write-Host "$GREEN✅ [Complete]$NC Update configuration processed: $file"
            continue
        }

        if ($file -like "*settings.json") {
            try {
                $settings = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $settings = @{}
            }
            if ($settings -is [hashtable]) {
                $settings["update.mode"] = "none"
            } else {
                $settings | Add-Member -MemberType NoteProperty -Name "update.mode" -Value "none" -Force
            }
            $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $file -Encoding UTF8
            Write-Host "$GREEN✅ [Complete]$NC Update configuration processed: $file"
            continue
        }
    }

    # Try to disable updater executable
    $updaterCandidates = @()
    $updaterCandidates += "$windsurfAppPath\Update.exe"
    if ($global:WindsurfLocalAppDataDir) {
        $updaterCandidates += (Join-Path $global:WindsurfLocalAppDataDir "Update.exe")

    $updaterCandidates += "$windsurfAppPath\WindsurfUpdater.exe"
    $updaterCandidates = $updaterCandidates | Where-Object { $_ }

    foreach ($updater in $updaterCandidates) {
        if (-not (Test-Path $updater)) { continue }
        $backup = "$updater.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Move-Item -Path $updater -Destination $backup -Force
            Write-Host "$GREEN✅ [Complete]$NC Updater disabled: $updater"
        } catch {
            Write-Host "$YELLOW⚠️  [Warning]$NC Updater disable failed: $updater"
        }
    }

    return $true
}

# Check configuration file and environment
function Test-WindsurfEnvironment {
    param(
        [string]$Mode = "FULL"
    )

    Write-Host ""
    Write-Host "$BLUE🔍 [Environment Check]$NC Checking Windsurf environment..."

    $windsurfAppData = $global:WindsurfAppDataDir

    # Check configuration file
    if (-not $config_path) {
        $issues += "Configuration file path not set"
    } elseif (-not (Test-Path $config_path)) {
        $issues += "Configuration file does not exist: $config_path"
    }

    # Check Windsurf directory structure
    if (-not $windsurfAppData -or -not (Test-Path $windsurfAppData)) {
        $issues += "Windsurf application data directory does not exist: $windsurfAppData"
    }

    # Check Windsurf installation
    $windsurfPaths = @()
    $installPath = Resolve-WindsurfInstallPath
    if ($installPath) {
        $windsurfPaths = @(Join-Path $installPath "Windsurf.exe")
    }

    $windsurfFound = $false
    foreach ($path in $windsurfPaths) {
        if (Test-Path $path) {
            Write-Host "$GREEN✅ [Check]$NC Windsurf installation found: $path"
            $windsurfFound = $true
            break
        }
    }

    if (-not $windsurfFound) {
        $issues += "Windsurf installation not found, please confirm Windsurf is properly installed"
    }

    # Return check results
    if ($issues.Count -eq 0) {
        Write-Host "$GREEN✅ [Environment Check]$NC All checks passed"
        return @{ Success = $true; Issues = @() }
    } else {
        Write-Host "$RED❌ [Environment Check]$NC Found $($issues.Count) issues:"
        foreach ($issue in $issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        return @{ Success = $false; Issues = $issues }
    }
}

# 🛠️ Modify machine code configuration (enhanced version)
function Modify-MachineCodeConfig {
    param(
        [string]$Mode = "FULL"
    )

    Write-Host ""
    Write-Host "$GREEN🛠️  [Configuration]$NC Modifying machine code configuration..."

    $configPath = $STORAGE_FILE
    if (-not $configPath) {
        Write-Host "$RED❌ [Error]$NC Unable to resolve configuration file path"
        return $false
    }

    # Enhanced configuration file check
    if (-not (Test-Path $configPath)) {
        Write-Host "$RED❌ [Error]$NC Configuration file does not exist: $configPath"
        Write-Host ""
        Write-Host "$YELLOW💡 [Solution]$NC Please try the following steps:"
        Write-Host "$BLUE  1️⃣  Manually start Windsurf application$NC"
        Write-Host "$BLUE  2️⃣  Wait for Windsurf to fully load (about 30 seconds)$NC"
        Write-Host "$BLUE  3️⃣  Close Windsurf application$NC"
        Write-Host "$BLUE  4️⃣  Re-run this script$NC"
        Write-Host ""
        Write-Host "$YELLOW⚠️  [Alternative]$NC If problem persists:"
        Write-Host "$BLUE  • Select 'Reset Environment + Modify Machine Code' option$NC"
        Write-Host "$BLUE  • This option will automatically generate configuration file$NC"
        Write-Host ""

        # Provide user choice
        $userChoice = Read-Host "Try to start Windsurf now to generate configuration file? (y/n)"

            Write-Host "$BLUE🚀 [Attempt]$NC Attempting to start Windsurf..."
            return Start-WindsurfToGenerateConfig
        }

        return $false
    }

    # Ensure processes are completely closed even in modify-only mode
    if ($Mode -eq "MODIFY_ONLY") {
        Write-Host "$BLUE🔒 [Security Check]$NC Even in modify-only mode, need to ensure Windsurf processes are completely closed"

            Write-Host "$RED❌ [Error]$NC Cannot close all Windsurf processes, modification may fail"
            $userChoice = Read-Host "Force continue? (y/n)"
            if ($userChoice -notmatch "^(y|yes)$") {
                return $false
            }
        }
    }

    # Check file permissions and lock status
    if (-not (Test-FileAccessibility -FilePath $configPath)) {
        Write-Host "$RED❌ [Error]$NC Cannot access configuration file, may be locked or insufficient permissions"
        return $false
    }

    # Verify configuration file format and display structure
    try {
        Write-Host "$BLUE🔍 [Verify]$NC Checking configuration file format..."
        $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $originalContent | ConvertFrom-Json -ErrorAction Stop
        Write-Host "$GREEN✅ [Verify]$NC Configuration file format is correct"

        # Display related properties in current configuration file
        Write-Host "$BLUE📋 [Current Config]$NC Checking existing telemetry properties:"
        $telemetryProperties = @('telemetry.machineId', 'telemetry.macMachineId', 'telemetry.devDeviceId', 'telemetry.sqmId')
        foreach ($prop in $telemetryProperties) {
            if ($config.PSObject.Properties[$prop]) {
                $value = $config.$prop
                $displayValue = if ($value.Length -gt 20) { "$($value.Substring(0,20))..." } else { $value }
                Write-Host "$GREEN  ✓ ${prop}$NC = $displayValue"
            } else {
                Write-Host "$YELLOW  - ${prop}$NC (does not exist, will create)"
            }
        }
        Write-Host ""
    } catch {
        Write-Host "$RED❌ [Error]$NC Configuration file format error: $($_.Exception.Message)"
        Write-Host "$YELLOW💡 [Suggestion]$NC Configuration file may be corrupted, suggest selecting 'Reset Environment + Modify Machine Code' option"
        return $false
    }

    # Implement atomic file operations and retry mechanism
    $maxRetries = 3
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        $retryCount++
        Write-Host ""
        Write-Host "$BLUE🔄 [Attempt]$NC Modification attempt $retryCount/$maxRetries..."

        try {
            # Display operation progress
            Write-Host "$BLUE⏳ [Progress]$NC 1/6 - Generating new device identifiers..."

            # Generate new IDs
            $MAC_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            $UUID = [System.Guid]::NewGuid().ToString()
            $prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
            $prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
            $randomBytes = New-Object byte[] 32
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($randomBytes)
            $randomPart = [System.BitConverter]::ToString($randomBytes) -replace '-',''
            $rng.Dispose()
            $MACHINE_ID = "${prefixHex}${randomPart}"
            $SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"
            # 🔧 Added: serviceMachineId (for storage.serviceMachineId)
            $SERVICE_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            # 🔧 Added: firstSessionDate (reset first session date, use UTC time to avoid semantic errors of local time with Z suffix)
            $FIRST_SESSION_DATE = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            $SESSION_ID = [System.Guid]::NewGuid().ToString()

            # Shared IDs (for consistency between configuration and JS injection)
            $global:WindsurfIds = @{
                machineId        = $MACHINE_ID
                macMachineId     = $MAC_MACHINE_ID
                devDeviceId      = $UUID
                sqmId            = $SQM_ID
                firstSessionDate = $FIRST_SESSION_DATE
                sessionId        = $SESSION_ID
                macAddress       = "00:11:22:33:44:55"
            }

            Write-Host "$GREEN✅ [Progress]$NC 1/7 - Device identifier generation completed"

            Write-Host "$BLUE⏳ [Progress]$NC 2/7 - Creating backup directory..."

            # Backup original values (enhanced version)
            $backupDir = $BACKUP_DIR
            if (-not $backupDir) {
                throw "Cannot resolve backup directory path"
            }
            if (-not (Test-Path $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
            }

            $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')_retry$retryCount"
            $backupPath = "$backupDir\$backupName"

            Write-Host "$BLUE⏳ [Progress]$NC 3/7 - Backing up original configuration..."
            Copy-Item $configPath $backupPath -ErrorAction Stop

            # Verify if backup was successful
            if (Test-Path $backupPath) {
                $backupSize = (Get-Item $backupPath).Length
                $originalSize = (Get-Item $configPath).Length
                if ($backupSize -eq $originalSize) {
                    Write-Host "$GREEN✅ [Progress]$NC 3/7 - Configuration backup successful: $backupName"
                } else {
                    Write-Host "$YELLOW⚠️  [Warning]$NC Backup file size mismatch, but continuing"
                }
            } else {
                throw "Backup file creation failed"
            }

            Write-Host "$BLUE⏳ [Progress]$NC 4/7 - Reading original configuration into memory..."

            # Atomic operation: Read original content into memory
            $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $originalContent | ConvertFrom-Json -ErrorAction Stop

            Write-Host "$BLUE⏳ [Progress]$NC 5/7 - Updating configuration in memory..."

            # Update configuration values (safe method, ensure properties exist)
            # 🔧 Fix: Add storage.serviceMachineId and telemetry.firstSessionDate
            $propertiesToUpdate = @{
                'telemetry.machineId' = $MACHINE_ID
                'telemetry.macMachineId' = $MAC_MACHINE_ID
                'telemetry.devDeviceId' = $UUID
                'telemetry.sqmId' = $SQM_ID
                'storage.serviceMachineId' = $SERVICE_MACHINE_ID
                'telemetry.firstSessionDate' = $FIRST_SESSION_DATE
            }

            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $value = $property.Value

                # Safe method using Add-Member or direct assignment
                if ($config.PSObject.Properties[$key]) {
                    # Property exists, update directly
                    $config.$key = $value
                    Write-Host "$BLUE  ✓ Updated property: ${key}$NC"
                } else {
                    # Property does not exist, add new property
                    $config | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
                    Write-Host "$BLUE  + Added property: ${key}$NC"
                }
            }

            Write-Host "$BLUE⏳ [Progress]$NC 6/7 - Atomically writing new configuration file..."

            # Atomic operation: Delete original file, write new file
            $tempPath = "$configPath.tmp"
            $updatedJson = $config | ConvertTo-Json -Depth 10

            # Write to temporary file
            [System.IO.File]::WriteAllText($tempPath, $updatedJson, [System.Text.Encoding]::UTF8)

            # Verify temporary file
            $tempContent = Get-Content $tempPath -Raw -Encoding UTF8 -ErrorAction Stop
            $tempConfig = $tempContent | ConvertFrom-Json -ErrorAction Stop

            # 🔧 Critical fix: PowerShell's ConvertFrom-Json automatically parses ISO-8601 date strings as DateTime
            # To avoid false positives from "expected value (string) vs actual value (DateTime)", normalize values before comparison
            $toComparableString = {
                param([object]$v)
                if ($null -eq $v) { return $null }
                if ($v -is [DateTime]) { return $v.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
                if ($v -is [DateTimeOffset]) { return $v.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
                return [string]$v
            }

            # Verify all properties are correctly written
            $tempVerificationPassed = $true
            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $tempConfig.$key

                $expectedComparable = & $toComparableString $expectedValue
                $actualComparable = & $toComparableString $actualValue

                if ($actualComparable -ne $expectedComparable) {
                    $tempVerificationPassed = $false
                    Write-Host "$RED  ✗ Temporary file verification failed: ${key}$NC"
                    $expectedType = if ($null -eq $expectedValue) { '<null>' } else { $expectedValue.GetType().FullName }
                    $actualType = if ($null -eq $actualValue) { '<null>' } else { $actualValue.GetType().FullName }
                    Write-Host "$YELLOW    [Debug] Type: Expected=${expectedType}; Actual=${actualType}$NC"
                    Write-Host "$YELLOW    [Debug] Value (normalized): Expected=${expectedComparable}; Actual=${actualComparable}$NC"
                    break
                }
            }

            if (-not $tempVerificationPassed) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                throw "Temporary file verification failed"
            }

            # Atomic replacement: Delete original file, rename temporary file
            Remove-Item $configPath -Force
            Move-Item $tempPath $configPath

            # Set file to read-only (optional)
            $file = Get-Item $configPath
            $file.IsReadOnly = $false  # Keep writable for subsequent modifications

            # Final verification of modification results
            Write-Host "$BLUE⏳ [Progress]$NC 7/7 - Verifying new configuration file..."

            $verifyContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $verifyConfig = $verifyContent | ConvertFrom-Json -ErrorAction Stop

            $verificationPassed = $true
            $verificationResults = @()

            # Safely verify each property
            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $verifyConfig.$key

                $expectedComparable = & $toComparableString $expectedValue
                $actualComparable = & $toComparableString $actualValue

                if ($actualComparable -eq $expectedComparable) {
                    $verificationResults += "✓ ${key}: Verification passed"
                } else {
                    $expectedType = if ($null -eq $expectedValue) { '<null>' } else { $expectedValue.GetType().FullName }
                    $actualType = if ($null -eq $actualValue) { '<null>' } else { $actualValue.GetType().FullName }
                    $verificationResults += "✗ ${key}: Verification failed (Expected type: ${expectedType}, Actual type: ${actualType}; Expected: ${expectedComparable}, Actual: ${actualComparable})"
                    $verificationPassed = $false
                }
            }

            # Display verification results
            Write-Host "$BLUE📋 [Verification Details]$NC"
            foreach ($result in $verificationResults) {
                Write-Host "   $result"
            }

            if ($verificationPassed) {
                Write-Host "$GREEN✅ [Success]$NC Modification attempt $retryCount successful!"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC Machine code configuration modification completed!"
                Write-Host "$BLUE📋 [Details]$NC Updated the following identifiers:"
                Write-Host "   🔹 machineId: $MACHINE_ID"
                Write-Host "   🔹 macMachineId: $MAC_MACHINE_ID"
                Write-Host "   🔹 devDeviceId: $UUID"
                Write-Host "   🔹 sqmId: $SQM_ID"
                Write-Host "   🔹 serviceMachineId: $SERVICE_MACHINE_ID"
                Write-Host "   🔹 firstSessionDate: $FIRST_SESSION_DATE"
                Write-Host ""
                Write-Host "$GREEN💾 [Backup]$NC Original configuration backed up to: $backupName"

                # 🔧 Added: Modify machineid file
                Write-Host "$BLUE🔧 [machineid]$NC Modifying machineid file..."
                $machineIdFilePath = if ($global:WindsurfAppDataDir) { Join-Path $global:WindsurfAppDataDir "machineid" } else { $null }
                if (-not $machineIdFilePath) {
                    Write-Host "$YELLOW⚠️  [machineid]$NC Cannot resolve machineid file path, skipping modification"
                } else {
                    try {
                        if (Test-Path $machineIdFilePath) {
                            # Backup original machineid file
                            $machineIdBackup = "$backupDir\machineid.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                            Copy-Item $machineIdFilePath $machineIdBackup -Force
                            Write-Host "$GREEN💾 [Backup]$NC machineid file backed up: $machineIdBackup"
                        }
                        # Write new serviceMachineId to machineid file
                        [System.IO.File]::WriteAllText($machineIdFilePath, $SERVICE_MACHINE_ID, [System.Text.Encoding]::UTF8)
                        Write-Host "$GREEN✅ [machineid]$NC machineid file modified successfully: $SERVICE_MACHINE_ID"

                        # Set machineid file to read-only
                        $machineIdFile = Get-Item $machineIdFilePath
                        $machineIdFile.IsReadOnly = $true
                        Write-Host "$GREEN🔒 [Protection]$NC machineid file set to read-only"
                    } catch {
                        Write-Host "$YELLOW⚠️  [machineid]$NC machineid file modification failed: $($_.Exception.Message)"
                        Write-Host "$BLUE💡 [Tip]$NC Can manually modify file: $machineIdFilePath"
                    }
                }

                # 🔧 Added: Modify .updaterId file (updater device identifier)
                Write-Host "$BLUE🔧 [updaterId]$NC Modifying .updaterId file..."
                $updaterIdFilePath = if ($global:WindsurfAppDataDir) { Join-Path $global:WindsurfAppDataDir ".updaterId" } else { $null }
                if (-not $updaterIdFilePath) {
                    Write-Host "$YELLOW⚠️  [updaterId]$NC Cannot resolve .updaterId file path, skipping modification"
                } else {
                    try {
                        if (Test-Path $updaterIdFilePath) {
                            # Backup original .updaterId file
                            $updaterIdBackup = "$backupDir\.updaterId.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                            Copy-Item $updaterIdFilePath $updaterIdBackup -Force
                            Write-Host "$GREEN💾 [Backup]$NC .updaterId file backed up: $updaterIdBackup"
                        }
                        # Generate new updaterId (UUID format)
                        $newUpdaterId = [System.Guid]::NewGuid().ToString()
                        [System.IO.File]::WriteAllText($updaterIdFilePath, $newUpdaterId, [System.Text.Encoding]::UTF8)
                        Write-Host "$GREEN✅ [updaterId]$NC .updaterId file modified successfully: $newUpdaterId"

                        # Set .updaterId file to read-only
                        $updaterIdFile = Get-Item $updaterIdFilePath
                        $updaterIdFile.IsReadOnly = $true
                        Write-Host "$GREEN🔒 [Protection]$NC .updaterId file set to read-only"
                    } catch {
                        Write-Host "$YELLOW⚠️  [updaterId]$NC .updaterId file modification failed: $($_.Exception.Message)"
                        Write-Host "$BLUE💡 [Tip]$NC Can manually modify file: $updaterIdFilePath"
                    }
                }

                # 🔒 Add configuration file protection mechanism
                Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
                try {
                    $configFile = Get-Item $configPath
                    $configFile.IsReadOnly = $true
                    Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting"
                    Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
                } catch {
                    Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                    Write-Host "$BLUE💡 [Suggestion]$NC Can manually right-click file → Properties → Check 'Read-only'"
                }
                Write-Host "$BLUE 🔒 [Security]$NC Recommend restarting Windsurf to ensure configuration takes effect"
                return $true
            } else {
                Write-Host "$RED❌ [Failed]$NC Modification attempt $retryCount verification failed"
                if ($retryCount -lt $maxRetries) {
                    Write-Host "$BLUE🔄 [Restore]$NC Restoring backup, preparing to retry..."
                    Copy-Item $backupPath $configPath -Force
                    Start-Sleep -Seconds 2
                    continue  # Continue to next retry
                } else {
                    Write-Host "$RED❌ [Final Failure]$NC All retries failed, restoring original configuration"
                    Copy-Item $backupPath $configPath -Force
                    return $false
                }
            }

        } catch {
            Write-Host "$RED❌ [Exception]$NC Modification attempt $retryCount encountered exception: $($_.Exception.Message)"
            Write-Host "$BLUE💡 [Debug Info]$NC Error type: $($_.Exception.GetType().FullName)"

            # Clean up temporary files
            if (Test-Path "$configPath.tmp") {
                Remove-Item "$configPath.tmp" -Force -ErrorAction SilentlyContinue
            }

            if ($retryCount -lt $maxRetries) {
                Write-Host "$BLUE🔄 [Restore]$NC Restoring backup, preparing to retry..."
                if (Test-Path $backupPath) {
                    Copy-Item $backupPath $configPath -Force
                }
                Start-Sleep -Seconds 3
                continue  # Continue to next retry
            } else {
                Write-Host "$RED❌ [Final Failure]$NC All retries failed"
                # Try to restore backup
                if (Test-Path $backupPath) {
                    Write-Host "$BLUE🔄 [Restore]$NC Restoring backup configuration..."
                    try {
                        Copy-Item $backupPath $configPath -Force
                        Write-Host "$GREEN✅ [Restore]$NC Original configuration restored"
                    } catch {
                        Write-Host "$RED❌ [Error]$NC Backup restore failed: $($_.Exception.Message)"
                    }
                }
                return $false
            }
        }
    }

    # If we reach here, all retries have failed
    Write-Host "$RED❌ [Final Failure]$NC Unable to complete modification after $maxRetries attempts"
    return $false

}

#  Start Windsurf to generate configuration file
function Start-WindsurfToGenerateConfig {
    Write-Host "$BLUE🚀 [Start]$NC Attempting to start Windsurf to generate configuration file..."

    # Find Windsurf executable (supports auto-detection + manual fallback)
    $installPath = Resolve-WindsurfInstallPath -AllowPrompt
    $windsurfPath = if ($installPath) { Join-Path $installPath "Windsurf.exe" } else { $null }

    if (-not $windsurfPath) {
        Write-Host "$RED❌ [Error]$NC Windsurf installation not found, please confirm Windsurf is properly installed"
        return $false
    }

    Write-Host "$BLUE📍 [Path]$NC Using Windsurf path: $windsurfPath"

    # Start Windsurf
    $process = Start-Process -FilePath $windsurfPath -PassThru -WindowStyle Normal
    Write-Host "$GREEN🚀 [Start]$NC Windsurf started, PID: $($process.Id)"

    Write-Host "$YELLOW⏳ [Wait]$NC Please wait for Windsurf to fully load (about 30 seconds)..."
    Write-Host "$BLUE💡 [Tip]$NC You can manually close Windsurf after it fully loads"

        # Wait for configuration file generation
        $configPath = $STORAGE_FILE
        if (-not $configPath) {
            Write-Host "$RED❌ [Error]$NC Cannot resolve configuration file path"
            return $false
        }
        $maxWait = 60
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Start-Sleep -Seconds 2
            $waited += 2
            if ($waited % 10 -eq 0) {
                Write-Host "$YELLOW⏳ [Wait]$NC Waiting for configuration file generation... ($waited/$maxWait seconds)"
            }
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN✅ [Success]$NC Configuration file generated!"
        Write-Host "$BLUE💡 [Tip]$NC You can now close Windsurf and re-run the script"

            Write-Host "$BLUE💡 [Suggestion]$NC Please manually operate Windsurf (e.g., create new file) to trigger configuration generation"
            return $false
        }

    } catch {
        Write-Host "$RED❌ [Error]$NC Failed to start Windsurf: $($_.Exception.Message)"
        return $false
    }
}

# Check administrator privileges
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[Error]$NC Please run this script as administrator"
    Write-Host "Please right-click the script and select 'Run as administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

# Display Logo
Clear-Host
Write-Host @"

   ██╗    ██╗██╗███╗   ██╗██████╗ ███████╗██╗   ██╗██████╗ ███████╗
   ██║    ██║██║████╗  ██║██╔══██╗██╔════╝██║   ██║██╔══██╗██╔════╝
   ██║ █╗ ██║██║██╔██╗ ██║██║  ██║███████╗██║   ██║██████╔╝█████╗  
   ██║███╗██║██║██║╚██╗██║██║  ██║╚════██║██║   ██║██╔══██╗██╔══╝  
   ╚███╔███╔╝██║██║ ╚████║██████╔╝███████║╚██████╔╝██║  ██║██║     
    ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN🚀   Cursor Trial Reset Tool          $NC"
Write-Host "$YELLOW📱  Follow WeChat Official Account [煎饼果子卷AI] $NC"
Write-Host "$YELLOW🤝  Exchange more Cursor tips and AI knowledge (script is free, follow official account to join group for more tips and experts)  $NC"
Write-Host "$YELLOW💡  [Important Notice] This tool is free, if helpful, please follow WeChat Official Account [煎饼果子卷AI]  $NC"
Write-Host ""
Write-Host "$YELLOW⚡  [Small Ad] Cursor official genuine accounts: Unlimited ♾️ ¥1050 | 7-day weekly card $100 ¥210 | 7-day weekly card $500 ¥1050 | 7-day weekly card $1000 ¥2450 | All 7-day warranty | WeChat: JavaRookie666  $NC"
Write-Host "$BLUE================================$NC"

# 🎯 User selection menu
Write-Host ""
Write-Host "$GREEN🎯 [Select Mode]$NC Please select the operation you want to perform:"
Write-Host ""
Write-Host "$BLUE  1️⃣  Modify machine code only$NC"
Write-Host "$YELLOW      • Execute machine code modification function$NC"
Write-Host "$YELLOW      • Inject crack JS code into core files$NC"
Write-Host "$YELLOW      • Skip folder deletion/environment reset steps$NC"
Write-Host "$YELLOW      • Keep existing Cursor configuration and data$NC"
Write-Host ""
Write-Host "$BLUE  2️⃣  Reset environment + Modify machine code$NC"
Write-Host "$RED      • Execute full environment reset (delete Cursor folders)$NC"
Write-Host "$RED      • ⚠️  Configuration will be lost, please backup$NC"
Write-Host "$YELLOW      • Modify machine code$NC"
Write-Host "$YELLOW      • Inject crack JS code into core files$NC"
Write-Host "$YELLOW      • This is equivalent to the current full script behavior$NC"
Write-Host ""

# Get user selection
do {
    $userChoice = Read-Host "Please enter choice (1 or 2)"
    if ($userChoice -eq "1") {
        Write-Host "$GREEN✅ [Selection]$NC You selected: Modify machine code only"
        $executeMode = "MODIFY_ONLY"
        break
    } elseif ($userChoice -eq "2") {
        Write-Host "$GREEN✅ [Selection]$NC You selected: Reset environment + Modify machine code"
        Write-Host "$RED⚠️  [Important Warning]$NC This operation will delete all Cursor configuration files!"
        $confirmReset = Read-Host "Confirm full reset? (Enter yes to confirm, any other key to cancel)"
        if ($confirmReset -eq "yes") {
            $executeMode = "RESET_AND_MODIFY"
            break
        } else {
            Write-Host "$YELLOW👋 [Cancel]$NC User cancelled reset operation"
            continue
        }
    } else {
        Write-Host "$RED❌ [Error]$NC Invalid choice, please enter 1 or 2"
    }
} while ($true)

Write-Host ""

# 📋 Display execution flow description based on selection
if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN📋 [Execution Flow]$NC Modify machine code only mode will execute in the following steps:"
    Write-Host "$BLUE  1️⃣  Detect Cursor configuration file$NC"
    Write-Host "$BLUE  2️⃣  Backup existing configuration file$NC"
    Write-Host "$BLUE  3️⃣  Modify machine code configuration$NC"
    Write-Host "$BLUE  4️⃣  Display operation completion information$NC"
    Write-Host ""
    Write-Host "$YELLOW⚠️  [Notes]$NC"
    Write-Host "$YELLOW  • Will not delete any folders or reset environment$NC"
    Write-Host "$YELLOW  • Keep all existing configuration and data$NC"
    Write-Host "$YELLOW  • Original configuration file will be automatically backed up$NC"
} else {
    Write-Host "$GREEN📋 [Execution Flow]$NC Reset environment + Modify machine code mode will execute in the following steps:"
    Write-Host "$BLUE  1️⃣  Detect and close Cursor processes$NC"
    Write-Host "$BLUE  2️⃣  Save Cursor program path information$NC"
    Write-Host "$BLUE  3️⃣  Delete specified Cursor trial-related folders$NC"
    Write-Host "$BLUE      📁 C:\Users\Administrator\.cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\Administrator\AppData\Roaming\Cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\%USERNAME%\.cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\%USERNAME%\AppData\Roaming\Cursor$NC"
    Write-Host "$BLUE  3.5️⃣ Pre-create necessary directory structure to avoid permission issues$NC"
    Write-Host "$BLUE  4️⃣  Restart Cursor to generate new configuration files$NC"
    Write-Host "$BLUE  5️⃣  Wait for configuration file generation (max 45 seconds)$NC"
    Write-Host "$BLUE  6️⃣  Close Cursor processes$NC"
    Write-Host "$BLUE  7️⃣  Modify newly generated machine code configuration file$NC"
    Write-Host "$BLUE  8️⃣  Display operation completion statistics$NC"
    Write-Host ""
    Write-Host "$YELLOW⚠️  [Notes]$NC"
    Write-Host "$YELLOW  • Do not manually operate Cursor during script execution$NC"
    Write-Host "$YELLOW  • Recommend closing all Cursor windows before execution$NC"
    Write-Host "$YELLOW  • Need to restart Cursor after execution$NC"
    Write-Host "$YELLOW  • Original configuration file will be automatically backed up to backups folder$NC"
}
Write-Host ""

# 🤔 User confirmation
Write-Host "$GREEN🤔 [Confirm]$NC Please confirm you understand the above execution flow"
$confirmation = Read-Host "Continue execution? (Enter y or yes to continue, any other key to exit)"
if ($confirmation -notmatch "^(y|yes)$") {
    Write-Host "$YELLOW👋 [Exit]$NC User cancelled execution, script exiting"
    Read-Host "Press Enter to exit"
    exit 0
}
Write-Host "$GREEN✅ [Confirm]$NC User confirmed to continue execution"
Write-Host ""

# Get and display Cursor version
function Get-CursorVersion {
    try {
        # Main detection path (based on installation path resolution)
        $installPath = Resolve-CursorInstallPath
        $packagePath = if ($installPath) { Join-Path $installPath "resources\app\package.json" } else { $null }
        if ($packagePath -and (Test-Path $packagePath)) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Info]$NC Current installed Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        # Backup path detection (compatible with old directory structure)
        $altPath = if ($global:CursorLocalAppDataRoot) { Join-Path $global:CursorLocalAppDataRoot "cursor\resources\app\package.json" } else { $null }
        if ($altPath -and (Test-Path $altPath)) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Info]$NC Current installed Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write-Host "$YELLOW[Warning]$NC Cannot detect Cursor version"
        Write-Host "$YELLOW[Tip]$NC Please ensure Cursor is properly installed"
        return $null
    }
    catch {
        Write-Host "$RED[Error]$NC Failed to get Cursor version: $_"
        return $null
    }
}

# Get and display version information
$cursorVersion = Get-CursorVersion
Write-Host ""

Write-Host "$YELLOW💡 [Important Notice]$NC Latest 1.0.x version is supported"

Write-Host ""

# 🔍 Check and close Cursor processes
Write-Host "$GREEN🔍 [Check]$NC Checking Cursor processes..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE🔍 [Debug]$NC Getting $processName process details:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" |
        Select-Object ProcessId, ExecutablePath, CommandLine |
        Format-List
}

# Define max retry count and wait time
$MAX_RETRIES = 5
$WAIT_TIME = 1

# 🔄 Handle process closure and save process information
function Close-CursorProcessAndSaveInfo {
    param($processName)

    $global:CursorProcessInfo = $null

    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "$YELLOW⚠️  [Warning]$NC Found $processName running"

        # 💾 Save process information for subsequent restart - Fix: Ensure getting single process path
        $firstProcess = if ($processes -is [array]) { $processes[0] } else { $processes }
        $processPath = $firstProcess.Path

        # Ensure path is string not array
        if ($processPath -is [array]) {
            $processPath = $processPath[0]
        }

        $global:CursorProcessInfo = @{
            ProcessName = $firstProcess.ProcessName
            Path = $processPath
            StartTime = $firstProcess.StartTime
        }
        Write-Host "$GREEN💾 [Save]$NC Process information saved: $($global:CursorProcessInfo.Path)"

        Get-ProcessDetails $processName

        Write-Host "$YELLOW🔄 [Operation]$NC Attempting to close $processName..."
        Stop-Process -Name $processName -Force

        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }

            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED❌ [Error]$NC Still unable to close $processName after $MAX_RETRIES attempts"
                Get-ProcessDetails $processName
                Write-Host "$RED💥 [Error]$NC Please manually close process and retry"
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting for process to close, attempt $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN✅ [Success]$NC $processName successfully closed"
    } else {
        Write-Host "$BLUE💡 [Tip]$NC $processName process not found running"
        # Try to find Cursor installation path
        $installPath = Resolve-CursorInstallPath
        $candidatePath = if ($installPath) { Join-Path $installPath "Cursor.exe" } else { $null }
        if ($candidatePath -and (Test-Path $candidatePath)) {
            $global:CursorProcessInfo = @{
                ProcessName = "Cursor"
                Path = $candidatePath
                StartTime = $null
            }
            Write-Host "$GREEN💾 [Found]$NC Cursor installation path found: $candidatePath"
        }

        if (-not $global:CursorProcessInfo) {
            Write-Host "$YELLOW⚠️  [Warning]$NC Cursor installation path not found, will use default path"
            $defaultInstallPath = if ($global:CursorLocalAppDataRoot) { Join-Path $global:CursorLocalAppDataRoot "Programs\cursor\Cursor.exe" } else { "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe" }
            $global:CursorProcessInfo = @{
                ProcessName = "Cursor"
                Path = $defaultInstallPath
                StartTime = $null
            }
        }
    }
}

if (-not $BACKUP_DIR) {
    Write-Host "$YELLOW⚠️  [Warning]$NC Cannot resolve backup directory path, skipping creation"
} elseif (-not (Test-Path $BACKUP_DIR)) {
    try {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write-Host "$GREEN✅ [Backup Directory]$NC Backup directory created successfully: $BACKUP_DIR"
    } catch {
        Write-Host "$YELLOW⚠️  [Warning]$NC Backup directory creation failed: $($_.Exception.Message)"
    }
}

# Execute corresponding function based on user selection
if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN🚀 [Start]$NC Starting to execute modify machine code only function..."

    # First perform environment check
    $envCheck = Test-CursorEnvironment -Mode "MODIFY_ONLY"
    if (-not $envCheck.Success) {
        Write-Host ""
        Write-Host "$RED❌ [Environment Check Failed]$NC Cannot continue execution, found the following issues:"
        foreach ($issue in $envCheck.Issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        Write-Host ""
        Write-Host "$YELLOW💡 [Suggestion]$NC Please select the following operation:"
        Write-Host "$BLUE  1️⃣  Select 'Reset Environment + Modify Machine Code' option (recommended)$NC"
        Write-Host "$BLUE  2️⃣  Manually start Cursor once, then re-run the script$NC"
        Write-Host "$BLUE  3️⃣  Check if Cursor is properly installed$NC"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Execute machine code modification
    $configSuccess = Modify-MachineCodeConfig -Mode "MODIFY_ONLY"

    if ($configSuccess) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Configuration File]$NC Machine code configuration file modification completed!"

        # Add registry modification
        Write-Host "$BLUE🔧 [Registry]$NC Modifying system registry..."
        $registrySuccess = Update-MachineGuid

        # 🔧 Added: JavaScript injection function (device identification bypass enhancement)
        Write-Host ""
        Write-Host "$BLUE🔧 [Device Identification Bypass]$NC Executing JavaScript injection function..."
        Write-Host "$BLUE💡 [Description]$NC This function will directly modify Cursor core JS files to achieve deeper device identification bypass"
        $jsSuccess = Modify-WindsurfJSFiles

        if ($registrySuccess) {
            Write-Host "$GREEN✅ [Registry]$NC System registry modification successful"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All machine code modifications completed (enhanced version)!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following modifications:"
                Write-Host "$GREEN  ✓ Cursor configuration file (storage.json)$NC"
                Write-Host "$GREEN  ✓ System registry (MachineGuid)$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed, but other functions succeeded"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All machine code modifications completed!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following modifications:"
                Write-Host "$GREEN  ✓ Cursor configuration file (storage.json)$NC"
                Write-Host "$GREEN  ✓ System registry (MachineGuid)$NC"
                Write-Host "$YELLOW  ⚠ JavaScript kernel injection (partially failed)$NC"
            }

            # 🔒 Add configuration file protection mechanism
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configPath = $STORAGE_FILE
                if (-not $configPath) {
                    throw "Cannot resolve configuration file path"
                }
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC Can manually right-click file → Properties → Check 'Read-only'"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Registry]$NC Registry modification failed, but configuration file modification succeeded"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Configuration file and JavaScript injection completed, registry modification failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May need administrator privileges to modify registry"
                Write-Host "$BLUE📋 [Details]$NC Completed the following modifications:"
                Write-Host "$GREEN  ✓ Cursor configuration file (storage.json)$NC"
                Write-Host "$YELLOW  ⚠ System registry (MachineGuid) - Failed$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Configuration file modification completed, registry and JavaScript injection failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May need administrator privileges to modify registry"
            }

            # 🔒 Even if registry modification fails, protect configuration file
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC Can manually right-click file → Properties → Check 'Read-only'"
            }
        }

        Write-Host ""
        Write-Host "$BLUE🚫 [Disable Update]$NC Disabling Cursor auto-update..."
        if (Disable-CursorAutoUpdate) {
            Write-Host "$GREEN✅ [Disable Update]$NC Auto-update processed"
        } else {
            Write-Host "$YELLOW⚠️  [Disable Update]$NC Unable to confirm update disable, may need manual handling"
        }

        Write-Host "$BLUE💡 [Tip]$NC You can now start Cursor to use the new machine code configuration"
    } else {
        Write-Host ""
        Write-Host "$RED❌ [Failed]$NC Machine code modification failed!"
        Write-Host "$YELLOW💡 [Suggestion]$NC Please try 'Reset Environment + Modify Machine Code' option"
    }
} else {
    # Complete reset environment + modify machine code flow
    Write-Host "$GREEN🚀 [Start]$NC Starting to execute reset environment + modify machine code function..."

    # 🚀 Close all Cursor processes and save information
    Close-CursorProcessAndSaveInfo "Cursor"
    if (-not $global:CursorProcessInfo) {
        Close-CursorProcessAndSaveInfo "cursor"
    }

    # 🚨 Important warning notice
    Write-Host ""
    Write-Host "$RED🚨 [Important Warning]$NC ============================================"
    Write-Host "$YELLOW⚠️  [Risk Control Reminder]$NC Cursor risk control mechanism is very strict!"
    Write-Host "$YELLOW⚠️  [Must Delete]$NC Must completely delete specified folders, no residual settings allowed"
    Write-Host "$YELLOW⚠️  [Trial Protection]$NC Only thorough cleanup can effectively prevent losing trial Pro status"
    Write-Host "$RED🚨 [Important Warning]$NC ============================================"
    Write-Host ""

    # 🎯 Execute Cursor trial reset folder deletion function
    Write-Host "$GREEN🚀 [Start]$NC Starting to execute core function..."
    Remove-WindsurfTrialFolders



    # 🔄 Restart Cursor to regenerate configuration files
    Restart-WindsurfAndWait

    # 🛠️ Modify machine code configuration
    $configSuccess = Modify-MachineCodeConfig
    
    # 🧹 Execute Cursor initialization cleanup
    Invoke-CursorInitialization

    if ($configSuccess) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Configuration File]$NC Machine code configuration file modification completed!"

        # Add registry modification
        Write-Host "$BLUE🔧 [Registry]$NC Modifying system registry..."
        $registrySuccess = Update-MachineGuid

        # 🔧 Added: JavaScript injection function (device identification bypass enhancement)
        Write-Host ""
        Write-Host "$BLUE🔧 [Device Identification Bypass]$NC Executing JavaScript injection function..."
        Write-Host "$BLUE💡 [Description]$NC This function will directly modify Cursor core JS files to achieve deeper device identification bypass"
        $jsSuccess = Modify-WindsurfJSFiles

        if ($registrySuccess) {
            Write-Host "$GREEN✅ [Registry]$NC System registry modification successful"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All operations completed (enhanced version)!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following operations:"
                Write-Host "$GREEN  ✓ Delete Cursor trial-related folders$NC"
                Write-Host "$GREEN  ✓ Cursor initialization cleanup$NC"
                Write-Host "$GREEN  ✓ Regenerate configuration files$NC"
                Write-Host "$GREEN  ✓ Modify machine code configuration$NC"
                Write-Host "$GREEN  ✓ Modify system registry$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed, but other functions succeeded"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All operations completed!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following operations:"
                Write-Host "$GREEN  ✓ Delete Cursor trial-related folders$NC"
                Write-Host "$GREEN  ✓ Cursor initialization cleanup$NC"
                Write-Host "$GREEN  ✓ Regenerate configuration files$NC"
                Write-Host "$GREEN  ✓ Modify machine code configuration$NC"
                Write-Host "$GREEN  ✓ Modify system registry$NC"
                Write-Host "$YELLOW  ⚠ JavaScript kernel injection (partially failed)$NC"
            }

            # 🔒 Add configuration file protection mechanism
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configPath = $STORAGE_FILE
                if (-not $configPath) {
                    throw "Cannot resolve configuration file path"
                }
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC Can manually right-click file → Properties → Check 'Read-only'"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Registry]$NC Registry modification failed, but other operations succeeded"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Most operations completed, registry modification failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May need administrator privileges to modify registry"
                Write-Host "$BLUE📋 [Details]$NC Completed the following operations:"
                Write-Host "$GREEN  ✓ Delete Cursor trial-related folders$NC"
                Write-Host "$GREEN  ✓ Cursor initialization cleanup$NC"
                Write-Host "$GREEN  ✓ Regenerate configuration files$NC"
                Write-Host "$GREEN  ✓ Modify machine code configuration$NC"
                Write-Host "$YELLOW  ⚠  Modify system registry - Failed$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Most operations completed, registry and JavaScript injection failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May need administrator privileges to modify registry"
            }

            # 🔒 Even if registry modification fails, protect configuration file
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC Can manually right-click file → Properties → Check 'Read-only'"
            }
        }

        Write-Host ""
        Write-Host "$BLUE🚫 [Disable Update]$NC Disabling Cursor auto-update..."
        if (Disable-CursorAutoUpdate) {
            Write-Host "$GREEN✅ [Disable Update]$NC Auto-update processed"
        } else {
            Write-Host "$YELLOW⚠️  [Disable Update]$NC Unable to confirm update disable, may need manual handling"
        }
    } else {
        Write-Host ""
        Write-Host "$RED❌ [Failed]$NC Machine code configuration modification failed!"
        Write-Host "$YELLOW💡 [Suggestion]$NC Please check error messages and retry"
    }
}


# 📱 Display WeChat Official Account information
Write-Host ""
Write-Host "$GREEN================================$NC"
Write-Host "$YELLOW📱  Follow WeChat Official Account [煎饼果子卷AI] to exchange more Cursor tips and AI knowledge (script is free, follow official account to join group for more tips and experts)  $NC"
Write-Host "$YELLOW⚡   [Small Ad] Cursor official genuine accounts: Unlimited ♾️ ¥1050 | 7-day weekly card $100 ¥210 | 7-day weekly card $500 ¥1050 | 7-day weekly card $1000 ¥2450 | All 7-day warranty | WeChat: JavaRookie666  $NC"
Write-Host "$GREEN================================$NC"
Write-Host ""

# 🎉 Script execution completed
Write-Host "$GREEN🎉 [Script Complete]$NC Thank you for using Cursor Machine Code Modification Tool!"
Write-Host "$BLUE💡 [Tip]$NC If you have questions, please refer to the WeChat Official Account or re-run the script"
Write-Host ""
Read-Host "Press Enter to exit"
exit 0
