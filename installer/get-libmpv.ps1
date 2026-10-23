# Downloads a current build of libmpv, the audio engine Lectern plays through,
# into windows\libmpv\libmpv-2.dll. The build then uses it in place of the
# older copy media_kit bundles (from 2023), which can't decode newer formats
# like xHE-AAC.
#
#   powershell -ExecutionPolicy Bypass -File installer\get-libmpv.ps1
#   powershell -ExecutionPolicy Bypass -File installer\get-libmpv.ps1 -Force   # re-download
#
# Source: https://github.com/shinchiro/mpv-winbuild-cmake (the regular x86_64
# build, not "v3", which needs a newer CPU).

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'windows\libmpv'
$dll = Join-Path $dest 'libmpv-2.dll'

if ((Test-Path $dll) -and -not $Force) {
    Write-Host "Audio engine already downloaded ($(Get-Content (Join-Path $dest 'VERSION.txt') -ErrorAction SilentlyContinue))." -ForegroundColor Green
    exit 0
}

Write-Host 'Finding the latest audio engine (libmpv) build ...' -ForegroundColor Cyan
$release = Invoke-RestMethod 'https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest' -Headers @{ 'User-Agent' = 'lectern-build' }
$asset = $release.assets | Where-Object { $_.name -match '^mpv-dev-x86_64-\d{8}-git-[0-9a-f]+\.7z$' } | Select-Object -First 1
if (-not $asset) {
    Write-Host 'Could not find the libmpv download on GitHub - please report it at https://github.com/majorpaynedof/lectern/issues' -ForegroundColor Red
    exit 1
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('lectern-libmpv-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $archive = Join-Path $work $asset.name
    Write-Host "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB)) MB) ..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $archive

    # Unpack the .7z: Windows' own tar can on Windows 11; otherwise use 7-Zip.
    $out = Join-Path $work 'x'
    New-Item -ItemType Directory -Path $out | Out-Null
    $ok = $false
    try {
        & tar.exe -xf $archive -C $out 2>$null
        $ok = ($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $out 'libmpv-2.dll'))
    } catch { $ok = $false }
    if (-not $ok) {
        $sevenZip = @(
            (Get-Command 7z -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
            "$env:ProgramFiles\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if (-not $sevenZip) {
            Write-Host 'Could not unpack the download. Install 7-Zip and run this again:' -ForegroundColor Red
            Write-Host '  winget install 7zip.7zip'
            exit 1
        }
        & $sevenZip x $archive "-o$out" -y | Out-Null
    }

    $found = Get-ChildItem $out -Recurse -Filter 'libmpv-2.dll' | Select-Object -First 1
    if (-not $found) {
        Write-Host 'libmpv-2.dll was not in the download - please report it at https://github.com/majorpaynedof/lectern/issues' -ForegroundColor Red
        exit 1
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item $found.FullName $dll -Force
    Set-Content (Join-Path $dest 'VERSION.txt') $asset.name
    Write-Host "Audio engine ready: $($asset.name)" -ForegroundColor Green
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit 0
