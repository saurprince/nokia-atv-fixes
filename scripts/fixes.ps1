<#
.SYNOPSIS
  Install, check, run or remove the Auto Volume + Netflix-button fixes on the TV. No AI needed.

.DESCRIPTION
  The fixes are one small Android app (local.avlfix) plus a helper script that lives on the TV.
  See README.md for what they do and docs/how-it-works.md for how.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\fixes.ps1 192.168.1.20 status
  powershell -ExecutionPolicy Bypass -File scripts\fixes.ps1 192.168.1.20 install
  powershell -ExecutionPolicy Bypass -File scripts\fixes.ps1 192.168.1.20 run
  powershell -ExecutionPolicy Bypass -File scripts\fixes.ps1 192.168.1.20 remove

.PARAMETER TvIp        The TV's IP address (Settings > Network).
.PARAMETER Action      status  = is the app installed, is the script safe, what did the last run say
                       install = install the APK, copy the script to the TV, turn on the Netflix-button watcher
                       run     = re-apply Auto Volume right now (the sound menu is visible for ~20-30 s)
                       remove  = turn the watcher off, uninstall the app, delete the script and logs
.PARAMETER Apk         APK to install. Default: app\avlfix.apk (build it first with app\build.ps1)
.PARAMETER ScriptOnly  With "install": only update the on-TV script and its permissions, keep the installed app.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$TvIp,
    [Parameter(Mandatory = $true, Position = 1)][ValidateSet('status', 'install', 'run', 'remove')][string]$Action,
    [string]$Apk = '',
    [switch]$ScriptOnly
)

# ($PSScriptRoot is empty inside a param() default in Windows PowerShell 5.1, so the default is set here.)
if (-not $Apk) { $Apk = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\app\avlfix.apk')) }
. (Join-Path $PSScriptRoot 'common.ps1')

$Component = 'local.avlfix/local.avlfix.NetflixKeyService'
$RemoteScript = '/data/local/tmp/avlfix.sh'
$AppLog = '/sdcard/Android/data/local.avlfix/files/avlfix.log'
$LocalScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\device\avlfix.sh'))

function Get-EnabledServices {
    $v = (@(Invoke-Tv 'settings get secure enabled_accessibility_services') -join '').Trim()
    if (-not $v -or $v -eq 'null') { return @() }
    return @($v -split ':' | Where-Object { $_ })
}

# Only touches our own entry: other accessibility services you use stay enabled.
function Set-EnabledServices([string[]]$Services) {
    if (-not $Services -or $Services.Count -eq 0) {
        Invoke-Tv 'settings delete secure enabled_accessibility_services' | Out-Null
        Invoke-Tv 'settings put secure accessibility_enabled 0' | Out-Null
    } else {
        $joined = $Services -join ':'
        Invoke-Tv "settings put secure enabled_accessibility_services '$joined'" | Out-Null
        Invoke-Tv 'settings put secure accessibility_enabled 1' | Out-Null
    }
}

function Push-Script {
    if (-not (Test-Path $LocalScript)) { throw "Script not found: $LocalScript" }
    # The script must have Unix line endings to run on the TV.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) 'avlfix.sh'
    [IO.File]::WriteAllText($tmp, ((Get-Content $LocalScript -Raw) -replace "`r`n", "`n"))
    $res = (& $script:Adb -s $script:Device push $tmp $RemoteScript 2>&1 | ForEach-Object { "$_" }) -join ' '
    $pushed = ($LASTEXITCODE -eq 0)
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if (-not $pushed) { throw "Could not copy the script to the TV: $res" }
    # adb push from Windows leaves the file writable by every app; only the adb shell user may change it.
    Invoke-Tv "chmod 755 $RemoteScript; chmod 600 /data/local/tmp/avlfix.log /data/local/tmp/avlfix-top.txt /data/local/tmp/avlfix-ui.xml 2>/dev/null; true" | Out-Null
    if (-not (@(Invoke-Tv "ls $RemoteScript 2>/dev/null") -join '')) { throw 'The script is not on the TV after copying - stopping.' }
}

function Get-LogLineCount {
    $n = (@(Invoke-Tv "wc -l < $AppLog 2>/dev/null") -join '').Trim()
    if ($n -match '^\d+$') { return [int]$n } else { return 0 }
}

# Waits for a NEW line from the app (old lines from earlier runs are ignored).
function Wait-AppResult([int]$Before) {
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 4
        $new = @(Invoke-Tv ('tail -n +{0} {1} 2>/dev/null' -f ($Before + 1), $AppLog))
        if (($new -join "`n") -match 'script:|could not run') { return $new }
    }
    return @('No result yet - check again with: fixes.ps1 <ip> status')
}

