# Hooks Lectern's own Windows code into the Flutter-generated Windows
# project (windows\runner). Safe to run as often as you like: it only
# changes what isn't already changed.
#
#   powershell -ExecutionPolicy Bypass -File installer\patch-windows-runner.ps1
#
# It:
#   - adds media_controls.cpp (Windows media controls) to the build
#   - creates the media controls when the window opens
#   - gives the app its Windows ID (so media controls say "Lectern")
#   - fixes the window title to "Lectern"
#   - adds windows_player.cpp (Windows' own audio player, for xHE-AAC)
#   - names the company/product "Lectern" (instead of "com.example")
#   - bundles the Visual C++ runtime (and the optional newer audio engine)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'windows\runner'

if (-not (Test-Path (Join-Path $runner 'main.cpp'))) {
    Write-Host "windows\runner not found. Run this first:" -ForegroundColor Red
    Write-Host "  flutter create --platforms=windows --project-name lectern ."
    exit 1
}
foreach ($f in 'media_controls.cpp', 'windows_player.cpp') {
    if (-not (Test-Path (Join-Path $runner $f))) {
        Write-Host "windows\runner\$f is missing. Copy it in from the Lectern update first." -ForegroundColor Red
        exit 1
    }
}

$script:failed = $false

function Patch-File([string]$name, [scriptblock]$change, [switch]$NoBom) {
    $path = Join-Path $runner $name
    $before = Get-Content $path -Raw
    $after = & $change $before
    if ($after -ne $before) {
        if ($NoBom) {
            # The resource compiler can trip over a byte-order mark.
            [IO.File]::WriteAllText($path, $after, (New-Object Text.UTF8Encoding($false)))
        } else {
            Set-Content -Path $path -Value $after -NoNewline -Encoding UTF8
        }
        Write-Host "  updated $name" -ForegroundColor Green
    }
}

function Need([bool]$ok, [string]$what) {
    if (-not $ok) {
        Write-Host "  could not find where to $what - please report it at https://github.com/majorpaynedof/lectern/issues" -ForegroundColor Yellow
        $script:failed = $true
    }
}

Write-Host "Patching windows\runner ..." -ForegroundColor Cyan

# 1. Build media_controls.cpp along with the rest of the runner.
Patch-File 'CMakeLists.txt' {
    param($s)
    if ($s -match 'media_controls\.cpp') { return $s }
    Need ($s -match '"flutter_window\.cpp"') 'add media_controls.cpp to CMakeLists.txt'
    return $s -replace '("flutter_window\.cpp")', "`$1`r`n  ""media_controls.cpp"""
}

# 2. Keep a MediaControls object alongside the Flutter view.
Patch-File 'flutter_window.h' {
    param($s)
    if ($s -match 'media_controls_') { return $s }
    Need ($s -match '#include "win32_window\.h"') 'include media_controls.h in flutter_window.h'
    Need ($s -match 'std::unique_ptr<flutter::FlutterViewController> flutter_controller_;') 'add media_controls_ to flutter_window.h'
    $s = $s -replace '#include "win32_window\.h"', "#include ""media_controls.h""`r`n#include ""win32_window.h"""
    $s = $s -replace '(std::unique_ptr<flutter::FlutterViewController> flutter_controller_;)', "`$1`r`n`r`n  // Windows media controls (media keys, Quick Settings tile).`r`n  std::unique_ptr<MediaControls> media_controls_;"
    return $s
}

# 3. Create it once the Flutter engine is running; drop it on close.
Patch-File 'flutter_window.cpp' {
    param($s)
    if ($s -match 'media_controls_') { return $s }
    Need ($s -match 'RegisterPlugins\(flutter_controller_->engine\(\)\);') 'create media controls in flutter_window.cpp'
    Need ($s -match 'void FlutterWindow::OnDestroy\(\) \{') 'clean up media controls in flutter_window.cpp'
    $s = $s -replace '(RegisterPlugins\(flutter_controller_->engine\(\)\);)', "`$1`r`n  media_controls_ = std::make_unique<MediaControls>(GetHandle(), flutter_controller_->engine()->messenger());"
    $s = $s -replace '(void FlutterWindow::OnDestroy\(\) \{)', "`$1`r`n  media_controls_ = nullptr;"
    return $s
}

# 3a. Compile the runner as C++20. The Windows media code (C++/WinRT) falls
#     back to old "experimental" coroutines under C++17, which Visual Studio
#     2026 refuses (error STL1011).
Patch-File 'CMakeLists.txt' {
    param($s)
    if ($s -match 'cxx_std_20') { return $s }
    Need ($s -match 'apply_standard_settings\(\$\{BINARY_NAME\}\)') 'switch the runner to C++20 in CMakeLists.txt'
    return $s -replace '(apply_standard_settings\(\$\{BINARY_NAME\}\))', "`$1`r`n`r`n# Lectern: C++/WinRT needs C++20 on newer Visual Studio.`r`ntarget_compile_features(`$`${BINARY_NAME} PRIVATE cxx_std_20)"
}

