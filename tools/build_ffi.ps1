# Build Rust FFI DLL / Helper and copy into Flutter Windows runner dirs.
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (-not (Test-Path $cargo)) {
  throw "cargo not found. Install Rustup first."
}

Push-Location $root
try {
  & $cargo build -p c_drive_manager_ffi --release
  $dll = Join-Path $root "target\release\c_drive_manager_ffi.dll"
  if (-not (Test-Path $dll)) {
    throw "DLL not produced: $dll"
  }

  $destinations = @(
    (Join-Path $root "apps\desktop_flutter\native"),
    (Join-Path $root "apps\desktop_flutter\build\windows\x64\runner\Debug"),
    (Join-Path $root "apps\desktop_flutter\build\windows\x64\runner\Release")
  )
  foreach ($dest in $destinations) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item $dll (Join-Path $dest "c_drive_manager_ffi.dll") -Force
    Write-Host "Copied DLL to $dest"
  }

  & $cargo build -p c_drive_manager_helper --release
  $helper = Join-Path $root "target\release\c_manager_helper.exe"
  if (Test-Path $helper) {
    foreach ($dest in $destinations) {
      Copy-Item $helper (Join-Path $dest "c_manager_helper.exe") -Force
      Write-Host "Copied Helper to $dest"
    }
  }
}
finally {
  Pop-Location
}
