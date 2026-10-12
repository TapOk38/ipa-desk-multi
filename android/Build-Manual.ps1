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

# AAPT2 single-shot mode avoids the daemon pipe failure in the Windows build sandbox.
[xml]$manifest = Get-Content "$PSScriptRoot\app\src\main\AndroidManifest.xml" -Raw
$ns = 'http://schemas.android.com/apk/res/android'
$manifest.manifest.SetAttribute('package', 'ru.ipadesk.usb.prototype')
$manifest.manifest.SetAttribute('versionCode', $ns, '9') | Out-Null
$manifest.manifest.SetAttribute('versionName', $ns, '0.7.0-beta.1') | Out-Null
$manifest.manifest.application.activity.SetAttribute('name', $ns, 'ru.ipadesk.usb.MainActivity') | Out-Null
$manifest.manifest.application.SetAttribute('label', $ns, 'IPA USB') | Out-Null
$sdkElement = $manifest.CreateElement('uses-sdk')
$sdkElement.SetAttribute('minSdkVersion', $ns, '26') | Out-Null
$sdkElement.SetAttribute('targetSdkVersion', $ns, '35') | Out-Null
$manifest.manifest.AppendChild($sdkElement) | Out-Null
$manifest.Save("$buildRoot\AndroidManifest.xml")
& "$bt\aapt2.exe" link -I $androidJar --manifest "$buildRoot\AndroidManifest.xml" -o "$buildRoot\aapt-output.apk"
$aaptExit = $LASTEXITCODE
& "$Jdk\bin\javac.exe" -d "$buildRoot" "$PSScriptRoot\build-tools\RecoverManifest.java" "$PSScriptRoot\build-tools\VerifyApk.java"
if ($LASTEXITCODE -ne 0) { throw 'Build helper compilation failed' }
& "$Jdk\bin\java.exe" -cp "$buildRoot" RecoverManifest "$buildRoot\aapt-output.apk" "$buildRoot\manifest.apk"
if ($LASTEXITCODE -ne 0) { throw "Resource linking failed ($aaptExit); binary manifest is incomplete" }

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
# Do not update a Java-created ZIP in place: .NET may retain the manifest's
# data-descriptor flag while overwriting its descriptor. Write every entry to
# a fresh archive so local headers and the central directory agree.
$manifestArchive = [IO.Compression.ZipFile]::OpenRead("$buildRoot\manifest.apk")
$apkStream = [IO.File]::Open("$buildRoot\unsigned.apk",[IO.FileMode]::Create)
$apk = [IO.Compression.ZipArchive]::new($apkStream,[IO.Compression.ZipArchiveMode]::Create)
try {
    $src = $manifestArchive.GetEntry('AndroidManifest.xml').Open()
    $dst = $apk.CreateEntry('AndroidManifest.xml').Open()
    try { $src.CopyTo($dst) } finally { $src.Dispose(); $dst.Dispose() }
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
} finally { $apk.Dispose(); $apkStream.Dispose(); $manifestArchive.Dispose() }
# All entries are DEFLATED, with no native libraries or app resources. There are
# no uncompressed entries requiring zipalign. Keep packaging entirely in managed code.
& "$Jdk\bin\java.exe" -cp "$buildRoot" VerifyApk "$buildRoot\unsigned.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK ZIP structure verification failed' }
$key = (Resolve-Path -LiteralPath $KeyStore).Path
& "$Jdk\bin\java.exe" -jar "$bt\lib\apksigner.jar" sign --ks $key --ks-key-alias $KeyAlias --ks-pass env:IPA_USB_STORE_PASSWORD --key-pass env:IPA_USB_KEY_PASSWORD --out "$buildRoot\ipa-usb-0.7.0-beta.1.apk" "$buildRoot\unsigned.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK signing failed' }
& "$Jdk\bin\java.exe" -jar "$bt\lib\apksigner.jar" verify --verbose --print-certs "$buildRoot\ipa-usb-0.7.0-beta.1.apk"
if ($LASTEXITCODE -ne 0) { throw 'APK verification failed' }
Get-FileHash "$buildRoot\ipa-usb-0.7.0-beta.1.apk" -Algorithm SHA256