# 3b. The Windows audio player (for formats like xHE-AAC): build it, keep one
#     alongside the Flutter view, create it with the engine, drop it on close.
Patch-File 'CMakeLists.txt' {
    param($s)
    if ($s -match 'windows_player\.cpp') { return $s }
    Need ($s -match '"media_controls\.cpp"') 'add windows_player.cpp to CMakeLists.txt'
    return $s -replace '("media_controls\.cpp")', "`$1`r`n  ""windows_player.cpp"""
}
Patch-File 'flutter_window.h' {
    param($s)
    if ($s -match 'windows_player_') { return $s }
    Need ($s -match 'std::unique_ptr<MediaControls> media_controls_;') 'add windows_player_ to flutter_window.h'
    $s = $s -replace '#include "media_controls\.h"', "#include ""media_controls.h""`r`n#include ""windows_player.h"""
    $s = $s -replace '(std::unique_ptr<MediaControls> media_controls_;)', "`$1`r`n  // Windows' own audio player, for formats the main player can't decode.`r`n  std::unique_ptr<WindowsPlayer> windows_player_;"
    return $s
}
Patch-File 'flutter_window.cpp' {
    param($s)
    if ($s -match 'windows_player_') { return $s }
    Need ($s -match 'media_controls_ = std::make_unique<MediaControls>') 'create the Windows player in flutter_window.cpp'
    Need ($s -match 'media_controls_ = nullptr;') 'clean up the Windows player in flutter_window.cpp'
    $s = $s -replace '(media_controls_ = std::make_unique<MediaControls>\([^;]*\);)', "`$1`r`n  windows_player_ = std::make_unique<WindowsPlayer>(flutter_controller_->engine()->messenger());"
    $s = $s -replace '(media_controls_ = nullptr;)', "windows_player_ = nullptr;`r`n  `$1"
    return $s
}

# 4. App ID (matches the installer's shortcut) and window title.
Patch-File 'main.cpp' {
    param($s)
    if ($s -notmatch 'shobjidl\.h') {
        $s = $s -replace '#include <windows.h>', "#include <windows.h>`r`n#include <shobjidl.h>"
    }
    if ($s -notmatch 'SetCurrentProcessExplicitAppUserModelID') {
        $fn = $s.IndexOf('wWinMain(')
        $brace = if ($fn -ge 0) { $s.IndexOf('{', $fn) } else { -1 }
        Need ($brace -ge 0) 'set the app ID in main.cpp'
        if ($brace -ge 0) {
            $s = $s.Insert($brace + 1, "`r`n  // Matches the installer's shortcut so Windows shows ""Lectern"" in media controls.`r`n  ::SetCurrentProcessExplicitAppUserModelID(L""Lectern.Desktop"");")
        }
    }
    return ($s -replace 'L"lectern"', 'L"Lectern"')
}

# 4b. Runner.rc: name the company and product "Lectern" instead of Flutter's
#     placeholder "com.example". This also moves the data folder to
#     %APPDATA%\Lectern\Lectern (the app moves the old one across itself).
Patch-File 'Runner.rc' -NoBom {
    param($s)
    $s = $s -replace '"CompanyName", "com\.example"', '"CompanyName", "Lectern"'
    $s = $s -replace '"FileDescription", "lectern"', '"FileDescription", "Lectern"'
    $s = $s -replace '"ProductName", "lectern"', '"ProductName", "Lectern"'
    $s = $s -replace '"LegalCopyright", "[^"]*"', '"LegalCopyright", "Copyright (C) Lectern contributors. GPL-3.0."'
    return $s
}

# 5. windows\CMakeLists.txt: ship the Visual C++ runtime next to lectern.exe
#    (so it runs on PCs without the redistributable), and use the newer audio
#    engine from installer\get-libmpv.ps1 instead of media_kit's older one.
Patch-File '..\CMakeLists.txt' {
    param($s)
    if ($s -match 'Lectern additions') { return $s }
    $block = @'


# --- Lectern additions (added by installer\patch-windows-runner.ps1) ---
# Visual C++ runtime DLLs next to lectern.exe, so no redistributable install
# is needed on other PCs.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
include(InstallRequiredSystemLibraries)
if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
  install(PROGRAMS ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()
# Newer audio engine (plays xHE-AAC and other newer formats). Installed after
# the plugins, so it replaces the libmpv-2.dll media_kit copies in.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libmpv/libmpv-2.dll")
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/libmpv/libmpv-2.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()
'@
    return $s.TrimEnd() + ($block -replace "`r?`n", "`r`n") + "`r`n"
}

if ($script:failed) {
    Write-Host "Some changes could not be made (see above)." -ForegroundColor Yellow
    exit 1
}
Write-Host "windows\runner is ready." -ForegroundColor Green
exit 0
