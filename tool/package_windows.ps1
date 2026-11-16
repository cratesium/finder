# Builds the Windows release WITH yt-dlp and FFmpeg inside it and wraps it in
# an Inno Setup installer. Run on Windows with Flutter, Visual Studio 2022
# ("Desktop development with C++") and Inno Setup 6 (`choco install innosetup`).
#
#   powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1
#
# Output: build\release\Finder-<version>-windows-x64-setup.exe
#         build\release\Finder-<version>-windows-x64.zip (portable)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)\+?([0-9]*)'
$version = $line.Matches[0].Groups[1].Value
$build = $line.Matches[0].Groups[2].Value
if (-not $build) { $build = '0' }

# 1. Verified dependencies (downloaded once; delete third_party\windows to refresh).
if (-not (Test-Path third_party\windows\bin\ffmpeg.exe) -or -not (Test-Path third_party\windows\bin\yt-dlp\yt-dlp.exe)) {
  dart run tool/fetch_dependencies.dart --platform windows --arch x64
  if ($LASTEXITCODE -ne 0) { throw 'fetching dependencies failed' }
}

# 2. App (CMake installs third_party\windows\bin into <install dir>\bin).
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
$release = 'build\windows\x64\runner\Release'
if (-not (Test-Path "$release\bin\ffmpeg.exe")) { throw 'bundled FFmpeg missing from the build' }

# 3. Self-check: the bundled tools run.
& "$release\bin\ffmpeg.exe" -hide_banner -version | Select-Object -First 1
& "$release\bin\yt-dlp\yt-dlp.exe" --ignore-config --version
if ($LASTEXITCODE -ne 0) { throw 'bundled yt-dlp failed to run' }

# 4. Installer + portable zip.
New-Item -ItemType Directory -Force build\release | Out-Null
$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
& $iscc "/DAppVersion=$version" "/DAppBuild=$build" packaging\windows\finder.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Compress-Archive -Force -Path "$release\*" -DestinationPath "build\release\Finder-$version-windows-x64.zip"
Get-ChildItem build\release\Finder-$version-windows-*