try { Connect-Tv $TvIp } catch { Write-Host $_.Exception.Message; exit 1 }

switch ($Action) {
    'status' {
        $app = (@(Invoke-Tv 'pm list packages local.avlfix') -join '').Trim()
        if ($app) { Write-Host 'App:        installed' } else { Write-Host 'App:        NOT installed  (run: fixes.ps1 <ip> install)' }
        $perm = ((@(Invoke-Tv "ls -l $RemoteScript 2>/dev/null") -join '') -split '\s+')[0]
        if (-not $perm) { Write-Host 'TV script:  MISSING        (run: fixes.ps1 <ip> install -ScriptOnly)' }
        elseif ($perm.Length -ge 9 -and $perm[8] -eq 'w') { Write-Host "TV script:  present but writable by every app ($perm)  (run: fixes.ps1 <ip> install -ScriptOnly)" }
        else { Write-Host "TV script:  present, protected ($perm)" }
        if ((Get-EnabledServices) -contains $Component) { Write-Host 'Netflix button watcher: on' } else { Write-Host 'Netflix button watcher: OFF' }
        Write-Host '--- last lines of the app log ---'
        Invoke-Tv "tail -n 6 $AppLog 2>/dev/null"
    }

    'install' {
        if (-not $ScriptOnly) {
            if (-not (Test-Path $Apk)) { throw "APK not found: $Apk`nBuild it first (app\build.ps1) or pass -Apk <file>." }
            $out = @(& $script:Adb -s $script:Device install -r $Apk 2>&1 | ForEach-Object { "$_" })
            Write-Host ($out | Select-Object -Last 1)
            if (($out -join ' ') -notmatch 'Success') {
                if (($out -join ' ') -match 'INCOMPATIBLE|signatures do not match') {
                    Write-Host 'The installed app was signed with a different key. Uninstall it first (fixes.ps1 <ip> remove), then install again.'
                }
                exit 1
            }
        }
        Push-Script
        $enabled = @(Get-EnabledServices)
        if ($enabled -notcontains $Component) { Set-EnabledServices ($enabled + $Component) }
        if ($ScriptOnly) {
            Write-Host "Script updated on the TV (nothing was run). Check it with: fixes.ps1 $TvIp status"
            exit 0
        }
        Write-Host 'Installed. Running once now. If the TV asks "Allow USB debugging?" for avlfix@tv, tick "Always allow" and press OK.'
        $before = Get-LogLineCount
        Invoke-Tv 'am broadcast -a local.avlfix.RUN -n local.avlfix/.RunReceiver' | Out-Null
        Wait-AppResult $before | ForEach-Object { Write-Host $_ }
    }

    'run' {
        $before = Get-LogLineCount
        Invoke-Tv 'am broadcast -a local.avlfix.RUN -n local.avlfix/.RunReceiver' | Out-Null
        Wait-AppResult $before | ForEach-Object { Write-Host $_ }
    }

    'remove' {
        Set-EnabledServices @((Get-EnabledServices) | Where-Object { $_ -ne $Component })
        & $script:Adb -s $script:Device uninstall local.avlfix 2>&1 | ForEach-Object { Write-Host "$_" }
        Invoke-Tv "rm -f $RemoteScript /data/local/tmp/avlfix.log /data/local/tmp/avlfix.pid /data/local/tmp/avlfix-top.txt /data/local/tmp/avlfix-ui.xml" | Out-Null
        Write-Host 'Removed. The TV still remembers the avlfix@tv debugging key until you use'
        Write-Host 'Developer options > Revoke USB debugging authorizations.'
    }
}
