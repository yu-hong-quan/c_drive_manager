# Build C Drive Manager Windows installer (Inno Setup).
# Steps: Rust FFI/Helper -> Flutter Release -> copy natives -> ISCC Setup.exe
# 中文说明：一键生成可分发给用户的安装程序。

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
$isccCandidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not (Test-Path $cargo)) {
  throw "cargo not found. Install Rustup first."
}
if (-not $iscc) {
  throw "Inno Setup 6 (ISCC.exe) not found. Install it before packaging."
}

$flutterApp = Join-Path $root "apps\desktop_flutter"
$releaseDir = Join-Path $flutterApp "build\windows\x64\runner\Release"
$iss = Join-Path $root "installer\c_drive_manager.iss"
$distDir = Join-Path $root "dist"

Write-Host "==> 1/4 Build Rust FFI + Helper"
Push-Location $root
try {
  & $cargo build -p c_drive_manager_ffi -p c_drive_manager_helper --release
  if ($LASTEXITCODE -ne 0) { throw "Rust build failed" }
}
finally {
  Pop-Location
}

Write-Host "==> 2/4 Build Flutter Windows Release"
Push-Location $flutterApp
try {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "Flutter build failed" }
}
finally {
  Pop-Location
}

Write-Host "==> 3/4 Copy FFI DLL and Helper into Release"
$dll = Join-Path $root "target\release\c_drive_manager_ffi.dll"
$helper = Join-Path $root "target\release\c_manager_helper.exe"
if (-not (Test-Path $dll)) { throw "Missing DLL: $dll" }
if (-not (Test-Path $helper)) { throw "Missing Helper: $helper" }
if (-not (Test-Path $releaseDir)) { throw "Missing Release dir: $releaseDir" }

Copy-Item $dll (Join-Path $releaseDir "c_drive_manager_ffi.dll") -Force
Copy-Item $helper (Join-Path $releaseDir "c_manager_helper.exe") -Force

$mainExe = Join-Path $releaseDir "c_drive_manager.exe"
if (-not (Test-Path $mainExe)) {
  throw "Missing main exe: $mainExe"
}

Write-Host "==> 4/4 Compile Inno Setup installer"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
& $iscc $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed" }

$setup = Get-ChildItem $distDir -Filter "CDriveManager-Setup-*.exe" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $setup) {
  throw "Setup exe not found in dist"
}

Write-Host ""
Write-Host "Installer ready:"
Write-Host $setup.FullName
Write-Host ("Size: {0:N1} MB" -f ($setup.Length / 1MB))
