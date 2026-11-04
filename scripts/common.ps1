# Shared helpers, dot-sourced by debloat.ps1 and fixes.ps1.
# Works in Windows PowerShell 5.1 (built into Windows) and in PowerShell 7.

function Find-Adb {
    if ($env:ADB -and (Test-Path $env:ADB)) { return $env:ADB }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $roots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    foreach ($r in $roots) {
        if ($r) {
            $p = Join-Path $r 'platform-tools\adb.exe'
            if (Test-Path $p) { return $p }
        }
    }
    throw 'adb not found. Install Android platform-tools (https://developer.android.com/tools/releases/platform-tools), put adb on your PATH, or set the ADB environment variable to the full path of adb.exe.'
}

# Connects to the TV over Wi-Fi (default port 5555) and checks that it has authorised this PC.
function Connect-Tv([string]$TvIp) {
    $script:Adb = Find-Adb
    if ($TvIp -match ':\d+$') { $script:Device = $TvIp } else { $script:Device = "${TvIp}:5555" }
    $out = (& $script:Adb connect $script:Device 2>&1 | ForEach-Object { "$_" }) -join ' '
    if ($out -notmatch 'connected to|already connected') {
        throw "Could not connect to $($script:Device): $out`nCheck the TV's IP address (Settings > Network), that the PC and the TV are on the same network, and that USB debugging is on."
    }
    $state = ((& $script:Adb -s $script:Device get-state 2>&1 | ForEach-Object { "$_" }) -join '').Trim()
    if ($state -ne 'device') {
        throw "The TV reports '$state'. Accept the 'Allow USB debugging?' prompt on the TV (tick 'Always allow'), then run this again."
    }
}

# Runs one command line in the TV's shell. Returns the output lines (carriage returns removed).
function Invoke-Tv([string]$Command) {
    & $script:Adb -s $script:Device shell $Command 2>&1 |
        ForEach-Object { "$_".TrimEnd("`r") } |
        Where-Object { $_ -notmatch 'Broken pipe' }
}

function Read-PackageList([string]$Path) {
    if (-not (Test-Path $Path)) { throw "Package list not found: $Path" }
    Get-Content $Path | ForEach-Object { ($_ -replace '#.*', '').Trim() } | Where-Object { $_ }
}

# Apps that keep the remote, voice, inputs, Wi-Fi/Bluetooth, launcher or Google services working.
# debloat.ps1 refuses to disable these unless you pass -Force.
$script:ProtectedPatterns = @(
    '^com\.realtek\.',
    '^com\.android\.bluetooth', '^com\.android\.systemui', '^com\.android\.tv(\.|$)',
    '^com\.android\.providers\.', '^com\.android\.settings', '^com\.android\.inputdevices$',
    '^com\.android\.shell$', '^com\.android\.vending$',
    '^com\.google\.android\.packageinstaller$', '^com\.google\.android\.tvlauncher$',
    '^com\.google\.android\.katniss', '^com\.google\.android\.tv\.remote\.service$',
    '^com\.google\.android\.gms', '^com\.google\.android\.gsf$',
    '^com\.google\.android\.inputmethod\.', '^com\.google\.android\.tts$',
    '^com\.google\.android\.tungsten\.', '^com\.google\.android\.apps\.initsetup$',
    '^com\.google\.android\.youtube\.tv$', '^com\.google\.android\.webview$',
    '^com\.apps\.(bluetoothremote|fivekey|smartkey|virtualkey|sys|puresound|usbmediaplayer|ota|authota)$',
    '^com\.functions\.autopair$', '^com\.netflix\.ninja$', '^com\.amazon\.amazonvideo\.',
    '^local\.avlfix$', '^android$'
)

function Test-Protected([string]$Package) {
    foreach ($pattern in $script:ProtectedPatterns) {
        if ($Package -match $pattern) { return $true }
    }
    return $false
}
