# Windsurf Machine ID Reset Tool (Simplified)
# Run with: powershell -ExecutionPolicy Bypass -File "windsurf_reset.ps1"

Write-Host "=== Windsurf Machine ID Reset Tool ==="

# Get Windsurf paths
$appdata = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
$windsurfDir = Join-Path $appdata "Windsurf"
$storageFile = Join-Path $windsurfDir "User\globalStorage\storage.json"

Write-Host "Checking Windsurf installation..."

if (-not (Test-Path $storageFile)) {
    Write-Host "ERROR: Windsurf storage.json not found at: $storageFile"
    Write-Host "Make sure Windsurf is installed and has been run at least once"
    exit 1
}

Write-Host "Found Windsurf storage.json: $storageFile"

# Create backup
$backupDir = Join-Path $windsurfDir "User\globalStorage\backups"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupDir "storage.json.backup_$timestamp"
Copy-Item $storageFile $backupFile -Force
Write-Host "Backup created: $backupFile"

# Generate new IDs
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$bytes = New-Object byte[] 32
$rng.GetBytes($bytes)
$machineId = [System.BitConverter]::ToString($bytes).Replace('-','').ToLower()
$rng.Dispose()

$deviceId = [System.Guid]::NewGuid().ToString().ToLower()

$bytes2 = New-Object byte[] 32
$rng2 = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$rng2.GetBytes($bytes2)
$macMachineId = [System.BitConverter]::ToString($bytes2).Replace('-','').ToLower()
$rng2.Dispose()

$sqmId = "{" + [System.Guid]::NewGuid().ToString().ToUpper() + "}"

Write-Host "Generating new IDs:"
Write-Host "  machineId: $($machineId.Substring(0,16))..."
Write-Host "  deviceId: $($deviceId.Substring(0,16))..."
Write-Host "  macMachineId: $($macMachineId.Substring(0,16))..."
Write-Host "  sqmId: $sqmId"

# Read and modify storage.json
try {
    $content = Get-Content $storageFile -Raw -Encoding UTF8 | ConvertFrom-Json

    # Update telemetry keys (they are direct properties with dot notation)
    # Only update properties that exist
    if ($content.'telemetry.machineId') {
        $content.'telemetry.machineId' = $machineId
        Write-Host "  Updated telemetry.machineId"
    }
    if ($content.'telemetry.devDeviceId') {
        $content.'telemetry.devDeviceId' = $deviceId
        Write-Host "  Updated telemetry.devDeviceId"
    }
    if ($content.'telemetry.macMachineId') {
        $content.'telemetry.macMachineId' = $macMachineId
        Write-Host "  Updated telemetry.macMachineId"
    }
    if ($content.'telemetry.sqmId') {
        $content.'telemetry.sqmId' = $sqmId
        Write-Host "  Updated telemetry.sqmId"
    }

    # Add missing properties if they don't exist
    if (-not $content.'telemetry.macMachineId') {
        $content | Add-Member -MemberType NoteProperty -Name 'telemetry.macMachineId' -Value $macMachineId -Force
        Write-Host "  Added telemetry.macMachineId"
    }

    # Convert back to JSON and save
    $jsonContent = $content | ConvertTo-Json -Depth 10
    $jsonContent | Set-Content $storageFile -Encoding UTF8 -NoNewline

    Write-Host "Successfully updated Windsurf storage.json"
    Write-Host "Please restart Windsurf to apply changes"

} catch {
    Write-Host "Error modifying storage.json: $($_.Exception.Message)"
    exit 1
}

Write-Host "Windsurf Machine ID reset complete!"