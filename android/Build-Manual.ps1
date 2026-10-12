param(
    [string]$Sdk = $env:ANDROID_HOME,
    [string]$Jdk = $env:JAVA_HOME,
    [string]$KeyStore = '',
    [string]$KeyAlias = 'prototype',
    [string]$BuildDirectory = '',
    [switch]$TestsOnly
)
$ErrorActionPreference = 'Stop'
if (-not $Sdk -or -not $Jdk) { throw 'Specify -Sdk and -Jdk or set ANDROID_HOME and JAVA_HOME.' }
if (-not $TestsOnly -and (-not $KeyStore -or -not $env:IPA_USB_STORE_PASSWORD -or -not $env:IPA_USB_KEY_PASSWORD)) {
    throw 'Signing requires -KeyStore, IPA_USB_STORE_PASSWORD and IPA_USB_KEY_PASSWORD. For tests use -TestsOnly.'
}
$Sdk = (Resolve-Path -LiteralPath $Sdk).Path
$Jdk = (Resolve-Path -LiteralPath $Jdk).Path
$buildRoot = if ($BuildDirectory) { [IO.Path]::GetFullPath($BuildDirectory) } else { Join-Path $PSScriptRoot 'manual-build' }
$classes = Join-Path $buildRoot 'classes'
$testClasses = Join-Path $buildRoot 'test-classes'
$dex = Join-Path $buildRoot 'dex'
New-Item -ItemType Directory -Force $classes,$testClasses,$dex | Out-Null
$androidJar = "$Sdk\platforms\android-35\android.jar"
$bt = "$Sdk\build-tools\35.0.0"
$libs = @(Get-ChildItem "$PSScriptRoot\libs" -Filter '*.jar')
$testLibs = @(Get-ChildItem "$PSScriptRoot\test-libs" -Filter '*.jar')
$cp = $androidJar + ';' + ($libs.FullName -join ';')
$sources = @(Get-ChildItem "$PSScriptRoot\app\src\main\java" -Recurse -Filter '*.java')
& "$Jdk\bin\javac.exe" -encoding UTF-8 -source 8 -target 8 -classpath $cp -d $classes $sources.FullName
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }
$testCp = "$cp;$classes;" + ($testLibs.FullName -join ';')
$tests = @(Get-ChildItem "$PSScriptRoot\app\src\test\java" -Recurse -Filter '*.java')
& "$Jdk\bin\javac.exe" -encoding UTF-8 -source 8 -target 8 -classpath $testCp -d $testClasses $tests.FullName
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed' }
$testNames = $tests | ForEach-Object { 'ru.ipadesk.usb.' + $_.BaseName }
& "$Jdk\bin\java.exe" -cp "$testCp;$testClasses" org.junit.runner.JUnitCore $testNames
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
if ($TestsOnly) { return }

