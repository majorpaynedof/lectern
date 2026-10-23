# Builds Lectern in release mode and packages it into an installer.
#
# Run from the project folder:
#   powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1
#
# Needs Inno Setup 6 once:  winget install JRSoftware.InnoSetup
# (Rust is no longer needed.)
# The installer ends up in installer\output\Lectern-Setup-<version>.exe

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# --- 1. Hook Lectern's Windows code (media controls, app ID, title) into
#        the generated windows\runner project. Safe to re-run.
& (Join-Path $PSScriptRoot 'patch-windows-runner.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

# --- 1b. Audio engine: the build uses media_kit's own libmpv unless
#         windows\libmpv\libmpv-2.dll exists (from installer\get-libmpv.ps1).
#         Official releases (GitHub Actions) always use media_kit's.
if (Test-Path (Join-Path $root 'windows\libmpv\libmpv-2.dll')) {
    Write-Host 'Note: using the newer libmpv from windows\libmpv (delete that folder to use the standard one).' -ForegroundColor Yellow
}

# --- 2. Read the version from pubspec.yaml (e.g. "version: 0.1.0+1" -> 0.1.0).
$versionLine = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
$version = if ($versionLine) { $versionLine.Matches[0].Groups[1].Value } else { '0.1.0' }
Write-Host "Building Lectern $version ..." -ForegroundColor Cyan

# --- 3. Release build. (pub get first regenerates Flutter's helper files,
#        which can go missing right after a debug 'flutter run' session.)
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host 'flutter pub get failed.' -ForegroundColor Red; exit 1 }
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Build failed; cleaning the build cache and trying once more...' -ForegroundColor Yellow
    flutter clean
    flutter pub get
    flutter build windows --release
}
if ($LASTEXITCODE -ne 0) { Write-Host 'Flutter build failed.' -ForegroundColor Red; exit 1 }

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'vcruntime140.dll'))) {
    Write-Host 'Warning: the Visual C++ runtime was not bundled; PCs without it will show DLL errors.' -ForegroundColor Yellow
}
$mpv = Get-Item (Join-Path $release 'libmpv-2.dll') -ErrorAction SilentlyContinue
if ($mpv) { Write-Host ("Audio engine: libmpv-2.dll, {0:N0} MB" -f ($mpv.Length / 1MB)) }

# --- 4. Find Inno Setup's compiler.
# (Any version: "Inno Setup 6", "Inno Setup 7", ...)
$iscc = @(
    (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    foreach ($base in "$env:LOCALAPPDATA\Programs", ${env:ProgramFiles(x86)}, $env:ProgramFiles) {
        if ($base -and (Test-Path $base)) {
            Get-ChildItem $base -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'ISCC.exe' }
        }
    }
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
    Write-Host 'Inno Setup not found. Install it with:  winget install JRSoftware.InnoSetup' -ForegroundColor Red
    exit 1
}

# --- 5. Package.
& $iscc "/DAppVersion=$version" (Join-Path $PSScriptRoot 'lectern.iss')
if ($LASTEXITCODE -ne 0) { Write-Host 'Packaging failed.' -ForegroundColor Red; exit 1 }

$out = Join-Path $PSScriptRoot "output\Lectern-Setup-$version.exe"
Write-Host ""
Write-Host "Done: $out" -ForegroundColor Green
