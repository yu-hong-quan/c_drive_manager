$ErrorActionPreference = "SilentlyContinue"
$roots = @(
  @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Bits = "64 位" },
  @{ Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Bits = "32 位" },
  @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Bits = "当前用户" }
)
$processes = Get-CimInstance Win32_Process | Select-Object Name,ExecutablePath
function Normalize-InstallPath($entry) {
  $path = [string]$entry.InstallLocation
  if ([string]::IsNullOrWhiteSpace($path) -and $entry.DisplayIcon) {
    $icon = [string]$entry.DisplayIcon
    $icon = $icon.Trim('"')
    $icon = $icon -replace ',\d+$',''
    if (Test-Path $icon) { $path = Split-Path $icon -Parent }
  }
  if ([string]::IsNullOrWhiteSpace($path)) { return "" }
  $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim('"'))
  if (!(Test-Path $expanded -PathType Container)) { return "" }
  return (Resolve-Path $expanded).Path.TrimEnd('\')
}
function Resolve-ExecutablePath($entry, $installPath) {
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($raw in @($entry.DisplayIcon, $entry.UninstallString)) {
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $expanded = [Environment]::ExpandEnvironmentVariables([string]$raw)
    $match = [regex]::Match($expanded, '([A-Za-z]:\\[^"]+?\.exe)')
    if ($match.Success) { $paths.Add($match.Groups[1].Value.Trim('"')) }
  }
  foreach ($path in $paths) {
    if ((Test-Path $path -PathType Leaf) -and
        $path.ToLowerInvariant().StartsWith($installPath.ToLowerInvariant()) -and
        !([IO.Path]::GetFileName($path).ToLowerInvariant() -match 'unins|uninstall|setup|update|helper')) {
      return (Resolve-Path $path).Path
    }
  }
  try {
    $name = ([string]$entry.DisplayName).ToLowerInvariant()
    $files = Get-ChildItem -LiteralPath $installPath -Recurse -File -Filter *.exe -Force |
      Sort-Object @{
        Expression = {
          $file = $_.Name.ToLowerInvariant()
          if ($name.Contains("7-zip") -and $file -eq "7zfm.exe") { return 0 }
          if ($file -match 'unins|uninstall|setup|update|helper') { return 8 }
          if ($name.Split(" -_.()[]{}") | Where-Object { $_.Length -ge 2 -and $file.Contains($_) }) { return 1 }
          return 3
        }
      }, @{ Expression = { $_.FullName.Split('\').Count } }, Length
    if ($files) { return $files[0].FullName }
  } catch {}
  return ""
}
function Measure-AppDir($path) {
  try {
    return [int64]((Get-ChildItem -LiteralPath $path -Recurse -File -Force |
      Measure-Object -Property Length -Sum).Sum)
  } catch {
    return 0
  }
}
function Is-CDriveUserAppPath($path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $false }
  $lowerPath = $path.ToLowerInvariant()
  if (!$lowerPath.StartsWith("c:\")) { return $false }
  $blockedRoots = @(
    "$env:WINDIR",
    "$env:ProgramData\Microsoft",
    "$env:ProgramFiles\WindowsApps",
    "$env:ProgramFiles\Common Files\Microsoft Shared",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared"
  )
  foreach ($root in $blockedRoots) {
    if (![string]::IsNullOrWhiteSpace($root) -and $lowerPath.StartsWith($root.ToLowerInvariant())) {
      return $false
    }
  }
  return $true
}
function Get-Compatibility($name, $publisher, $path, $uninstall) {
  $reasons = New-Object System.Collections.Generic.List[string]
  $lower = "$name $publisher $path $uninstall".ToLowerInvariant()
  $systemTokens = @(
    "microsoft windows",
    "windows driver",
    "driver package",
    "defender",
    "security update",
    "runtime",
    "redistributable",
    "appx",
    "msix",
    "system32",
    "windowsapps",
    "visual c++"
  )
  foreach ($token in $systemTokens) {
    if ($lower.Contains($token)) {
      $reasons.Add("系统组件、运行库、驱动或商店应用默认不支持迁移")
      return @{ Level = "unsupported"; Reasons = @($reasons) }
    }
  }
  if ($lower.Contains("update") -or $lower.Contains("service") -or $lower.Contains("helper")) {
    $reasons.Add("存在更新器、服务或辅助进程，迁移前需谨慎验证")
    return @{ Level = "caution"; Reasons = @($reasons) }
  }
  $reasons.Add("非系统应用位于 C 盘，可生成迁移计划")
  return @{ Level = "movable"; Reasons = @($reasons) }
}
$apps = foreach ($root in $roots) {
  Get-ItemProperty $root.Path | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.DisplayName) -or $_.SystemComponent -eq 1) { return }
    $path = Normalize-InstallPath $_
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (!(Is-CDriveUserAppPath $path)) { return }
    $compat = Get-Compatibility $_.DisplayName $_.Publisher $path $_.UninstallString
    if ($compat.Level -eq "unsupported") { return }
    $running = @($processes | Where-Object {
      $_.ExecutablePath -and $_.ExecutablePath.ToLowerInvariant().StartsWith($path.ToLowerInvariant())
    }).Count -gt 0
    [pscustomobject]@{
      id = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($_.DisplayName)|$path"))
      name = [string]$_.DisplayName
      version = [string]$_.DisplayVersion
      publisher = [string]$_.Publisher
      bitness = [string]$root.Bits
      installPath = $path
      executablePath = Resolve-ExecutablePath $_ $path
      sizeBytes = Measure-AppDir $path
      running = $running
      compatibility = $compat.Level
      reasons = @($compat.Reasons)
    }
  }
}
[pscustomobject]@{ apps = @($apps) } | ConvertTo-Json -Depth 5 -Compress