# Compile resources into individual files and link into a directory. This avoids
# native ZIP finalization failures while retaining the complete resource table.
$compiled = Join-Path $buildRoot ('compiled-' + [guid]::NewGuid().ToString('N'))
$linked = Join-Path $buildRoot ('linked-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $compiled,$linked | Out-Null
# AAPT2's directory writer requires parent folders for file resources.
New-Item -ItemType Directory -Force "$linked\res\drawable-nodpi-v4" | Out-Null
foreach ($resource in Get-ChildItem "$PSScriptRoot\app\src\main\res" -Recurse -File) {
    & "$bt\aapt2.exe" compile --no-crunch $resource.FullName -o $compiled
    if ($LASTEXITCODE -ne 0) { throw "Resource compilation failed: $($resource.Name)" }
}
[xml]$manifest = Get-Content "$PSScriptRoot\app\src\main\AndroidManifest.xml" -Raw
$ns = 'http://schemas.android.com/apk/res/android'
$manifest.manifest.SetAttribute('package', 'ru.ipadesk.usb.prototype')
$manifest.manifest.SetAttribute('versionCode', $ns, '11') | Out-Null
$manifest.manifest.SetAttribute('versionName', $ns, '0.7.0-beta.3') | Out-Null
$manifest.manifest.application.activity.SetAttribute('name', $ns, 'ru.ipadesk.usb.MainActivity') | Out-Null
$sdkElement = $manifest.CreateElement('uses-sdk')
$sdkElement.SetAttribute('minSdkVersion', $ns, '26') | Out-Null
$sdkElement.SetAttribute('targetSdkVersion', $ns, '35') | Out-Null
# Android derives activity compatibility defaults while parsing <application>.
# Declare the target SDK first, or a tall screen may be treated as a legacy 1.86:1 window.
$manifest.manifest.InsertBefore($sdkElement, $manifest.manifest.application) | Out-Null
$manifest.Save("$buildRoot\AndroidManifest.xml")
$resourceFiles = @(Get-ChildItem $compiled -Filter '*.flat' -File | ForEach-Object FullName)
& "$bt\aapt2.exe" link -I $androidJar --manifest "$buildRoot\AndroidManifest.xml" --output-to-dir -o $linked @resourceFiles
if ($LASTEXITCODE -ne 0) { throw 'Resource linking failed' }
if (-not (Test-Path "$linked\resources.arsc") -or -not (Test-Path "$linked\res\drawable-nodpi-v4\ic_launcher.png")) {
    throw 'Linked APK resources are incomplete'
}
& "$Jdk\bin\javac.exe" -d "$buildRoot" "$PSScriptRoot\build-tools\VerifyApk.java" "$PSScriptRoot\build-tools\AlignApk.java"
if ($LASTEXITCODE -ne 0) { throw 'Build helper compilation failed' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$allJar = "$buildRoot\program.jar"
$file = [IO.File]::Open($allJar,[IO.FileMode]::Create)
$archive = [IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Create)
$added = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
try {
    foreach ($class in Get-ChildItem $classes -Recurse -Filter '*.class') {
        $name = $class.FullName.Substring($classes.Length + 1).Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$class.FullName,$name) | Out-Null
        $added.Add($name) | Out-Null
    }
    foreach ($lib in $libs) {
        $inputArchive = [IO.Compression.ZipFile]::OpenRead($lib.FullName)
        try {
            foreach ($entry in $inputArchive.Entries) {
                $name = $entry.FullName
                if (-not $name.EndsWith('.class') -or $name.StartsWith('META-INF/') -or $name -eq 'module-info.class') { continue }
                if (-not $added.Add($name)) { throw "Duplicate program class: $name" }
                $src = $entry.Open(); $dst = $archive.CreateEntry($name).Open()
                try { $src.CopyTo($dst) } finally { $src.Dispose(); $dst.Dispose() }
            }
        } finally { $inputArchive.Dispose() }
    }
} finally { $archive.Dispose(); $file.Dispose() }
& "$Jdk\bin\java.exe" -Xmx2048m -cp "$bt\lib\d8.jar" com.android.tools.r8.D8 --release --min-api 26 --lib $androidJar --output $dex $allJar
if ($LASTEXITCODE -ne 0) { throw 'DEX compilation failed' }
# Package linked resources and bytecode into one fresh ZIP.
$apkStream = [IO.File]::Open("$buildRoot\unsigned.apk",[IO.FileMode]::Create)
$apk = [IO.Compression.ZipArchive]::new($apkStream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($resource in Get-ChildItem $linked -Recurse -File) {
        $name = $resource.FullName.Substring($linked.Length + 1).Replace('\','/')
        # Android 11+ requires an uncompressed, aligned resource table.
        $compression = if ($name -eq 'resources.arsc') { [IO.Compression.CompressionLevel]::NoCompression } else { [IO.Compression.CompressionLevel]::Optimal }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($apk,$resource.FullName,$name,$compression) | Out-Null
    }
    foreach ($d in Get-ChildItem $dex -Filter '*.dex') {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($apk,$d.FullName,$d.Name) | Out-Null
    }
    # Keep runtime resources of dependencies, excluding signatures and Java 9+ overlays.
    $resources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($lib in $libs) {
        $inputArchive = [IO.Compression.ZipFile]::OpenRead($lib.FullName)
        try {
            foreach ($entry in $inputArchive.Entries) {
                $name = $entry.FullName
                if ($name.EndsWith('/') -or $name.EndsWith('.class') -or $name.StartsWith('META-INF/') -or -not $resources.Add($name)) { continue }
                $src=$entry.Open(); $dst=$apk.CreateEntry($name).Open()
                try { $src.CopyTo($dst) } finally { $src.Dispose(); $dst.Dispose() }
            }
        } finally { $inputArchive.Dispose() }
    }
    if (Test-Path "$PSScriptRoot\licenses") {
        foreach ($license in Get-ChildItem "$PSScriptRoot\licenses" -File) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($apk,$license.FullName,"assets/licenses/$($license.Name)") | Out-Null
        }
    }
} finally { $apk.Dispose(); $apkStream.Dispose() }
& "$Jdk\bin\java.exe" -cp "$buildRoot" VerifyApk "$buildRoot\unsigned.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK ZIP structure verification failed' }
& "$PSScriptRoot\build-tools\Verify-Manifest.ps1" -Apk "$buildRoot\unsigned.apk" -Aapt2 "$bt\aapt2.exe"
& "$Jdk\bin\java.exe" -cp "$buildRoot" AlignApk "$buildRoot\unsigned.apk" "$buildRoot\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK alignment failed' }
& "$Jdk\bin\java.exe" -cp "$buildRoot" VerifyApk "$buildRoot\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'Aligned APK ZIP verification failed' }
& "$bt\zipalign.exe" -c 4 "$buildRoot\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK alignment verification failed' }
$key = (Resolve-Path -LiteralPath $KeyStore).Path
& "$Jdk\bin\java.exe" -jar "$bt\lib\apksigner.jar" sign --ks $key --ks-key-alias $KeyAlias --ks-pass env:IPA_USB_STORE_PASSWORD --key-pass env:IPA_USB_KEY_PASSWORD --out "$buildRoot\ipa-usb-0.7.0-beta.3.apk" "$buildRoot\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK signing failed' }
& "$Jdk\bin\java.exe" -jar "$bt\lib\apksigner.jar" verify --verbose --print-certs "$buildRoot\ipa-usb-0.7.0-beta.3.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK verification failed' }
Get-FileHash "$buildRoot\ipa-usb-0.7.0-beta.3.apk" -Algorithm SHA256
