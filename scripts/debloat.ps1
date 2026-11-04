<#
.SYNOPSIS
  Back up, disable and restore apps on an Android TV over Wi-Fi ADB. No AI needed.

.DESCRIPTION
  This is the same thing as typing the adb commands by hand (see docs/manual-steps.md).
  Nothing is uninstalled: apps are switched off with "pm disable-user" and can be switched back on.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 status
  powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 apply
  powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 restore
  powershell -ExecutionPolicy Bypass -File scripts\debloat.ps1 192.168.1.20 restore com.apps.eshow

.PARAMETER TvIp    The TV's IP address (Settings > Network). Port 5555 is used unless you write ip:port.
.PARAMETER Action  status = show the state of every app in the list (changes nothing)
                   apply  = back up, then disable every app in the list
                   restore = re-enable the list (or only the packages written after "restore")
.PARAMETER List    Package list. Default: debloat\nokia-atv-r2-disable-list.txt
.PARAMETER Backup  Backup folder. Default: .\tv-backup-<date>; "restore" uses the newest one.
.PARAMETER Force   Allow apps on the protected list (remote, voice, inputs, launcher...). Can break the TV.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$TvIp,
    [Parameter(Mandatory = $true, Position = 1)][ValidateSet('status', 'apply', 'restore')][string]$Action,
    [Parameter(Position = 2, ValueFromRemainingArguments = $true)][string[]]$Packages,
    [string]$List = '',
    [string]$Backup = '',
    [switch]$Force
)

# ($PSScriptRoot is empty inside a param() default in Windows PowerShell 5.1, so the default is set here.)
if (-not $List) { $List = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\debloat\nokia-atv-r2-disable-list.txt')) }
. (Join-Path $PSScriptRoot 'common.ps1')

function Restore-Screensaver([string]$Dir) {
    $file = Join-Path $Dir 'screensaver.txt'
    if (-not (Test-Path $file)) { return $false }
    foreach ($line in Get-Content $file) {
        if ($line -match '^(components|default)=(.*)$') {
            if ($Matches[1] -eq 'components') { $key = 'screensaver_components' } else { $key = 'screensaver_default_component' }
            $value = $Matches[2].Trim()
            if ($value -eq '' -or $value -eq 'null') {
                Invoke-Tv "settings delete secure $key" | Out-Null
            } else {
                Invoke-Tv "settings put secure $key '$value'" | Out-Null
            }
        }
    }
    return $true
}

try { Connect-Tv $TvIp } catch { Write-Host $_.Exception.Message; exit 1 }

$model = (@(Invoke-Tv 'getprop ro.product.model') -join '').Trim()
$build = (@(Invoke-Tv 'getprop ro.build.display.id') -join '').Trim()
$android = (@(Invoke-Tv 'getprop ro.build.version.release') -join '').Trim()
Write-Host "TV: $model, Android $android, build $build"

$listed = @(Read-PackageList $List)
$installed = @(Invoke-Tv 'pm list packages' | ForEach-Object { $_ -replace '^package:', '' })
$disabled = @(Invoke-Tv 'pm list packages -d' | ForEach-Object { $_ -replace '^package:', '' })

switch ($Action) {
    'status' {
        Write-Host "List: $List"
        foreach ($p in $listed) {
            if ($disabled -contains $p) { $state = 'disabled' }
            elseif ($installed -contains $p) { $state = 'ENABLED' }
            else { $state = 'not installed' }
            if (Test-Protected $p) { $state += '   (PROTECTED - will be refused)' }
            Write-Host ('{0,-48} {1}' -f $p, $state)
        }
    }

    'apply' {
        $blocked = @($listed | Where-Object { Test-Protected $_ })
        if ($blocked.Count -gt 0 -and -not $Force) {
            Write-Host 'Refusing: these are on the protected list (remote, voice, inputs, launcher, Wi-Fi/Bluetooth, Google services):'
            $blocked | ForEach-Object { Write-Host "  $_" }
            Write-Host 'Remove them from the list, or add -Force if you really know what you are doing.'
            exit 1
        }

        if (-not $Backup) { $Backup = Join-Path (Get-Location).Path ('tv-backup-' + (Get-Date -Format 'yyyy-MM-dd')) }
        New-Item -ItemType Directory -Force $Backup | Out-Null
        Invoke-Tv 'pm list packages -e' | ForEach-Object { $_ -replace '^package:', '' } | Sort-Object | Set-Content (Join-Path $Backup 'packages-enabled.txt') -Encoding ASCII
        $disabled | Sort-Object | Set-Content (Join-Path $Backup 'packages-disabled-before.txt') -Encoding ASCII
        $ssComp = (@(Invoke-Tv 'settings get secure screensaver_components') -join '').Trim()
        $ssDef = (@(Invoke-Tv 'settings get secure screensaver_default_component') -join '').Trim()
        "components=$ssComp`ndefault=$ssDef" | Set-Content (Join-Path $Backup 'screensaver.txt') -Encoding ASCII
        "$(Get-Date -Format s)  $model  Android $android  build $build" | Set-Content (Join-Path $Backup 'info.txt') -Encoding ASCII
        Write-Host "Backup saved in $Backup (it lists the apps on your TV - do not publish it)."

        foreach ($p in $listed) {
            if ($installed -notcontains $p) { Write-Host ('{0,-48} not installed - skipped' -f $p); continue }
            if ($disabled -contains $p) { Write-Host ('{0,-48} already disabled' -f $p); continue }
            $r = (@(Invoke-Tv "pm disable-user --user 0 $p") -join ' ') -replace '.*new state: ', ''
            Write-Host ('{0,-48} {1}' -f $p, $r)
        }

        # Ambient mode is the screensaver; switch to the plain built-in one so the TV never points at a disabled app.
        if (($listed -contains 'com.google.android.backdrop') -and ((@(Invoke-Tv 'pm list packages com.android.dreams.basic') -join '') -match 'dreams.basic')) {
            Invoke-Tv "settings put secure screensaver_components com.android.dreams.basic/.Colors" | Out-Null
            Invoke-Tv "settings put secure screensaver_default_component com.android.dreams.basic/.Colors" | Out-Null
            Write-Host 'Screensaver set to the built-in "Colors" screensaver (the old setting is in the backup).'
        }
        Write-Host ''
        Write-Host 'Done. Restart the TV once and check that your apps, remote and voice still work.'
        Write-Host "Undo any time with:  scripts\debloat.ps1 $TvIp restore"
    }

    'restore' {
        if ($Packages -and $Packages.Count -gt 0) { $targets = @($Packages) } else { $targets = $listed }
        foreach ($p in $targets) {
            if ($installed -notcontains $p) { Write-Host ('{0,-48} not installed - skipped' -f $p); continue }
            $r = (@(Invoke-Tv "pm enable --user 0 $p") -join ' ') -replace '.*new state: ', ''
            Write-Host ('{0,-48} {1}' -f $p, $r)
        }
        if ($targets -contains 'com.google.android.backdrop') {
            if ($Backup) { $dir = $Backup } else {
                $newest = Get-ChildItem -Directory -Filter 'tv-backup-*' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
                if ($newest) { $dir = $newest.FullName } else { $dir = '' }
            }
            if ($dir -and (Restore-Screensaver $dir)) {
                Write-Host "Screensaver settings restored from $dir"
            } else {
                Write-Host 'No backup folder found. To get Ambient mode back run:'
                Write-Host '  adb shell settings put secure screensaver_components com.google.android.backdrop/.Backdrop'
            }
        }
        Write-Host 'Done. Restart the TV if anything still looks off.'
    }
}
