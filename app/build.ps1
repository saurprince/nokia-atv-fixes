# Builds app\avlfix.apk with the command-line Android SDK tools (no Gradle or Android Studio project needed).
# Windows + PowerShell. Needs: the Android SDK (build-tools + a platform, android-30 or newer) and a JDK 17+.
#   powershell -ExecutionPolicy Bypass -File app\build.ps1
#
# The APK is signed with a key that is created on the first build (app\avlfix.keystore, never committed).
# Keep that file: Android only lets an app be updated by an APK signed with the same key.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Find-Sdk {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path (Join-Path $p 'build-tools')) -and (Test-Path (Join-Path $p 'platforms'))) { return $p }
    }
    throw 'Android SDK not found. Set ANDROID_HOME to the SDK folder (it must contain build-tools and platforms).'
}

function Find-JdkBin {
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\javac.exe'))) { return (Join-Path $env:JAVA_HOME 'bin') }
    $c = Get-Command javac.exe -ErrorAction SilentlyContinue
    if ($c) { return (Split-Path $c.Source) }
    $studio = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin'
    if (Test-Path (Join-Path $studio 'javac.exe')) { return $studio }
    throw 'JDK not found. Install JDK 17 or newer and set JAVA_HOME.'
}

function Run([string]$exe, [string[]]$argList) {
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { throw "$([IO.Path]::GetFileName($exe)) failed (exit code $LASTEXITCODE)" }
}

$sdk = Find-Sdk
$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)*$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $bt) { throw 'No build-tools found in the SDK (install them with the SDK Manager).' }
$platform = Get-ChildItem (Join-Path $sdk 'platforms') -Directory | Where-Object { $_.Name -match '^android-\d+$' } |
    Sort-Object { [int]($_.Name -replace 'android-', '') } -Descending | Select-Object -First 1
if (-not $platform -or [int]($platform.Name -replace 'android-', '') -lt 30) { throw 'No Android platform 30 or newer found in the SDK.' }
$androidJar = Join-Path $platform.FullName 'android.jar'
$jdk = Find-JdkBin
$env:JAVA_HOME = Split-Path $jdk
$env:PATH = "$jdk;$env:PATH"
"Using build-tools $($bt.Name), $($platform.Name), JDK at $env:JAVA_HOME"

if (Test-Path build) { Remove-Item build -Recurse -Force }
New-Item -ItemType Directory build, build\gen, build\obj | Out-Null

# Resources + manifest -> base APK (and R.java)
Run (Join-Path $bt.FullName 'aapt2.exe') @('compile', '--dir', 'res', '-o', 'build\res.zip')
Run (Join-Path $bt.FullName 'aapt2.exe') @('link', '-I', $androidJar, '--manifest', 'AndroidManifest.xml', '--java', 'build\gen',
    '--min-sdk-version', '30', '--target-sdk-version', '30', '-o', 'build\unsigned.apk', 'build\res.zip')

# Java -> classes -> classes.dex
$sources = Get-ChildItem src, build\gen -Recurse -Filter *.java | ForEach-Object FullName
Run (Join-Path $jdk 'javac.exe') (@('--release', '8', '-classpath', $androidJar, '-d', 'build\obj') + $sources)
$classes = Get-ChildItem build\obj -Recurse -Filter *.class | ForEach-Object FullName
Run (Join-Path $bt.FullName 'd8.bat') (@('--min-api', '30', '--lib', $androidJar, '--output', 'build') + $classes)

# Add the dex, align, sign
Run (Join-Path $jdk 'jar.exe') @('uMf', 'build\unsigned.apk', '-C', 'build', 'classes.dex')
Run (Join-Path $bt.FullName 'zipalign.exe') @('-f', '-p', '4', 'build\unsigned.apk', 'build\aligned.apk')
if (-not (Test-Path avlfix.keystore)) {
    # A local key for sideloading; its password only protects the file on your own PC.
    Run (Join-Path $jdk 'keytool.exe') @('-genkeypair', '-keystore', 'avlfix.keystore', '-alias', 'avlfix', '-keyalg', 'RSA',
        '-keysize', '2048', '-validity', '10000', '-storepass', 'avlfix-local', '-keypass', 'avlfix-local',
        '-dname', 'CN=Auto Volume Fix (local build)')
}
Run (Join-Path $bt.FullName 'apksigner.bat') @('sign', '--ks', 'avlfix.keystore', '--ks-pass', 'pass:avlfix-local', '--out', 'avlfix.apk', 'build\aligned.apk')
Run (Join-Path $bt.FullName 'apksigner.bat') @('verify', 'avlfix.apk')
"Built: $(Join-Path $PSScriptRoot 'avlfix.apk') ($([math]::Round((Get-Item avlfix.apk).Length / 1KB)) KB)"
